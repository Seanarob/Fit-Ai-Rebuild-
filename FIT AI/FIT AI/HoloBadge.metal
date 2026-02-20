#include <metal_stdlib>
using namespace metal;

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 34.45);
    return fract(p.x * p.y);
}

static float noise2D(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

[[ stitchable ]] half4 holoBadge(float2 position, half4 color, float2 size, float2 touch, float touching) {
    float2 safeSize = max(size, float2(1.0));
    float2 uv = position / safeSize;
    float2 toTouch = uv - touch;
    float dist = length(toTouch);

    float touchFalloff = smoothstep(0.65, 0.0, dist) * touching;

    float band = sin((uv.x * 14.0 + uv.y * 7.0 + dot(toTouch, float2(2.0, -3.0))) * 3.14159);
    float hueShift = band * 0.5 + 0.5;
    float3 rainbow = 0.5 + 0.5 * cos(6.28318 * (hueShift + float3(0.0, 0.33, 0.67)));

    float noise = noise2D(uv * 42.0) - 0.5;
    float3 sparkle = noise * 0.12;

    float spec = pow(clamp(1.0 - dist * 3.2, 0.0, 1.0), 8.0);
    float3 highlight = float3(1.0) * (spec * 0.55);

    float3 holo = (rainbow * 0.38 + sparkle) * touchFalloff;
    float3 effect = holo + highlight * touchFalloff;

    float3 baseColor = float3(float(color.r), float(color.g), float(color.b));
    float3 result = baseColor + effect;
    return half4(half(result.x), half(result.y), half(result.z), color.a);
}
