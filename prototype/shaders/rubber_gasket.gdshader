shader_type canvas_item;
// Dark rubber gasket texture - tight radial noise for a moulded rubber look.
// Used as a thin band overlaid on the border of the toolbox panel.
// The base color is driven by the modulate of the node so it can be tinted
// without changing this shader.

uniform float noise_scale = 60.0;
uniform float roughness = 0.55;

// Fast hash
float hash(vec2 p) {
    p = fract(p * vec2(127.1, 311.7));
    p += dot(p, p + 19.19);
    return fract(p.x * p.y);
}

// Value noise
float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
    vec2 p = UV * noise_scale;
    float n = vnoise(p) * 0.6 + vnoise(p * 2.1) * 0.3 + vnoise(p * 4.3) * 0.1;
    
    // Dark rubber base - very dark, slight warm grey-black
    vec3 rubber = mix(vec3(0.06, 0.06, 0.07), vec3(0.14, 0.14, 0.15), n * roughness);
    
    // Subtle specular catch on high spots - rubber has a slight sheen
    float spec = pow(n, 4.0) * 0.15;
    rubber += vec3(spec);
    
    COLOR = vec4(rubber, COLOR.a);
}
