import os
import sys
import json
import time
from pathlib import Path

# Load prompts
PROMPTS_FILE = Path(r"E:\Build-A-Bomber\image_prompts.json")
OUTPUT_DIR = Path(r"E:\Build-A-Bomber\prototype\assets\temp_images")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

with open(PROMPTS_FILE, "r") as f:
    prompt_categories = json.load(f)

# Flat dictionary of all prompts
all_prompts = {}
for category, items in prompt_categories.items():
    for name, prompt in items.items():
        all_prompts[name] = prompt

def generate_with_google_genai(api_key):
    """Uses the official google-genai SDK"""
    try:
        from google import genai
        from google.genai import types
    except ImportError:
        print("Please install google-genai: pip install google-genai")
        return False

    client = genai.Client(api_key=api_key)
    
    for name, prompt in all_prompts.items():
        target_path = OUTPUT_DIR / f"{name}.jpg"
        if target_path.exists():
            print(f"Skipping {name}, already exists.")
            continue
            
        print(f"Generating image for {name}...")
        try:
            result = client.models.generate_images(
                model='imagen-3.0-generate-002',
                prompt=prompt,
                config=types.GenerateImagesConfig(
                    number_of_images=1,
                    aspect_ratio="1:1",
                    output_mime_type="image/jpeg"
                )
            )
            for i, generated_image in enumerate(result.generated_images):
                image = Image.open(io.BytesIO(generated_image.image.image_bytes))
                image.save(target_path)
                print(f"Saved: {target_path}")
            
            # Rate limit friendly sleep
            time.sleep(2)
        except Exception as e:
            print(f"Failed to generate {name}: {e}")
    return True

def generate_with_google_generativeai(api_key):
    """Uses the legacy google-generativeai SDK"""
    try:
        import google.generativeai as genai
    except ImportError:
        print("Please install google-generativeai: pip install google-generativeai")
        return False

    # Note: Vertex / AI Studio Imagen API endpoints vary. 
    # google-generativeai uses the generative models endpoint or Imagen endpoint.
    # Often, AI Studio Imagen is called using a different API or the Vertex AI SDK.
    # To be safe, we will write a generic requests-based fallback.
    print("Trying legacy SDK is not recommended for Imagen. Using direct API request instead.")
    return False

def generate_with_requests(api_key):
    """Uses standard requests to hit the Gemini API directly"""
    import requests
    import base64
    
    url = f"https://generativelanguage.googleapis.com/v1beta/models/imagen-3.0-generate-002:predict?key={api_key}"
    headers = {"Content-Type": "application/json"}

    for name, prompt in all_prompts.items():
        target_path = OUTPUT_DIR / f"{name}.jpg"
        if target_path.exists():
            print(f"Skipping {name}, already exists.")
            continue
            
        print(f"Generating image for {name}...")
        payload = {
            "instances": [
                {
                    "prompt": prompt
                }
            ],
            "parameters": {
                "sampleCount": 1,
                "aspectRatio": "1:1"
            }
        }
        
        try:
            response = requests.post(url, headers=headers, json=payload)
            if response.status_code == 200:
                data = response.json()
                img_b64 = data["predictions"][0]["bytesBase64Encoded"]
                img_bytes = base64.b64decode(img_b64)
                
                with open(target_path, "wb") as f:
                    f.write(img_bytes)
                print(f"Saved: {target_path}")
            else:
                print(f"Failed to generate {name}: HTTP {response.status_code} - {response.text}")
                
            # Rate limit friendly sleep
            time.sleep(3)
        except Exception as e:
            print(f"Error generating {name}: {e}")

def main():
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        print("Error: GEMINI_API_KEY environment variable not set.")
        print("Please set it: $env:GEMINI_API_KEY='your_key'")
        sys.exit(1)

    print("Checking for SDKs...")
    try:
        import requests
    except ImportError:
        print("Please install requests: pip install requests")
        sys.exit(1)
        
    # We will default to the requests method since it has no dependencies other than requests
    # and is guaranteed to work with standard AI Studio API keys.
    generate_with_requests(api_key)

if __name__ == "__main__":
    main()
