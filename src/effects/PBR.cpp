#include "PBR.h"

void PBRShaders::RegisterConstants() {
	TheShaderManager->RegisterConstant("TESR_PBRData", &Constants.Data);
	TheShaderManager->RegisterConstant("TESR_PBRExtraData", &Constants.ExtraData);
}


void PBRShaders::UpdateSettings() {
	Settings.Default.Saturation = TheSettingManager->GetSettingF("Shaders.PBR.Main", "Saturation");
	Settings.Default.Metallicness = TheSettingManager->GetSettingF("Shaders.PBR.Main", "Metallicness");
	Settings.Default.Roughness = TheSettingManager->GetSettingF("Shaders.PBR.Main", "Roughness");
	Settings.Default.LightScale = TheSettingManager->GetSettingF("Shaders.PBR.Main", "LightingScale");
	Settings.Default.AmbientScale = TheSettingManager->GetSettingF("Shaders.PBR.Main", "AmbientScale");
	Settings.Default.SkylightingScale = TheSettingManager->GetSettingF("Shaders.PBR.Main", "SkylightingScale");
	Settings.Default.SkylightingDirectionality = TheSettingManager->GetSettingF("Shaders.PBR.Main", "SkylightingDirectionality");
	Settings.Default.AmbientDirectionality = TheSettingManager->GetSettingF("Shaders.PBR.Main", "AmbientDirectionality");

	Settings.Rain.Saturation = TheSettingManager->GetSettingF("Shaders.PBR.Rain", "Saturation");
	Settings.Rain.Metallicness = TheSettingManager->GetSettingF("Shaders.PBR.Rain", "Metallicness");
	Settings.Rain.Roughness = TheSettingManager->GetSettingF("Shaders.PBR.Rain", "Roughness");
	Settings.Rain.LightScale = TheSettingManager->GetSettingF("Shaders.PBR.Rain", "LightingScale");
	Settings.Rain.AmbientScale = TheSettingManager->GetSettingF("Shaders.PBR.Rain", "AmbientScale");
	Settings.Rain.SkylightingScale = TheSettingManager->GetSettingF("Shaders.PBR.Rain", "SkylightingScale");
	Settings.Rain.SkylightingDirectionality = TheSettingManager->GetSettingF("Shaders.PBR.Rain", "SkylightingDirectionality");
	Settings.Rain.AmbientDirectionality = TheSettingManager->GetSettingF("Shaders.PBR.Rain", "AmbientDirectionality");

	Settings.Night.Saturation = TheSettingManager->GetSettingF("Shaders.PBR.Night", "Saturation");
	Settings.Night.Metallicness = TheSettingManager->GetSettingF("Shaders.PBR.Night", "Metallicness");
	Settings.Night.Roughness = TheSettingManager->GetSettingF("Shaders.PBR.Night", "Roughness");
	Settings.Night.LightScale = TheSettingManager->GetSettingF("Shaders.PBR.Night", "LightingScale");
	Settings.Night.AmbientScale = TheSettingManager->GetSettingF("Shaders.PBR.Night", "AmbientScale");
	Settings.Night.SkylightingScale = TheSettingManager->GetSettingF("Shaders.PBR.Night", "SkylightingScale");
	Settings.Night.SkylightingDirectionality = TheSettingManager->GetSettingF("Shaders.PBR.Night", "SkylightingDirectionality");
	Settings.Night.AmbientDirectionality = TheSettingManager->GetSettingF("Shaders.PBR.Night", "AmbientDirectionality");

	Settings.NightRain.Saturation = TheSettingManager->GetSettingF("Shaders.PBR.NightRain", "Saturation");
	Settings.NightRain.Metallicness = TheSettingManager->GetSettingF("Shaders.PBR.NightRain", "Metallicness");
	Settings.NightRain.Roughness = TheSettingManager->GetSettingF("Shaders.PBR.NightRain", "Roughness");
	Settings.NightRain.LightScale = TheSettingManager->GetSettingF("Shaders.PBR.NightRain", "LightingScale");
	Settings.NightRain.AmbientScale = TheSettingManager->GetSettingF("Shaders.PBR.NightRain", "AmbientScale");
	Settings.NightRain.SkylightingScale = TheSettingManager->GetSettingF("Shaders.PBR.NightRain", "SkylightingScale");
	Settings.NightRain.SkylightingDirectionality = TheSettingManager->GetSettingF("Shaders.PBR.NightRain", "SkylightingDirectionality");
	Settings.NightRain.AmbientDirectionality = TheSettingManager->GetSettingF("Shaders.PBR.NightRain", "AmbientDirectionality");

	Settings.Interiors.Saturation = TheSettingManager->GetSettingF("Shaders.PBR.Interiors", "Saturation");
	Settings.Interiors.Metallicness = TheSettingManager->GetSettingF("Shaders.PBR.Interiors", "Metallicness");
	Settings.Interiors.Roughness = TheSettingManager->GetSettingF("Shaders.PBR.Interiors", "Roughness");
	Settings.Interiors.LightScale = TheSettingManager->GetSettingF("Shaders.PBR.Interiors", "LightingScale");
	Settings.Interiors.AmbientScale = TheSettingManager->GetSettingF("Shaders.PBR.Interiors", "AmbientScale");
	Settings.Interiors.SkylightingScale = TheSettingManager->GetSettingF("Shaders.PBR.Interiors", "SkylightingScale");
	Settings.Interiors.SkylightingDirectionality = TheSettingManager->GetSettingF("Shaders.PBR.Interiors", "SkylightingDirectionality");
	Settings.Interiors.AmbientDirectionality = TheSettingManager->GetSettingF("Shaders.PBR.Interiors", "AmbientDirectionality");
}

