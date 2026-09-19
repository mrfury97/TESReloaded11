// PBR calculations.
#if defined(__INTELLISENSE__)
    #include "Helpers.hlsl"
#endif

// Geometric specular AA
// http://www.jp.square-enix.com/tech/library/pdf/ImprovedGeometricSpecularAA.pdf
// https://www.jcgt.org/published/0010/02/02/paper.pdf
float SpecularAA(float3 normal, float roughness, float sigma, float kappa) {
    float SIGMA2 = 0.15915494;
    float KAPPA = 0.18;
    float3 dndu = ddx(normal);
    float3 dndv = ddy(normal);
    float variance = SIGMA2 * (dot(dndu, dndu) + dot(dndv, dndv));
    float kernel_roughness = min(KAPPA, variance);
    return sqrt(saturate(roughness * roughness + kernel_roughness));
}

// Fresnel
// Schlick approximation
float3 Fresnel(float3 f0, float3 f90, float cosine) {
    return f0 + (f90 - f0) * pow(1 - cosine, 5.f);
}

// Diffuse
float3 DisneyDiffuse(float3 albedo, float roughness, float NdotV, float NdotL, float LdotH) {
    const float linearRoughness = roughness * roughness;
    
    const float energyBias = lerp (0, 0.5 , linearRoughness);
    const float energyFactor = lerp (1.0, 1.0 / 1.51, linearRoughness);
    const float fd90 = energyBias + 2.0 * LdotH * LdotH * linearRoughness;
    const float3 f0 = float(1.0).xxx;
    const float lightScatter = Fresnel(f0, fd90, NdotL).r;
    const float viewScatter = Fresnel(f0, fd90, NdotV).r;

    return (albedo / PI) * lightScatter * viewScatter * energyFactor;
}

// Specular
// D (normal distribution function)
float GGX(float NdotH, float roughness) {
    float alpha = roughness * roughness;
    float a2 = pow(roughness, 4);
    float d = max((NdotH * a2 - NdotH) * NdotH + 1, 1e-5);
    return a2 / (PI * d * d);
}

// V (visibility = G / (4*NdotV*NdotL)), height-correlated Smith. Heitz 2014, "Understanding the
// Masking-Shadowing Function in Microfacet-Based BRDFs"; this formulation as used in Filament
// (https://google.github.io/filament/Filament.html#materialsystem/specularbrdf/geometricshadowing(specularg)).
// Replaces a separable Schlick-Beckmann G1(V)*G1(L): height-correlation is physically correct
// (a microfacet visible to the eye is more likely visible to the light too, since taller facets
// occlude both), and this form folds the BRDF's 4*NdotV*NdotL denominator straight in rather
// than dividing by it separately afterward, avoiding a second near-zero denominator at grazing
// angles.
float VisibilitySmithGGXCorrelated(float roughness, float NdotV, float NdotL) {
    float a2 = pow(roughness, 4);
    float GGXV = NdotL * sqrt(NdotV * NdotV * (1 - a2) + a2);
    float GGXL = NdotV * sqrt(NdotL * NdotL * (1 - a2) + a2);
    return 0.5 / max(GGXV + GGXL, 1e-5);
}

// F
float3 FresnelShlick(float3 reflectance, float3 halfway, float3 eyeDir) {
    return reflectance + (1 - reflectance) * pow(1 - shades(halfway, eyeDir), 5.0);
}

// BRDF
float3 BRDF(float roughness, float3 fresnel, float NdotV, float NdotL, float NdotH){
    float D = GGX(NdotH, roughness);
    float V = VisibilitySmithGGXCorrelated(roughness, NdotV, NdotL);
    return D * V * fresnel;
}

float3 PBRDiffuse(float metallicness, float roughness, float3 albedo, float3 normal, float3 eyeDir, float3 lightDir, float3 lightColor) {
    normal = normalize(normal);
    lightDir = normalize(lightDir);

    const float NdotL = shades(normal, lightDir);

    // No Fresnel. These permutations render no specular lobe, so energy taken out of diffuse
    // has nowhere to reappear -- PBRSun returns it as spec * NdotS, this path just loses it.
    // (1 - LdotH)^5 then drives the surface to black as eyeDir approaches -lightDir, where
    // normalize(eyeDir + lightDir) is singular besides. Dropping the term removes the last
    // view dependence, which is what a purely Lambertian material should have.
    const float3 diffuse = (1 - metallicness) * albedo / PI;

    return diffuse * NdotL * lightColor * PI;
}

