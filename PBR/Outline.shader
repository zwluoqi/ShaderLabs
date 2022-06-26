
Shader "Qingzhu/URP/Lighting/Outline"
{
    Properties
    {
        _MainTex("Base",2D) = "black" {}
        _MetallicTex("Metallic",2D) = "black" {}
		_MetallicAmplitude("MetallicAmplitude", Range(0.0, 1.0)) = 0.5
        _AOTex("AO",2D) = "black" {}
        _NormalTex("Normal",2D) = "blue" {}
        _RoughnessTex("Roughness",2D) = "black" {}
		_Smoothness("Smoothness", Range(0.0, 1.0)) = 0.5

		_MaskTexture("matcap(R),Alpha(G),Fresnel(B)",2D) = "black" {}

		_MatCapTexture("MatCapTexture",2D) = "black" {}

        _FresnelAmplitude("FresnelAmplitude",float) = 1
        _FresnelPow("FresnelPow",float) = 1
        _FresnelColor("FresnelColor",Color) = (1,1,1,1)

		//Depth Rim
		_Spread("Spread",Range(0,200))= 1
		_Width("Width",float)= 1
		_MinDis("MinDis",Range(0,1))= 0
		_MaxDis("MaxDis",Range(0,1))= 1
		_StartDis("StartDis",Range(0,200))= 1
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalRenderPipeline" "Queue"="Geometry"}

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "PBRCommon.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

//            TEXTURE2D(_BumpMap);            SAMPLER(sampler_BumpMap);
            sampler2D _MainTex;
            float4 _MainTex_ST;
            sampler2D _MetallicTex;
            sampler2D _AOTex;
            sampler2D _NormalTex;
            sampler2D _RoughnessTex;
            sampler2D _MatCapTexture;
            sampler2D _MaskTexture;
            
            
            CBUFFER_START(UnityPerMaterial)            
            half3 _MinnaertColor;
            half _MinnaertRoughness;
            half _FresnelAmplitude;
            half _FresnelPow;
            half3 _FresnelColor;
            half _Smoothness;
            half _MetallicAmplitude;

            half _Width;
            half _MinDis;
            half _MaxDis;
            half _Spread;
            half _StartDis;
            CBUFFER_END

            //一般用来模拟月亮的光照
            half LightingMinnaert(half3 lightDirWS, half3 normalWS, half3 viewDirWS, half minnaertRoughness)
            {
                half NdotL = saturate(dot(normalWS, lightDirWS));
                half NdotV = saturate(dot(normalWS, viewDirWS));
                half minnaert = saturate(NdotL * pow(NdotL * NdotV, minnaertRoughness));
                return minnaert;
            }

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                UNITY_SETUP_INSTANCE_ID(IN);
				UNITY_TRANSFER_INSTANCE_ID(IN, OUT);
				UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);
            	
                VertexPositionInputs vertexInput = GetVertexPositionInputs(IN.positionOS.xyz);
                VertexNormalInputs normalInput = GetVertexNormalInputs(IN.normalOS, IN.tangentOS);
                OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);
            	
                float3 positionWS = TransformObjectToWorld(IN.positionOS.xyz);
            	float dist = length(_WorldSpaceCameraPos-positionWS);
            	float radio = saturate((dist-_StartDis)/_Spread);
            	float width = lerp(_MinDis,_MaxDis,radio);
            	positionWS += OUT.normalWS*_Width*width;
            	
            	OUT.positionWS = positionWS;
                OUT.positionHCS = TransformWorldToHClip(positionWS);
            	OUT.screenPS = ComputeScreenPos(OUT.positionHCS);
                
                OUT.tangentWS = float4(TransformObjectToWorldDir(IN.tangentOS),IN.tangentOS.w);
                OUT.viewDirWS = GetWorldSpaceViewDir(positionWS);
                            
                half3 vertexLight = VertexLighting(positionWS, normalInput.normalWS);
                half fogFactor = ComputeFogFactor(OUT.positionHCS.z);
                OUT.fogFactorAndVertexLight = float4(fogFactor,vertexLight);

                //宏定义使用lightmap或者lightprobe
                OUTPUT_LIGHTMAP_UV(input.lightmapUV, unity_LightmapST, OUT.lightmapUV);
                OUTPUT_SH(OUT.normalWS.xyz, OUT.vertexSH);
                            
                OUT.uv = TRANSFORM_TEX(IN.uv, _MainTex); 
                return OUT;
            }


            half4 frag(Varyings IN) : SV_Target
            {
            	UNITY_SETUP_INSTANCE_ID(IN);
				UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(IN);

                
            	
            	return half4(_FresnelColor,1);               
            }

            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags{"LightMode" = "DepthOnly"}

            ZWrite On
            ColorMask 0
//            Cull[_Cull]

            HLSLPROGRAM
            // #pragma exclude_renderers gles gles3 glcore
            // #pragma target 4.5

            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment

            // -------------------------------------
            // Material Keywords
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            #pragma shader_feature_local_fragment _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            #pragma multi_compile _ DOTS_INSTANCING_ON

            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthOnlyPass.hlsl"
            ENDHLSL
        }

        // This pass is used when drawing to a _CameraNormalsTexture texture
        Pass
        {
            Name "DepthNormals"
            Tags{"LightMode" = "DepthNormals"}

            ZWrite On
//            Cull[_Cull]

            HLSLPROGRAM
            // #pragma exclude_renderers gles gles3 glcore
            // #pragma target 4.5

            #pragma vertex DepthNormalsVertex
            #pragma fragment DepthNormalsFragment

            // -------------------------------------
            // Material Keywords
            #pragma shader_feature_local _NORMALMAP
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            #pragma shader_feature_local_fragment _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            #pragma multi_compile _ DOTS_INSTANCING_ON

            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthNormalsPass.hlsl"
            ENDHLSL
        }
    }
}
