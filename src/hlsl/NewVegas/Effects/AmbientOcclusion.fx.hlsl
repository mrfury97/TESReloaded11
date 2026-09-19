// Ambient Occlusion fullscreen shader for Oblivion/Skyrim Reloaded

#define viewao 0
#define halfres 0
#define HBAO_MAX_STEPS 8 // upper bound for the runtime Steps slider's dynamic loop

float4 TESR_AmbientOcclusionAOData;
float4 TESR_AmbientOcclusionData;
float4 TESR_ReciprocalResolution;
float4 TESR_FogData; // x: fog start, y: fog end, z: sun glare, w: fog power
float4 TESR_FogColor;

sampler2D TESR_RenderedBuffer : register(s0) = sampler_state { ADDRESSU = CLAMP; ADDRESSV = CLAMP; MAGFILTER = LINEAR; MINFILTER = LINEAR; MIPFILTER = LINEAR; };
sampler2D TESR_DepthBuffer : register(s1) = sampler_state { ADDRESSU = CLAMP; ADDRESSV = CLAMP; MAGFILTER = LINEAR; MINFILTER = LINEAR; MIPFILTER = LINEAR; };
sampler2D TESR_SourceBuffer : register(s2) = sampler_state { ADDRESSU = CLAMP; ADDRESSV = CLAMP; MAGFILTER = LINEAR; MINFILTER = LINEAR; MIPFILTER = LINEAR; };
sampler2D TESR_BlueNoiseSampler : register(s3) < string ResourceName = "Effects\bluenoise256.dds"; > = sampler_state { ADDRESSU = WRAP; ADDRESSV = WRAP; MAGFILTER = NONE; MINFILTER = NONE; MIPFILTER = NONE; };
sampler2D TESR_NormalsBuffer : register(s4) = sampler_state { ADDRESSU = CLAMP; ADDRESSV = CLAMP; MAGFILTER = NONE; MINFILTER = NONE; MIPFILTER = NONE; };

static const float AOsteps = TESR_AmbientOcclusionAOData.x; // horizon-search steps per side, runtime-tunable
static const float AOstrength = TESR_AmbientOcclusionAOData.y;
static const float AOclamp = TESR_AmbientOcclusionAOData.z;
static const float AOrange = TESR_AmbientOcclusionAOData.w;
static const float AObias = TESR_AmbientOcclusionData.x; // dot-product bias against self-occlusion acne
static const float AOlumThreshold = TESR_AmbientOcclusionData.y;
static const float blurDrop = TESR_AmbientOcclusionData.z;
static const float blurRadius = TESR_AmbientOcclusionData.w;
static const int startFade = 2000;
static const int endFade = 8000;
static const float2 io = float2(1.0f, 0.0f);
 
struct VSOUT
{
	float4 vertPos : POSITION;
	float2 UVCoord : TEXCOORD0;
};
 
struct VSIN
{
	float4 vertPos : POSITION0;
	float2 UVCoord : TEXCOORD0;
};
 
VSOUT FrameVS(VSIN IN)
{
	VSOUT OUT = (VSOUT)0.0f;
	OUT.vertPos = IN.vertPos;
	OUT.UVCoord = IN.UVCoord;
	return OUT;
}
 
#include "Includes/Depth.hlsl"
#include "Includes/BlurDepth.hlsl"
#include "Includes/Helpers.hlsl"
#include "Includes/Normals.hlsl"


// returns a semi random float3 between 0 and 1 based on the given seed.
// tailored to return a different value for each uv coord of the screen.
float3 random(float2 seed)
{
	return tex2D(TESR_BlueNoiseSampler, (seed/256 + 0.5) / TESR_ReciprocalResolution.xy).xyz;
}

float fogCoeff(float depth){
	return saturate(invlerp(TESR_FogData.x, TESR_FogData.y, depth));
}