float3 PBRSpecular(float metallicness, float roughness, float3 albedo, float3 normal, float3 eyeDir, float3 lightDir, float3 lightColor) {
    const float3 reflectance = lerp(float(0.04).rrr, albedo, metallicness);
    
    normal = normalize(normal);
    eyeDir = normalize(eyeDir);
    lightDir = normalize(lightDir);
    
    const float3 halfway = normalize(eyeDir + lightDir);
    const float NdotL = max(shades(normal, lightDir), 0.00001);
    const float NdotV = max(shades(normal, eyeDir), 0.00001);
    const float NdotH = shades(normal, halfway);
    const float LdotH = shades(lightDir, halfway);

    const float3 fresnel = Fresnel(reflectance, (1.0).xxx, LdotH);
    
    const float3 spec = BRDF(roughness, fresnel, NdotV, NdotL, NdotH);

    return spec * NdotL * lightColor * PI;
}

float3 PBR(float metallicness, float roughness, float3 albedo, float3 normal, float3 eyeDir, float3 lightDir, float3 lightColor) {
    const float3 reflectance = lerp(float(0.04).rrr, albedo, metallicness);
    
    normal = normalize(normal);
    eyeDir = normalize(eyeDir);
    lightDir = normalize(lightDir);
    
    const float3 halfway = normalize(eyeDir + lightDir);
    const float NdotL = max(shades(normal, lightDir), 0.00001);
    const float NdotV = max(shades(normal, eyeDir), 0.00001);
    const float NdotH = shades(normal, halfway);
    const float LdotH = shades(lightDir, halfway);

    const float3 fresnel = Fresnel(reflectance, (1.0).xxx, LdotH);

    const float3 diffuse = (1 - metallicness) * DisneyDiffuse(albedo, roughness, NdotV, NdotL, LdotH);

    const float3 spec = BRDF(roughness, fresnel, NdotV, NdotL, NdotH);

    return (diffuse + spec) * NdotL * lightColor * PI;
}

#define SUN_RADIUS 0.00918043

float3 PBRSunSpecular(float metallicness, float roughness, float3 albedo, float3 normal, float3 eyeDir, float3 lightDir, float3 lightColor) {
    const float3 reflectance = lerp(float(0.04).rrr, albedo, metallicness);
    
    normal = normalize(normal);
    eyeDir = normalize(eyeDir);
    lightDir = normalize(lightDir);
    
    const float3 reflectDir = reflect(lightDir, normal);

    const float radius = sin(SUN_RADIUS);
    const float dist = cos(SUN_RADIUS);
    
    const float3 LdotR = dot(lightDir, reflectDir);
    const float3 closestPoint = reflectDir - LdotR * lightDir;
    const float3 sunDir = LdotR < dist ? normalize(dist * lightDir + normalize(closestPoint) * radius) : reflectDir;
    
    const float3 halfway = normalize(eyeDir + sunDir);
    const float NdotS = max(shades(normal, sunDir), 0.00001);
    const float NdotV = max(shades(normal, eyeDir), 0.00001);
    const float NdotH = shades(normal, halfway);
    const float NdotL = shades(normal, lightDir);
    const float LdotH = shades(lightDir, halfway);

    const float3 fresnel = Fresnel(reflectance, (1.0).xxx, LdotH);
    
    const float3 spec = BRDF(roughness, fresnel, NdotV, NdotS, NdotH);

    return spec * NdotS * lightColor * PI;
}

float3 PBRSun(float metallicness, float roughness, float3 albedo, float3 normal, float3 eyeDir, float3 lightDir, float3 lightColor) {
    const float3 reflectance = lerp(float(0.04).rrr, albedo, metallicness);
    
    normal = normalize(normal);
    eyeDir = normalize(eyeDir);
    lightDir = normalize(lightDir);
    
    const float3 reflectDir = reflect(lightDir, normal);

    const float radius = sin(SUN_RADIUS);
    const float dist = cos(SUN_RADIUS);
    
    const float3 LdotR = dot(lightDir, reflectDir);
    const float3 closestPoint = reflectDir - LdotR * lightDir;
    const float3 sunDir = LdotR < dist ? normalize(dist * lightDir + normalize(closestPoint) * radius) : reflectDir;
    
    const float3 halfway = normalize(eyeDir + sunDir);
    const float NdotS = max(shades(normal, sunDir), 0.00001);
    const float NdotV = max(shades(normal, eyeDir), 0.00001);
    const float NdotH = shades(normal, halfway);
    const float NdotL = shades(normal, lightDir);
    const float LdotH = shades(lightDir, halfway);

    const float3 fresnel = Fresnel(reflectance, (1.0).xxx, LdotH);

    const float3 diffuse = (1 - metallicness) * DisneyDiffuse(albedo, roughness, NdotV, NdotL, LdotH);

    const float3 spec = BRDF(roughness, fresnel, NdotV, NdotS, NdotH);

    return (diffuse * NdotL + spec * NdotS) * lightColor * PI;
}
