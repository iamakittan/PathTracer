
// The constants from the original code to use in the gpuTracer
	__constant float PI = 3.14159265359f;
	__constant float INVPI = 1.0f / 3.14159265359f;
	__constant float EPSILON = 0.0001f;
	__constant int MAXDEPTH = 20;
	__constant int LIGHTSCALE = 1.0f;
	__constant float3 zeroVector = (float3)(0, 0, 0);
	__constant float3 oneVector = (float3)(1, 1, 1);
	__constant float BRIGHTNESS = 1.5f;

//Declaring all the needed Structs for the gpuTracer
	
	typedef struct
	{
		int screenWidth;
		int screenHeight;
		float4 p1;
		float4 p2;
		float4 p3;
		float4 pos;
		float4 right;
		float4 up;
		float lensSize;
	} Camera;
		
	typedef struct
	{
		float3 O, D, N;
		float t;
		int objIdx;
		bool inside;
		bool isFinished;
	} Ray;

	typedef struct
	{
		float refl;
		float refr;
		bool emissive;
		float3 diffuse;
	} Material;

	typedef struct
	{
		float3 pos;
		float r;
	} Sphere;
	
	typedef struct
	{
		int x, y, z, w;
	}	Random;

	
	// apply gamma correction and convert to integer rgb
	int ToIntegerRGB( float3 color )
	{	
		int r = (int)min( (float)255.0, (float)(256.0f * BRIGHTNESS * sqrt( color.x )) );
		int g = (int)min( (float)255.0, (float)(256.0f * BRIGHTNESS * sqrt( color.y )) );
		int b = (int)min( (float)255.0, (float)(256.0f * BRIGHTNESS * sqrt( color.z )) );
		return (r << 16) + (g << 8) + b;
	}

	float3 convertFloat4(float4 original)
	{
		float3 new;
		new.x = original.x;
		new.y = original.y;
		new.z = original.z;
		return new;
	}


// Given a rng object, calculates a random floating point number
	float RandomFloat(Random* rng)
	{			
		int t = rng->x;
		t ^= t << 11;
		t ^= t >> 8;
		rng->x = rng->y;
		rng->y = rng->z; 
		rng->z = rng->w;
		rng->w ^= rng->w >> 19;
		rng->w ^= t;
		return clamp((float)rng->w/(float)10000000,0.0f,1.0f);
	}
// Creates a new random object
	Random newRandom(int seed)
	{
		Random rng;
		rng.x = (int)pow(2.0, 18.0) - 3*seed;
		rng.y = (int)pow(2.0, 12.0) - 7*seed;;
		rng.z = 9* seed + 2;
		rng.w = seed + 3;
		return rng;
	}

//Gets the material of the object with id objIdx
	Material GetMaterial(int objIdx, float3 I)
	{
		Material mat;
		float3 lightColor = (float3)( 8.5f * LIGHTSCALE, 8.5f * LIGHTSCALE, 7.0f * LIGHTSCALE );

		if (objIdx == 0) 
		{
			// procedural checkerboard pattern for floor plane
			mat.refl = mat.refr = 0;
			mat.emissive = false;
			int tx = ((int)(I.x * 3.0f + 1000) + (int)(I.z * 3.0f + 1000)) & 1;
			mat.diffuse = oneVector * ((tx == 1) ? 1.0f : 0.2f);
		}

		if ((objIdx == 1) || (objIdx > 8) || ((objIdx > 4) && (objIdx < 8))) { mat.refl = mat.refr = 0; mat.emissive = false; mat.diffuse = oneVector; }
		if (objIdx == 2) { mat.refl = 0.8f; mat.refr = 0; mat.emissive = false; mat.diffuse = (float3)( 1, 0.2f, 0.2f ); }
		if (objIdx == 3) { mat.refl = 0; mat.refr = 1; mat.emissive = false; mat.diffuse = (float3)( 0.9f, 1.0f, 0.9f ); }
		if (objIdx == 4) { mat.refl = 0.8f; mat.refr = 0; mat.emissive = false; mat.diffuse = (float3)( 0.2f, 0.2f, 1 ); }
		if (objIdx == 8) { mat.refl = mat.refr = 0; mat.emissive = true; mat.diffuse = lightColor; }
		return mat;
	}

