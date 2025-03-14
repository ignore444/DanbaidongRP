#ifndef UNIVERSAL_GBUFFERUTIL_INCLUDED
#define UNIVERSAL_GBUFFERUTIL_INCLUDED

#include "Packages/com.unity.render-pipelines.danbaidong/ShaderLibrary/SurfaceData.hlsl"
#include "Packages/com.unity.render-pipelines.danbaidong/ShaderLibrary/Lighting.hlsl"

// inspired from [builtin_shaders]/CGIncludes/UnityGBuffer.cginc

// Non-static meshes with real-time lighting need to write shadow mask, which in that case stores per-object occlusion probe values.
#if !defined(LIGHTMAP_ON) && defined(LIGHTMAP_SHADOW_MIXING) && !defined(SHADOWS_SHADOWMASK)
#define OUTPUT_SHADOWMASK 1 // subtractive
#elif defined(SHADOWS_SHADOWMASK)
#define OUTPUT_SHADOWMASK 2 // shadow mask
#elif defined(_DEFERRED_MIXED_LIGHTING)
#define OUTPUT_SHADOWMASK 3 // we don't know if it's subtractive or just shadowMap (from deferred lighting shader, LIGHTMAP_ON does not need to be defined)
#else
#endif

#if _RENDER_PASS_ENABLED
    #define GBUFFER_OPTIONAL_SLOT_1 GBuffer4
    #define GBUFFER_OPTIONAL_SLOT_1_TYPE float
#if OUTPUT_SHADOWMASK && (defined(_WRITE_RENDERING_LAYERS) || defined(_LIGHT_LAYERS))
    #define GBUFFER_OPTIONAL_SLOT_2 GBuffer5
    #define GBUFFER_OPTIONAL_SLOT_3 GBuffer6
    #define GBUFFER_LIGHT_LAYERS GBuffer5
    #define GBUFFER_SHADOWMASK GBuffer6
#elif OUTPUT_SHADOWMASK
    #define GBUFFER_OPTIONAL_SLOT_2 GBuffer5
    #define GBUFFER_SHADOWMASK GBuffer5
#elif (defined(_WRITE_RENDERING_LAYERS) || defined(_LIGHT_LAYERS))
    #define GBUFFER_OPTIONAL_SLOT_2 GBuffer5
    #define GBUFFER_LIGHT_LAYERS GBuffer5
#endif //#if OUTPUT_SHADOWMASK && defined(_WRITE_RENDERING_LAYERS)
#else
    #define GBUFFER_OPTIONAL_SLOT_1_TYPE float4
#if OUTPUT_SHADOWMASK && (defined(_WRITE_RENDERING_LAYERS) || defined(_LIGHT_LAYERS))
    #define GBUFFER_OPTIONAL_SLOT_1 GBuffer4
    #define GBUFFER_OPTIONAL_SLOT_2 GBuffer5
    #define GBUFFER_LIGHT_LAYERS GBuffer4
    #define GBUFFER_SHADOWMASK GBuffer5
#elif OUTPUT_SHADOWMASK
    #define GBUFFER_OPTIONAL_SLOT_1 GBuffer4
    #define GBUFFER_SHADOWMASK GBuffer4
#elif (defined(_WRITE_RENDERING_LAYERS) || defined(_LIGHT_LAYERS))
    #define GBUFFER_OPTIONAL_SLOT_1 GBuffer4
    #define GBUFFER_LIGHT_LAYERS GBuffer4
#endif //#if OUTPUT_SHADOWMASK && defined(_WRITE_RENDERING_LAYERS)
#endif //#if _RENDER_PASS_ENABLED
#define kLightingInvalid  -1  // No dynamic lighting: can aliase any other material type as they are skipped using stencil
#define kLightingLit       1  // lit shader
#define kLightingSimpleLit 2  // Simple lit shader
// clearcoat 3
// backscatter 4
// skin 5

// Material flags
#define kMaterialFlagReceiveShadowsOff        1 // Does not receive dynamic shadows
#define kMaterialFlagSpecularHighlightsOff    2 // Does not receivce specular
#define kMaterialFlagSubtractiveMixedLighting 4 // The geometry uses subtractive mixed lighting
#define kMaterialFlagSpecularSetup            8 // Lit material use specular setup instead of metallic setup

// Light flags.
#define kLightFlagSubtractiveMixedLighting    4 // The light uses subtractive mixed lighting.

// Character Material flags
#define kCharacterMaterialFlagOutline           1
#define kCharacterMaterialFlagFace              2
#define kCharacterMaterialFlagTemp1             4
#define kCharacterMaterialFlagTemp2             8

