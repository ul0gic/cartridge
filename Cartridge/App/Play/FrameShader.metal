#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut frameVertex(uint vertexID [[vertex_id]], constant float2 &uvScale [[buffer(0)]])
{
    float2 corner = float2(vertexID & 1, (vertexID >> 1) & 1);
    VertexOut out;
    out.position = float4(corner.x * 2.0 - 1.0, 1.0 - corner.y * 2.0, 0.0, 1.0);
    out.uv = corner * uvScale;
    return out;
}

fragment float4 frameFragment(VertexOut in [[stage_in]], texture2d<float> frame [[texture(0)]])
{
    constexpr sampler nearest(filter::nearest, address::clamp_to_edge);
    return float4(frame.sample(nearest, in.uv).rgb, 1.0);
}
