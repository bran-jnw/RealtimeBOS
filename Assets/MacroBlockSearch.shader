Shader "Custom/MacroBlockSearch"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _Amplification("Amplification of velocity", Range(0.0, 14.0)) = 1.0
    }
    SubShader
    {
        // No culling or depth
        Cull Off ZWrite Off ZTest Always

        //0: Pass to do macroblock search
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

            uniform sampler2D _MainTex; //current frame data
            uniform half4 _MainTex_TexelSize;
            uniform sampler2D _PreviousFrame; //should be same size as _MainTex

            // Defines the block dimensions in width & height
            // Pre defined: 
            // BLOCK_SIZE   16px
            // SEARCH_SIZE   7px
            // ^ Defines the search area as (BLOCK_SIZE + SEARCH_SIZE) rectangle for block

            // Returns previous frame value
            float4 prev(int2 xy) 
            {
                float2 uv = (xy + 0.5) * _MainTex_TexelSize.xy;
                return tex2D(_PreviousFrame, uv);
            }

            // Returns current frame value (does not contain g, b, a)
            float4 curr(int2 xy) 
            {
                float2 uv = (xy + 0.5) * _MainTex_TexelSize.xy;
                return float4(tex2D(_MainTex, uv).x, 0.0, 0.0, 1.0);
            }

            // Returns previous frame value with checking for coord bounds
            float prevFrame(int2 xy) 
            {                
                if (xy.x < 0 || xy.y < 0 || xy.x >= int(_MainTex_TexelSize.z) || xy.y >= int(_MainTex_TexelSize.w))
                {
                    return 0.0;
                }
                    
                float2 uv = (xy + 0.5) * _MainTex_TexelSize.xy;
                return tex2D(_PreviousFrame, uv).x;
            }

            // Returns current frame value (does not contain g, b, a) with checking for coord bounds
            float currFrame(int2 xy) 
            {
                if (xy.x < 0 || xy.y < 0 || xy.x >= int(_MainTex_TexelSize.z) || xy.y >= int(_MainTex_TexelSize.w))
                {
                    return 0.0;
                }
                    
                float2 uv = (xy + 0.5) * _MainTex_TexelSize.xy;
                return tex2D(_MainTex, uv).x;
            }

            // Computes Mean Squared Difference between two blocks in the specified location
            //
            // Input is:
            // icoordPrev - coordinates of the previous block.
            //              prev block should stay in place while current block 
            //              is moving trying to find the best match.
            // icoordCurrent - coordinates of the current block.
            float metric(int2 icoordPrev, int2 icoordCurrent) 
            {
                float collector = 0.0;
                float delta = 0.0;

                // As SUM(old - new) ^ 2 / N^2
                for (int2 ij = int2(0, 0); ij.x < 8; ++ij.x)
                {
                    for (ij.y = 0; ij.y < 8; ++ij.y)
                    {
                        delta = prevFrame(icoordPrev + ij) - currFrame(icoordCurrent + ij);
                        delta *= delta;
                        collector += delta;
                    }                        
                }                    

                return collector * 0.015625; // (1/ (16 * 16)) = 0.00390625,  (1/ (8 * 8)) = 0.015625
            }

            // Three step search algorithm third step function, S = 1
            //
            // Input is:
            // icoord - coordinate of the top-left pixel of the block
            float3 threeStepSearchThird(int2 icoord) 
            {
                // Start calculating metric over all block locations
                float3 result = float3(0, 0, 0);

                // Search: 2, 2
                // 
                //  1  2  3
                //         
                //  8  0  4
                //         
                //  7  6  5
                // 
                // 0 - it's your uber driver here

                // -> 0
                result.z = metric(icoord, icoord + int2(0, 0)); result.x = 0.0; result.y = 0.0;
                // -> 1
                float nval = 0.0;
                if ((nval = metric(icoord, icoord + int2(-1, -1))) < result.z) { result.z = nval; result.x = -1.0; result.y = -1.0; }
                // -> 2
                if ((nval = metric(icoord, icoord + int2(0, -1))) < result.z) { result.z = nval; result.x = 0.0; result.y = -1.0; }
                // -> 3 
                if ((nval = metric(icoord, icoord + int2(1, -1))) < result.z) { result.z = nval; result.x = 1.0; result.y = -1.0; }
                // -> 4 
                if ((nval = metric(icoord, icoord + int2(1, 0))) < result.z) { result.z = nval; result.x = 1.0; result.y = 0.0; }
                // -> 5 
                if ((nval = metric(icoord, icoord + int2(1, 1))) < result.z) { result.z = nval; result.x = 1.0; result.y = 1.0; }
                // -> 6 
                if ((nval = metric(icoord, icoord + int2(0, 1))) < result.z) { result.z = nval; result.x = 0.0; result.y = 1.0; }
                // -> 7 
                if ((nval = metric(icoord, icoord + int2(-2, 1))) < result.z) { result.z = nval; result.x = -1.0; result.y = 1.0; }
                // -> 8 
                if ((nval = metric(icoord, icoord + int2(-1, 0))) < result.z) { result.z = nval; result.x = -1.0; result.y = 0.0; }

                return result;
            }


            // Three step search algorithm second step function, S = 2
            //
            // Input is:
            // icoord - coordinate of the top-left pixel of the block
            float3 threeStepSearchSecond(int2 icoord) 
            {
                // Start calculating metric over all block locations
                float3 result = float3(0, 0, 0);

                // Search: 2, 2
                // 
                //  1  2  3
                //         
                //  8  0  4
                //         
                //  7  6  5
                // 
                // 0 - it's your uber driver here

                // -> 0
                result.z = metric(icoord, icoord + int2(0, 0)); result.x = 0.0; result.y = 0.0;
                // -> 1
                float nval = 0.0;
                if ((nval = metric(icoord, icoord + int2(-2, -2))) < result.z) { result.z = nval; result.x = -2.0; result.y = -2.0; }
                // -> 2
                if ((nval = metric(icoord, icoord + int2(0, -2))) < result.z) { result.z = nval; result.x = 0.0; result.y = -2.0; }
                // -> 3 
                if ((nval = metric(icoord, icoord + int2(2, -2))) < result.z) { result.z = nval; result.x = 2.0; result.y = -2.0; }
                // -> 4 
                if ((nval = metric(icoord, icoord + int2(2, 0))) < result.z) { result.z = nval; result.x = 2.0; result.y = 0.0; }
                // -> 5 
                if ((nval = metric(icoord, icoord + int2(2, 2))) < result.z) { result.z = nval; result.x = 2.0; result.y = 2.0; }
                // -> 6 
                if ((nval = metric(icoord, icoord + int2(0, 2))) < result.z) { result.z = nval; result.x = 0.0; result.y = 2.0; }
                // -> 7 
                if ((nval = metric(icoord, icoord + int2(-2, 2))) < result.z) { result.z = nval; result.x = -2.0; result.y = 2.0; }
                // -> 8 
                if ((nval = metric(icoord, icoord + int2(-2, 0))) < result.z) { result.z = nval; result.x = -2.0; result.y = 0.0; }

                return threeStepSearchThird(icoord + int2(result.xy)) + float3(result.xy, 0.0);
            }

            // Three step search algorithm function, entry, S = 4
            //
            // Input is:
            // icoord - coordinate of the top-left pixel of the block
            float3 threeStepSearch(int2 icoord) 
            {
                // Start calculating metric over all block locations
                float3 result = float3(0, 0, 0);

                // Search: 4, 4
                // 
                //  1  2  3
                //         
                //  8  0  4
                //         
                //  7  6  5
                // 
                // 0 - it's your uber driver here

                // -> 0
                result.z = metric(icoord, icoord + int2(0, 0)); result.x = 0.0; result.y = 0.0;
                // -> 1
                float nval = 0.0;
                if ((nval = metric(icoord, icoord + int2(-4, -4))) < result.z) { result.z = nval; result.x = -4.0; result.y = -4.0; }
                // -> 2
                if ((nval = metric(icoord, icoord + int2(0, -4))) < result.z) { result.z = nval; result.x = 0.0; result.y = -4.0; }
                // -> 3 
                if ((nval = metric(icoord, icoord + int2(4, -4))) < result.z) { result.z = nval; result.x = 4.0; result.y = -4.0; }
                // -> 4 
                if ((nval = metric(icoord, icoord + int2(4, 0))) < result.z) { result.z = nval; result.x = 4.0; result.y = 0.0; }
                // -> 5  
                if ((nval = metric(icoord, icoord + int2(4, 4))) < result.z) { result.z = nval; result.x = 4.0; result.y = 4.0; }
                // -> 6  
                if ((nval = metric(icoord, icoord + int2(0, 4))) < result.z) { result.z = nval; result.x = 0.0; result.y = 4.0; }
                // -> 7 
                if ((nval = metric(icoord, icoord + int2(-4, 4))) < result.z) { result.z = nval; result.x = -4.0; result.y = 4.0; }
                // -> 8 
                if ((nval = metric(icoord, icoord + int2(-4, 0))) < result.z) { result.z = nval; result.x = -4.0; result.y = 0.0; }

                return threeStepSearchSecond(icoord + int2(result.xy)) + float3(result.xy, 0.0);
            }

            fixed4 frag(v2f i) : SV_Target
            {
                fixed4 frag = fixed4(0, 0, 0, 1);
                float2 size = float2(_MainTex_TexelSize.z, _MainTex_TexelSize.w);
                //calculate center pixel coordinate
                int2 coord = int2(i.uv.x * size.x, i.uv.y * size.y);

                // The following vector contains (dx, dy, metric) for the block [icoord.x, icoord.y]
                float3 result = threeStepSearch(coord);
                frag.gb = 0.5 + result.xy / 14; //Bound in [-7, 7], so movement can't be larger than 7 pixels in each direction
                frag.a = result.z;                

                return frag;
            }
            ENDCG
        }

        //1: second pass that combines data with underlying image
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

            uniform sampler2D _MainTex; 
            uniform sampler2D _Data;
            uniform fixed _Amplification;

            fixed4 frag(v2f i) : SV_Target
            {
                fixed4 frag = fixed4(0, 0, 0, 1);
                //fixed4 frag = tex2D(_MainTex, i.uv);
                frag.rg = tex2D(_Data, i.uv).bg * _Amplification; //vector
                //frag.r += tex2D(_Data, i.uv).a  * 1000; //delta
                return frag;
            }
            ENDCG
        }
    }
}
