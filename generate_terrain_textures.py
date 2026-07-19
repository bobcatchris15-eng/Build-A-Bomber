import os
import sys
import json
import time
import base64
from pathlib import Path

# Try to import dependencies
try:
    import requests
    import numpy as np
    from PIL import Image, ImageFilter
except ImportError as e:
    print(f"Error: Missing dependencies. Please run: pip install requests numpy pillow")
    sys.exit(1)

OUTPUT_DIR = Path(r"E:\Build-A-Bomber\prototype\assets\textures\terrain")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# Prompts and parameters for each terrain type
# We ask for a top-down, orthographic, tileable seamless texture.
TERRAIN_CONFIGS = {
    "grassland": {
        "prompt": "A seamless tileable top-down texture of flat, warm, desaturated olive-green grassland, dry grass, and sparse soil. Uniform low-angle lighting, matte finish, organic ground details.",
        "roughness_base": 0.95,
        "roughness_wet_detect": False,
        "normal_strength": 8.0
    },
    "marsh": {
        "prompt": "A seamless tileable top-down texture of dark green-brown swamp mud, mossy wet vegetation, and small glossy dark water puddles. Matte soil, wet glossy pockets.",
        "roughness_base": 0.94,
        "roughness_wet_detect": True, # Darker areas will be glossier (lower roughness)
        "normal_strength": 5.0
    },
    "rocky": {
        "prompt": "A seamless tileable top-down texture of broken rocky cliff face, basalt stone slabs, and dark crevices. Slate gray and earth tones, matte rough rock surface.",
        "roughness_base": 0.95,
        "roughness_wet_detect": False,
        "normal_strength": 15.0
    },
    "sand": {
        "prompt": "A seamless tileable top-down texture of warm tan desert sand dunes with soft wind-swept ripples. Matte finish, soft highlights and shadows.",
        "roughness_base": 0.93,
        "roughness_wet_detect": False,
        "normal_strength": 4.0
    },
    "snow_mud": {
        "prompt": "A seamless tileable top-down texture of bright white snow drifts cut through by dark, wet, muddy tire ruts. High contrast, matte snow, highly glossy wet mud.",
        "roughness_base": 0.92,
        "roughness_wet_detect": True, # Darker mud areas will be highly glossy
        "normal_strength": 8.0
    },
    "shallow_water": {
        "prompt": "A seamless tileable top-down texture of clear shallow teal water, soft gentle ripples showing sandy bed underneath. Semi-glossy surface.",
        "roughness_base": 0.3,
        "roughness_wet_detect": False,
        "normal_strength": 3.0
    },
    "blue_water": {
        "prompt": "A seamless tileable top-down texture of deep blue open ocean water with subtle rolling waves and faint sun glints. Uniform low roughness glossy surface.",
        "roughness_base": 0.28,
        "roughness_wet_detect": False,
        "normal_strength": 4.0
    }
}

def generate_albedo(api_key, name, prompt):
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-image:generateContent?key={api_key}"
    headers = {"Content-Type": "application/json"}
    
    payload = {
        "contents": [
            {
                "parts": [
                    {
                        "text": prompt
                    }
                ]
            }
        ],
        "generationConfig": {
            "responseModalities": ["TEXT", "IMAGE"]
        }
    }
    
    response = requests.post(url, json=payload, headers=headers)
    if response.status_code == 200:
        data = response.json()
        try:
            candidates = data.get("candidates", [])
            if candidates:
                parts = candidates[0].get("content", {}).get("parts", [])
                if parts:
                    inline_data = parts[0].get("inlineData", {})
                    img_b64 = inline_data.get("data", "")
                    if img_b64:
                        return base64.b64decode(img_b64)
            print(f"Failed to parse image from response: {data}")
        except Exception as e:
            print(f"Error parsing response: {e}")
    else:
        print(f"HTTP Error {response.status_code}: {response.text}")
    return None

