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
    float fresnel = sqr(1 - shades(normal, eyeDirection)) * shades(lightDirection, -eyeDirection) * 0.5; // vanilla fresnel that shows when light is behind

    // float fresnelCoeff = pows(1 - shades(normal, eyeDir), 5);
    float diffuse = shades(normal, lightDirection);
    // float3 fresnel = fresnelCoeff * lightColor * 0.5 * pow(diffuse, TESR_DebugVar.w);
    float3 lighting = diffuse * lightColor + fresnel * lightColor;
    return max(lighting, 0);
}

float GetSpecular(float3 lightDirection, float3 eyeDirection, float3 normal, float3 lightColor){
    return  pow(shades(normal, normalize(lightDirection + eyeDirection)), TESR_SkinData.y) * luma(lightColor) * SKIN_SPECULAR_STRENGTH;
}

// Skin translucency: subsurface light wrapping around the terminator. Physically, thin tissue
// (nose, ears, cheek edges) lets a little sunlight bleed a short distance past the geometric
// light/dark line instead of cutting off sharply, and that bled light picks up the skin's warm
// subsurface colour. Modelled as a band straddling N.L = 0 (TranslucencyWidth wide either side),
// not a full backlit-hemisphere glow -- so it stays physically coherent with the forward shadow
// system: an object actually blocking the sun should suppress it same as direct light, since
// there is no nearby sunlight left to scatter through. View-independent (normal vs. light only),
// so it reads the same from any camera angle.
//
// Callers should scale the result by TranslucencyShadowInfluence, a caller-visible knob (this
// function does not read TESR_ShadowData itself: see each SKIN*.pso.hlsl's sunShadow handling)
// letting the sun-shadow multiply be dialled from 0 (translucency ignores shadows) to 1 (fully
// gated like diffuse), since how much that trade-off matters depends on shadow map resolution
// and how much of this band ends up flagged self-shadowed near grazing angles.
float3 GetSkinTranslucency(float3 lightDirection, float3 normal, float3 lightColor) {
    float ndotl = dot(normal, lightDirection);
    float width = max(TESR_SkinSSSData.x, 0.001f); // TranslucencyWidth
    float band = saturate(1 - abs(ndotl) / width);
    float translucency = pow(band, TESR_SkinSSSData.y) * TESR_SkinSSSData.z; // Power, Scale
    translucency *= TESR_SkinData.x * TESR_SkinData.z; // Attenuation * MaterialThickness

    return translucency * TESR_SkinColor.rgb * lightColor;
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
