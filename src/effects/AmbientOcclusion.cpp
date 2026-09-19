#include "AmbientOcclusion.h"

void AmbientOcclusionEffect::UpdateConstants() {
}

void AmbientOcclusionEffect::RegisterConstants() {
	TheShaderManager->ConstantsTable["TESR_AmbientOcclusionAOData"] = &Constants.AOData;
	TheShaderManager->ConstantsTable["TESR_AmbientOcclusionData"] = &Constants.Data;
}

void AmbientOcclusionEffect::UpdateSettings() {
	const char* sectionName = TheShaderManager->GameState.isExterior?"Shaders.AmbientOcclusion.Exteriors":"Shaders.AmbientOcclusion.Interiors";

	Constants.Enabled = TheSettingManager->GetSettingI(sectionName, "Enabled");
	Constants.AOData.x = TheSettingManager->GetSettingF(sectionName, "SampleCount");
	Constants.AOData.y = TheSettingManager->GetSettingF(sectionName, "AOIntensity");
	Constants.AOData.z = TheSettingManager->GetSettingF(sectionName, "AOClamp");
	Constants.AOData.w = TheSettingManager->GetSettingF(sectionName, "SampleRadius");
	Constants.Data.x = TheSettingManager->GetSettingF(sectionName, "Bias");
	Constants.Data.y = TheSettingManager->GetSettingF(sectionName, "LumaThreshold");
	Constants.Data.z = TheSettingManager->GetSettingF(sectionName, "BlurThreshold");
	Constants.Data.w = TheSettingManager->GetSettingF(sectionName, "BlurRadius");
}

bool AmbientOcclusionEffect::ShouldRender() {
	return Constants.Enabled && !bNVAOLoaded;
}