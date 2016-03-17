using System;
using System.Numerics;
using System.Runtime.InteropServices;

namespace Template
{
    [StructLayout(LayoutKind.Explicit, Size = 128, Pack = 1)]
    struct GPUCamera
    {
        [FieldOffset(0)]
        public int screenWidth;
        [FieldOffset(4)]
        public int screenHeight;
        [FieldOffset(16)]
        public Vector3 p1;
        [FieldOffset(32)]
        public Vector3 p2;
        [FieldOffset(48)]
        public Vector3 p3;
        [FieldOffset(64)]
        public Vector3 pos;
        [FieldOffset(80)]
        public Vector3 right;
        [FieldOffset(96)]
        public Vector3 up;
        [FieldOffset(112)]
        public Vector3 target;
        [FieldOffset(128)]
        public Vector3 E;
        [FieldOffset(144)]
        public float focalDistance;
        [FieldOffset(148)]
        public float aspectRatio;
        [FieldOffset(152)]
        public float lensSize;


        public GPUCamera(int w, int h)
        {
            screenWidth = w;
            screenHeight = h;
            aspectRatio = (float)w / (float)h;
            lensSize = 0.04f;
            pos = new Vector3(-0.94f, -0.037f, -3.342f);
            target = new Vector3(-0.418f, -0.026f, -2.435f);
            p1 = Vector3.Zero;
            p2 = Vector3.Zero;
            p3 = Vector3.Zero;
            up = Vector3.Zero;
            right = Vector3.Zero;
            E = Vector3.Zero;

            focalDistance = 0;
        }

        public bool HandleInput()
        {
            var keyboard = OpenTK.Input.Keyboard.GetState();
            target = pos + E;
            bool changed = false;
            if (keyboard[OpenTK.Input.Key.A]) { changed = true; pos -= right * 0.1f; target -= right * 0.1f; }
            if (keyboard[OpenTK.Input.Key.D]) { changed = true; pos += right * 0.1f; target += right * 0.1f; }
            if (keyboard[OpenTK.Input.Key.W]) { changed = true; pos += E * 0.1f; }
            if (keyboard[OpenTK.Input.Key.S]) { changed = true; pos -= E * 0.1f; }
            if (keyboard[OpenTK.Input.Key.R]) { changed = true; pos += up * 0.1f; target += up * 0.1f; }
            if (keyboard[OpenTK.Input.Key.F]) { changed = true; pos -= up * 0.1f; target -= up * 0.1f; }
            if (keyboard[OpenTK.Input.Key.Up]) { changed = true; target -= up * 0.1f; }
            if (keyboard[OpenTK.Input.Key.Down]) { changed = true; target += up * 0.1f; }
            if (keyboard[OpenTK.Input.Key.Left]) { changed = true; target -= right * 0.1f; }
            if (keyboard[OpenTK.Input.Key.Right]) { changed = true; target += right * 0.1f; }
            if (changed)
            {
                Update();
                return true;
            }
            return false;
        }

        public void Update()
        {
            // construct a look-at matrix
            E = Vector3.Normalize(target - pos);
            up = Vector3.UnitY;
            right = Vector3.Cross(up, E);
            up = Vector3.Cross(E, right);
            // calculate focal distance
            Ray ray = new Ray(pos, E, 1e34f);
            Scene.Intersect(ray);
            focalDistance = Math.Min(20, ray.t);
            // calculate virtual screen corners
            Vector3 C = pos + focalDistance * E;
            p1 = C - 0.5f * focalDistance * aspectRatio * right + 0.5f * focalDistance * up;
            p2 = C + 0.5f * focalDistance * aspectRatio * right + 0.5f * focalDistance * up;
            p3 = C - 0.5f * focalDistance * aspectRatio * right - 0.5f * focalDistance * up;
        }

        public Ray Generate(Random rng, int x, int y)
        {
            float r0 = (float)rng.NextDouble();
            float r1 = (float)rng.NextDouble();
            float r2 = (float)rng.NextDouble() - 0.5f;
            float r3 = (float)rng.NextDouble() - 0.5f;
            // calculate sub-pixel ray target position on screen plane
            float u = ((float)x + r0) / (float)screenWidth;
            float v = ((float)y + r1) / (float)screenHeight;
            Vector3 T = p1 + u * (p2 - p1) + v * (p3 - p1);
            // calculate position on aperture
            Vector3 P = pos + lensSize * (r2 * right + r3 * up);
            // calculate ray direction
            Vector3 D = Vector3.Normalize(T - P);
            // return new primary ray
            return new Ray(P, D, 1e34f);
        }
    }
} // namespace Template
