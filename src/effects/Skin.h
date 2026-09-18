#pragma once

class SkinShaders : public ShaderCollection
{
public:
	SkinShaders() : ShaderCollection("Skin") {};

	struct SkinStruct {
		D3DXVECTOR4		SkinData;
		D3DXVECTOR4		SkinColor;
		D3DXVECTOR4		SkinSSSData; // x: TranslucencyWidth, y: TranslucencyPower, z: TranslucencyScale, w: TranslucencyShadowInfluence
		D3DXVECTOR4		SkinSSSData2; // x: DeepScatterWidth, y: DeepScatterPower, z: DeepScatterScale, w: unused
		D3DXVECTOR4		SkinDeepColor; // xyz: DeepCoeffRed/Green/Blue, w: unused
	};
	SkinStruct Constants;

	void	UpdateConstants();
	void	RegisterConstants();
	void	UpdateSettings();
};