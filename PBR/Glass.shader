
Shader "Qingzhu/URP/Lighting/Glass"
{
    Properties
    {
        _MainTex("Base",2D) = "black" {}
        _NormalTex("NormalTex",2D) = "blue" {}
		_AOTex("AOTex",2D) = "black" {}

		_MatCapTexture("MatCapTexture",2D) = "black" {}


		_Width("Width",Range(0,100))= 1
		_RefractAmount("RefractAmount",Range(0,1))= 1
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "RenderPipeline"="UniversalRenderPipeline" "Queue"="Transparent"}

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "PBRCommon.hlsl"
            // #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"

//            TEXTURE2D(_BumpMap);            SAMPLER(sampler_BumpMap);
            sampler2D _MainTex;
            float4 _MainTex_ST;
            sampler2D _NormalTex;
            sampler2D _AOTex;

            sampler2D _MatCapTexture;

            
            
            CBUFFER_START(UnityPerMaterial)
            half _Width;
            half _RefractAmount;
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

            	half4 normalColor = tex2D(_NormalTex, IN.uv);
            	half3 tangentNormalDir = UnpackNormal(normalColor);
            	float crossSign = (IN.tangentWS.w > 0.0 ? 1.0 : -1.0) * GetOddNegativeScale();
				float3 bitangent = crossSign * cross(IN.normalWS.xyz, IN.tangentWS.xyz);
				half3 normalWS = TransformTangentToWorld(tangentNormalDir, half3x3(IN.tangentWS.xyz, bitangent, IN.normalWS.xyz));
   
            	
            	half3 vNor = mul(UNITY_MATRIX_V,float4(normalize(normalWS),0));
            	half2 offset = vNor.xy*_Width*half2(_ScreenParams.z-1,_ScreenParams.w-1);
            	
            	// half2 offset = half3(0,0,1)*_Width*;
            	half2 suv = IN.screenPS.xy/IN.screenPS.w;
            	half3 refractCol = SampleSceneColor(suv+offset);
            	half ao = tex2D(_AOTex,IN.uv).r;

				half3 mainColor = tex2D(_MainTex,IN.uv);
            	half3 color = lerp(mainColor,refractCol*max(ao,0.5),_RefractAmount);
            	
            	return half4(color,1);               
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