struct FragmentOutput
{
    float4 GBuffer0 : SV_Target0;
    float4 GBuffer1 : SV_Target1;
    float4 GBuffer2 : SV_Target2;
    float4 GBuffer3 : SV_Target3; // Camera color attachment

    #ifdef GBUFFER_OPTIONAL_SLOT_1
    GBUFFER_OPTIONAL_SLOT_1_TYPE GBuffer4 : SV_Target4;
    #endif
    #ifdef GBUFFER_OPTIONAL_SLOT_2
    float4 GBuffer5 : SV_Target5;
    #endif
    #ifdef GBUFFER_OPTIONAL_SLOT_3
    float4 GBuffer6 : SV_Target6;
    #endif
};

float PackMaterialFlags(uint materialFlags)
{
    return materialFlags * (1.0h / 255.0h);
}

uint UnpackMaterialFlags(float packedMaterialFlags)
{
    return uint((packedMaterialFlags * 255.0h) + 0.5h);
}

#ifdef _GBUFFER_NORMALS_OCT
float3 PackNormal(float3 n)
{
    float2 octNormalWS = PackNormalOctQuadEncode(n);                  // values between [-1, +1], must use fp32 on some platforms.
    float2 remappedOctNormalWS = saturate(octNormalWS * 0.5 + 0.5);   // values between [ 0, +1]
    return float3(PackFloat2To888(remappedOctNormalWS));               // values between [ 0, +1]
}

float3 UnpackNormal(float3 pn)
{
    float2 remappedOctNormalWS = float2(Unpack888ToFloat2(pn));          // values between [ 0, +1]
    float2 octNormalWS = remappedOctNormalWS.xy * 2.0 - 1.0;// values between [-1, +1]
    return float3(UnpackNormalOctQuadEncode(octNormalWS));              // values between [-1, +1]
}

float3 DecodeNormal(float3 pn)
{
    float2 remappedOctNormalWS = Unpack888ToFloat2(pn);          // values between [ 0, +1]
    float2 octNormalWS = remappedOctNormalWS.xy * 2.0f - 1.0f;// values between [-1, +1]
    return UnpackNormalOctQuadEncode(octNormalWS);              // values between [-1, +1]
}

#else
float3 PackNormal(float3 n)
{ return n; }                                                         // values between [-1, +1]

float3 UnpackNormal(float3 pn)
{ return pn; }                                                        // values between [-1, +1]

float3 DecodeNormal(float3 pn)
{ return pn; }
#endif

// This will encode SurfaceData into GBuffer
FragmentOutput SurfaceDataToGbuffer(SurfaceData surfaceData, InputData inputData, float3 globalIllumination, int lightingMode)
{
    float3 packedNormalWS = PackNormal(inputData.normalWS);

    uint materialFlags = 0;

    // SimpleLit does not use _SPECULARHIGHLIGHTS_OFF to disable specular highlights.

    #ifdef _RECEIVE_SHADOWS_OFF
    materialFlags |= kMaterialFlagReceiveShadowsOff;
    #endif

    #if defined(LIGHTMAP_ON) && defined(_MIXED_LIGHTING_SUBTRACTIVE)
    materialFlags |= kMaterialFlagSubtractiveMixedLighting;
    #endif

    FragmentOutput output;
    output.GBuffer0 = float4(surfaceData.albedo.rgb, PackMaterialFlags(materialFlags));   // albedo          albedo          albedo          materialFlags   (sRGB rendertarget)
    output.GBuffer1 = float4(surfaceData.specular.rgb, surfaceData.occlusion);            // specular        specular        specular        occlusion
    output.GBuffer2 = float4(packedNormalWS, surfaceData.smoothness);                     // encoded-normal  encoded-normal  encoded-normal  smoothness
    output.GBuffer3 = float4(globalIllumination, 1);                                      // GI              GI              GI              unused          (lighting buffer)
    #if _RENDER_PASS_ENABLED
    output.GBuffer4 = inputData.positionCS.z;
    #endif
    #if OUTPUT_SHADOWMASK
    output.GBUFFER_SHADOWMASK = inputData.shadowMask; // will have unity_ProbesOcclusion value if subtractive lighting is used (baked)
    #endif
    #ifdef _WRITE_RENDERING_LAYERS
    uint renderingLayers = GetMeshRenderingLayer();
    output.GBUFFER_LIGHT_LAYERS = float4(EncodeMeshRenderingLayer(renderingLayers), 0.0, 0.0, 0.0);
    #endif

    return output;
}

