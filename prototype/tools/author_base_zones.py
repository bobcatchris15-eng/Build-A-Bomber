#!/usr/bin/env python3
"""Author `base_zones` on every bundled map.

Idempotent: skips maps that already have the field. Per-map zone size is
scaled off the map's `map_half_extents` (the same way the procedural
scatter density and the navmesh tile size are scaled), and the zone
centres reuse the existing `spawns[].hq` positions - the maps were
authored around the assumption that those pads sit on flat ground
already, so re-using them avoids new terrain-fit questions.

Run from the prototype/ directory:
    python tools/author_base_zones.py
"""
from __future__ import annotations
import json
import os
import sys

MAPS_DIR = "data/maps"

# 2-player maps always have HQ pads at +/- Z. The fixture's two spawn
# entries - the "player" and the "enemy" - are the same convention
# every bundled map uses (B3 in RTS_CORE_ROADMAP.md). The zone id is
# "north" for the +Z spawn and "south" for the -Z spawn, which is what
# anyone reading the file in isolation will assume.
ZONE_HALF_BY_HALF = [
    (150, 12.5),
    (220, 15.0),
    (250, 17.5),
    (320, 20.0),
    (10**9, 25.0),
]


def zone_half(map_half: float) -> float:
    for ceiling, half in ZONE_HALF_BY_HALF:
        if map_half <= ceiling:
            return half
    return ZONE_HALF_BY_HALF[-1][1]


def is_real_map(path: str) -> bool:
    name = os.path.basename(path)
    return name.endswith(".json") and "surface" not in name and "height" not in name


def author_zones(path: str) -> bool:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)

    if "base_zones" in data:
        print(f"[skip] {os.path.basename(path)} already has base_zones")
        return False

    half = float(data["map_half_extents"])
    zh = zone_half(half)

    spawns = data.get("spawns", [])
    if len(spawns) < 2:
        print(f"[warn] {os.path.basename(path)} has {len(spawns)} spawns, expected 2 - skipping")
        return False

    hqs = [s["hq"] for s in spawns]
    # Sort by z descending so the "north" zone (higher z) gets id "north"
    # - the same convention assign_base_zones()'s tests use. Pads at
    # the same z would tie-break on the spawn's id field.
    hqs_sorted = sorted(hqs, key=lambda h: -h[2])
    zones = []
    names = ["north", "south"]
    for i, hq in enumerate(hqs_sorted[:2]):
        zones.append({
            "id": names[i] if i < len(names) else f"zone_{i}",
            "center": [float(hq[0]), 0.0, float(hq[2])],
            "half_extents": [zh, zh],
        })

    # Insert base_zones right after resource_nodes (the natural sibling
    # in FIELD_SPEC) - works regardless of the file's specific key
    # order, because Python's dict preserves insertion order and we
    # rebuild the dict in that order.
    new_data: dict = {}
    inserted = False
    for k, v in data.items():
        new_data[k] = v
        if k == "resource_nodes":
            new_data["base_zones"] = zones
            inserted = True
    if not inserted:
        # resource_nodes wasn't a top-level key (older map without it)
        # - fall back to inserting at the end.
        new_data["base_zones"] = zones

    with open(path, "w", encoding="utf-8") as f:
        json.dump(new_data, f, indent=1, ensure_ascii=False)
        f.write("\n")
    print(f"[done] {os.path.basename(path)} -> {zh} x {zh} zones at z={hqs_sorted[0][2]} and z={-hqs_sorted[1][2]}")
    return True


def main() -> int:
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    maps_dir = os.path.join(here, MAPS_DIR)
    if not os.path.isdir(maps_dir):
        print(f"maps dir not found: {maps_dir}", file=sys.stderr)
        return 1
    paths = sorted(p for p in (os.path.join(maps_dir, f) for f in os.listdir(maps_dir)) if is_real_map(p))
    if not paths:
        print("no maps found", file=sys.stderr)
        return 1
    touched = 0
    for p in paths:
        if author_zones(p):
            touched += 1
    print(f"Touched {touched} of {len(paths)} map files.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
