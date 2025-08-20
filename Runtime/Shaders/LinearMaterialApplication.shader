Shader "Custom/RadialMaterialApplication"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _Color ("Color", Color) = (1,1,1,1)
        _Progress ("Progress", Range(0, 1)) = 0
        _Center ("Center", Vector) = (0,0,0,0)
        _Radius ("Max Radius", Float) = 1.0
        _GridColor ("Grid Color", Color) = (1,1,0,1)
        _GridSize ("Grid Size", Float) = 1.0
        _GridLineWidth ("Grid Line Width", Range(0.01, 0.1)) = 0.02
        _ShowGrid ("Show Grid", Range(0, 1)) = 1
    }
    
    // URP SubShader - Will be used if URP is active
    SubShader
    {
        Tags 
        { 
            "RenderType"="Transparent" 
            "Queue"="Geometry+100" 
            "RenderPipeline"="UniversalPipeline"
        }
        LOD 100
        
        Pass
        {
            Name "ForwardLit"
            Tags {"LightMode"="UniversalForward"}
            
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite On
            ZTest LEqual
            Cull Back
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0
            
            // Check if URP is available, fallback if not
            #if defined(UNIVERSAL_PIPELINE_CORE_INCLUDED) || defined(UNITY_PIPELINE_URP)
                #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
                #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
                #define URP_AVAILABLE
            #else
                #include "UnityCG.cginc"
                #include "Lighting.cginc"
            #endif
            
            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float3 normalOS : NORMAL;
            };
            
            struct Varyings
            {
                float2 uv : TEXCOORD0;
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
            };
            
            #ifdef URP_AVAILABLE
                TEXTURE2D(_MainTex);
                SAMPLER(sampler_MainTex);
                
                CBUFFER_START(UnityPerMaterial)
                    float4 _MainTex_ST;
                    half4 _Color;
                    float _Progress;
                    float3 _Center;
                    float _Radius;
                    half4 _GridColor;
                    float _GridSize;
                    float _GridLineWidth;
                    float _ShowGrid;
                CBUFFER_END
            #else
                sampler2D _MainTex;
                float4 _MainTex_ST;
                fixed4 _Color;
                float _Progress;
                float3 _Center;
                float _Radius;
                fixed4 _GridColor;
                float _GridSize;
                float _GridLineWidth;
                float _ShowGrid;
            #endif
            
            float GetGridFactor(float3 worldPos, float3 worldNormal, float gridSize, float lineWidth)
            {
                float3 absNormal = abs(worldNormal);
                float2 gridCoord;
                
                if (absNormal.y > absNormal.x && absNormal.y > absNormal.z)
                {
                    gridCoord = float2(worldPos.x, worldPos.z) / gridSize;
                }
                else if (absNormal.x > absNormal.z)
                {
                    gridCoord = float2(worldPos.y, worldPos.z) / gridSize;
                }
                else
                {
                    gridCoord = float2(worldPos.x, worldPos.y) / gridSize;
                }
                
                float2 gridFract = frac(abs(gridCoord));
                float2 distToLine = min(gridFract, 1.0 - gridFract);
                float minDistToLine = min(distToLine.x, distToLine.y);
                float gridFactor = 1.0 - smoothstep(0.0, lineWidth, minDistToLine);
                
                return gridFactor;
            }
            
            Varyings vert(Attributes input)
            {
                Varyings output;
                
                #ifdef URP_AVAILABLE
                    VertexPositionInputs positionInputs = GetVertexPositionInputs(input.positionOS.xyz);
                    VertexNormalInputs normalInputs = GetVertexNormalInputs(input.normalOS);
                    
                    output.positionCS = positionInputs.positionCS;
                    output.positionWS = positionInputs.positionWS;
                    output.normalWS = normalInputs.normalWS;
                #else
                    output.positionCS = UnityObjectToClipPos(input.positionOS);
                    output.positionWS = mul(unity_ObjectToWorld, input.positionOS).xyz;
                    output.normalWS = UnityObjectToWorldNormal(input.normalOS);
                #endif
                
                output.uv = input.uv * _MainTex_ST.xy + _MainTex_ST.zw;
                
                return output;
            }
            
            half4 frag(Varyings input) : SV_Target
            {
                #ifdef URP_AVAILABLE
                    half4 c = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv) * _Color;
                #else
                    half4 c = tex2D(_MainTex, input.uv) * _Color;
                #endif
                
                #ifdef URP_AVAILABLE
                    float3 objectSpacePos = mul(UNITY_MATRIX_I_M, float4(input.positionWS, 1.0)).xyz;
                #else
                    float3 objectSpacePos = mul(unity_WorldToObject, float4(input.positionWS, 1.0)).xyz;
                #endif
                
                float distanceFromCenter = distance(objectSpacePos, _Center);
                float normalizedDistance = distanceFromCenter / _Radius;
                
                float threshold = _Progress;
                
                if (normalizedDistance < threshold)
                {
                    float gridFactor = GetGridFactor(input.positionWS, input.normalWS, _GridSize, _GridLineWidth);
                    
                    float3 finalColor = lerp(c.rgb, _GridColor.rgb, gridFactor * _ShowGrid);
                    float finalAlpha = max(c.a, gridFactor * _GridColor.a * _ShowGrid);
                    
                    // Ensure minimum alpha for VR visibility
                    finalAlpha = max(finalAlpha, 0.3);
                    
                    // Simple lighting
                    #ifdef URP_AVAILABLE
                        Light mainLight = GetMainLight();
                        float ndotl = max(0.3, dot(input.normalWS, mainLight.direction)); // Increased minimum lighting
                        float3 lighting = mainLight.color * ndotl + half3(0.4, 0.4, 0.4); // Increased ambient
                    #else
                        float3 worldLightDir = normalize(_WorldSpaceLightPos0.xyz);
                        float ndotl = max(0.3, dot(input.normalWS, worldLightDir)); // Increased minimum lighting
                        float3 lighting = _LightColor0.rgb * ndotl + half3(0.4, 0.4, 0.4); // Increased ambient
                    #endif
                    
                    finalColor *= lighting;
                    
                    return half4(finalColor, finalAlpha);
                }
                else
                {
                    // Use discard instead of transparent black for better VR performance
                    discard;
                    return half4(0,0,0,0);
                }
            }
            ENDHLSL
        }
    }
    
    // Built-in Render Pipeline SubShader - Will be used if Built-in RP is active
    SubShader
    {
        Tags {"Queue"="Geometry+100" "RenderType"="Transparent"}
        LOD 100

        Pass
        {
            Tags {"LightMode"="ForwardBase"}
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite On
            ZTest LEqual
            Cull Back
            
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fwdbase
            
            #include "UnityCG.cginc"
            #include "Lighting.cginc"
            
            sampler2D _MainTex;
            float4 _MainTex_ST;
            fixed4 _Color;
            float _Progress;
            float3 _Center;
            float _Radius;
            fixed4 _GridColor;
            float _GridSize;
            float _GridLineWidth;
            float _ShowGrid;
            
            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : NORMAL;
            };
            
            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 pos : SV_POSITION;
                float3 worldPos : TEXCOORD1;
                float3 worldNormal : TEXCOORD2;
            };
            
            float GetGridFactor(float3 worldPos, float3 worldNormal, float gridSize, float lineWidth)
            {
                float3 absNormal = abs(worldNormal);
                float2 gridCoord;
                
                if (absNormal.y > absNormal.x && absNormal.y > absNormal.z)
                {
                    gridCoord = float2(worldPos.x, worldPos.z) / gridSize;
                }
                else if (absNormal.x > absNormal.z)
                {
                    gridCoord = float2(worldPos.y, worldPos.z) / gridSize;
                }
                else
                {
                    gridCoord = float2(worldPos.x, worldPos.y) / gridSize;
                }
                
                float2 gridFract = frac(abs(gridCoord));
                float2 distToLine = min(gridFract, 1.0 - gridFract);
                float minDistToLine = min(distToLine.x, distToLine.y);
                float gridFactor = 1.0 - smoothstep(0.0, lineWidth, minDistToLine);
                
                return gridFactor;
            }
            
            v2f vert (appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.worldNormal = UnityObjectToWorldNormal(v.normal);
                return o;
            }
            
            fixed4 frag (v2f i) : SV_Target
            {
                fixed4 c = tex2D(_MainTex, i.uv) * _Color;
                
                float3 objectSpacePos = mul(unity_WorldToObject, float4(i.worldPos, 1.0)).xyz;
                float distanceFromCenter = distance(objectSpacePos, _Center);
                float normalizedDistance = distanceFromCenter / _Radius;
                
                float threshold = _Progress;
                
                if (normalizedDistance < threshold)
                {
                    float gridFactor = GetGridFactor(i.worldPos, i.worldNormal, _GridSize, _GridLineWidth);
                    
                    float3 finalColor = lerp(c.rgb, _GridColor.rgb, gridFactor * _ShowGrid);
                    float finalAlpha = max(c.a, gridFactor * _GridColor.a * _ShowGrid);
                    
                    // Ensure minimum alpha for VR visibility
                    finalAlpha = max(finalAlpha, 0.3);
                    
                    // Simple Lambert lighting with increased ambient for VR
                    float3 worldLightDir = normalize(_WorldSpaceLightPos0.xyz);
                    float ndotl = max(0.3, dot(i.worldNormal, worldLightDir)); // Increased minimum lighting
                    float3 lighting = _LightColor0.rgb * ndotl + half3(0.4, 0.4, 0.4); // Increased ambient
                    finalColor *= lighting;
                    
                    return fixed4(finalColor, finalAlpha);
                }
                else
                {
                    // Use discard instead of transparent black for better VR performance
                    discard;
                    return fixed4(0,0,0,0);
                }
            }
            ENDCG
        }
    }
    
    // Surface Shader Fallback for Built-in RP (Original version)
    SubShader
    {
        Tags {"Queue"="Transparent" "RenderType"="Transparent"}
        LOD 100

        CGPROGRAM
        #pragma surface surf Lambert alpha

        sampler2D _MainTex;
        fixed4 _Color;
        float _Progress;
        float3 _Center;
        float _Radius;
        fixed4 _GridColor;
        float _GridSize;
        float _GridLineWidth;
        float _ShowGrid;

        struct Input
        {
            float2 uv_MainTex;
            float3 worldPos;
            float3 worldNormal;
        };

        float GetGridFactor(float3 worldPos, float3 worldNormal, float gridSize, float lineWidth)
        {
            float3 absNormal = abs(worldNormal);
            float2 gridCoord;
            
            if (absNormal.y > absNormal.x && absNormal.y > absNormal.z)
            {
                gridCoord = float2(worldPos.x, worldPos.z) / gridSize;
            }
            else if (absNormal.x > absNormal.z)
            {
                gridCoord = float2(worldPos.y, worldPos.z) / gridSize;
            }
            else
            {
                gridCoord = float2(worldPos.x, worldPos.y) / gridSize;
            }
            
            float2 gridFract = frac(abs(gridCoord));
            float2 distToLine = min(gridFract, 1.0 - gridFract);
            float minDistToLine = min(distToLine.x, distToLine.y);
            float gridFactor = 1.0 - smoothstep(0.0, lineWidth, minDistToLine);
            
            return gridFactor;
        }

        void surf (Input IN, inout SurfaceOutput o)
        {
            fixed4 c = tex2D (_MainTex, IN.uv_MainTex) * _Color;
            
            float3 objectSpacePos = mul(unity_WorldToObject, float4(IN.worldPos, 1.0)).xyz;
            float distanceFromCenter = distance(objectSpacePos, _Center);
            float normalizedDistance = distanceFromCenter / _Radius;
            
            float threshold = _Progress;
            
            if (normalizedDistance < threshold)
            {
                float gridFactor = GetGridFactor(IN.worldPos, IN.worldNormal, _GridSize, _GridLineWidth);
                
                float3 finalColor = lerp(c.rgb, _GridColor.rgb, gridFactor * _ShowGrid);
                float finalAlpha = max(c.a, gridFactor * _GridColor.a * _ShowGrid);
                
                o.Albedo = finalColor;
                o.Alpha = finalAlpha;
            }
            else
            {
                o.Albedo = float3(0,0,0);
                o.Alpha = 0;
            }
        }
        ENDCG
    }
    
    FallBack "Sprites/Default"
}