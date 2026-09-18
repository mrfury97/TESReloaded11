// Skin lighting helpers.
// Must not reference TESR_DebugVar: it carries whatever the Debug effect is set to.
#ifndef SKIN_FACEGEN_BLEND
    #define SKIN_FACEGEN_BLEND 1.0f      // 0 = raw base texture, 1 = full FaceGen complexion
#endif
#ifndef SKIN_SPECULAR_STRENGTH
    #define SKIN_SPECULAR_STRENGTH 0.0f   // 0 = vanilla (vanilla skin has no specular term)
#endif

float HalfLambert(float3 Vector1, float3 Vector2) {
	
	float product = dot(Vector1, Vector2);
	product *= 0.5;
	product += 0.5;
	return product;
	
}

float BlinnPhongSpecular(float3 Normal, float3 LightDir) {
	
	float3 halfAngle = Normal + LightDir;
	return pow(saturate(dot(Normal, halfAngle)), TESR_SkinData.y);
	
}

float3 Skin(float3 SkinColor, float3 LightColor, float3 CameraDir, float3 LightDir, float3 Normal) {

	float4 dotLN = HalfLambert(LightDir, Normal) * TESR_SkinData.x;
	float3 indirectLightComponent  = TESR_SkinData.z * max(0, dot(-Normal, LightDir));
	
	indirectLightComponent += TESR_SkinData.z * HalfLambert(-CameraDir, LightDir);
	indirectLightComponent *= TESR_SkinData.x;
	indirectLightComponent *= pow(SkinColor, 2);

	float3 rim = (float3)(1.0f - max(0.0f, dot(Normal, CameraDir)));
	rim = pow(rim, 3);
	rim *= max(0.0f, dot(Normal, LightDir)) * LightColor;
	rim *= TESR_SkinData.w;

	float4 finalCol = dotLN * 0.5 + float4(indirectLightComponent, 1.0f);

	finalCol.rgb += finalCol.a * TESR_SkinData.x * rim;
	finalCol.rgb += finalCol.a * TESR_SkinData.x * BlinnPhongSpecular(Normal, LightDir) * TESR_SkinColor.rgb * 0.05f;
	finalCol.rgb *= LightColor;
	
	return finalCol.rgb;
	
};


float3 GetLighting(float3 lightDirection, float3 eyeDirection, float3 normal, float3 lightColor){
    // Rim light effect: vanilla fresnel that shows when light is behind, now scaled by
    // RimScalar (TESR_SkinData.w) instead of a hardcoded 0.5 so it can be tuned or disabled.
    float fresnel = sqr(1 - shades(normal, eyeDirection)) * shades(lightDirection, -eyeDirection) * TESR_SkinData.w;

    // Wrap diffuse effect: softens the N.L falloff around the terminator to fake light
    // scattering under the skin. WrapDiffuse (TESR_SkinSSSData.w) of 0 reproduces the original
    // shades(normal, lightDirection) exactly; raising it pushes the falloff past 90 degrees.
    float wrap = TESR_SkinSSSData.w;
    float diffuse = saturate((dot(normal, lightDirection) + wrap) / (1 + wrap));

    float3 lighting = diffuse * lightColor + fresnel * lightColor;
    return max(lighting, 0);
}

float GetSpecular(float3 lightDirection, float3 eyeDirection, float3 normal, float3 lightColor){
    return  pow(shades(normal, normalize(lightDirection + eyeDirection)), TESR_SkinData.y) * luma(lightColor) * SKIN_SPECULAR_STRENGTH;
}

// Translucency effect: fast screen-space subsurface scattering (Barre-Brisebois & Bouchard,
// "Approximating Translucency for a Fast, Cheap and Convincing Subsurface Scattering Look",
// GDC 2011). There is no thickness map, so TranslucencyDistortion bends the light vector into the
// surface; when the eye ends up roughly facing the light back through the surface (ears, nose,
// fingers, a cheek backlit by the sun) light "leaks" through and picks up the skin's warm
// subsurface tint instead of just going dark. TranslucencyPower/TranslucencyScale (TESR_SkinSSSData)
// shape the glow's falloff and brightness; Attenuation/MaterialThickness (TESR_SkinData) scale its
// overall strength and tinted by TESR_SkinColor -- all from Shaders.Skin.Main in the settings TOML.
float3 GetSubsurfaceScattering(float3 lightDirection, float3 eyeDirection, float3 normal, float3 lightColor) {
    float3 scatterDir = lightDirection + normal * TESR_SkinSSSData.x; // TranslucencyDistortion
    float transmittance = pow(saturate(dot(eyeDirection, -scatterDir)), TESR_SkinSSSData.y) * TESR_SkinSSSData.z; // TranslucencyPower, TranslucencyScale
    transmittance *= TESR_SkinData.x * TESR_SkinData.z; // Attenuation * MaterialThickness

    return transmittance * TESR_SkinColor.rgb * lightColor;
}

float3 getNormal(float2 uv){
    return (expand(tex2D(NormalMap, uv).xyz));
}

// float2 getScreenpos(VS_INPUT IN){
//     return IN.position.xy * TESR_ReciprocalResolution.xy;
// };


float3 ApplyVertexColor(float3 baseColor, float3 vertexColor, float4 toggles){
   return toggles.x <= 0.0 ? baseColor : (baseColor.rgb * vertexColor); // apply vertex color
}

float3 ApplyFog(float3 baseColor, float4 fogColor, float4 toggles){
    return toggles.y <= 0.0 ? baseColor : ((fogColor.a * (fogColor.rgb - baseColor)) + baseColor);
}

float4 getBaseColor(float2 uv, sampler2D FaceGenMap0Buffer, sampler2D FaceGenMap1Buffer, sampler2D BaseColorBuffer){

    float3 faceGenMap0 = tex2D(FaceGenMap0Buffer, uv).rgb;
    float3 faceGenMap1 = tex2D(FaceGenMap1Buffer, uv).rgb;
    float4 baseTexture = tex2D(BaseColorBuffer, uv);
    float4 baseColor = float4(2 * ((expand(faceGenMap0) + baseTexture.rgb) * (2 * faceGenMap1)), baseTexture.a);

	baseColor = lerp(baseTexture, baseColor, SKIN_FACEGEN_BLEND);
    return baseColor;
}


float3 getPointLight(float3 LightDirection, float3 eyeDirection, float3 LightColor, float3 glowTexture, float3 normal, float Attenuation1, float Attenuation2){
    float4 SSScolor;
    SSScolor.rgb = lerp(LightColor, glowTexture, 0.5);

    float fresnel = sqr(1 - shades(normal, eyeDirection));
    //SSScolor.a = (AmbientColor.a >= 1 ? 0 : (baseColor.a - Toggles.w)); // alpha flag?

    float diffuse = dot(normal, LightDirection);
    float diffuse2 = saturate((diffuse + 0.3) * 0.769230783); // ?
    diffuse = saturate(diffuse);

    float3 pointLightContribution = saturate(((3 - diffuse2 * 2) * sqr(diffuse2)) - ((3 - (diffuse * 2)) * sqr(diffuse))) * glowTexture;
    pointLightContribution += diffuse * LightColor;
    pointLightContribution += fresnel * shades(eyeDirection, -LightDirection) * SSScolor.rgb;
    // clip(normal);

    return saturate((1 - Attenuation1) - Attenuation2) * pointLightContribution;
}
