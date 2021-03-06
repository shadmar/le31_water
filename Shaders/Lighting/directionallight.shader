SHADER version 1
@OpenGL2.Vertex

@OpenGLES2.Vertex

@OpenGLES2.Fragment

@OpenGL4.Vertex
#version 400

uniform mat4 projectionmatrix;
uniform mat4 drawmatrix;
uniform vec2 offset;
uniform vec2 position[4];

in vec3 vertex_position;

void main(void)
{
	gl_Position = projectionmatrix * (drawmatrix * vec4(position[gl_VertexID], 0.0, 1.0));
}
@OpenGL4.Fragment
#version 400
#define PI 3.14159265359
#define HALFPI PI/2.0
#define LOWERLIGHTTHRESHHOLD 0.001
#ifndef SHADOWSTAGES
	#define SHADOWSTAGES 4
#endif
#ifndef SAMPLES
	#define SAMPLES 1
#endif
#ifndef KERNEL
	#define KERNEL 3
#endif
#define KERNELF float(KERNEL)
#define GLOSS 10.0

uniform sampler2DMS texture0;//depth
uniform sampler2DMS texture1;//diffuse.rgba
uniform sampler2DMS texture2;//normal.xyz, diffuse.a
uniform sampler2DMS texture3;//specular, ao, flags, diffuse.a
uniform sampler2DMS texture4;//emission.rgb, diffuse.a
uniform sampler2DShadow texture5;//shadowmap

/* Possible future optimization:
uniform sampler2DMS texture0;//depth
uniform sampler2DMS texture1;//diffuse.rgba
uniform sampler2DMS texture2;//normal.xyz, specular
uniform sampler2DMS texture4;//emission.rgb, flags
*/

uniform vec4 ambientlight;
uniform vec2 buffersize;
uniform vec3 lightdirection;
uniform vec4 lightcolor;
uniform vec4 lightspecular;
uniform vec2 camerarange;
uniform float camerazoom;
uniform vec2[SHADOWSTAGES] lightshadowmapoffset;
uniform mat4 lightmatrix;
uniform mat3 lightnormalmatrix0;
uniform mat3 lightnormalmatrix1;
uniform mat3 lightnormalmatrix2;
uniform mat3 lightnormalmatrix3;
uniform float shadowmapsize;
uniform vec2 lightrange;
uniform vec3[SHADOWSTAGES] lightposition;
//uniform vec3 lightposition0;
//uniform vec3 lightposition1;
//uniform vec3 lightposition2;
//uniform vec3 lightposition3;
uniform float[SHADOWSTAGES] shadowstagearea;
uniform float[SHADOWSTAGES] shadowstagerange;
uniform bool isbackbuffer;

out vec4 fragData0;

float depthToPosition(in float depth, in vec2 depthrange)
{
	return depthrange.x / (depthrange.y - depth * (depthrange.y - depthrange.x)) * depthrange.y;
}

float shadowLookup(in sampler2DShadow shadowmap, in vec3 shadowcoord, in float offset)
{
	if (shadowcoord.y<0.0) return 0.5;
	if (shadowcoord.y>1.0) return 0.5;
	if (shadowcoord.x<0.0) return 0.5;
	if (shadowcoord.x>1.0) return 0.5;
	
	float f=0.0;
	int x,y;
	vec2 sampleoffset;

	for (x=0; x<KERNEL; ++x)
	{
		sampleoffset.x = float(x) - KERNELF*0.5 + 0.5;
		for (y=0; y<KERNEL; ++y)
		{
			sampleoffset.y = float(y) - KERNELF*0.5 + 0.5;
			f += texture(shadowmap,vec3(shadowcoord.x+sampleoffset.x*offset/SHADOWSTAGES,shadowcoord.y+sampleoffset.y*offset,shadowcoord.z));
		}
	}
	return f/(KERNEL*KERNEL);
}