def process_textures(name, albedo_bytes, config):
    albedo_path = OUTPUT_DIR / f"{name}_albedo.png"
    normal_path = OUTPUT_DIR / f"{name}_normal.png"
    rough_path = OUTPUT_DIR / f"{name}_roughness.png"
    
    # Save Albedo
    with open(albedo_path, "wb") as f:
        f.write(albedo_bytes)
    
    img = Image.open(albedo_path)
    # Ensure 512x512 resolution for consistency
    img = img.resize((512, 512), Image.Resampling.LANCZOS)
    img.save(albedo_path)
    
    print(f"Saved Albedo: {albedo_path}")
    
    # 1. Generate Normal Map (Sobel filter over height)
    # Convert to grayscale to use as height
    gray_img = img.convert("L")
    # Soft blur to reduce high frequency noise in normal map
    gray_img = gray_img.filter(ImageFilter.GaussianBlur(radius=1))
    arr = np.array(gray_img, dtype=np.float32) / 255.0
    
    dy, dx = np.gradient(arr)
    strength = config["normal_strength"]
    dx = dx * strength
    dy = dy * strength
    
    magnitude = np.sqrt(dx**2 + dy**2 + 1.0)
    nx = -dx / magnitude
    ny = -dy / magnitude
    nz = 1.0 / magnitude
    
    # Map [-1, 1] to [0, 255]
    r = ((nx * 0.5 + 0.5) * 255).astype(np.uint8)
    g = ((ny * 0.5 + 0.5) * 255).astype(np.uint8)
    b = ((nz * 0.5 + 0.5) * 255).astype(np.uint8)
    
    normal_arr = np.stack((r, g, b), axis=-1)
    normal_img = Image.fromarray(normal_arr)
    normal_img.save(normal_path)
    print(f"Generated Normal Map: {normal_path}")
    
    # 2. Generate Roughness Map
    # Default uniform roughness
    r_val = config["roughness_base"]
    rough_arr = np.full((512, 512), int(r_val * 255), dtype=np.uint8)
    
    if config["roughness_wet_detect"]:
        # Darker pixels in the albedo image indicate water or mud
        # We make darker regions glossier (lower roughness)
        albedo_arr = np.array(img.convert("L"))
        # Normalize to [0, 1]
        normalized_brightness = albedo_arr / 255.0
        
        # Mapping: brightness of 0 (black mud/puddle) -> roughness of 0.15 (glossy)
        # brightness of 0.5+ (grass/snow) -> roughness_base (matte)
        for y in range(512):
            for x in range(512):
                brightness = normalized_brightness[y, x]
                if brightness < 0.5:
                    # Interpolate between glossy and matte
                    t = brightness / 0.5
                    rough_arr[y, x] = int(lerp(0.15, r_val, t) * 255)
                    
    rough_img = Image.fromarray(rough_arr)
    # Convert to RGB since Godot imports RGB roughness maps
    rough_img_rgb = Image.merge("RGB", (rough_img, rough_img, rough_img))
    rough_img_rgb.save(rough_path)
    print(f"Generated Roughness Map: {rough_path}")

def lerp(a, b, t):
    return a + (b - a) * t

def main():
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        print("Error: GEMINI_API_KEY environment variable not set.")
        print("Please set it: $env:GEMINI_API_KEY='your_key'")
        sys.exit(1)
        
    print(f"Starting terrain texture generation pipeline...")
    for name, config in TERRAIN_CONFIGS.items():
        print(f"\n--- Generating: {name} ---")
        albedo_bytes = generate_albedo(api_key, name, config["prompt"])
        if albedo_bytes:
            process_textures(name, albedo_bytes, config)
            time.sleep(3) # Rate limit delay
        else:
            print(f"Skipping {name} due to generation error.")
            
    print("\nTerrain texture pipeline complete!")

if __name__ == "__main__":
    main()
