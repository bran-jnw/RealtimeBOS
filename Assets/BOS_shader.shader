Shader "Custom/BOS_shader"
{
    Properties
    {
        _MainTex("Main texture", 2D) = "white" {}
        _ScaleGradient("ScaleGradient", 2D) = "green" {}
        _Amplification("Amplification of delta", Range(0.1, 10.0)) = 4.0
        _LowerCutoff("Cuttoff delta lower", Range(0.0, 1.0)) = 0.05
        _UpperCutoff("Cuttoff delta upper", Range(0.0, 1.0)) = 0.25
    }
    SubShader
    {
        // No culling or depth
        Cull Off ZWrite Off ZTest Always

        //0: pass for greyscale
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

            sampler2D _MainTex;

            fixed4 frag(v2f i) : SV_Target
            {
                float2 uv = i.uv;
                //uv.x = 1.0 - uv.x;
                fixed4 c = tex2D(_MainTex, uv);
                // convert to grey scale
                float grey = c.r * .2989 + c.g * .5870 + c.b * .1140;
                c.rgb = float3(grey, grey, grey);
                
                return c;
            }
            ENDCG
        }

        //1: Pass to create delta
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            v2f vert(appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

            sampler2D _MainTex;
            sampler2D _ReferenceTex;
            sampler2D _ScaleGradient;
            fixed _Amplification;
            fixed _LowerCutoff;
            fixed _UpperCutoff;

            fixed4 frag(v2f i) : SV_Target
            {
                fixed4 c = tex2D(_MainTex, i.uv);
                fixed4 ref = tex2D(_ReferenceTex, i.uv);
                c.rgb = float3(abs(c.r - ref.r), abs(c.g - ref.g), abs(c.b - ref.b));

                return c;
            }
            ENDCG
        }
        
        //2: pass for temporal smoothing
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            v2f vert(appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

            sampler2D _MainTex;
            sampler2D _ReferenceTex;
            fixed _newWeight;

            fixed4 frag(v2f i) : SV_Target
            {
                fixed4 c = tex2D(_MainTex, i.uv);
                fixed4 ref = tex2D(_ReferenceTex, i.uv);

                c = _newWeight * c + (1.0 - _newWeight) * ref;

                return c;
            }
            ENDCG
        }

        //3: pass for denoising
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            v2f vert(appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

            sampler2D _MainTex;  
            half4 _MainTex_TexelSize;

            // https://github.com/BrutPitt/glslSmartDeNoise
            //  smartDeNoise - parameters
            //~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
            //
            //  sampler2D tex     - sampler image / texture
            //  vec2 uv           - actual fragment coord
            //  float sigma  >  0 - sigma Standard Deviation
            //  float kSigma >= 0 - sigma coefficient 
            //      kSigma * sigma  -->  radius of the circular kernel
            //  float threshold   - edge sharpening threshold 

            #define INV_SQRT_OF_2PI 0.39894228040143267793994605993439  // 1.0/SQRT_OF_2PI
            #define INV_PI 0.31830988618379067153776752674503

            fixed4 smartDeNoise(sampler2D tex, float2 uv, float2 size, float sigma, float kSigma, float threshold)
            {
                //ported from OpenGL so have to flip y-axis
                uv = float2(uv.x, 1.0 - uv.y);
                float radius = round(kSigma * sigma);
                float radQ = radius * radius;

                float invSigmaQx2 = 0.5 / (sigma * sigma);      // 1.0 / (sigma^2 * 2.0)
                float invSigmaQx2PI = INV_PI * invSigmaQx2;    // 1/(2 * PI * sigma^2)

                float invThresholdSqx2 = 0.5 / (threshold * threshold);     // 1.0 / (sigma^2 * 2.0)
                float invThresholdSqrt2PI = INV_SQRT_OF_2PI / threshold;   // 1.0 / (sqrt(2*PI) * sigma^2)

                float4 centrPx = tex2D(tex, uv);

                float zBuff = 0.0;
                float4 aBuff = float4(0, 0, 0, 0);

                float2 d;
                for (d.x = -radius; d.x <= radius; d.x++) 
                {
                    float pt = sqrt(radQ - d.x * d.x);       // pt = yRadius: have circular trend
                    for (d.y = -pt; d.y <= pt; d.y++) 
                    {
                        float blurFactor = exp(-dot(d, d) * invSigmaQx2) * invSigmaQx2PI;

                        float4 walkPx = tex2D(tex, uv + d / size);
                        float4 dC = walkPx - centrPx;
                        float deltaFactor = exp(-dot(dC, dC) * invThresholdSqx2) * invThresholdSqrt2PI * blurFactor;

                        zBuff += deltaFactor;
                        aBuff += deltaFactor * walkPx;
                    }
                }
                return aBuff / zBuff;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                float2 size = float2(_MainTex_TexelSize.z, _MainTex_TexelSize.w);
                fixed4 c = smartDeNoise(_MainTex, i.uv, size, 5.0, 2.0, 0.1);
                return c;
            }
            ENDCG
        }

        //4: calculate window diff
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            v2f vert(appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

            sampler2D _MainTex;
            half4 _MainTex_TexelSize;
            sampler2D _ReferenceTex;
            sampler2D _ScaleGradient;
            fixed _Amplification;
            fixed _LowerCutoff;
            fixed _UpperCutoff;

            fixed3 GetWindowAverage(sampler2D tex, float2 uv, float2 texSize, float kernelSize)
            {
                //ported from OpenGL so have to flip y-axis
                //uv = float2(uv.x, 1.0 - uv.y);
                //how much is UV changing based on pixel window size
                float2 deltaUV = float2(kernelSize / texSize.x, kernelSize / texSize.y);
                float2 lowerUV = float2(uv.x - deltaUV.x, uv.y - deltaUV.y);
                float2 upperUV = float2(uv.x + deltaUV.x, uv.y + deltaUV.y);

                float zBuff = 0.0;
                float4 aBuff = float4(0, 0, 0, 0);

                float count = 0;
                float3 accumulatedValue = float3(0, 0, 0);
                float2 d;
                for (d.y = -kernelSize; d.y <= kernelSize; d.y++)
                {
                    for (d.x = -kernelSize; d.x <= kernelSize; d.x++)
                    {
                        float2 currentUV = uv + (d / kernelSize) * deltaUV;
                        float3 pixel = tex2D(tex, currentUV).rgb;
                        accumulatedValue += pixel;
                        ++count;
                    }
                }
                float average = accumulatedValue / count;

                return fixed3(average, average, average);
            }

            fixed4 frag(v2f i) : SV_Target
            {
                fixed4 c = tex2D(_MainTex, i.uv);
                float2 size = float2(_MainTex_TexelSize.z, _MainTex_TexelSize.w);
                float3 windowAverage = GetWindowAverage(_MainTex, i.uv, size, 4.0);

                //using red channel, all should be same since we are in grey scale
                if (windowAverage.r < _LowerCutoff || windowAverage.r > _UpperCutoff)
                {
                    c = 0;
                }

                float scale = saturate(c.r * _Amplification);
                //scale = pow(scale, 0.8);
                float2 uv = float2(scale, 0.5);
                c.rgb = tex2D(_ScaleGradient, uv);

                //grey scale
                //c.rgb = scale * _Amplification; //float3(1, 1, 1) - 

                return c;
            }
            ENDCG
        }
    }
}