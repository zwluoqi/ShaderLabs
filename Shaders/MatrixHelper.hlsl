#ifndef QINGZHU_SHADER_LAB_MARTRIX
#define QINGZHU_SHADER_LAB_MARTRIX

float4 GetPreClip(float2 uv,float4x4 _InverseProjection,float4x4 _InverseRotation,float4x4 _PreviousRotation,float4x4 _Projection)
{
    float4 screenPos = float4(uv*2.0-1.0,1.0,1.0);
    float4 cameraPos = mul(_InverseProjection,screenPos);
    cameraPos = cameraPos/cameraPos.w;
    float3 worldPos = mul((float3x3)_InverseRotation,cameraPos.xyz);
    float3 preCameraPos = mul((float3x3)_PreviousRotation,worldPos.xyz);
    float4 pre_clip = mul(_Projection,preCameraPos);
    pre_clip /= pre_clip.w;
    pre_clip.xy = pre_clip.xy*0.5+0.5;
    return float4(pre_clip.xy,0,1);
}
#endif