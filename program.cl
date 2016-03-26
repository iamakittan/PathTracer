// The constants from the original code to use in the gpuTracer
__constant float EPSILON = 0.0001f;
__constant int MAXDEPTH = 20;
__constant int LIGHTSCALE = 1.0f;
__constant float4 zeroVector = (float4)(0, 0, 0, 0);
__constant float4 oneVector = (float4)(1, 1, 1, 0);
__constant float BRIGHTNESS = 1.5f;

// Declaring all the needed Structs for the gpuTracer
	
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
	float4 O, D, N;
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
	float4 diffuse;
} Material;

typedef struct
{
	float4 pos;
	float r;
} Sphere;
	
typedef struct
{
	int x, y, z, w;
}	Random;

	
// apply gamma correction and convert to integer rgb
int ToIntegerRGB( float4 color )
{	
	int r = (int)min( (float)255.0, (float)(256.0f * BRIGHTNESS * sqrt( color.x )) );
	int g = (int)min( (float)255.0, (float)(256.0f * BRIGHTNESS * sqrt( color.y )) );
	int b = (int)min( (float)255.0, (float)(256.0f * BRIGHTNESS * sqrt( color.z )) );
	return (r << 16) + (g << 8) + b;
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
Material GetMaterial(int objIdx, float4 I)
{
	Material mat;
	float4 lightColor = (float4)( 8.5f * LIGHTSCALE, 8.5f * LIGHTSCALE, 7.0f * LIGHTSCALE, 0 );

	if (objIdx == 0) 
	{
		// procedural checkerboard pattern for floor plane
		mat.refl = mat.refr = 0;
		mat.emissive = false;
		int tx = ((int)(I.x * 3.0f + 1000) + (int)(I.z * 3.0f + 1000)) & 1;
		mat.diffuse = oneVector * ((tx == 1) ? 1.0f : 0.2f);
	}

	if ((objIdx == 1) || (objIdx > 8) || ((objIdx > 4) && (objIdx < 8))) { mat.refl = mat.refr = 0; mat.emissive = false; mat.diffuse = oneVector; }
	if (objIdx == 2) { mat.refl = 0.8f; mat.refr = 0; mat.emissive = false; mat.diffuse = (float4)( 1, 0.2f, 0.2f, 0 ); }
	if (objIdx == 3) { mat.refl = 0; mat.refr = 1; mat.emissive = false; mat.diffuse = (float4)( 0.9f, 1.0f, 0.9f, 0 ); }
	if (objIdx == 4) { mat.refl = 0.8f; mat.refr = 0; mat.emissive = false; mat.diffuse = (float4)( 0.2f, 0.2f, 1, 0 ); }
	if (objIdx == 8) { mat.refl = mat.refr = 0; mat.emissive = true; mat.diffuse = lightColor; }
	return mat;
}

// Generates a ray given the id and gpuCamera attributes.
Ray Generate(int x, int y, Random* rng, Camera gpuCamera)
{
		float r0 = 0.3f;//RandomFloat(rng);
		float r1 = 0.3f;//RandomFloat(rng);
		float r2 = 0.3f;//RandomFloat(rng) - 0.5f;
		float r3 = 0.3f;//RandomFloat(rng) - 0.5f;

		float u = ((float)x + r0) / (float)gpuCamera.screenWidth;
		float v = ((float)y + r1) / (float)gpuCamera.screenHeight;
		float4 T = gpuCamera.p1.xyzw + u * (gpuCamera.p2.xyzw - gpuCamera.p1.xyzw) + v * (gpuCamera.p3.xyzw - gpuCamera.p1.xyzw);
		float4 P = gpuCamera.pos.xyzw + gpuCamera.lensSize * (r2 * gpuCamera.right.xyzw + r3 * gpuCamera.up.xyzw);
		float4 D = normalize( T - P );
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
float4 Reflect(float4 D, float4 N)
{
	float4 r = D - 2 * dot(D, N) * N;
	return r;
}

// Calculates the Refraction of a ray
float4 Refraction(bool inside, float4 D, float4 N, float4 R, Random* rng)
{
	float nc = inside ? 1 : 1.2f, nt = inside ? 1.2f : 1;
	float nnt = nt / nc, ddn = dot( D, N ); 
	float cos2t = 1.0f - nnt * nnt * (1 - ddn * ddn);
	R = Reflect( D, N); 
	if (cos2t >= 0)
	{
		float r1 = 0.3f;//RandomFloat(rng);
		float a = nt - nc, b = nt + nc, R0 = a * a / (b * b), c = 1 + ddn;
		float Tr = 1 - (R0 + (1 - R0) * c * c * c * c * c);
		if (r1 < Tr) R = (D * nnt - N * (ddn * nnt + (float)sqrt( cos2t )));
	}
	return R;
}

// Calculates the DiffuseReflection for a float4
float4 DiffuseReflection(Random* rng, float4 N)
{
	float r1 = 0.3f;//RandomFloat(rng);
	float r2 = 0.3f;//RandomFloat(rng);
	float r = (float)sqrt( 1.0 - r1 * r1 );
	float phi = 2 * M_PI_F * r2;
	float4 R;
	R.x = (float)cos( phi ) * r;
	R.y = (float)sin( phi ) * r;
	R.z = r1;
	R.w = 0;
	if (dot( N, R ) < 0) R *= -1.0f;
	return R;
}

// Returns the sample for hitting the skydome
float4 SampleSkydome( float4 D, __global float* skyboxArray )
{
	int u = (int)(2500.0f * 0.5f * (1.0f + atan2( D.x, -D.z ) * M_1_PI_F));
	int v = (int)(1250.0f * acos( D.y ) * M_1_PI_F);
	int idx = u + v * 2500;
	return (float4)(skyboxArray[idx * 3 + 0], skyboxArray[idx * 3 + 1], skyboxArray[idx * 3 + 2], 0);
}

// Calculates the intersections with the spheres
void IntersectSphere( int idx, Sphere sphere, Ray* ray )
{
	float4 L = sphere.pos - ray->O;
	float tca = dot( L, ray->D );
	if (tca < 0) 
		return;

	float d2 = dot( L, L ) - tca * tca;
	if (d2 > sphere.r) 
		return;

	float thc = (float)sqrt( sphere.r - d2 );
	float t0 = tca - thc;
	float t1 = tca + thc;

	if (t0 > 0)
	{
		if (t0 > ray->t) return;
		ray->N = normalize( ray->O + t0 * ray->D - sphere.pos );
		ray->objIdx = idx;
		ray->t = t0;
	}
	else
	{
		if ((t1 > ray->t) || (t1 < 0)) return;
		ray->N = normalize( sphere.pos - (ray->O + t1 * ray->D) );
		ray->objIdx = idx;
		ray->t = t1;
	}
}

// Calculates the intersections with the planes, spheres and the light
void Intersect(Ray* ray, __global Sphere* plane, __global Sphere* spheres, Sphere light)
{
	IntersectSphere( 0, plane[0], ray );
	IntersectSphere( 1, plane[1], ray );
	for( int i = 0; i < 6; i++ ) 
		IntersectSphere( i + 2, spheres[i], ray );

	IntersectSphere( 8, light, ray );
}

// Samples the ray for a given depth
float4 Sample(Ray* r, int depth, __global Sphere* plane, __global Sphere* spheres, Sphere light, Random* rng, __global float* skyboxArray)
{
	Ray ray = *r;
	Ray extensionRay;
	float4 temp;
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
	float4 I = ray.O + ray.t * ray.D;
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
	float r0 = 0.3f;//RandomFloat(rng);
	float4 R = zeroVector;
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

__kernel void device_function(__global int* pixels, __global float* skyboxArray, __read_only Camera gpuCamera, float scale, __global Sphere* spheres, __global Sphere* planes, Sphere light)
{ 	
	Random rng = newRandom(10 + get_global_id(0) * get_global_id(0));
				
	Ray ray = Generate(get_global_id(0), get_global_id(1), &rng, gpuCamera);
	ray.isFinished = false;
	float4 result = oneVector;
	int depth = 0;

	for(int i = 0; i < 20; i++)
	{
		//if (!ray.isFinished)
		//	break;
		
		result *= Sample(&ray, depth, planes, spheres, light, &rng, skyboxArray);
		depth++;
	}

	pixels[get_global_id(0) + get_global_id(1) * gpuCamera.screenWidth] = ToIntegerRGB(result);

}