// Generates a ray given the id and camera attributes.
	Ray Generate(int id, Random* rng, Camera camera)
	{
		 int x = id % camera.screenWidth;
		 int y = id / camera.screenHeight;

		 float r0 = RandomFloat(rng);
		 float r1 = RandomFloat(rng);
		 float r2 = RandomFloat(rng) - 0.5f;
		 float r3 = RandomFloat(rng) - 0.5f;

		 float u = ((float)x + r0) / (float)camera.screenWidth;
		 float v = ((float)y + r1) / (float)camera.screenHeight;
		 float3 T = convertFloat4(camera.p1) + u * (convertFloat4(camera.p2) - convertFloat4(camera.p1)) + v * (convertFloat4(camera.p3) - convertFloat4(camera.p1));
		 float3 P = convertFloat4(camera.pos) + camera.lensSize * (r2 * convertFloat4(camera.right) + r3 * convertFloat4(camera.up));
		 float3 D = normalize( T - P );
		 // return new primary ray
		 Ray ray;
		 ray.O = P;
		 ray.D = D;
		 ray.t = 1e34f;
		 ray.objIdx = -1;
		 ray.inside = false;
		 return ray;
	}

// Calculates the Reflect of a vector3
	float3 Reflect(float3 D, float3 N)
	{
		float3 r = D - 2 * dot(D, N) * N;
		return r;
	}

