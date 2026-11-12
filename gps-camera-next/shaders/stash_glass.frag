#include <flutter/runtime_effect.glsl>

uniform vec2 inputSize;
uniform vec2 lensOrigin;
uniform vec2 lensSize;
uniform float cornerRadius;
uniform float tintAlpha;
uniform vec3 tint;
uniform float head;
uniform float tail;
uniform float dropRadius;
uniform float dropHalfWidth;
uniform float vertical;
uniform float menuScale;
uniform sampler2D backdrop;
out vec4 fragColor;

vec4 sampleBackdrop(vec2 p) {
    vec2 uv = p / inputSize;
#ifdef IMPELLER_TARGET_OPENGLES
    uv.y = 1.0 - uv.y;
#endif
    return texture(backdrop, uv);
}

float blob(vec2 p, float x, float radius, float halfWidth) {
    return length(vec2(max(abs(p.x - x) - halfWidth, 0.0), p.y - mix(lensSize.y, lensSize.x, vertical) * 0.5)) - radius;
}

float melt(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Stash 0.28.0 GLASS_DROP: a capsule with three trailing, merged beads.
float dropField(vec2 p) {
    float pull = clamp(abs(head - tail) / (dropRadius * 4.0), 0.0, 1.0);
    float r = dropRadius * (1.0 - 0.16 * pull);
    float k = dropRadius * 0.7;
    float d = blob(p, head, r, dropHalfWidth);
    d = melt(d, blob(p, mix(head, tail, 0.34), r * 0.8, dropHalfWidth * 0.6), k);
    d = melt(d, blob(p, mix(head, tail, 0.67), r * 0.6, dropHalfWidth * 0.3), k);
    return melt(d, blob(p, tail, r * 0.42, 0.0), k);
}

void main() {
    vec2 coordinate = FlutterFragCoord().xy;
    // Impeller may supply a clipped snapshot or the full render target.
    vec2 origin = mix(vec2(0.0), lensOrigin, step(lensSize + vec2(2.0), inputSize));
    vec2 p = coordinate - origin;
    float r = dropRadius;
    float depth;
    vec2 n;
    if (r > 0.0) {
        p = mix(p, p.yx, vertical);
        depth = -dropField(p);
        n = normalize(vec2(
            dropField(p + vec2(1.0, 0.0)) - dropField(p - vec2(1.0, 0.0)),
            dropField(p + vec2(0.0, 1.0)) - dropField(p - vec2(0.0, 1.0))
        ) + vec2(0.00001));
        n = mix(n, n.yx, vertical);
    } else {
        vec2 center = lensSize * 0.5;
        r = min(cornerRadius, min(center.x, center.y));
        vec2 q = abs(p - center) - (center - vec2(r));
        vec2 corner = max(q, vec2(0.0));
        depth = r - length(corner) - min(max(q.x, q.y), 0.0);
        vec2 side = mix(vec2(-1.0), vec2(1.0), step(center, p));
        n = (q.x > 0.0 || q.y > 0.0)
            ? normalize(corner + vec2(0.0001)) * side
            : (q.x > q.y ? vec2(side.x, 0.0) : vec2(0.0, side.y));
    }
    if (depth <= 0.0) {
        fragColor = sampleBackdrop(coordinate);
        return;
    }

    if (menuScale > 0.0) {
        // A broad bevel bends the scene at the rim. The centre keeps the
        // underlying shapes visible through the smoky glass.
        float bevel = clamp(1.0 - depth / (r * 0.36), 0.0, 1.0);
        vec2 bent = coordinate - n * r * 0.30 * bevel * bevel;
        vec2 soften = vec2(2.5 * menuScale, 0.0);
        vec3 scene = (sampleBackdrop(bent + soften).rgb
                    + sampleBackdrop(bent - soften).rgb
                    + sampleBackdrop(bent + soften.yx).rgb
                    + sampleBackdrop(bent - soften.yx).rgb) * 0.25;
        vec3 rgb = mix(scene, tint, tintAlpha - 0.12 * bevel);
        float highlight = 0.3 + 0.7 * max(0.0, dot(n, vec2(-0.6, -0.8)));
        float rim = exp(-depth / (1.2 * menuScale));
        rgb = mix(rgb, vec3(1.0), highlight * (0.42 * rim + 0.12 * bevel));
        fragColor = mix(sampleBackdrop(coordinate), vec4(rgb, 1.0),
                        clamp(depth + 0.5, 0.0, 1.0));
        return;
    }

    // Stash 0.28.0 GLASS optics: displacement, colour split and rim light.
    float deep = depth / r;
    float shift = r * max(0.0, 0.7298 * exp(-deep / 0.1684) - 0.0375);
    vec4 mid = sampleBackdrop(coordinate - n * shift);
    vec3 rgb = vec3(
        sampleBackdrop(coordinate - n * shift * 0.92).r,
        mid.g,
        sampleBackdrop(coordinate - n * shift * 1.08).b
    );
    rgb = mix(rgb, tint, tintAlpha);
    float lit = 0.45 + 0.55 * n.y * n.y;
    float light = 0.004 + lit * (
        0.62 * exp(-deep / 0.028) + 0.20 * exp(-deep / 0.11) + 0.04 * exp(-deep / 0.4)
    );
    rgb += (vec3(1.0) - rgb) * light;
    fragColor = mix(sampleBackdrop(coordinate), vec4(rgb, 1.0), clamp(depth + 0.5, 0.0, 1.0));
}
