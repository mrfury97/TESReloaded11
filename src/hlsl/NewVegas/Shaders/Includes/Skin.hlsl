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


// Direct diffuse. Wrap diffuse effect: softens the N.L falloff around the terminator to fake
// light scattering under the skin. WrapDiffuse (TESR_SkinSSSData.w) of 0 reproduces the original
// shades(normal, lightDirection) exactly; raising it pushes the falloff past 90 degrees.
// This is real N.L reflected light, so callers should still multiply it by any sun shadow term.
float3 GetDiffuse(float3 lightDirection, float3 normal, float3 lightColor){
    float wrap = TESR_SkinSSSData.w;
    float diffuse = saturate((dot(normal, lightDirection) + wrap) / (1 + wrap));
    return max(diffuse * lightColor, 0);
}

// Rim light effect: glows the side of the surface facing away from the light, scaled by
// RimScalar (TESR_SkinData.w). Deliberately takes NO eyeDirection: it depends only on the
// surface's normal vs. the light, so it reads the same regardless of which way the camera is
// looking, instead of only appearing when the camera itself happens to face the sun.
// Also NOT multiplied by a sun shadow term by callers: it represents light grazing/scattering
// around the silhouette rather than direct N.L reflection, and the surface point it lights up is
// almost always the same one a shadow map marks self-shadowed (the head occluding the ear from
// the sun). Gating it by that shadow term was a bug -- it silenced the rim glow in exactly the
// backlit condition it exists to show.
float3 GetRimLight(float3 lightDirection, float3 normal, float3 lightColor){
    float backlight = saturate(-dot(normal, lightDirection)) * TESR_SkinData.w;
    return max(backlight * lightColor, 0);
}

float GetSpecular(float3 lightDirection, float3 eyeDirection, float3 normal, float3 lightColor){
    return  pow(shades(normal, normalize(lightDirection + eyeDirection)), TESR_SkinData.y) * luma(lightColor) * SKIN_SPECULAR_STRENGTH;
}

// Translucency effect: fake subsurface scattering, adapted from the classic fast-SSS "backlight"
// look (Barre-Brisebois & Bouchard, GDC 2011) but made view-independent by design: it takes NO
// eyeDirection, only normal vs. light, so the warm glow on ears/nose/fingers/cheek shows up from
// ANY camera angle once that patch of surface faces away from the sun -- not only when the
// camera itself happens to face the sun too. There is no thickness map, so TranslucencyDistortion
// (TESR_SkinSSSData.x) offsets how far onto the LIT side the glow starts bleeding in before the
// true terminator (0 = starts exactly at the terminator). TranslucencyPower/TranslucencyScale
// shape the falloff and brightness; Attenuation/MaterialThickness (TESR_SkinData) scale its
// overall strength and tinted by TESR_SkinColor -- all from Shaders.Skin.Main in the settings TOML.
// Also NOT multiplied by a sun shadow term by callers, same reasoning as GetRimLight: this is
// light scattering through the surface, most visible exactly where a shadow map would call the
// point self-shadowed.
float3 GetSubsurfaceScattering(float3 lightDirection, float3 normal, float3 lightColor) {
    float ndotl = dot(normal, lightDirection);
    float transmittance = pow(saturate(TESR_SkinSSSData.x - ndotl), TESR_SkinSSSData.y) * TESR_SkinSSSData.z; // Distortion, Power, Scale
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
