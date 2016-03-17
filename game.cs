using System;
using System.Diagnostics;
using System.Numerics;
using System.Threading.Tasks;
using System.Threading;
using System.Collections.Generic;
using System.Drawing;
using Cloo;
using System.IO;
using OpenTK.Graphics;
using OpenTK.Graphics.OpenGL;
using System.Runtime.InteropServices;

// making vectors work in VS2013:
// - Uninstall Nuget package manager
// - Install Nuget v2.8.6 or later
// - In Package Manager Console: Install-Package System.Numerics.Vectors -Pre

namespace Template
{
    class Game
    {
        // member variables
        public Surface screen;					// camera
        Scene scene;							// hardcoded scene
        Stopwatch timer = new Stopwatch();		// timer
        Vector3[] accumulator;					// buffer for accumulated samples
        int spp = 0;							// samples per pixel; accumulator will be divided by this
        int runningTime = -1;					// running time (from commandline); default = -1 (infinite)
        bool useGPU = true;						// GPU code enabled (from commandline)
        int gpuPlatform = 0;					// OpenCL platform to use (from commandline)
        bool firstFrame = true;					// first frame: used to start timer once
        ParallelOptions parallelOptions;
        List<DataBundle> amount = new List<DataBundle>();
        DataBundle[] dataArray = new DataBundle[2744];
        // constants for rendering algorithm
        const float PI = 3.14159265359f;
        const float INVPI = 1.0f / PI;
        const float EPSILON = 0.0001f;
        const int MAXDEPTH = 20;

        // GPU variables
        bool GLInterop = false;
        static ComputeContext context;
        static ComputeCommandQueue queue;
        static ComputeProgram program;
        static ComputeKernel kernel;
        static ComputeBuffer<int> buffer;
        static int[] data;
        static float[] texData = new float[512 * 512 * 4];
        static int texID;
        ComputeImage2D texBuffer;
        [System.Runtime.InteropServices.DllImport("opengl32", SetLastError = true)]
        static extern IntPtr wglGetCurrentDC();
        static ComputeBuffer<Vector3> accBuffer;
        GPUCamera gpuCamera;
        long[] work;
        static float t = 0;

        // clear the accumulator: happens when camera moves
        private void ClearAccumulator()
        {
            for (int s = screen.width * screen.height, i = 0; i < s; i++)
                accumulator[i] = Vector3.Zero;
            spp = 0;
            var flags = ComputeMemoryFlags.ReadWrite | ComputeMemoryFlags.UseHostPointer;
            accBuffer = new ComputeBuffer<Vector3>(context, flags, accumulator);
            kernel.SetMemoryArgument(0, buffer);
        }

