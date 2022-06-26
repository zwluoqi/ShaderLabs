/*Minnaert照明模型最初设计用于模拟月球的着色，因此它通常被称为moon shader。
Minnaert适合模拟多孔或纤维状表面，如月球或天鹅绒。这些表面会导致大量光线反向散射。
这一点在纤维主要垂直于表面（如天鹅绒、天鹅绒甚至地毯）的地方尤为明显。
此模拟提供的结果与Oren Nayar非常接近，后者也经常被称为velvet（天鹅绒）或moon着色器。
*/

Shader "Qingzhu/URP/Lighting/PBR_Minnaert"
{
    Properties
    {
        _MainTex("Base",2D) = "white" {}
        _MetallicTex("Metallic",2D) = "white" {}
		_MetallicAmplitude("MetallicAmplitude", Range(0.0, 1.0)) = 0.5
        _AOTex("AO",2D) = "white" {}
        _NormalTex("Normal",2D) = "blue" {}
        _RoughnessTex("Roughness",2D) = "white" {}
		_Smoothness("Smoothness", Range(0.0, 1.0)) = 0.5

        _MinnaertColor("MinnaertColor",Color) = (0.5,0.5,0.5,1)        
        _MinnaertRoughness("MinnaertRoughness",float) = 1

        _FresnelAmplitude("FresnelAmplitude",float) = 1
        _FresnelPow("FresnelPow",float) = 1
        _FresnelColor("FresnelColor",Color) = (1,1,1,1)
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
            

//            TEXTURE2D(_BumpMap);            SAMPLER(sampler_BumpMap);
            sampler2D _MainTex;
            float4 _MainTex_ST;
            sampler2D _MetallicTex;
            sampler2D _AOTex;
            sampler2D _NormalTex;
            sampler2D _RoughnessTex;
            
            CBUFFER_START(UnityPerMaterial)            
            half3 _MinnaertColor;
            half _MinnaertRoughness;
            half _FresnelAmplitude;
            half _FresnelPow;
            half3 _FresnelColor;
            half _Smoothness;
            half _MetallicAmplitude;
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
                
                float3 positionWS = TransformObjectToWorld(IN.positionOS.xyz);
            	OUT.positionWS = positionWS;
                OUT.positionHCS = TransformWorldToHClip(positionWS);
            	OUT.screenPS = ComputeScreenPos(OUT.positionHCS);
                OUT.normalWS= TransformObjectToWorldNormal(IN.normalOS);
                OUT.tangentWS = float4(TransformObjectToWorldDir(IN.tangentOS),IN.tangentOS.w);
                OUT.viewDirWS = GetWorldSpaceViewDir(positionWS);
                            
                half3 vertexLight = VertexLighting(vertexInput.positionWS, normalInput.normalWS);
                half fogFactor = ComputeFogFactor(vertexInput.positionCS.z);
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

                half4 baseColor = tex2D(_MainTex, IN.uv);
				half metallicColor = tex2D(_MetallicTex, IN.uv).r;
				half aoColor = tex2D(_AOTex, IN.uv).r;
                half4 normalColor = tex2D(_NormalTex, IN.uv);
            	half3 tangentNormalDir = UnpackNormal(normalColor);
				half roughnessColor = tex2D(_RoughnessTex, IN.uv).r;


                InputData inputData;
                BuildInputData(IN, tangentNormalDir, inputData);
                half3 normalWS = normalize(IN.normalWS);
                half3 viewWS = SafeNormalize(IN.viewDirWS);

                half3 fresnelValue = fresnel(normalWS,viewWS,_FresnelAmplitude,_FresnelPow)*_FresnelColor;
                Light mainLight = GetMainLight();
                half minnaert = LightingMinnaert(mainLight.direction, normalWS, viewWS, _MinnaertRoughness);
                
                half3 Albedo = lerp(baseColor,_MinnaertColor,minnaert);
				half Metallic = metallicColor*_MetallicAmplitude;
				half3 Specular = 0;//metallic/roughness模式,
				half Smoothness = (1-roughnessColor)*_Smoothness;
				half Occlusion = aoColor;
				half3 Emission = fresnelValue;
				half Alpha = 1;

                half4 totlaColor = UniversalFragmentPBR(
					inputData, 
					Albedo, 
					Metallic, 
					Specular, 
					Smoothness, 
					Occlusion, 
					Emission, 
					Alpha);
                return totlaColor;
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
