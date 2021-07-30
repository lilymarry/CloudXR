/*
 * Copyright (c) 2021, NVIDIA CORPORATION. All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;


typedef struct
{
    float2 pos;
    float2 texCoord;
} vert;

constant vert quadVerts[] =
{
    // Pixel positions, Texture coordinates
    { {  1,  -1 },  { 1.f, 1.f } },
    { { -1,  -1 },  { 0.f, 1.f } },
    { { -1,   1 },  { 0.f, 0.f } },

    { {  1,  -1 },  { 1.f, 1.f } },
    { { -1,   1 },  { 0.f, 0.f } },
    { {  1,   1 },  { 1.f, 0.f } },
};

typedef struct
{
    // The [[position]] attribute qualifier of this member indicates this value is
    // the clip space position of the vertex when this structure is returned from
    // the vertex shader
    float4 position [[position]];

    // Since this member does not have a special attribute qualifier, the rasterizer
    // will interpolate its value with values of other vertices making up the triangle
    // and pass that interpolated value to the fragment shader for each fragment in
    // that triangle.
    float2 texCoord;
    
    float2 camTexCoord;

} RasterizerData;

vertex RasterizerData
vertexShader(uint vertexID [[ vertex_id ]],
             constant float2* camTexCoord [[buffer(0)]])

{

    RasterizerData out;
    out.position = float4(quadVerts[vertexID].pos.xy, 0, 1);
    out.texCoord = quadVerts[vertexID].texCoord;
    out.camTexCoord = camTexCoord[vertexID];
    return out;
}

float4 ycbcr_to_rgb(texture2d<float, access::sample> texY,
                    texture2d<float, access::sample> texCbCr,
                    float2 texCoord)
{
    constexpr sampler colorSampler(mip_filter::linear,
                                   mag_filter::linear,
                                   min_filter::linear);
    
    const float4x4 ycbcrToRGBTransform = float4x4(
        float4(+1.0000f, +1.0000f, +1.0000f, +0.0000f),
        float4(+0.0000f, -0.3441f, +1.7720f, +0.0000f),
        float4(+1.4020f, -0.7141f, +0.0000f, +0.0000f),
        float4(-0.7010f, +0.5291f, -0.8860f, +1.0000f)
    );
    
    // Sample Y and CbCr textures to get the YCbCr color at the given texture coordinate
    float4 ycbcr = float4(texY.sample(colorSampler, texCoord).r,
                          texCbCr.sample(colorSampler, texCoord).rg, 1.0);
    
    // Return converted RGB color
    return ycbcrToRGBTransform * ycbcr;
}

float4 ycbcr_to_rgb_bt709(texture2d<float, access::sample> texY,
                    texture2d<float, access::sample> texCbCr,
                    float2 texCoord)
{
    constexpr sampler colorSampler(mip_filter::linear,
                                   mag_filter::linear,
                                   min_filter::linear);
    
    const float4x4 ycbcrToRGBTransform = float4x4(
        float4( 1.0000f, 1.0000f, 1.0000f, 0.0000f),
        float4( 0.0000f, -0.1873f, 1.8556f, 0.0000f),
        float4( 1.5748f, -0.4681f, -0.0000f, 0.0000f),
        float4(-0.7905f, 0.3290f, -0.9314f, 1.0000f)
    );
    
    // Sample Y and CbCr textures to get the YCbCr color at the given texture coordinate
    float4 ycbcr = float4(texY.sample(colorSampler, texCoord).r,
                          texCbCr.sample(colorSampler, texCoord).rg, 1.0);
    
    // Return converted RGB color
    return ycbcrToRGBTransform * ycbcr;
}

// Fragment function
fragment float4
fragmentShader(RasterizerData in [[stage_in]],
               texture2d<float, access::sample> texY [[ texture(0) ]],
               texture2d<float, access::sample> texCbCr [[ texture(1) ]])
{
    return ycbcr_to_rgb(texY, texCbCr, in.camTexCoord);
}

float4 lerp(float4 a, float4 b, float l)
{
    return (a * (1.0 - l)) + (b * l);
}

fragment float4
fragmentShaderComposite(RasterizerData in [[stage_in]],
               texture2d<float, access::sample> texY [[ texture(0) ]],
               texture2d<float, access::sample> texCbCr [[ texture(1) ]],
               texture2d<float, access::sample> cxrTexY [[ texture(2) ]],
               texture2d<float, access::sample> cxrTexCbCr [[ texture(3) ]])
{
    float4 arColor = ycbcr_to_rgb(texY, texCbCr, in.texCoord);
    float4 cxrColor = ycbcr_to_rgb_bt709(cxrTexY, cxrTexCbCr, in.texCoord);
    return lerp(arColor, cxrColor, .5);
}

fragment float4
fragmentShaderCompositeXR(RasterizerData in [[stage_in]],
               texture2d<float, access::sample> texY [[ texture(0) ]],
               texture2d<float, access::sample> texCbCr [[ texture(1) ]],
               texture2d<float, access::sample> cxrTexY [[ texture(2) ]],
               texture2d<float, access::sample> cxrTexCbCr [[ texture(3) ]],
               texture2d<float, access::sample> cxrTexAlphaY [[ texture(4) ]],
               texture2d<float, access::sample> cxrTexAlphaCbCr [[ texture(5) ]])
{
    float4 arColor = ycbcr_to_rgb(texY, texCbCr, in.camTexCoord);
    float4 cxrColor = ycbcr_to_rgb_bt709(cxrTexY, cxrTexCbCr, in.texCoord);
    float4 cxrAlpha = ycbcr_to_rgb_bt709(cxrTexAlphaY, cxrTexAlphaCbCr, in.texCoord);
    return lerp(arColor, cxrColor, cxrAlpha.r);
}

typedef struct shader_data
{
    simd_float4x4 viewMatrix;
    simd_float4x4 projectionMatrix;
} shader_data;

typedef struct basicRastOut
{
    float4 position [[position]];
} basicRastOut;
                     
vertex basicRastOut basicVS(uint vertexID [[ vertex_id ]],
                            constant shader_data* data [[ buffer(0) ]],
                            constant float4* verts [[ buffer(1) ]])
{
    basicRastOut result;
    result.position = data->projectionMatrix * data->viewMatrix * verts[vertexID];
    return result;
}

fragment float4 solidColor()
{
    return float4(0, 1, 0, 1);
}

typedef struct texRastOut
{
    float4 position [[position]];
    float2 texCoord;
} texRastOut;

vertex texRastOut triVS(uint vertexID [[ vertex_id ]],
                            constant shader_data* data [[ buffer(0) ]],
                            constant float4* verts [[ buffer(1) ]])
{
    texRastOut result;
    result.position = data->projectionMatrix * data->viewMatrix * verts[vertexID];
    result.texCoord = verts[vertexID].xz;
#if 0
    while(result.texCoord.x < 1.f) result.texCoord.x += 1.f;
    while(result.texCoord.x > 1.f) result.texCoord.x -= 1.f;
    while(result.texCoord.y < 1.f) result.texCoord.y += 1.f;
    while(result.texCoord.y > 1.f) result.texCoord.y -= 1.f;
#endif
    return result;
}

fragment float4 triFS(texRastOut in [[stage_in]],
                      texture2d<float, access::sample> gridTex [[ texture(0) ]])
{
    constexpr sampler colorSampler(mip_filter::linear,
                                   mag_filter::linear,
                                   min_filter::linear,
                                   s_address::repeat,
                                   t_address::repeat);
    float4 gridCol = gridTex.sample(colorSampler, in.texCoord).rgba;
    return gridCol;
}

kernel void copyTextureKernel(texture2d<float, access::read>  inTexture  [[ texture(0) ]],
                          texture2d<float, access::write> outTexture [[ texture(1) ]],
                          uint2                           gid        [[thread_position_in_grid]])
{
    if((gid.x >= outTexture.get_width()) || (gid.y >= outTexture.get_height())) {
        return;
    }

    float4 inColor  = inTexture.read(gid);
    outTexture.write(inColor, gid);
}
