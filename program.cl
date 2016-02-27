#define GLINTEROP

#ifdef GLINTEROP
__kernel void device_function( write_only image2d_t a, float t )
#else
kernel void device_function( global int* a, float t )
#endif
{ // adapted from inigo quilez - iq/2013
	int idx = get_global_id( 0 );
	int idy = get_global_id( 1 );
	int id = idx + 512 * idy;
	if (id >= (512 * 512)) return;
		float2 fragCoord = (float2)( (float)idx, (float)idy ), resolution = (float2)( 512, 512 );
	float3 col = (float3)( 0.f, 0.f, 0.f );
	for( int m = 0; m < 4; m++ ) for( int n = 0; n < 4; n++ )
	{
		float2 p = -resolution + 2.f * (fragCoord + (float2)( .5f * (float)m, .5f * (float)n ));
		float w = (float)( 2 * m + n ), l = 0.0f;
		float time = t + .5f * (1.f / 24.f) * w / 4.f;
		float zoo = .32f + .2f * cos( .07f * time );
		float coa = cos( .15f * (1.f - zoo) * time );
		float sia = sin( .15f * (1.f - zoo) * time );
		zoo = pow( zoo, 8.f );
		float2 xy = (float2)( p.x * coa - p.y * sia, p.x * sia + p.y * coa );
		float2 c = (float2)( -.745f, .186f ) + xy * zoo, z = (float2)( 0.f, 0.f );
			for( int i = 0; i < 256; i++ )
		{
			z = (float2)( z.x * z.x - z.y * z.y, 2.f * z.x * z.y ) + c;
			if (dot( z, z ) > 65536.f) break; else l += 1.f;
		}
			float sl = l - log2( log2( dot( z, z ) ) ) + 4.f;
		float al = smoothstep( -.1f, 0.f, 1.f );
		l = mix( l, sl, al );
		col += .5f + .5f * cos( 3.f + l * 0.15f + (float3)( .0f, .6f, 1.f ) );
	}
	#ifdef GLINTEROP
		int2 pos = (int2)(idx,idy);
		write_imagef( a, pos, (float4)(col * (1.0f / 16.0f), 1.0f ) );
	#else
		int r = (int)clamp( 16.0f * col.x, 0.f, 255.f );
		int g = (int)clamp( 16.0f * col.y, 0.f, 255.f );
		int b = (int)clamp( 16.0f * col.z, 0.f, 255.f );
		a[id] = (r << 16) + (g << 8) + b;
	#endif
}
