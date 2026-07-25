import os
import sys
from pathlib import Path

MODLY_DIR = Path(r"C:\Users\Chris\Documents\Modly")
EXT_DIR = MODLY_DIR / "extensions" / "triposg"
VENDOR_DIR = EXT_DIR / "vendor"
MODEL_DIR = MODLY_DIR / "models" / "triposg" / "generate"
OUT_DIR = Path(r"e:\Build-A-Bomber-GitHub\prototype\assets\models\buildings")

if str(EXT_DIR) not in sys.path:
    sys.path.insert(0, str(EXT_DIR))
if str(VENDOR_DIR) not in sys.path:
    sys.path.insert(0, str(VENDOR_DIR))

import torch
from triposg.pipelines.pipeline_triposg import TripoSGPipeline
from PIL import Image
import trimesh
import numpy as np

print("Testing direct TripoSG load and generate...")
device = "cpu"
dtype = torch.float32

print(f"Loading pipeline on {device} ({dtype})...")
pipe = TripoSGPipeline.from_pretrained(str(MODEL_DIR)).to(device, dtype)
print("Pipeline loaded!")

img_path = r"e:\Build-A-Bomber-GitHub\prototype\assets\temp_images\medium_manufactory.png"
image = Image.open(img_path).convert("RGB").resize((512, 512))

print("Running TripoSG inference (20 steps)...")
generator = torch.Generator(device=pipe.device).manual_seed(42)
with torch.no_grad():
    outputs = pipe(
        image=image,
        generator=generator,
        num_inference_steps=20,
        guidance_scale=7.0,
        use_flash_decoder=False,
    ).samples[0]

mesh = trimesh.Trimesh(
    vertices=outputs[0].astype(np.float32),
    faces=np.ascontiguousarray(outputs[1]),
)
out_path = OUT_DIR / "medium_manufactory.glb"
print(f"Exporting to {out_path}...")
mesh.export(str(out_path))
print("medium_manufactory.glb generation SUCCESSFUL!")