// This decodes the Gbuffer into a SurfaceData struct
SurfaceData SurfaceDataFromGbuffer(float4 gbuffer0, float4 gbuffer1, float4 gbuffer2, int lightingMode)
{
    SurfaceData surfaceData;

    surfaceData.albedo = gbuffer0.rgb;
    uint materialFlags = UnpackMaterialFlags(gbuffer0.a);
    surfaceData.occlusion = 1.0; // Not used by SimpleLit material.
    surfaceData.specular = gbuffer1.rgb;
    float smoothness = gbuffer2.a;

    surfaceData.metallic = 0.0; // Not used by SimpleLit material.
    surfaceData.alpha = 1.0; // gbuffer only contains opaque materials
    surfaceData.smoothness = smoothness;

    surfaceData.emission = (float3)0; // Note: this is not made available at lighting pass in this renderer - emission contribution is included (with GI) in the value GBuffer3.rgb, that is used as a renderTarget during lighting
    surfaceData.normalTS = (float3)0; // Note: does this normalTS member need to be in SurfaceData? It looks like an intermediate value

    return surfaceData;
}

// This will encode SurfaceData into GBuffer
FragmentOutput BRDFDataToGbuffer(BRDFData brdfData, InputData inputData, float smoothness, float3 globalIllumination, float occlusion = 1.0)
{
    float3 packedNormalWS = PackNormal(inputData.normalWS);

    uint materialFlags = 0;

    #ifdef _RECEIVE_SHADOWS_OFF
    materialFlags |= kMaterialFlagReceiveShadowsOff;
    #endif

    float3 packedSpecular;

    #ifdef _SPECULAR_SETUP
    materialFlags |= kMaterialFlagSpecularSetup;
    packedSpecular = brdfData.specular.rgb;
    #else
    packedSpecular.r = brdfData.reflectivity;
    packedSpecular.gb = 0.0;
    #endif

    #ifdef _SPECULARHIGHLIGHTS_OFF
    // During the next deferred shading pass, we don't use a shader variant to disable specular calculations.
    // Instead, we can either silence specular contribution when writing the gbuffer, and/or reserve a bit in the gbuffer
    // and use this during shading to skip computations via dynamic branching. Fastest option depends on platforms.
    materialFlags |= kMaterialFlagSpecularHighlightsOff;
    packedSpecular = 0.0.xxx;
    #endif

    #if defined(LIGHTMAP_ON) && defined(_MIXED_LIGHTING_SUBTRACTIVE)
    materialFlags |= kMaterialFlagSubtractiveMixedLighting;
    #endif

    FragmentOutput output;
    output.GBuffer0 = float4(brdfData.albedo.rgb, PackMaterialFlags(materialFlags));  // diffuse           diffuse         diffuse         materialFlags   (sRGB rendertarget)
    output.GBuffer1 = float4(packedSpecular, occlusion);                              // metallic/specular specular        specular        occlusion
    output.GBuffer2 = float4(packedNormalWS, smoothness);                             // encoded-normal    encoded-normal  encoded-normal  smoothness
    output.GBuffer3 = float4(globalIllumination, 1);                                  // GI                GI              GI              unused          (lighting buffer)
    #if _RENDER_PASS_ENABLED
    output.GBuffer4 = inputData.positionCS.z;
    #endif
    #if OUTPUT_SHADOWMASK
    output.GBUFFER_SHADOWMASK = inputData.shadowMask; // will have unity_ProbesOcclusion value if subtractive lighting is used (baked)
    #endif
    #ifdef _WRITE_RENDERING_LAYERS
    uint renderingLayers = GetMeshRenderingLayer();
    output.GBUFFER_LIGHT_LAYERS = float4(EncodeMeshRenderingLayer(renderingLayers), 0.0, 0.0, 0.0);
    #endif

    return output;
}

// This decodes the Gbuffer into a SurfaceData struct
BRDFData BRDFDataFromGbuffer(float4 gbuffer0, float4 gbuffer1, float4 gbuffer2)
{
    float3 albedo = gbuffer0.rgb;
    float3 specular = gbuffer1.rgb;
    uint materialFlags = UnpackMaterialFlags(gbuffer0.a);
    float smoothness = gbuffer2.a;

    BRDFData brdfData = (BRDFData)0;
    float alpha = float(1.0); // NOTE: alpha can get modfied, forward writes it out (_ALPHAPREMULTIPLY_ON).

    float3 brdfDiffuse;
    float3 brdfSpecular;
    float reflectivity;
    float oneMinusReflectivity;

    if ((materialFlags & kMaterialFlagSpecularSetup) != 0)
    {
        // Specular setup
        reflectivity = ReflectivitySpecular(specular);
        oneMinusReflectivity = float(1.0) - reflectivity;
        brdfDiffuse = albedo * oneMinusReflectivity;
        brdfSpecular = specular;
    }
    else
    {
        // Metallic setup
        reflectivity = specular.r;
        oneMinusReflectivity = 1.0 - reflectivity;
        float metallic = MetallicFromReflectivity(reflectivity);
        brdfDiffuse = albedo * oneMinusReflectivity;
        brdfSpecular = lerp(kDieletricSpec.rgb, albedo, metallic);
    }
    InitializeBRDFDataDirect(albedo, brdfDiffuse, brdfSpecular, reflectivity, oneMinusReflectivity, smoothness, alpha, brdfData);

    return brdfData;
}