        // initialize renderer: takes in command line parameters passed by template code
        public void Init(int rt, bool gpu, int platformIdx)
        {
            // pass command line parameters
            runningTime = rt;
            useGPU = gpu;
            gpuPlatform = platformIdx;
            // initialize accumulator
            accumulator = new Vector3[screen.width * screen.height];
            // setup scene
            scene = new Scene();
            // setup camera
            gpuCamera = new GPUCamera(screen.width, screen.height);

            // initialize max threads
            parallelOptions = new ParallelOptions();
            parallelOptions.MaxDegreeOfParallelism = Environment.ProcessorCount;
            
            // GPU variables
            // pick first platform
            var platform = ComputePlatform.Platforms[gpuPlatform];

            // create context with all gpu devices
            if (GLInterop)
            {
                ComputeContextProperty p1 = new ComputeContextProperty(ComputeContextPropertyName.Platform, platform.Handle.Value);
                ComputeContextProperty p2 = new ComputeContextProperty(ComputeContextPropertyName.CL_GL_CONTEXT_KHR, (GraphicsContext.CurrentContext as IGraphicsContextInternal).Context.Handle);
                ComputeContextProperty p3 = new ComputeContextProperty(ComputeContextPropertyName.CL_WGL_HDC_KHR, wglGetCurrentDC());
                ComputeContextPropertyList cpl = new ComputeContextPropertyList(new ComputeContextProperty[] { p1, p2, p3 });
                context = new ComputeContext(ComputeDeviceTypes.Gpu, cpl, null, IntPtr.Zero);
            }
            else
            {
                context = new ComputeContext(ComputeDeviceTypes.Gpu, new ComputeContextPropertyList(platform), null, IntPtr.Zero);
            }

            var streamReader = new StreamReader("../../program.cl");
            string clSource = streamReader.ReadToEnd();
            streamReader.Close();

            // create program with opencl source
            program = new ComputeProgram(context, clSource);

            // compile opencl source
            try
            {
                program.Build(null, null, null, IntPtr.Zero);
            }
            catch
            {
                Console.Write("error in kernel code:\n");
                Console.Write(program.GetBuildLog(context.Devices[0]) + "\n");
            }
           
            // load chosen kernel from program
            kernel = program.CreateKernel("device_function");
            // create some data
            data = new int[screen.width * screen.height];
            // allocate a memory buffer with the message (the int array)
            var flags = ComputeMemoryFlags.WriteOnly | ComputeMemoryFlags.UseHostPointer;
            buffer = new ComputeBuffer<int>(context, flags, data);

            kernel.SetMemoryArgument(0, buffer);
            ComputeBuffer<float> skyboxBuffer = new ComputeBuffer<float>(context, flags, Scene.skybox);
            ComputeBuffer<Sphere> sphereBuffer = new ComputeBuffer<Sphere>(context, flags, Scene.sphere);
            ComputeBuffer<Sphere> planeBuffer = new ComputeBuffer<Sphere>(context, flags, Scene.planes);
            kernel.SetMemoryArgument(1, skyboxBuffer);
            kernel.SetValueArgument(2, gpuCamera);
            kernel.SetMemoryArgument(4, sphereBuffer);
            kernel.SetMemoryArgument(5, planeBuffer);
            kernel.SetValueArgument(6, Scene.light);

            // create a command queue with first gpu found
            queue = new ComputeCommandQueue(context, context.Devices[0], 0);
            work = new long[] { screen.pixels.Length };


            ClearAccumulator();
            /*
            // create a texture to draw to from OpenCL
            if (GLInterop)
            {
                texID = GL.GenTexture();
                GL.BindTexture(TextureTarget.Texture2D, texID);
                GL.TexParameter(TextureTarget.Texture2D, TextureParameterName.TextureMinFilter, (int)TextureMinFilter.Nearest);
                GL.TexParameter(TextureTarget.Texture2D, TextureParameterName.TextureMagFilter, (int)TextureMagFilter.Nearest);
                GL.TexImage2D(TextureTarget.Texture2D, 0, PixelInternalFormat.Rgba32f, 512, 512, 0, OpenTK.Graphics.OpenGL.PixelFormat.Rgb, PixelType.Float, texData);
                flags = ComputeMemoryFlags.WriteOnly;
                texBuffer = ComputeImage2D.CreateFromGLTexture2D(context, flags, (int)TextureTarget.Texture2D, 0, texID);
            }
            */
            // initialize dataArray
            int counter = 0;
            for (int y = 0; y < screen.height; y += 8)
            {
                for (int x = 0; x < screen.width; x += 16)
                {
                    //amount.Add(new DataBundle(x, y, 12, 8));
                    dataArray[counter] = new DataBundle(x, y, 16, 8);
                    counter++;
                }
            }
        }

        // sample: samples a single path up to a maximum depth
        private Vector3 Sample(Ray ray, int depth)
        {
            // find nearest ray/scene intersection
            Scene.Intersect(ray);
            if (ray.objIdx == -1)
            {
                // no scene primitive encountered; skybox
                return 1.0f * scene.SampleSkydome(ray.D);
            }
            // calculate intersection point
            Vector3 I = ray.O + ray.t * ray.D;
            // get material at intersection point
            Material material = scene.GetMaterial(ray.objIdx, I);
            if (material.emissive)
            {
                // hit light
                return material.diffuse;
            }
            // terminate if path is too long
            if (depth >= MAXDEPTH) return Vector3.Zero;
            // handle material interaction
            float r0 = RTTools.RandomFloat();
            Vector3 R = Vector3.Zero;
            if (r0 < material.refr)
            {
                // dielectric: refract or reflect
                RTTools.Refraction(ray.inside, ray.D, ray.N, ref R);
                Ray extensionRay = new Ray(I + R * EPSILON, R, 1e34f);
                extensionRay.inside = (Vector3.Dot(ray.N, R) < 0);
                return material.diffuse * Sample(extensionRay, depth + 1);
            }
            else if ((r0 < (material.refl + material.refr)) && (depth < MAXDEPTH))
            {
                // pure specular reflection
                R = Vector3.Reflect(ray.D, ray.N);
                Ray extensionRay = new Ray(I + R * EPSILON, R, 1e34f);
                return material.diffuse * Sample(extensionRay, depth + 1);
            }
            else
            {
                // diffuse reflection
                R = RTTools.DiffuseReflection(RTTools.GetRNG(), ray.N);
                Ray extensionRay = new Ray(I + R * EPSILON, R, 1e34f);
                return Vector3.Dot(R, ray.N) * material.diffuse * Sample(extensionRay, depth + 1);
            }
        }

