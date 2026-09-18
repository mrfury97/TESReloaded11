#pragma once

class SkinShaders : public ShaderCollection
{
public:
	SkinShaders() : ShaderCollection("Skin") {};

	struct SkinStruct {
		D3DXVECTOR4		SkinData;
		D3DXVECTOR4		SkinColor;
		D3DXVECTOR4		SkinSSSData; // x: TranslucencyWidth, y: TranslucencyPower, z: TranslucencyScale, w: TranslucencyShadowInfluence
	};
	SkinStruct Constants;

	void	UpdateConstants();
	void	RegisterConstants();
	void	UpdateSettings();
};