InputData InputDataFromGbufferAndWorldPosition(float4 gbuffer2, float3 wsPos)
{
    InputData inputData = (InputData)0;

    inputData.positionWS = wsPos;
    inputData.normalWS = normalize(UnpackNormal(gbuffer2.xyz)); // normalize() is required because terrain shaders use additive blending for normals (not unit-length anymore)

    inputData.viewDirectionWS = GetWorldSpaceNormalizeViewDir(wsPos.xyz);

    // TODO: pass this info?
    inputData.shadowCoord     = (float4)0;
    inputData.fogCoord        = (float  )0;
    inputData.vertexLighting  = (float3 )0;

    inputData.bakedGI = (float3)0; // Note: this is not made available at lighting pass in this renderer - bakedGI contribution is included (with emission) in the value GBuffer3.rgb, that is used as a renderTarget during lighting

    return inputData;
}


float3 PackColorToR8G8B8(float3 color)
{
    color /= 15.0;
    color = sqrt(color);
    return color;
}
float3 UnPackColorFromR8G8B8(float3 color)
{
    color = color * color;
    color *= 15;
    return color;
}

struct CharacterData
{
    float3 albedo;
    float3 directColor;

    float3 normalWS;
    float rimStrength;
    float useShadow;
    float metallic;
    float smoothness;
    uint materialFlags;
};

// This will encode SurfaceData into GBuffer
FragmentOutput CharacterDataToGbuffer(float3 albedo, float3 directColor, float3 indirectColor, float smoothness, float metallic, float3 normalWS, float isFace = 0.0, float isOutLine = 0.0)
{
    // Pack normal
    float3 packedNormalWS = PackNormal(normalWS);

    // Pack directColor
    directColor = PackColorToR8G8B8(directColor);

    // Pack materialFlags
    uint materialFlags = 0;
    if (isFace == 1.0)
    {
        materialFlags |= kCharacterMaterialFlagFace;
    }
    if (isOutLine == 1.0)
    {
        materialFlags |= kCharacterMaterialFlagOutline;
    }


    // GBuffer3: ColorAttachment format is precisely, no need to pack.
    FragmentOutput output;
    output.GBuffer0 = float4(albedo.rgb, PackMaterialFlags(materialFlags));  // diffuse              diffuse             diffuse             materialFlags   (sRGB albedo will used for additional lighting)
    output.GBuffer1 = float4(directColor.rgb, metallic);                     // direct               direct              direct              metallic        (directLightColor will mul shadow in defered shading)
    output.GBuffer2 = float4(packedNormalWS, smoothness);                    // encoded-normal       encoded-normal      encoded-normal      smoothness      (normal1212)
    output.GBuffer3 = float4(indirectColor, 1);                              // indirect             indirect            indirect            unused          (shadowColor with occlusion applied)

    return output;
}

// This decodes the Gbuffer into a SurfaceData struct
CharacterData CharacterDataFromGbuffer(float4 gbuffer0, float4 gbuffer1, float4 gbuffer2)
{
    float3 albedo = gbuffer0.rgb;
    float3 directColor = gbuffer1.rgb;

    uint materialFlags = UnpackMaterialFlags(gbuffer0.a);
    float metallic = gbuffer1.a;
    float smoothness = gbuffer2.a;

    float3 normalWS = normalize(UnpackNormal(gbuffer2.xyz));

    // materialFlags
    float useShadow = 1.0;
    float rimStrength = 1.0;
    if ((materialFlags & kCharacterMaterialFlagFace) != 0 )
    {
        useShadow = 0.0;
    }
    if ((materialFlags & kCharacterMaterialFlagOutline) != 0)
    {
        // useShadow = 0.0;
        rimStrength = 0.0;
    }

    CharacterData data;
    data.albedo = albedo;
    data.directColor = UnPackColorFromR8G8B8(directColor);
    data.normalWS = normalWS;
    data.rimStrength = rimStrength;
    data.useShadow = useShadow;
    data.metallic = metallic;
    data.smoothness = smoothness;
    data.materialFlags = materialFlags;
    return data;
}

#endif // UNIVERSAL_GBUFFERUTIL_INCLUDED
