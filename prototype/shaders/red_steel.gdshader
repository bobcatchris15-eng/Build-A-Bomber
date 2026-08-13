shader_type canvas_item;

// Procedural red painted steel with slight grime and depth variation
uniform vec4 base_red : source_color = vec4(0.8, 0.13, 0.13, 1.0);
uniform vec4 dark_red : source_color = vec4(0.5, 0.05, 0.05, 1.0);
uniform vec4 grime_color : source_color = vec4(0.2, 0.05, 0.05, 1.0);

// Simple pseudo-random noise
float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(vec2 x) {
    vec2 p = floor(x);
    vec2 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    float n = p.x + p.y * 57.0;
    return mix(mix(hash(p + vec2(0.0, 0.0)), hash(p + vec2(1.0, 0.0)), f.x),
               mix(hash(p + vec2(0.0, 1.0)), hash(p + vec2(1.0, 1.0)), f.x), f.y);
}

// Fractal Brownian Motion for depth/texture
float fbm(vec2 x) {
    float v = 0.0;
    float a = 0.5;
    vec2 shift = vec2(100.0);
    mat2 rot = mat2(vec2(cos(0.5), sin(0.5)), vec2(-sin(0.5), cos(0.5)));
    for (int i = 0; i < 5; ++i) {
        v += a * noise(x);
        x = rot * x * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

void fragment() {
    // Screen UV for seamless look
    vec2 uv = FRAGCOORD.xy / 200.0;
    
    // Base metal noise
    float n1 = fbm(uv * 3.0);
    
    // Grime passes
    float n2 = fbm(uv * 10.0 + vec2(4.2, 1.1));
    
    // Add subtle vertical streaks (stamped metal stress marks)
    float streak = noise(vec2(uv.x * 20.0, uv.y * 2.0));
    
    // Mix the reds based on the broad noise
    vec4 color = mix(dark_red, base_red, n1 * 0.8 + 0.2);
    
    // Add streaks
    color = mix(color, dark_red, streak * 0.1);
    
    // Add grime in crevices
    float grime_mask = smoothstep(0.4, 0.8, n2) * 0.3;
    color = mix(color, grime_color, grime_mask);
    
    // Mild vignette/edge darkening
    vec2 obj_uv = UV;
    float vignette = 1.0 - smoothstep(0.5, 1.5, length(obj_uv - 0.5) * 2.0);
    color.rgb *= vignette * 0.6 + 0.4;
    
    COLOR = color;
}
