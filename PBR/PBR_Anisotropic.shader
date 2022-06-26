/*
物理上的各向异性解释我无法直接和图形这边的现象联想在一起，所以寻找了在图形渲染中比较贴切的解释。
各项异性表面从表面上细致的纹理、槽或丝缕来获得它特有的外观，比如拉丝金属、CD的闪光面。
当使用普通的材质进行光照时，计算仅考虑表面的法线向量、到光源的向量、及到相机的向量。
但是对于各向异性表面，没有真正可以使用的连续的法线向量，因为每个丝缕或槽都有各种不同的法线方向，法线方向和槽的方向垂直。
其实在渲染中来实现各向异性光照时，并不是让每一个顶点在不同的方向都拥有不同的法线信息，它的计算是基于片元着色器的；
如果是各项同性，我们只需要通过插值得到各个片元的法线信息即可，而对于各向异性来说，我们需要在片远着色器中根据法线扰动规则重新计算法线。
这样虽然看起来是一个平面，但它上面的像素却会因为法线扰动而形成一些纹理、凹槽的效果，从而展示出更多的细节表现，
而且，法线的扰动通常是有规律的，所以在不同的方向上，表现出的效果可能会不一样，从而表现出所谓的光学各向异性。
这个法线扰动规则可以是一个公式，也可以是一张纹理

各向异性使用头发渲染的常见算法Kajiya-Kay来演示,
为方便观察各项异性高光，所以并没有完整的去实现Kajiya-Kay模型，完整的可以参考 http://web.engr.oregonstate.edu/~mjb/cs519/Projects/Papers/HairRendering.pdf
*/

Shader "Qingzhu/URP/Lighting/PBR_Anisotropic"
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


        _AnisotropicColor ("AnisotropicColor", Color) = (1,1,1,1)
        _AnisotropicExp ("AnisotropicExp",  float) = 2
        _StretchedNoise("StretchedNoise", 2D) = "white" {}
        _Shift("Shift",float) = 0

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

            sampler2D _MaskTexture;

            sampler2D _StretchedNoise;
            
            
            CBUFFER_START(UnityPerMaterial)    

            half _FresnelAmplitude;
            half _FresnelPow;
            half3 _FresnelColor;
            half _Smoothness;
            half _MetallicAmplitude;

            half3 _AnisotropicColor;
            half _AnisotropicExp;
            half _Shift;
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

            //注意是副切线不是切线，也就是切线空间 TBN 中的 B
            half3 ShiftTangent(half3 bitangentWS,half3 normalWS,half shift)
            {
                half3 shiftedT = bitangentWS + shift * normalWS;
                return normalize(shiftedT);
            }

            half StrandSpecular(half3 bitangentWS,half3 viewDirWS,half3 lightDirWS,half exponent)
            {
                half3 H = normalize(lightDirWS + viewDirWS);
                half dotTH = dot(bitangentWS,H); // 点乘 计算出来的是2个单位向量的cos的值
                half sinTH = sqrt(1.0 - dotTH * dotTH);//因为 sin^2 + cos^2 = 1 所以 sin = sqrt(1 - cos^2);
                half dirAttenuation = smoothstep(-1.0,0.0,dotTH);
                return dirAttenuation * pow(sinTH,exponent);
            }

            half3 LightingHair(half3 bitangentWS, half3 lightDirWS, half3 normalWS, half3 viewDirWS, float2 uv,half exp,half3 specular)
            {
                //shift tangents
                half shiftTex = tex2D(_StretchedNoise, uv).r - 0.5;
                half3 t1 = ShiftTangent(bitangentWS,normalWS,_Shift + shiftTex);

                //specular
                half3 specularColor  = StrandSpecular(t1,viewDirWS,lightDirWS,exp) * specular;

                return specularColor;

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
                half3 normalWS = normalize(IN.normalWS);
                half3 viewWS = SafeNormalize(IN.viewDirWS);
            	float crossSign = (IN.tangentWS.w > 0.0 ? 1.0 : -1.0) * GetOddNegativeScale();
				float3 bitangentWS = crossSign * cross(normalWS, normalize(IN.tangentWS.xyz));

                half3 fresnelValue = maskColor.b*fresnel(normalWS,viewWS,_FresnelAmplitude,_FresnelPow)*_FresnelColor;

            	Light light = GetMainLight();
            	half3 anisotropic = LightingHair(bitangentWS,light.direction,normalWS,viewWS,IN.uv,_AnisotropicExp,_AnisotropicColor);
            	return half4(anisotropic,1);
            	
            	half3 normalVS = TransformWorldToViewDir(IN.normalWS,true);
            	normalVS = normalVS*0.5+0.5f;

                half3 Albedo = baseColor;
				half Metallic = metallicColor*_MetallicAmplitude;
				half3 Specular = 0;//metallic/roughness模式,
				half Smoothness = (1-roughnessColor)*_Smoothness;
				half Occlusion = aoColor;
				half3 Emission = fresnelValue;
				half Alpha = maskColor.g;

            	//BRDFData brdfData;
			    // NOTE: can modify alpha
			    //InitializeBRDFData(Albedo, Metallic, Specular, Smoothness, Alpha, brdfData);
				//return half4(brdfData.diffuse + brdfData.specular*anisotropic,1);
            	
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
