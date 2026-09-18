#include "Skin.h"

void SkinShaders::RegisterConstants() {
	TheShaderManager->RegisterConstant("TESR_SkinData", &Constants.SkinData);
	TheShaderManager->RegisterConstant("TESR_SkinColor", &Constants.SkinColor);
	TheShaderManager->RegisterConstant("TESR_SkinSSSData", &Constants.SkinSSSData);
	TheShaderManager->RegisterConstant("TESR_SkinSSSData2", &Constants.SkinSSSData2);
	TheShaderManager->RegisterConstant("TESR_SkinDeepColor", &Constants.SkinDeepColor);
}

void SkinShaders::UpdateConstants() {}

void SkinShaders::UpdateSettings() {
	Constants.SkinData.x = TheSettingManager->GetSettingF("Shaders.Skin.Main", "Attenuation");
	Constants.SkinData.y = TheSettingManager->GetSettingF("Shaders.Skin.Main", "SpecularPower");
	Constants.SkinData.z = TheSettingManager->GetSettingF("Shaders.Skin.Main", "MaterialThickness");
	Constants.SkinData.w = TheSettingManager->GetSettingF("Shaders.Skin.Main", "RimScalar");

	Constants.SkinColor.x = TheSettingManager->GetSettingF("Shaders.Skin.Main", "CoeffRed");
	Constants.SkinColor.y = TheSettingManager->GetSettingF("Shaders.Skin.Main", "CoeffGreen");
	Constants.SkinColor.z = TheSettingManager->GetSettingF("Shaders.Skin.Main", "CoeffBlue");

	Constants.SkinSSSData.x = TheSettingManager->GetSettingF("Shaders.Skin.Main", "TranslucencyWidth");
	Constants.SkinSSSData.y = TheSettingManager->GetSettingF("Shaders.Skin.Main", "TranslucencyPower");
	Constants.SkinSSSData.z = TheSettingManager->GetSettingF("Shaders.Skin.Main", "TranslucencyScale");
	Constants.SkinSSSData.w = TheSettingManager->GetSettingF("Shaders.Skin.Main", "TranslucencyShadowInfluence");

	Constants.SkinSSSData2.x = TheSettingManager->GetSettingF("Shaders.Skin.Main", "DeepScatterWidth");
	Constants.SkinSSSData2.y = TheSettingManager->GetSettingF("Shaders.Skin.Main", "DeepScatterPower");
	Constants.SkinSSSData2.z = TheSettingManager->GetSettingF("Shaders.Skin.Main", "DeepScatterScale");

	Constants.SkinDeepColor.x = TheSettingManager->GetSettingF("Shaders.Skin.Main", "DeepCoeffRed");
	Constants.SkinDeepColor.y = TheSettingManager->GetSettingF("Shaders.Skin.Main", "DeepCoeffGreen");
	Constants.SkinDeepColor.z = TheSettingManager->GetSettingF("Shaders.Skin.Main", "DeepCoeffBlue");
}