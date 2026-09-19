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
// Lambert
float3 LambertianDiffuse(float3 albedo, float3 fresnel) {
    return (1 - fresnel) * albedo / PI;
}

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

// G1
float ShlickBeckmann(float NdotX, float roughness) {
    float k = pow(roughness + 1, 2) / 8.0;
    return NdotX/max(NdotX * (1 - k) + k, 0.00000001);
}

// Smith
float GeometryShadowing(float roughness, float NdotV, float NdotL) {
    return ShlickBeckmann(NdotV, roughness) * ShlickBeckmann(NdotL, roughness);
}

// F
float3 FresnelShlick(float3 reflectance, float3 halfway, float3 eyeDir) {
    return reflectance + (1 - reflectance) * pow(1 - shades(halfway, eyeDir), 5.0);
}

// BRDF
float3 BRDF(float roughness, float3 fresnel, float NdotV, float NdotL, float NdotH){
    float3 num = GGX(NdotH, roughness) * GeometryShadowing(roughness, NdotV, NdotL) * fresnel;
    float denom = 4.0 * NdotV * NdotL;
    return num/denom;
}

// Clearcoat: a second, independent GGX specular lobe representing a thin glossy top coat
// (varnish/wax/wet-look finish) layered over the base material -- common on leather, painted
// metal, and coated fabric. Always dielectric (fixed F0 = 0.04, the standard value for a clear
// polyurethane-like coating at normal incidence) regardless of the base material's own
// metallicness/albedo -- a clear coat has no pigment of its own to tint or absorb into -- and
// driven by its own roughness rather than the base layer's, since a coat is typically much
// smoother than what's underneath it. Purely additive: does not attenuate the base layer, so
// strength = 0 is an exact no-op, and reuses BRDF() (same D/G/Fresnel as the base lobe) rather
// than a separate implementation.
float3 ClearcoatSpecular(float3 normal, float3 eyeDir, float3 lightDir, float3 lightColor, float roughness, float strength) {
    normal = normalize(normal);
    eyeDir = normalize(eyeDir);
    lightDir = normalize(lightDir);

    const float3 halfway = normalize(eyeDir + lightDir);
    const float NdotL = max(shades(normal, lightDir), 0.00001);
    const float NdotV = max(shades(normal, eyeDir), 0.00001);
    const float NdotH = shades(normal, halfway);
    const float LdotH = shades(lightDir, halfway);

    const float3 fresnel = Fresnel(float(0.04).rrr, (1.0).xxx, LdotH);
    const float3 spec = BRDF(roughness, fresnel, NdotV, NdotL, NdotH);

    return spec * NdotL * lightColor * PI * strength;
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

float3 PBRSpecular(float metallicness, float roughness, float3 albedo, float3 normal, float3 eyeDir, float3 lightDir, float3 lightColor, float clearcoatRoughness = 0.0, float clearcoatStrength = 0.0) {
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
    const float3 clearcoat = ClearcoatSpecular(normal, eyeDir, lightDir, lightColor, clearcoatRoughness, clearcoatStrength);

    return spec * NdotL * lightColor * PI + clearcoat;
}

float3 PBR(float metallicness, float roughness, float3 albedo, float3 normal, float3 eyeDir, float3 lightDir, float3 lightColor, float clearcoatRoughness = 0.0, float clearcoatStrength = 0.0) {
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

    const float3 diffuse = (1 - metallicness) * LambertianDiffuse(albedo, fresnel);

    const float3 spec = BRDF(roughness, fresnel, NdotV, NdotL, NdotH);
    const float3 clearcoat = ClearcoatSpecular(normal, eyeDir, lightDir, lightColor, clearcoatRoughness, clearcoatStrength);

    return (diffuse + spec) * NdotL * lightColor * PI + clearcoat;
}

#define SUN_RADIUS 0.00918043

float3 PBRSunSpecular(float metallicness, float roughness, float3 albedo, float3 normal, float3 eyeDir, float3 lightDir, float3 lightColor, float clearcoatRoughness = 0.0, float clearcoatStrength = 0.0) {
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
    // sunDir (disc-widened), not lightDir: a near-mirror clearcoat evaluated against the raw
    // point-light sun direction would only catch the highlight at one exact pixel, same reason
    // the base lobe above widens it.
    const float3 clearcoat = ClearcoatSpecular(normal, eyeDir, sunDir, lightColor, clearcoatRoughness, clearcoatStrength);

    return spec * NdotS * lightColor * PI + clearcoat;
}

float3 PBRSun(float metallicness, float roughness, float3 albedo, float3 normal, float3 eyeDir, float3 lightDir, float3 lightColor, float clearcoatRoughness = 0.0, float clearcoatStrength = 0.0) {
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

    const float3 diffuse = (1 - metallicness) * LambertianDiffuse(albedo, fresnel);

    const float3 spec = BRDF(roughness, fresnel, NdotV, NdotS, NdotH);
    // sunDir (disc-widened), not lightDir -- see PBRSunSpecular above.
    const float3 clearcoat = ClearcoatSpecular(normal, eyeDir, sunDir, lightColor, clearcoatRoughness, clearcoatStrength);

    return (diffuse * NdotL + spec * NdotS) * lightColor * PI + clearcoat;
}
