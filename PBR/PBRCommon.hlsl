#ifndef PBR_COMMON
#define PBR_COMMON

half fresnel(half3 normal,half3 viewDir,half amplitude,half fresnelPow)
{
    half NdotV = dot(normal,viewDir);
    half fresnelVal = amplitude * pow(1.0-NdotV,fresnelPow);
    return fresnelVal;
}

struct Attributes
{
    float4 positionOS   : POSITION;
    float3 normalOS : NORMAL;
    float4 tangentOS : TANGENT;
    float2 uv : TEXCOORD0;
    float2 lightmapUV   : TEXCOORD1;
};

struct Varyings
{
    float4 positionHCS  : SV_POSITION;
    float3 normalWS : TEXCOORD0;
    float3 viewDirWS : TEXCOORD1;
    float2 uv : TEXCOORD2;
    float3 positionWS:TEXCOORD3;
    float4 screenPS:TEXCOORD4;
    float4 tangentWS:TEXCOORD5;
    float4 fogFactorAndVertexLight:TEXCOORD6;
    DECLARE_LIGHTMAP_OR_SH(lightmapUV,vertexSH,7);
};

void BuildInputData(Varyings input,float3 NormalTS, out InputData inputData)
{
    inputData = (InputData)0;
                
    inputData.positionWS = input.positionWS;

    //使用发现贴图NormalTS
    float crossSign = (input.tangentWS.w > 0.0 ? 1.0 : -1.0) * GetOddNegativeScale();
    float3 bitangent = crossSign * cross(input.normalWS.xyz, input.tangentWS.xyz);
    inputData.normalWS = TransformTangentToWorld(NormalTS, half3x3(input.tangentWS.xyz, bitangent, input.normalWS.xyz));
                
    inputData.normalWS = NormalizeNormalPerPixel(inputData.normalWS);
    inputData.viewDirectionWS = SafeNormalize(input.viewDirWS);

    inputData.shadowCoord = TransformWorldToShadowCoord(inputData.positionWS);

    inputData.fogCoord = input.fogFactorAndVertexLight.x;
    inputData.vertexLighting = input.fogFactorAndVertexLight.yzw;
    inputData.bakedGI = SAMPLE_GI(input.lightmapUV, input.vertexSH, inputData.normalWS);
    inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionHCS);
    inputData.shadowMask = SAMPLE_SHADOWMASK(input.lightmapUV);
}

#endif