void PBRShaders::UpdateConstants() {
	// get max value between rain animator and puddle animator
	float rainFactor = max(TheShaderManager->Effects.WetWorld->Constants.Data.x, TheShaderManager->Effects.WetWorld->Constants.Data.z);

	Constants.ExtraData.x = std::lerp(TheShaderManager->GetTransitionValue(Settings.Default.Saturation, Settings.Night.Saturation, Settings.Interiors.Saturation),
		TheShaderManager->GetTransitionValue(Settings.Rain.Saturation, Settings.NightRain.Saturation, Settings.Interiors.Saturation), rainFactor);

	// Hemisphere skylight strength. No separate toggle: 0 disables it.
	Constants.ExtraData.y = std::lerp(TheShaderManager->GetTransitionValue(Settings.Default.SkylightingScale, Settings.Night.SkylightingScale, Settings.Interiors.SkylightingScale),
		TheShaderManager->GetTransitionValue(Settings.Rain.SkylightingScale, Settings.NightRain.SkylightingScale, Settings.Interiors.SkylightingScale), rainFactor);


	// Used only when SKYLIGHTING_MODE is 1; the SH path has no direction to lean.
	Constants.ExtraData.z = std::lerp(TheShaderManager->GetTransitionValue(Settings.Default.SkylightingDirectionality, Settings.Night.SkylightingDirectionality, Settings.Interiors.SkylightingDirectionality),
		TheShaderManager->GetTransitionValue(Settings.Rain.SkylightingDirectionality, Settings.NightRain.SkylightingDirectionality, Settings.Interiors.SkylightingDirectionality), rainFactor);

	Constants.Data.x = std::lerp(TheShaderManager->GetTransitionValue(Settings.Default.Metallicness, Settings.Night.Metallicness, Settings.Interiors.Metallicness),
		TheShaderManager->GetTransitionValue(Settings.Rain.Metallicness, Settings.NightRain.Metallicness, Settings.Interiors.Metallicness), rainFactor);
	Constants.Data.y = std::lerp(TheShaderManager->GetTransitionValue(Settings.Default.Roughness, Settings.Night.Roughness, Settings.Interiors.Roughness),
		TheShaderManager->GetTransitionValue(Settings.Rain.Roughness, Settings.NightRain.Roughness, Settings.Interiors.Roughness), rainFactor);

	Constants.Data.z = std::lerp(TheShaderManager->GetTransitionValue(Settings.Default.LightScale, Settings.Night.LightScale, Settings.Interiors.LightScale),
		TheShaderManager->GetTransitionValue(Settings.Rain.LightScale, Settings.NightRain.LightScale, Settings.Interiors.LightScale), rainFactor);
	Constants.Data.w = std::lerp(TheShaderManager->GetTransitionValue(Settings.Default.AmbientScale, Settings.Night.AmbientScale, Settings.Interiors.AmbientScale),
		TheShaderManager->GetTransitionValue(Settings.Rain.AmbientScale, Settings.NightRain.AmbientScale, Settings.Default.AmbientScale), rainFactor);

	// Flat-ambient hemisphere weighting (Includes/Object.hlsl getAmbientLighting). Unlike
	// SkylightingScale, this applies indoors too -- it only needs the surface normal, not the
	// exterior sky SH coefficients.
	Constants.ExtraData.w = std::lerp(TheShaderManager->GetTransitionValue(Settings.Default.AmbientDirectionality, Settings.Night.AmbientDirectionality, Settings.Interiors.AmbientDirectionality),
		TheShaderManager->GetTransitionValue(Settings.Rain.AmbientDirectionality, Settings.NightRain.AmbientDirectionality, Settings.Interiors.AmbientDirectionality), rainFactor);
};
