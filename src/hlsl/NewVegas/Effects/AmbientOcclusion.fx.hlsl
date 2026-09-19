// Ambient Occlusion fullscreen shader for Oblivion/Skyrim Reloaded

#define viewao 0
#define halfres 0
#define GTAO_MAX_STEPS 8 // upper bound for the runtime Steps slider's dynamic loop

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

static const float AOsteps = TESR_AmbientOcclusionAOData.x; // horizon-search steps per slice, runtime-tunable
static const float AOstrength = TESR_AmbientOcclusionAOData.y;
static const float AOclamp = TESR_AmbientOcclusionAOData.z;
static const float AOrange = TESR_AmbientOcclusionAOData.w;
static const float AOfalloff = TESR_AmbientOcclusionData.x; // softness of the Range cutoff: 0 hard, higher softer
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

// Ground Truth AO (Jimenez et al. 2016, "Practical Realtime Strategies for
// Accurate Indirect Occlusion"). Closed-form integral of cosine-weighted
// visibility over the arc between horizon angles h1/h2 (measured from V,
// clamped to n +/- 90deg) around the in-slice angle n of the surface normal.
float IntegrateArc(float h1, float h2, float n) {
	float cosN = cos(n);
	float a = -cos(2.0 * h1 - n) + cosN + 2.0 * h1 * sin(n);
	float b = -cos(2.0 * h2 - n) + cosN + 2.0 * h2 * sin(n);
	return 0.25 * (a + b);
}

// pass2: 0 on the first pass (resets the accumulator), 1 on the second
// (chains onto the first pass's result the same way the old kernel-split
// SSAO did) -- also offsets the second pass's slice angle ~90deg from the
// first so the two passes average two roughly-perpendicular slices.
float4 GTAO(VSOUT IN, uniform float pass2) : COLOR0
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
	float3 V = normalize(-P); // view-space direction from the surface to the camera

	float noise = random(uv).x;
	float sliceAngle = (pass2 * 0.5 + noise * 0.5) * PI;
	float2 sliceDir = float2(cos(sliceAngle), sin(sliceAngle));
	float3 sliceDir3 = float3(sliceDir, 0.0);

	// in-slice-plane basis: V is the "zenith" (angle 0), orthoDir the horizon
	// direction the +side march walks toward.
	float3 orthoDir = sliceDir3 - V * dot(sliceDir3, V);
	float orthoLen = length(orthoDir);
	if (orthoLen < 1e-4) return 1.0; // slice plane degenerate at this pixel
	orthoDir /= orthoLen;

	// project N into the slice plane; its remaining length is how much this
	// slice actually contributes (a slice edge-on to N contributes ~0)
	float3 planeNormal = cross(sliceDir3, V);
	float3 projN = N - planeNormal * dot(N, planeNormal);
	float projNLen = max(length(projN), 1e-4);
	float n = atan2(dot(projN, orthoDir), dot(projN, V));

	float uRadius = abs(AOrange);
	float h1 = -PI / 2.0; // furthest occluder found on the +orthoDir side
	float h2 = PI / 2.0;  // furthest occluder found on the -orthoDir side

	// Steps is runtime-tunable (not [unroll]'d -- ps_3_0 supports a dynamic
	// trip count), clamped so a stray large value can't blow the shader's
	// instruction budget.
	int steps = clamp((int)AOsteps, 1, GTAO_MAX_STEPS);
	float radiusSq = uRadius * uRadius;
	float falloff = max(AOfalloff, 0.0);

	for (int step = 1; step <= steps; ++step) {
		float t = (step + noise) / steps;

		// March the actual view-space sample point along the slice direction
		// and reproject it, instead of stepping uv by a fixed amount -- a
		// fixed uv-space step covers a wildly different world-space distance
		// depending on depth (perspective foreshortening), which produced a
		// flat, depth-banded dark patch instead of real contact occlusion.
		// This mirrors how the old kernel SSAO placed its samples.

		// Falloff softens the hard Range cutoff: a sample's pull on the
		// horizon angle is weighted down as it nears uRadius instead of
		// being an all-or-nothing cutoff. falloff=0 reproduces a hard
		// cutoff (weight is 1 everywhere inside the radius, same as the
		// old range check); higher values taper it off more gradually.
		float2 sampleUV1 = projectPosition(P + sliceDir3 * t * uRadius).xy;
		float3 hv1 = reconstructPosition(sampleUV1) - P;
		float d1 = dot(hv1, hv1);
		if (d1 < radiusSq) {
			float a1 = atan2(dot(hv1, orthoDir), dot(hv1, V));
			float w1 = pow(saturate(1.0 - d1 / radiusSq), falloff);
			h1 = max(h1, lerp(h1, a1, w1));
		}

		float2 sampleUV2 = projectPosition(P - sliceDir3 * t * uRadius).xy;
		float3 hv2 = reconstructPosition(sampleUV2) - P;
		float d2 = dot(hv2, hv2);
		if (d2 < radiusSq) {
			float a2 = atan2(dot(hv2, orthoDir), dot(hv2, V));
			float w2 = pow(saturate(1.0 - d2 / radiusSq), falloff);
			h2 = min(h2, lerp(h2, a2, w2));
		}
	}

	h1 = n + clamp(h1 - n, -PI / 2.0, PI / 2.0);
	h2 = n + clamp(h2 - n, -PI / 2.0, PI / 2.0);

	float visibility = IntegrateArc(h1, h2, n) * projNLen;
	float occlusion = 1.0 - saturate(visibility) * AOstrength;

	float fogColor = luma(TESR_FogColor.rgb);
	float darkness = clamp(lerp(occlusion, fogColor, fogCoeff(P.z)), occlusion, 1.0);

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
		PixelShader = compile ps_3_0 GTAO(0.0);
	}

	pass
	{
		VertexShader = compile vs_3_0 FrameVS();
		PixelShader = compile ps_3_0 GTAO(1.0);
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