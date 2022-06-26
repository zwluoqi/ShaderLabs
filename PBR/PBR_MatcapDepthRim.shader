/*//Matcap全称MaterialCapture（材质捕获）
//MatCap本质是将法线转换到摄像机空间，然后用法线的x和y作为UV，来采样MatCat贴图
//因为最后使用的是摄像机空间的法线的xy采样，所以法线的取值范围决定了贴图的有效范围是个圆形
//优点：不需要进行一大堆的光照计算，只通过简单的采样一张贴图就可以实现PBR等其他复杂效果
//缺点：因为只是采样一张贴图，所以当灯光改变时效果不会变化，看起来好像一直朝向摄像机，也就是常说的难以使效果与环境产生交互
//可以考虑将复杂的光照信息（例如高光，漫反射）烘焙在MatCap贴图上，然后将环境信息（例如建筑，天空）烘培在CubeMap上，然后将2者结合在一起，多少能弥补一下缺点
//MatCap基于它的效果，很多使用用来低成本的实现车漆，卡通渲染头发的“天使环（angel ring）”等相关效果
*/

Shader "Qingzhu/URP/Lighting/PBR_MatcapDepthRim"
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


		_RimColor("RimColor",color) = (1,1,1,1)

		//Depth Rim
		_Spread("Spread",Range(0,200))= 1
		_Width("Width",float)= 1
		_MinDis("MinDis",Range(0,1))= 0
		_MaxDis("MaxDis",Range(0,1))= 1
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

            half3 _RimColor;
            
            half _Smoothness;
            half _MetallicAmplitude;

            half _Width;
            half _MinDis;
            half _MaxDis;
            half _Spread;
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

            half edgeDisCal(Varyings IN)
            {
	            
            	half4 spos = IN.screenPS;
            	half2 suv = spos.xy/spos.w;
            	// return  spos.w;
            	half3 vNor = mul(UNITY_MATRIX_V,float4(normalize(IN.normalWS),0));
            	suv += vNor.xy*_Width*half2(_ScreenParams.z-1,_ScreenParams.w-1);//offset
            	half dd = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, suv.xy);
            	half depth = LinearEyeDepth(dd,_ZBufferParams);
            	// return depth;
            	half dis = saturate((depth-spos.w)/max(1,_Spread));
            	// return dis;
            	half rim = smoothstep(_MinDis,_MaxDis,dis);
            	return rim;
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
            	half3 maskColor = tex2D(_MaskTexture, IN.uv).rgb;

                InputData inputData;
                BuildInputData(IN, tangentNormalDir, inputData);

            	half3 fresnelValue = edgeDisCal(IN)*_RimColor;
				
                
            	half3 normalVS = TransformWorldToViewDir(IN.normalWS,true);
            	normalVS = normalVS*0.5+0.5f;

				half4 matcap = maskColor.r*tex2D(_MatCapTexture, normalVS.xy);
            	// return matcap;
                half3 Albedo = baseColor;
				half Metallic = metallicColor*_MetallicAmplitude;
				half3 Specular = 0;//metallic/roughness模式,
				half Smoothness = (1-roughnessColor)*_Smoothness;
				half Occlusion = aoColor;
				half3 Emission = fresnelValue + matcap.rgb;
				half Alpha = maskColor.g;

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
