#include <metal_stdlib>
using namespace metal;

struct LookVertexOut {
    float4 position [[position]];
    float2 uv;
};

struct LookUniforms {
    float2 sourceSize;
    float2 textureSize;
    float2 outputSize;
};

// Port of sharp-bilinear.slang (Themaister, public domain) with auto prescale on.
fragment float4 sharpFragment(
    LookVertexOut in [[stage_in]],
    texture2d<float> frame [[texture(0)]],
    constant LookUniforms &look [[buffer(0)]]
)
{
    constexpr sampler linear(filter::linear, address::clamp_to_edge);
    float2 texel = in.uv * look.textureSize;
    float2 texelFloored = floor(texel);
    float2 s = texel - texelFloored;
    float scale = max(floor(look.outputSize.y / look.sourceSize.y + 0.01), 1.0);
    float regionRange = 0.5 - 0.5 / scale;
    float2 centerDist = s - 0.5;
    float2 f = (centerDist - clamp(centerDist, float2(-regionRange), float2(regionRange))) * scale + 0.5;
    float2 modTexel = clamp(texelFloored + f, float2(0.5), look.sourceSize - 0.5);
    return float4(frame.sample(linear, modTexel / look.textureSize).rgb, 1.0);
}

// Port of crt-lottes.slang (Timothy Lottes, public domain) at its published defaults.
namespace crt {

constant float hardScan = -8.0;
constant float hardPix = -3.0;
constant float warpX = 0.031;
constant float warpY = 0.041;
constant float maskDark = 0.5;
constant float maskLight = 1.5;
constant float brightBoost = 1.0;
constant float hardBloomPix = -1.5;
constant float hardBloomScan = -2.0;
constant float bloomAmount = 0.15;
constant float shape = 2.0;

struct Source {
    texture2d<float> frame;
    float2 sourceSize;
    float2 textureSize;
};

float3 toLinear(float3 c)
{
    return select(pow((c + 0.055) / 1.055, 2.4), c / 12.92, c <= 0.04045);
}

float3 toSrgb(float3 c)
{
    return select(1.055 * pow(c, 0.41666) - 0.055, c * 12.92, c < 0.0031308);
}

float3 fetch(Source src, float2 pos, float2 off)
{
    constexpr sampler nearest(filter::nearest, address::clamp_to_edge);
    float2 texel = floor(pos * src.sourceSize + off);
    if (any(texel < 0.0) || any(texel >= src.sourceSize)) {
        return float3(0.0);
    }
    return toLinear(brightBoost * src.frame.sample(nearest, (texel + 0.5) / src.textureSize).rgb);
}

float2 dist(Source src, float2 pos)
{
    pos = pos * src.sourceSize;
    return -((pos - floor(pos)) - 0.5);
}

float gaus(float pos, float scale)
{
    return exp2(scale * pow(abs(pos), shape));
}

float3 horz3(Source src, float2 pos, float off)
{
    float3 b = fetch(src, pos, float2(-1.0, off));
    float3 c = fetch(src, pos, float2(0.0, off));
    float3 d = fetch(src, pos, float2(1.0, off));
    float dst = dist(src, pos).x;
    float wb = gaus(dst - 1.0, hardPix);
    float wc = gaus(dst + 0.0, hardPix);
    float wd = gaus(dst + 1.0, hardPix);
    return (b * wb + c * wc + d * wd) / (wb + wc + wd);
}

float3 horz5(Source src, float2 pos, float off)
{
    float3 a = fetch(src, pos, float2(-2.0, off));
    float3 b = fetch(src, pos, float2(-1.0, off));
    float3 c = fetch(src, pos, float2(0.0, off));
    float3 d = fetch(src, pos, float2(1.0, off));
    float3 e = fetch(src, pos, float2(2.0, off));
    float dst = dist(src, pos).x;
    float wa = gaus(dst - 2.0, hardPix);
    float wb = gaus(dst - 1.0, hardPix);
    float wc = gaus(dst + 0.0, hardPix);
    float wd = gaus(dst + 1.0, hardPix);
    float we = gaus(dst + 2.0, hardPix);
    return (a * wa + b * wb + c * wc + d * wd + e * we) / (wa + wb + wc + wd + we);
}

float3 horz7(Source src, float2 pos, float off)
{
    float3 a = fetch(src, pos, float2(-3.0, off));
    float3 b = fetch(src, pos, float2(-2.0, off));
    float3 c = fetch(src, pos, float2(-1.0, off));
    float3 d = fetch(src, pos, float2(0.0, off));
    float3 e = fetch(src, pos, float2(1.0, off));
    float3 f = fetch(src, pos, float2(2.0, off));
    float3 g = fetch(src, pos, float2(3.0, off));
    float dst = dist(src, pos).x;
    float wa = gaus(dst - 3.0, hardBloomPix);
    float wb = gaus(dst - 2.0, hardBloomPix);
    float wc = gaus(dst - 1.0, hardBloomPix);
    float wd = gaus(dst + 0.0, hardBloomPix);
    float we = gaus(dst + 1.0, hardBloomPix);
    float wf = gaus(dst + 2.0, hardBloomPix);
    float wg = gaus(dst + 3.0, hardBloomPix);
    return (a * wa + b * wb + c * wc + d * wd + e * we + f * wf + g * wg) / (wa + wb + wc + wd + we + wf + wg);
}

float scan(Source src, float2 pos, float off)
{
    return gaus(dist(src, pos).y + off, hardScan);
}

float bloomScan(Source src, float2 pos, float off)
{
    return gaus(dist(src, pos).y + off, hardBloomScan);
}

float3 tri(Source src, float2 pos)
{
    float3 a = horz3(src, pos, -1.0);
    float3 b = horz5(src, pos, 0.0);
    float3 c = horz3(src, pos, 1.0);
    return a * scan(src, pos, -1.0) + b * scan(src, pos, 0.0) + c * scan(src, pos, 1.0);
}

float3 bloom(Source src, float2 pos)
{
    float3 a = horz5(src, pos, -2.0);
    float3 b = horz7(src, pos, -1.0);
    float3 c = horz7(src, pos, 0.0);
    float3 d = horz7(src, pos, 1.0);
    float3 e = horz5(src, pos, 2.0);
    return a * bloomScan(src, pos, -2.0) + b * bloomScan(src, pos, -1.0) + c * bloomScan(src, pos, 0.0)
        + d * bloomScan(src, pos, 1.0) + e * bloomScan(src, pos, 2.0);
}

float2 warp(float2 pos)
{
    pos = pos * 2.0 - 1.0;
    pos *= float2(1.0 + pos.y * pos.y * warpX, 1.0 + pos.x * pos.x * warpY);
    return pos * 0.5 + 0.5;
}

float3 mask(float2 pos)
{
    float3 mask = float3(maskDark);
    pos.x += pos.y * 3.0;
    pos.x = fract(pos.x * 0.166666666);
    if (pos.x < 0.333) {
        mask.r = maskLight;
    } else if (pos.x < 0.666) {
        mask.g = maskLight;
    } else {
        mask.b = maskLight;
    }
    return mask;
}

}

fragment float4 crtFragment(
    LookVertexOut in [[stage_in]],
    texture2d<float> frame [[texture(0)]],
    constant LookUniforms &look [[buffer(0)]]
)
{
    crt::Source src = {frame, look.sourceSize, look.textureSize};
    float2 coord = in.uv * look.textureSize / look.sourceSize;
    float2 pos = crt::warp(coord);
    float3 color = crt::tri(src, pos);
    color += crt::bloom(src, pos) * crt::bloomAmount;
    color *= crt::mask(coord * look.outputSize * 1.000001);
    return float4(crt::toSrgb(color), 1.0);
}
