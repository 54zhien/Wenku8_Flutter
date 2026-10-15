#version 460 core
precision highp float;
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform vec4 uRect;
uniform float uMaximum;
uniform float uPlateau;
uniform float uFromBottom;
uniform float uAxis;
uniform float uPrefilter;
uniform float uStage;
uniform vec2 uViewport;
uniform vec2 uOutputPadding;
uniform float uCull;
uniform sampler2D uInput;
uniform sampler2D uSrgbLut;
out vec4 fragColor;

vec4 sampleEncoded(vec2 position) {
    // A backdrop texture can extend beyond the physical viewport. Clamp to
    // painted pixels, not its allocation's opaque clear/padding pixels.
    vec2 validSize = min(uSize, uViewport);
    vec2 inset = min(vec2(2.5), validSize * 0.5);
    vec2 uv = clamp(position, inset, validSize - inset) / uSize;
    #ifdef IMPELLER_TARGET_OPENGLES
        uv.y = 1.0 - uv.y;
    #endif
    return texture(uInput, uv);
}

float decodeChannel(float value) {
    if (value <= 0.04045) return value / 12.92;
    // Piecewise highp Horner EOTF. Every interval is within 0.001 of an
    // encoded 8-bit level (including float32 rounding). Preserve linear-light
    // convolution and all 33 taps, without three LUT reads for every tap.
    // Retain the exact packed LUT only at the short transfer-function knee.
    if (value < 0.05) {
        vec2 code = texture(uSrgbLut, vec2((value * 1023.0 + 0.5) / 1024.0, 0.5)).rg;
        return dot(code, vec2(65280.0 / 65535.0, 255.0 / 65535.0));
    }
    if (value < 0.25) {
        float t = (value - 0.15) * 10.0;
        return (((((0.000006379416885046 * t - 0.000039121598247557) * t
            + 0.000509525782101012) * t + 0.007838617274082615) * t
            + 0.02295415479655049) * t + 0.019606618420798107);
    }
    if (value < 0.5) {
        float t = (value - 0.375) * 8.0;
        return (((((0.000002671273995393 * t - 0.000028294405011234) * t
            + 0.000638359717173892) * t + 0.016470805702481352) * t
            + 0.08094149320872775) * t + 0.11601612687032124);
    }
    float t = (value - 0.75) * 4.0;
    return (((((0.000016817974036288 * t - 0.000166387001686686) * t
        + 0.00350550843236986) * t + 0.08466561379012862) * t
        + 0.3894570892118941) * t + 0.5225215043752115);
}

vec3 decodeSrgb(vec3 srgb) {
    return vec3(decodeChannel(srgb.r), decodeChannel(srgb.g), decodeChannel(srgb.b));
}

vec4 decodeInput(vec4 color) {
    if (color.a <= 0.00001) return vec4(0.0);
    vec3 srgb = clamp(color.rgb / color.a, vec3(0.0), vec3(1.0));
    return vec4(decodeSrgb(srgb) * color.a, color.a);
}

vec3 encodeSrgb(vec3 linear) {
    linear = max(linear, vec3(0.0));
    vec3 encoded = mix(linear * 12.92,
        1.055 * pow(linear, vec3(1.0 / 2.4)) - 0.055,
        step(vec3(0.0031308), linear));
    return mix(encoded, vec3(1.0), step(vec3(0.99999), linear));
}

void main() {
    vec2 position = FlutterFragCoord().xy;
    // Runtime-filter intermediates may cover the whole source texture. Only
    // convolve pixels sampled by a following pass, including its full halo.
    // Pixels beyond that dependency region have no downstream consumers.
    vec2 lower = uRect.xy - uOutputPadding;
    vec2 upper = uRect.xy + uRect.zw + uOutputPadding;
    if (any(lessThan(position, lower)) || any(greaterThan(position, upper))) {
        // No subsequent pass can read this pixel: the bounds include its full
        // convolution/refraction halo. Avoid a full-screen identity texture
        // copy for every intermediate; do not capture/freeze the backdrop.
        fragColor = uCull > 0.5 ? vec4(0.0) : sampleEncoded(position);
        return;
    }
    float distance = position.y - uRect.y;
    if (uFromBottom > 0.5) distance = uRect.w - distance;
    float progress = clamp((distance - uPlateau) / max(1.0, uRect.w - uPlateau), 0.0, 1.0);
    float depth = 1.0 - progress;
    float sigma = uStage < 0.5 ? uPrefilter : uMaximum * depth * depth;
    float residual = uStage < 0.5 ? sigma : sqrt(max(0.0, sigma * sigma - uPrefilter * uPrefilter));
    float alpha = uStage < 0.5 || uAxis < 0.5 || uPrefilter <= 0.0
        ? 1.0 : clamp(sigma * sigma / (uPrefilter * uPrefilter), 0.0, 1.0);
    if (alpha <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }
    // The clear end (or a fully seeded pass) needs no additional convolution.
    // Preserve its encoded pixels directly rather than decode/encode them again.
    if (residual <= 0.01) {
        vec4 encoded = sampleEncoded(position);
        fragColor = encoded.a > 0.00001
            ? vec4(encoded.rgb / encoded.a, 1.0) * alpha : vec4(0.0);
        return;
    }
    vec2 direction = uAxis < 0.5 ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
    vec4 color = decodeInput(sampleEncoded(position));
    float weights = 1.0;
    // Pixel-continuous radius. Dense prefiltering suppresses sparse-tap aliasing
    // at high sigma and high DPR, instead of repeating sharp letter fragments.
    if (residual > 0.01) {
        for (int i = 1; i <= 16; i++) {
            float t = float(i) * (3.0 / 16.0);
            float weight = exp(-0.5 * t * t);
            vec2 offset = direction * (t * residual);
            color += (decodeInput(sampleEncoded(position + offset))
                + decodeInput(sampleEncoded(position - offset))) * weight;
            weights += 2.0 * weight;
        }
    }
    color /= weights;
    // Intermediate filters can include transparent padding at a viewport edge.
    // Normalized convolution removes that padding instead of leaking the sharp
    // original through srcOver at the very top of the physical status bar.
    color = color.a > 0.00001 ? vec4(encodeSrgb(color.rgb / color.a), 1.0) : vec4(0.0);
    // Below the 3dp prefilter, continuously reduce its contribution to the
    // original backdrop. Preserve premultiplication and a fully clear endpoint.
    fragColor = color * alpha;
}