        // tick: renders one frame
        public void Tick()
        {
            //float t = 21.5f;
            // initialize timer
            if (firstFrame)
            {
                timer.Reset();
                timer.Start();
                firstFrame = false;
            }
            // handle keys, only when running time set to -1 (infinite)
            if (runningTime == -1) if (gpuCamera.HandleInput())
                {
                    // camera moved; restart
                    ClearAccumulator();
                }
            // render
            if (useGPU)
            {
                /*
                // add your CPU + OpenCL path here
                // mind the gpuPlatform parameter! This allows us to specify the platform on our
                // test system.
                // note: it is possible that the automated test tool provides you with a different
                // platform number than required by your hardware. In that case, you can hardcode
                // the platform during testing (ignoring gpuPlatform); do not forget to put back
                // gpuPlatform before submitting!
                GL.Finish();
                // clear the screen
                screen.Clear(0);
                // do opencl stuff
                if (GLInterop)
                {
                    kernel.SetMemoryArgument(0, texBuffer);
                }
                else
                {
                    kernel.SetMemoryArgument(0, buffer);
                }
                kernel.SetValueArgument(1, t);
                t += 0.1f;
                // execute kernel
                long[] workSize = { screen.width, screen.height };
                long[] localSize = { 32, 4 };
                // long [] workSize = { 512 * 512 };
                if (GLInterop)
                {
                    List<ComputeMemory> c = new List<ComputeMemory>() { texBuffer };
                    queue.AcquireGLObjects(c, null);
                    queue.Execute(kernel, null, workSize, localSize, null);
                    queue.Finish();
                    queue.ReleaseGLObjects(c, null);
                }
                else
                {
                    queue.Execute(kernel, null, workSize, localSize, null);
                    queue.Finish();
                    // fetch results
                    if (!GLInterop)
                    {
                        queue.ReadFromBuffer(buffer, ref data, true, null);

                        // visualize result
                        for (int y = 0; y < screen.height; y++) for (int x = 0; x < screen.width; x++)
                            {
                                int temp = x + y * screen.width;
                                screen.pixels[temp] = data[temp];
                            }
                    }
                }
                 */

                gpuCamera.Update();
                float scale = 1.0f / (float)++spp;
                kernel.SetValueArgument(2, gpuCamera);
                kernel.SetValueArgument(3, scale);
                queue.Execute(kernel, null, work, null, null);
                queue.Finish();
                queue.ReadFromBuffer(buffer, ref screen.pixels, true, null);
                int[] pixels = new int[screen.pixels.Length];
            }
            else
            {
                // this is your CPU only path
                float scale = 1.0f / (float)++spp;
                Parallel.For(0, dataArray.Length, parallelOptions, (id) =>
                {
                    for (int j = dataArray[id].y1; j < dataArray[id].y2 && j < screen.height; j++)
                    {
                        for (int i = dataArray[id].x1; i < dataArray[id].x2 && i < screen.width; i++)
                        {
                            // generate primary ray
                            Ray ray = gpuCamera.Generate(RTTools.GetRNG(), i, j);
                            // trace path
                            int pixelIdx = i + j * screen.width;
                            accumulator[pixelIdx] += Sample(ray, 0);
                            // plot final color
                            screen.pixels[pixelIdx] = RTTools.Vector3ToIntegerRGB(scale * accumulator[pixelIdx]);
                        }
                    }
                });
            }

            // stop and report when max render time elapsed
            int elapsedSeconds = (int)(timer.ElapsedMilliseconds / 1000);
            if (runningTime != -1) if (elapsedSeconds >= runningTime)
                {
                    OpenTKApp.Report((int)timer.ElapsedMilliseconds, spp, screen);
                }
        }

        public void Render()
        {
            // draw a quad using the texture that was filled by OpenCL
            if (GLInterop)
            {
                GL.LoadIdentity();
                GL.BindTexture(TextureTarget.Texture2D, texID);
                GL.Begin(PrimitiveType.Quads);
                GL.TexCoord2(0.0f, 1.0f); GL.Vertex2(-1.0f, -1.0f);
                GL.TexCoord2(1.0f, 1.0f); GL.Vertex2(1.0f, -1.0f);
                GL.TexCoord2(1.0f, 0.0f); GL.Vertex2(1.0f, 1.0f);
                GL.TexCoord2(0.0f, 0.0f); GL.Vertex2(-1.0f, 1.0f);
                GL.End();
            }
        }
    }

    public class DataBundle
    {
        public int x1;
        public int y1;
        public int x2;
        public int y2;

        public DataBundle(int x, int y, int skipX, int skipY)
        {
            this.x1 = x;
            this.x2 = x + skipX;
            this.y1 = y;
            this.y2 = y + skipY;
        }
    }
} // namespace Template