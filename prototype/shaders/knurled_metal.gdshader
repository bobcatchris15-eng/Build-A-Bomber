shader_type canvas_item;

// A simple knurled metal texture shader for drawer handles.
// Creates a diamond/cross-hatch pattern commonly seen on tool handles or knobs.

uniform float pattern_scale = 15.0;
uniform float depth = 0.5;

void fragment() {
    // Basic diamond cross-hatch pattern
    vec2 pos = UV * pattern_scale;
    
    // Diagonal lines
    float line1 = fract(pos.x + pos.y);
    float line2 = fract(pos.x - pos.y);
    
    // Create soft ridges
    float ridge1 = smoothstep(0.3, 0.5, line1) - smoothstep(0.5, 0.7, line1);
    float ridge2 = smoothstep(0.3, 0.5, line2) - smoothstep(0.5, 0.7, line2);
    
    // Combine ridges for a knurled look
    float knurl = max(ridge1, ridge2);
    
    // Mix colors based on the pattern
    vec4 final_color = mix(COLOR * 0.8, COLOR * 1.2, knurl * depth + 0.5);
    
    // Add a slight vertical gradient for a cylindrical/rounded feel
    float v_grad = smoothstep(0.0, 0.3, UV.y) * smoothstep(1.0, 0.7, UV.y);
    final_color.rgb *= mix(0.7, 1.1, v_grad);
    
    COLOR = final_color;
}
