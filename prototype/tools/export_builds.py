#!/usr/bin/env python3
import os
import sys
import re
import datetime
import subprocess

import shutil

def archive_old_builds(root_dir):
    builds_dir = os.path.join(root_dir, "builds")
    old_builds_dir = os.path.join(root_dir, "old_builds")
    
    platforms = ["windows", "linux", "macos"]
    for os_name in platforms:
        src_dir = os.path.join(builds_dir, os_name)
        dst_dir = os.path.join(old_builds_dir, os_name)
        if not os.path.exists(src_dir):
            continue
        os.makedirs(dst_dir, exist_ok=True)
        for item in os.listdir(src_dir):
            src_item = os.path.join(src_dir, item)
            dst_item = os.path.join(dst_dir, item)
            if os.path.isdir(src_item) and item.lower() in ["old builds", "old_builds"]:
                continue
            try:
                if os.path.exists(dst_item):
                    if os.path.isdir(dst_item):
                        shutil.rmtree(dst_item, ignore_errors=True)
                    else:
                        os.remove(dst_item)
                shutil.move(src_item, dst_item)
                print(f"  [ARCHIVE] Moved {item} -> old_builds/{os_name}/")
            except Exception as e:
                print(f"  [ARCHIVE WARNING] Could not move {item}: {e}")

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    proto_dir = os.path.abspath(os.path.join(script_dir, ".."))
    root_dir = os.path.abspath(os.path.join(proto_dir, ".."))
    
    # 1. Archive old builds
    print("=== Archiving Previous Builds ===")
    archive_old_builds(root_dir)

    # 2. Read version from project.godot
    godot_file = os.path.join(proto_dir, "project.godot")
    version = "1.0.0"
    if os.path.exists(godot_file):
        with open(godot_file, "r", encoding="utf-8") as f:
            content = f.read()
            m = re.search(r'config/version="([^"]+)"', content)
            if m:
                version = m.group(1)
    
    today_str = datetime.date.today().strftime("%Y-%m-%d")
    print(f"=== Exporting Kitbash Command v{version} ({today_str}) ===")
    
    godot_exe = os.path.join(proto_dir, "Godot_v4.7.1-stable_win64_console.exe")
    if not os.path.exists(godot_exe):
        godot_exe = "godot"
        
    builds_dir = os.path.join(root_dir, "builds")
    win_dir = os.path.join(builds_dir, "windows")
    lin_dir = os.path.join(builds_dir, "linux")
    mac_dir = os.path.join(builds_dir, "macos")
    
    os.makedirs(win_dir, exist_ok=True)
    os.makedirs(lin_dir, exist_ok=True)
    os.makedirs(mac_dir, exist_ok=True)
    
    win_out = os.path.join(win_dir, f"KitbashCommandPrototype_v{version}_{today_str}.exe")
    lin_out = os.path.join(lin_dir, f"KitbashCommandPrototype_v{version}_{today_str}.x86_64")
    mac_out = os.path.join(mac_dir, f"KitbashCommandPrototype_v{version}_{today_str}.zip")
    
    # Export Windows
    print(f"[1/3] Exporting Windows: {win_out}...")
    staging_dir = os.path.join(proto_dir, "temp_export")
    os.makedirs(staging_dir, exist_ok=True)
    stage_win = os.path.join(staging_dir, f"KitbashCommandPrototype_v{version}_{today_str}.exe")
    if os.path.exists(stage_win):
        try: os.remove(stage_win)
        except Exception: pass

    cmd_win = [godot_exe, "--headless", "--export-release", "Windows Desktop", stage_win, "--path", proto_dir]
    res_win = subprocess.run(cmd_win, capture_output=True, text=True)
    if res_win.returncode == 0 and os.path.exists(stage_win):
        print("  [PASS] Windows export succeeded.")
        # Copy to final destination and un-versioned fallback
        link_win = os.path.join(win_dir, "KitbashCommandPrototype.exe")
        with open(stage_win, "rb") as sf:
            data = sf.read()
        try:
            with open(win_out, "wb") as df:
                df.write(data)
        except PermissionError:
            print("  [NOTE] KitbashCommandPrototype_v1.4.0_2026-08-05.exe is currently running in Windows and could not be overwritten.")
        try:
            with open(link_win, "wb") as df:
                df.write(data)
        except PermissionError:
            print("  [NOTE] KitbashCommandPrototype.exe is currently running in Windows and could not be overwritten.")
        try: os.remove(stage_win)
        except Exception: pass
    else:
        print("  [FAIL] Windows export failed:\n", res_win.stderr)
        
    # Export Linux
    print(f"[2/3] Exporting Linux: {lin_out}...")
    cmd_lin = [godot_exe, "--headless", "--export-release", "Linux", lin_out, "--path", proto_dir]
    res_lin = subprocess.run(cmd_lin, capture_output=True, text=True)
    if res_lin.returncode == 0:
        print("  [PASS] Linux export succeeded.")
        link_lin = os.path.join(lin_dir, "KitbashCommandPrototype.x86_64")
        with open(lin_out, "rb") as sf, open(link_lin, "wb") as df:
            df.write(sf.read())
    else:
        print("  [FAIL] Linux export failed:\n", res_lin.stderr)

    # Export macOS
    print(f"[3/3] Exporting macOS: {mac_out}...")
    cmd_mac = [godot_exe, "--headless", "--export-release", "macOS", mac_out, "--path", proto_dir]
    res_mac = subprocess.run(cmd_mac, capture_output=True, text=True)
    if res_mac.returncode == 0:
        print("  [PASS] macOS export succeeded.")
        link_mac = os.path.join(mac_dir, "KitbashCommandPrototype.zip")
        with open(mac_out, "rb") as sf, open(link_mac, "wb") as df:
            df.write(sf.read())
    else:
        print("  [FAIL] macOS export failed:\n", res_mac.stderr)

    print("\n=== Export Process Complete ===")

if __name__ == "__main__":
    main()