// Calculates the Refraction of a ray
	float3 Refraction(bool inside, float3 D, float3 N, float3 R, Random* rng)
	{
		float nc = inside ? 1 : 1.2f, nt = inside ? 1.2f : 1;
		float nnt = nt / nc, ddn = dot( D, N ); 
		float cos2t = 1.0f - nnt * nnt * (1 - ddn * ddn);
		R = Reflect( D, N); 
		if (cos2t >= 0)
		{
			float r1 = RandomFloat(rng);
			float a = nt - nc, b = nt + nc, R0 = a * a / (b * b), c = 1 + ddn;
			float Tr = 1 - (R0 + (1 - R0) * c * c * c * c * c);
			if (r1 < Tr) R = (D * nnt - N * (ddn * nnt + (float)sqrt( cos2t )));
		}
		return R;
	}

	// Calculates the DiffuseReflection for a float3
    float3 DiffuseReflection(Random* rng, float3 N)
	{
		float r1 = RandomFloat(rng);
		float r2 = RandomFloat(rng);
		float r = (float)sqrt( 1.0 - r1 * r1 );
		float phi = 2 * PI * r2;
		float3 R;
		R.x = (float)cos( phi ) * r;
		R.y = (float)sin( phi ) * r;
		R.z = r1;
		if (dot( N, R ) < 0) R *= -1.0f;
		return R;
	}

	// Returns the sample for hitting the skydome
	float3 SampleSkydome( float3 D, __global float* skyboxArray )
	{
		int u = (int)(2500.0f * 0.5f * (1.0f + atan2( D.z, -D.z ) * INVPI));
		int v = (int)(1250.0f * acos( D.y ) * INVPI);
		int idx = u + v * 2500;
		return (skyboxArray[idx * 3 + 0], skyboxArray[idx * 3 + 1], skyboxArray[idx * 3 + 2] );
	}

	//Calculates the intersections with the spheres
	Ray* IntersectSphere( int idx, Sphere sphere, Ray* ray )
	{
		float3 L = sphere.pos- ray->O;
		float tca = dot( L, ray->D );
		if (tca < 0) return ray;
		float d2 = dot( L, L ) - tca * tca;
		if (d2 > sphere.r) return ray;
		float thc = (float)sqrt( sphere.r - d2 );
		float t0 = tca - thc;
		float t1 = tca + thc;
		if (t0 > 0)
		{
			if (t0 > ray->t) return ray;
			ray->N = normalize( ray->O + t0 * ray->D - sphere.pos );
			ray->objIdx = idx;
			ray->t = t0;
		}
		else
		{
			if ((t1 > ray->t) || (t1 < 0)) return ray;
			ray->N = normalize( sphere.pos - (ray->O + t1 * ray->D) );
			ray->objIdx = idx;
			ray->t = t1;
		}
		return ray;

	}
	//Calculates the intersections with the planes, spheres and the light
	Ray* Intersect(Ray* ray, __global Sphere* plane, __global Sphere* spheres, Sphere light)
	{
		IntersectSphere( 0, plane[0], ray );
		IntersectSphere( 1, plane[1], ray );
		for( int i = 0; i < 6; i++ ) IntersectSphere( i + 2, spheres[i], ray );
		IntersectSphere( 8, light, ray );
		return ray;
		}

	//Samples the ray for a given depth
	float3 Sample(Ray* r, int depth, __global Sphere* plane, __global Sphere* spheres, Sphere light, Random* rng, __global float* skyboxArray)
	{
		Ray ray = *r;
		Ray extensionRay;
		float3 temp;
		bool done = false;

		// find nearest ray/scene intersection
		Intersect(r, plane, spheres, light);
		if (ray.objIdx == -1)
		{
			// no scene primitive encountered; skybox
			r->isFinished = true;
			done = true;
			temp = 1.0f * SampleSkydome(ray.D, skyboxArray);
		}

		// calculate intersection point
		float3 I = ray.O + ray.t * ray.D;
		// get material at intersection point
		Material material = GetMaterial(ray.objIdx, I);
		if (material.emissive && !done)
		{
			// hit light
			r->isFinished = true;
			done = true;
			temp = material.diffuse;
		}

		// terminate if path is too long
		if (depth >= MAXDEPTH && !done)
		{	r->isFinished = true;
			done = true;
			temp = zeroVector;
		}
	 
	  // handle material interaction
	  float r0 = RandomFloat(rng);
	  float3 R = zeroVector;
	  if (r0 < material.refr && !done)
	  {
			// dielectric: refract or reflect
			R = Refraction(ray.inside, ray.D, ray.N, R, rng);
			
			extensionRay.O = I + R * EPSILON;
			extensionRay.D = R;
			extensionRay.t = 1e34f;
			extensionRay.inside = (dot(ray.N, R) < 0);		

			temp =  material.diffuse;
			r->O = extensionRay.O;
			r->D = extensionRay.D;
			r->t = 1.e34f;
			r->isFinished = false; 
		}
		else if ((r0 < (material.refl + material.refr)) && (depth < MAXDEPTH) && !done)
		{
			// pure specular reflection
			R = Reflect(ray.D, ray.N);
			extensionRay.O = I + R * EPSILON;
			extensionRay.D = R;
			extensionRay.t = 1e34f;

			temp = material.diffuse;
			r->O = extensionRay.O;
			r->D = extensionRay.D;
			r->t = 1.e34f;
			r->isFinished = false; 
		}
	  else if(!done)
	  {
			// diffuse reflection
			R = DiffuseReflection(rng, ray.N);
			extensionRay.O = I + R * EPSILON;
			extensionRay.D = R;
			extensionRay.t = 1e34f;
			
			temp = dot(R, ray.N) * material.diffuse;
			r->O = extensionRay.O;
			r->D = extensionRay.D;
			r->t = 1.e34f;
			r->isFinished = false; 

	  }

	  return temp;
	}

		__kernel void device_function(__global int* pixels, __global float* skyboxArray, __read_only Camera camera, float scale, __global Sphere* spheres, __global Sphere* planes, Sphere light)
	{ 	
		Random rng = newRandom(10 + get_global_id(0) * get_global_id(0));
				
		Ray ray = Generate(get_global_id(0), &rng, camera);
		ray.isFinished = false;
		float3 result = (float3) (1, 1, 1);
		int depth = 0;

		while(!ray.isFinished)
		{
			result *= Sample(&ray, depth, planes, spheres, light, &rng, skyboxArray);
			depth ++;
		}

		pixels[get_global_id(0)] = ToIntegerRGB(result);

	}







