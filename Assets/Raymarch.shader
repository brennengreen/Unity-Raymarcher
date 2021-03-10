// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

Shader "Unlit/Raymarch"
{
    Properties
    {
		_Color("Color", Color) = (1, 1, 1, 1) // Object Color
        _MainTex ("Texture", 2D) = "white" {} // Optional Texture
		_Shininess("Shininess", Float) = 10 // Shininess
		_SpecColor("Specular Color", Color) = (1, 1, 1, 1) // Specular highlights color
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 200

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

			#define MAX_STEPS 1000
			#define MAX_DIST 1000
			#define SURF_DIST 1e-6
            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
				float3 ro : TEXCOORD1;
				float3 hitPos : TEXCOORD2;
				float4 posWorld : TEXCOORD3;
            };

			uniform float4 _LightColor0;

            sampler2D _MainTex;
            float4 _MainTex_ST;

			uniform float4 _Color;
			uniform float4 _SpecColor;
			uniform float _Shininess;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
				o.posWorld = mul(unity_ObjectToWorld, v.vertex);
				o.ro = _WorldSpaceCameraPos;
				o.hitPos = mul(unity_ObjectToWorld, v.vertex);
                return o;
            }


			/* RAY MARCHING / CSG */
			float3x3 rotateX(float theta) {
				float c = cos(theta);
				float s = sin(theta);
				return float3x3(
					float3(1, 0, 0),
					float3(0, c, -s),
					float3(0, s, c)
					);
			}

			float3x3 rotateY(float theta) {
				float c = cos(theta);
				float s = sin(theta);
				return float3x3(
					float3(c, 0, s),
					float3(0, 1, 0),
					float3(-s, 0, c)
					);
			}

			float3x3 rotateZ(float theta) {
				float c = cos(theta);
				float s = sin(theta);
				return float3x3(
					float3(c, -s, 0),
					float3(s, c, 0),
					float3(0, 0, 1)
					);
			}

			float unionSDF(float distA, float distB) {
				return min(distA, distB);
			}

			float intersectSDF(float distA, float distB) {
				return max(distA, distB);
			}

			float differenceSDF(float distA, float distB) {
				return max(distA, -distB);
			}

			float sphereSDF(float3 p, float r) {
				return length(p) - r;
			}

			float cubeSDF(float3 p) {
				float3 q = abs(p) - .5;
				return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
			}

			float boxSDF(float3 p, float3 size) {
				float3 d = abs(p) - (size / 2.0);
				float insideDistance = min(max(d.x, max(d.y, d.z)), 0.0);
				float outsideDistance = length(max(d, 0.0));
				return insideDistance + outsideDistance;
			}

			float cylinderSDF(float3 p, float h, float r) {
				float inOutRadius = length(p.xy) - r;
				float inOutHeight = abs(p.z) - h / 2.0;
				float insideDistance = min(max(inOutRadius, inOutHeight), 0.0);
				float outsideDistance = length(max(float2(inOutRadius, inOutHeight), 0.0));
				return insideDistance + outsideDistance;
			}

			float GetDist(float3 p) {
				p = mul(rotateY(_Time.y / 2.0), p);

				float cylinderRadius = 0.4 + (1.0 - 0.4) * (1.0 + sin(1.7 * _Time.y)) / 2.0;
				float cylinder1 = cylinderSDF(p, 2.0, cylinderRadius);
				float cylinder2 = cylinderSDF(mul(rotateX(radians(90.0)), p), 2.0, cylinderRadius);
				float cylinder3 = cylinderSDF(mul(rotateY(radians(90.0)), p), 2.0, cylinderRadius);
				
				float cube = boxSDF(p, float3(1.8, 1.8, 1.8));
				float sphere = sphereSDF(p, 1.2);

				float ballOffset = 0.4 + 1.0 + sin(1.7 * _Time.y);
				float ballRadius = 0.4;
				float balls = sphereSDF(p - float3(ballOffset, 0.0, 0.0), ballRadius);
				balls = unionSDF(balls, sphereSDF(p + float3(ballOffset, 0.0, 0.0), ballRadius));
				balls = unionSDF(balls, sphereSDF(p - float3(0.0, ballOffset, 0.0), ballRadius));
				balls = unionSDF(balls, sphereSDF(p + float3(0.0, ballOffset, 0.0), ballRadius));
				balls = unionSDF(balls, sphereSDF(p - float3(0.0, 0.0, ballOffset), ballRadius));
				balls = unionSDF(balls, sphereSDF(p + float3(0.0, 0.0, ballOffset), ballRadius));

				float csgNut = differenceSDF(intersectSDF(cube, sphere), unionSDF(cylinder1, unionSDF(cylinder2, cylinder3)));

				return unionSDF(balls, csgNut);
			}

			float Raymarch(float3 ro, float3 rd) {
				float dO = 0;
				float dS;
				for (int i = 0; i < MAX_STEPS; i++) {
					float3 p = ro + dO * rd;
					dS = GetDist(p);
					dO += dS;
					if (dS < SURF_DIST || dO > MAX_DIST) {
						break;
					} // check if hit object or marched past obj
				}

				return dO;
			}

			float3 GetNormal(float3 p) {
				float2 e = float2(1e-2, 0);
				float3 n = GetDist(p) - float3(
					GetDist(p - e.xyy),
					GetDist(p - e.yxy),
					GetDist(p - e.yyx)
					);
				return normalize(n);
			}
			/* RAY MARCHING / CSG | END */

            fixed4 frag (v2f i) : SV_Target
            {
				float2 uv = i.uv;
				float3 ro = i.ro;
				float3 rd = normalize(i.hitPos - ro);

				
				// sample the texture
				float d = Raymarch(ro, rd);
				fixed4 col = 0;

				if (d < MAX_DIST) {
					float3 p = ro + rd * d;
					float3 n = GetNormal(p);
					float3 normalDirection = normalize(n);

					float3 viewDirection = normalize(_WorldSpaceCameraPos - i.posWorld.xyz);
					float3 vert2LightSource = _WorldSpaceLightPos0.xyz - i.posWorld.xyz;
					float oneOverDistance = 1.0 / length(vert2LightSource);
					float attenuation = lerp(1.0, oneOverDistance, _WorldSpaceLightPos0.w);
					float3 lightDirection = _WorldSpaceLightPos0.xyz - i.posWorld.xyz * _WorldSpaceLightPos0.w;

					float3 ambientLighting = UNITY_LIGHTMODEL_AMBIENT.rgb * _Color.rgb;
					float3 diffuseReflection = attenuation * _LightColor0.rgb * _Color.rgb * max(0.0, dot(normalDirection, lightDirection));
					float3 specularReflection;
					if (dot(n, lightDirection) < 0.0) {
						specularReflection = float3(0.0, 0.0, 0.0);
					}
					else {
						specularReflection = attenuation * _LightColor0.rgb * _SpecColor.rgb * pow(max(0.0, dot(reflect(-lightDirection, normalDirection), viewDirection)), _Shininess);
					}
					col.rgb = (ambientLighting + diffuseReflection) * n + specularReflection;
				}
				else {
					discard;
				}

                return col;
            }
            ENDCG
        }
    }
}