void main(void)
{
	vec3 flipcoord = vec3(1.0);
	if (isbackbuffer) flipcoord.y = -1.0;

	//----------------------------------------------------------------------
	//Calculate screen texcoord
	//----------------------------------------------------------------------
	vec2 coord = gl_FragCoord.xy / buffersize;
	if (isbackbuffer) coord.y = 1.0 - coord.y;
	
	ivec2 icoord = ivec2(gl_FragCoord.xy);
	if (isbackbuffer) icoord.y = int(buffersize.y) - icoord.y;
	
	float depth;
	vec4 diffuse;
	vec3 normal;
	vec4 materialdata;
	float specularity;
	float ao;
	bool uselighting;
	vec4 emission;	
	vec4 sampleoutput;
	vec4 stagecolor;
	vec3 screencoord;
	vec3 screennormal;
	float attenuation;
	vec4 specular;
	vec3 lightreflection;
	float fade;
	vec3 shadowcoord;
	float dist;
	vec3 offset;
	mat3 lightnormalmatrix;
	int stage;
	vec3 lp;
	vec4 normaldata;
	int materialflags;
	
	fragData0 = vec4(0.0);

	for (int i=0; i<SAMPLES; i++)
	{
		//----------------------------------------------------------------------
		//Retrieve data from gbuffer
		//----------------------------------------------------------------------
		depth = 		texelFetch(texture0,icoord,i).x;
		diffuse = 		texelFetch(texture1,icoord,i);
		normaldata =		texelFetch(texture2,icoord,i);
		normal = 		normalize(normaldata.xyz*2.0-1.0);
		specularity =		normaldata.a;
		emission = 		texelFetch(texture3,icoord,i);
		materialflags = 	int(emission.a * 255.0 + 0.5);
		uselighting =		false;
		if ((1 & materialflags)!=0) uselighting=true;
		sampleoutput = 		diffuse + emission;
		stagecolor =		vec4(1.0,0.0,1.0,1.0);
		
		//----------------------------------------------------------------------
		//Calculate screen position and vector
		//----------------------------------------------------------------------
		screencoord = vec3(((gl_FragCoord.x/buffersize.x)-0.5) * 2.0 * (buffersize.x/buffersize.y),((-gl_FragCoord.y/buffersize.y)+0.5) * 2.0,depthToPosition(depth,camerarange));
		screencoord.x *= screencoord.z / camerazoom;
		screencoord.y *= -screencoord.z / camerazoom;
		screennormal = normalize(screencoord);
		if (!isbackbuffer) screencoord.y *= -1.0;
		
		if (uselighting)
		{
			//----------------------------------------------------------------------
			//Calculate lighting
			//----------------------------------------------------------------------		

			attenuation = max(0.0,-dot(lightdirection,normal));			
						
			lightreflection = normalize(reflect(lightdirection,normal));
			if (!isbackbuffer) lightreflection.y *= -1.0;
			specular = lightspecular * specularity * vec4( pow(clamp(-dot(lightreflection,screennormal),0.0,1.0),GLOSS) * 0.5);
			specular *= lightcolor.r * 0.299 + lightcolor.g * 0.587 + lightcolor.b * 0.114;

#ifdef USESHADOW
			fade=1.0;
			if (attenuation>LOWERLIGHTTHRESHHOLD)
			{
				//----------------------------------------------------------------------
				//Shadow lookup
				//----------------------------------------------------------------------
				dist = clamp(length(screencoord)/shadowstagerange[0],0.0,1.0);
				offset = vec3(0.0);
				//vec3 lightposition;
				lightnormalmatrix = mat3(0);
				stage=0;
				fade=1.0;
				lp = vec3(0);
				
				if (dist<1.0)
				{
					offset.x = 0.0;
					offset.z = -lightshadowmapoffset[0].x;
					lp = lightposition[0];
					lightnormalmatrix = lightnormalmatrix0;
					fade=0.0;
					stage=0;
					stagecolor=vec4(1.0,0.0,0.0,1.0);
				}
				else
				{
					//fade=0.0;
					dist = clamp(length(screencoord)/shadowstagerange[1],0.0,1.0);
					if (dist<1.0)
					{
						offset.x = 1.0;
						offset.z = -lightshadowmapoffset[1].x;
						lp = lightposition[1];
						lightnormalmatrix = lightnormalmatrix1;
						fade=0.0;
						stagecolor=vec4(0.0,1.0,0.0,1.0);
	#if SHADOWSTAGES==2
						fade = clamp((dist-0.75)/0.25,0.0,1.0);// gradually fade out the last shadow stage
	#endif
					}
	#if SHADOWSTAGES>2
					else
					{	
						dist = clamp(length(screencoord)/shadowstagerange[2],0.0,1.0);
						if (dist<1.0)
						{
							offset.x = 2.0;
							offset.z = -lightshadowmapoffset[2].x;
							lp = lightposition[2];
							lightnormalmatrix = lightnormalmatrix2;
							stagecolor=vec4(0.0,0.0,1.0,1.0);
							fade=0.0;
		#if SHADOWSTAGES==3
							fade = clamp((dist-0.75)/0.25,0.0,1.0);// gradually fade out the last shadow stage
		#endif
						}
		#if SHADOWSTAGES==4
						else
						{
							dist = clamp(length(screencoord)/shadowstagerange[3],0.0,1.0);
							if (dist<1.0)
							{
								stagecolor=vec4(0.0,1.0,1.0,1.0);
								offset.x = 3.0;
								offset.z = -lightshadowmapoffset[3].x;
								lp = lightposition[3];
								lightnormalmatrix = lightnormalmatrix3;
								fade = clamp((dist-0.75)/0.25,0.0,1.0);// gradually fade out the last shadow stage
							}
							else
							{
								fade = 1.0;
							}
						}
		#endif
					}
	#endif
				}
				if (fade<1.0)
				{
					shadowcoord = lightnormalmatrix * (screencoord - lp);
					shadowcoord += offset;
					shadowcoord.z = (shadowcoord.z - lightrange.x) / (lightrange.y-lightrange.x);	
					shadowcoord.xy += 0.5;
					shadowcoord.x /= SHADOWSTAGES;
					attenuation = attenuation * fade + attenuation * shadowLookup(texture5,shadowcoord,1.0/shadowmapsize) * (1.0-fade);
					//attenuation = shadowLookup(texture5,shadowcoord,1.0/shadowmapsize);
				}
			}
#endif			
			//----------------------------------------------------------------------
			//Final light calculation
			//----------------------------------------------------------------------
			sampleoutput = (diffuse * lightcolor + specular) * attenuation + emission + diffuse * ambientlight;
			//sampleoutput = stagecolor;//(sampleoutput + stagecolor) / 2.0;
		}
		//Blend with red if selected
		if ((2 & materialflags)!=0)
		{
			sampleoutput = (sampleoutput + vec4(1.0,0.0,0.0,0.0))/2.0;
		}
		fragData0 += sampleoutput * 1.0;
	}
	
	fragData0 /= float(SAMPLES);
	gl_FragDepth = depth;
}