// Horizon-based AO (Bavoil/Sainz/Dimitrov 2008), per-sample occlusion via the
// classic dot(N, sampleDir) - bias estimator (as in John Chapman's widely-
// used HBAO writeup) rather than a closed-form angular integral -- simpler
// and far fewer places for a sign/convention mistake to hide than GTAO's
// arc integral, which produced two separate visible artifacts in testing.
float4 HBAO(VSOUT IN, uniform float pass2) : COLOR0
{
	float2 uv = IN.UVCoord.xy;
	float4 color = tex2D(TESR_RenderedBuffer, uv);
	color = pass2 ? color : float(1).xxxx; // use previous rendered buffer if not first pass

#if halfres
	clip ((IN.UVCoord.x < 0.5 && IN.UVCoord.y < 0.5)-1); // discard half the screen to render at half resolution
	uv *= 2;
#endif

	float3 P = reconstructPosition(uv);
	if (P.z > endFade) return 1.0;

	float3 N = GetNormal(uv);

	// One search direction per pass (two passes chain into the same buffer,
	// same structure the old kernel SSAO used), jittered per pixel so the
	// pattern doesn't band; both +dir and -dir are marched below.
	float noise = random(uv).x;
	float dirAngle = (pass2 * 0.5 + noise * 0.5) * PI;
	float3 dir3 = float3(cos(dirAngle), sin(dirAngle), 0.0);

	float uRadius = abs(AOrange);
	float radiusSq = uRadius * uRadius;
	float bias = saturate(AObias);

	// Steps is runtime-tunable (not [unroll]'d -- ps_3_0 supports a dynamic
	// trip count), clamped so a stray large value can't blow the shader's
	// instruction budget.
	int steps = clamp((int)AOsteps, 1, HBAO_MAX_STEPS);

	float occlusion = 0.0;
	[unroll]
	for (int side = -1; side <= 1; side += 2) {
		for (int step = 1; step <= steps; ++step) {
			float t = (step + noise) / steps;

			// March the actual view-space sample point and reproject it
			// (rather than stepping uv directly), so the search radius is a
			// real world-space distance regardless of depth/perspective.
			float2 sampleUV = projectPosition(P + side * dir3 * t * uRadius).xy;
			float3 S = reconstructPosition(sampleUV);
			float3 hv = S - P;
			float d2 = dot(hv, hv);

			if (d2 > 1e-6 && d2 < radiusSq) {
				float ndotv = dot(N, hv * rsqrt(d2));
				float falloff = saturate(1.0 - d2 / radiusSq); // fade out near the Range edge
				occlusion += saturate(ndotv - bias) * falloff;
			}
		}
	}

	occlusion = saturate(occlusion / (2 * steps) * AOstrength);
	float visibility = 1.0 - occlusion;

	float fogColor = luma(TESR_FogColor.rgb);
	float darkness = clamp(lerp(visibility, fogColor, fogCoeff(P.z)), visibility, 1.0);

	darkness = lerp(darkness, 1.0, saturate(invlerp(startFade, endFade, P.z))) * color.x;

	return float2(darkness, 1.0).xxxy;
}

float4 Expand(VSOUT IN) : COLOR0
{
	float2 coord = IN.UVCoord * 0.5;
	return tex2D(TESR_RenderedBuffer, coord);
}

float4 Combine(VSOUT IN) : COLOR0
{
	float3 color = tex2D(TESR_SourceBuffer, IN.UVCoord).rgb;
	color = pows(color,2.2); // linearise
	float ao = lerp(AOclamp, 1.0, tex2D(TESR_RenderedBuffer, IN.UVCoord).r);

	float luminance = luma(color);
	float lt = luminance - AOlumThreshold;
	luminance = saturate(lt * 3.0);
	ao = lerp(ao, 1.0, luminance);
	color *= ao;

    #if viewao
		return float4(ao, ao, ao, 1.0f);
	#endif
	
	color.rgb = pows(color.rgb,1.0/2.2); // delinearise
	return float4(color.rgb, 1.0f);
}
 

// perform depth aware 12 taps blur along the direction of the offsetmask
float4 NormalBlurRChannel(VSOUT IN, uniform float2 OffsetMask, uniform float blurRadius,uniform float depthDrop,uniform float endFade) : COLOR0
{
	float WeightSum = 0.114725602f;
	float4 color1 = tex2D(TESR_RenderedBuffer, IN.UVCoord) * WeightSum;
	float3 normal = GetNormal(IN.UVCoord);
	float depth = tex2D(TESR_DepthBuffer, IN.UVCoord).y;
	
    if (invertedDepth) {
        depth = 1 - depth;
    }

    float depth1 = readDepth(IN.UVCoord);
	clip(endFade - depth1);

	// coeff for blurring to increase blur depthDrop on surfaces facing away from the camera
	float normalCoeff = (0.5 + 2 * compress(dot(normal, float3(0, 0, 1))));

    for (int i = 0; i < cKernelSize; i++)
    {
		float2 uvOff = (BlurOffsets[i] * OffsetMask) * blurRadius/depth;
		float4 color2 = tex2D(TESR_RenderedBuffer, IN.UVCoord + uvOff).r;
		float depth2 = readDepth(IN.UVCoord + uvOff);
		float3 normal2 = GetNormal(IN.UVCoord + uvOff);

		float diff = abs(depth1 - depth2);

		int useForBlur = (diff <= depthDrop * normalCoeff);
		color1.r += BlurWeights[i] * color2.r * useForBlur;
		WeightSum += BlurWeights[i] * useForBlur;
    }
	
	color1.r /= WeightSum;
    return float4(color1.rgb, 1);
}


technique
{
	pass
	{
		VertexShader = compile vs_3_0 FrameVS();
		PixelShader = compile ps_3_0 HBAO(0.0);
	}

	pass
	{
		VertexShader = compile vs_3_0 FrameVS();
		PixelShader = compile ps_3_0 HBAO(1.0);
	}

#if halfres
	pass
	{
		VertexShader = compile vs_3_0 FrameVS();
		PixelShader = compile ps_3_0 Expand();
	}
#endif
	
	pass
	{ 
		VertexShader = compile vs_3_0 FrameVS();
		PixelShader = compile ps_3_0 NormalBlurRChannel(io.xy, blurRadius, blurDrop, endFade);
	}
	
	pass
	{ 
		VertexShader = compile vs_3_0 FrameVS();
		PixelShader = compile ps_3_0 NormalBlurRChannel(io.yx, blurRadius, blurDrop, endFade);
	}
	
	pass
	{
		VertexShader = compile vs_3_0 FrameVS();
		PixelShader = compile ps_3_0 Combine();
	}
}