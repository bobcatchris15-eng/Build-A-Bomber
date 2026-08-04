import os
import math
import struct
import random
import wave

# Derived from this file's own location, not hardcoded. The previous
# value was an absolute path into a checkout that no longer exists.
AUDIO_DIR = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")
)
SFX_DIR = os.path.join(AUDIO_DIR, "sfx")
MUSIC_DIR = os.path.join(AUDIO_DIR, "music")

os.makedirs(SFX_DIR, exist_ok=True)
os.makedirs(MUSIC_DIR, exist_ok=True)

SAMPLE_RATE = 44100

def write_wav(filepath, samples):
    with wave.open(filepath, 'w') as wav:
        wav.setnchannels(1) # Mono
        wav.setsampwidth(2) # 16-bit
        wav.setframerate(SAMPLE_RATE)
        packed = bytearray()
        for s in samples:
            val = max(-32768, min(32767, int(s * 32767.0)))
            packed.extend(struct.pack('<h', val))
        wav.writeframes(packed)
    print(f"Generated WAV audio file: {filepath}")

def gen_noise(duration, decay=3.0):
    num_samples = int(SAMPLE_RATE * duration)
    samples = []
    for i in range(num_samples):
        t = i / SAMPLE_RATE
        env = math.exp(-decay * t)
        val = (random.random() * 2.0 - 1.0) * env
        samples.append(val)
    return samples

def gen_sine(freq, duration, decay=0.0):
    num_samples = int(SAMPLE_RATE * duration)
    samples = []
    for i in range(num_samples):
        t = i / SAMPLE_RATE
        env = math.exp(-decay * t) if decay > 0 else 1.0
        val = math.sin(2.0 * math.pi * freq * t) * env
        samples.append(val)
    return samples

def gen_pitch_sweep(f_start, f_end, duration, decay=2.0):
    num_samples = int(SAMPLE_RATE * duration)
    samples = []
    phase = 0.0
    for i in range(num_samples):
        t = i / SAMPLE_RATE
        progress = i / num_samples
        freq = f_start + (f_end - f_start) * progress
        phase += 2.0 * math.pi * freq / SAMPLE_RATE
        env = math.exp(-decay * t)
        samples.append(math.sin(phase) * env)
    return samples

# 1. UI Sounds
# sfx_click
click = []
for i in range(int(SAMPLE_RATE * 0.05)):
    t = i / SAMPLE_RATE
    env = math.exp(-80.0 * t)
    val = (math.sin(2.0 * math.pi * 1200.0 * t) + random.random() * 0.5) * env * 0.5
    click.append(val)
write_wav(os.path.join(SFX_DIR, "sfx_click.wav"), click)

# sfx_hover
hover = gen_sine(800.0, 0.03, decay=100.0)
write_wav(os.path.join(SFX_DIR, "sfx_hover.wav"), hover)

# sfx_error
error = []
for i in range(int(SAMPLE_RATE * 0.2)):
    t = i / SAMPLE_RATE
    env = math.exp(-15.0 * t)
    val = math.sin(2.0 * math.pi * 150.0 * t) + math.sin(2.0 * math.pi * 155.0 * t)
    error.append(val * env * 0.4)
write_wav(os.path.join(SFX_DIR, "sfx_error.wav"), error)

# sfx_select
select = gen_pitch_sweep(600.0, 1200.0, 0.12, decay=15.0)
write_wav(os.path.join(SFX_DIR, "sfx_select.wav"), select)

# sfx_place
place_samples = []
n_place = int(SAMPLE_RATE * 0.25)
for i in range(n_place):
    t = i / SAMPLE_RATE
    env = math.exp(-18.0 * t)
    thud = math.sin(2.0 * math.pi * 90.0 * t) * 0.8
    noise = (random.random() * 2.0 - 1.0) * 0.3
    place_samples.append((thud + noise) * env)
write_wav(os.path.join(SFX_DIR, "sfx_place.wav"), place_samples)

# 2. Combat Sounds
# sfx_cannon
cannon = []
n_cannon = int(SAMPLE_RATE * 0.45)
for i in range(n_cannon):
    t = i / SAMPLE_RATE
    env = math.exp(-10.0 * t)
    sub = math.sin(2.0 * math.pi * 65.0 * t) * 0.7
    noise = (random.random() * 2.0 - 1.0) * 0.6
    cannon.append((sub + noise) * env)
write_wav(os.path.join(SFX_DIR, "sfx_cannon.wav"), cannon)

# sfx_machine_gun
mg = []
n_mg = int(SAMPLE_RATE * 0.1)
for i in range(n_mg):
    t = i / SAMPLE_RATE
    env = math.exp(-35.0 * t)
    noise = (random.random() * 2.0 - 1.0) * 0.7
    snap = math.sin(2.0 * math.pi * 800.0 * t) * 0.3
    mg.append((noise + snap) * env)
write_wav(os.path.join(SFX_DIR, "sfx_machine_gun.wav"), mg)

# sfx_laser
laser = gen_pitch_sweep(1400.0, 300.0, 0.2, decay=12.0)
write_wav(os.path.join(SFX_DIR, "sfx_laser.wav"), laser)

# sfx_missile
missile = gen_pitch_sweep(200.0, 800.0, 0.35, decay=6.0)
write_wav(os.path.join(SFX_DIR, "sfx_missile.wav"), missile)

# sfx_explosion
explosion = []
n_exp = int(SAMPLE_RATE * 0.7)
for i in range(n_exp):
    t = i / SAMPLE_RATE
    env = math.exp(-5.0 * t)
    sub = math.sin(2.0 * math.pi * 45.0 * t) * 0.8
    noise = (random.random() * 2.0 - 1.0) * 0.8
    explosion.append((sub + noise) * env)
write_wav(os.path.join(SFX_DIR, "sfx_explosion.wav"), explosion)

# sfx_hit
hit = []
n_hit = int(SAMPLE_RATE * 0.12)
for i in range(n_hit):
    t = i / SAMPLE_RATE
    env = math.exp(-25.0 * t)
    clack = math.sin(2.0 * math.pi * 500.0 * t) * 0.6
    noise = (random.random() * 2.0 - 1.0) * 0.4
    hit.append((clack + noise) * env)
write_wav(os.path.join(SFX_DIR, "sfx_hit.wav"), hit)

# 3. Base & Economy
# sfx_harvest
harvest = []
n_harv = int(SAMPLE_RATE * 0.3)
for i in range(n_harv):
    t = i / SAMPLE_RATE
    env = math.exp(-8.0 * t)
    pulse = math.sin(2.0 * math.pi * 220.0 * t + math.sin(2.0 * math.pi * 20.0 * t) * 2.0)
    harvest.append(pulse * env * 0.5)
write_wav(os.path.join(SFX_DIR, "sfx_harvest.wav"), harvest)

# sfx_construct
construct = gen_pitch_sweep(400.0, 900.0, 0.25, decay=10.0)
write_wav(os.path.join(SFX_DIR, "sfx_construct.wav"), construct)

# 4. Music & Jingles
# sfx_victory
vic = []
n_vic = int(SAMPLE_RATE * 1.5)
chords = [261.63, 329.63, 392.00, 523.25] # C Major tri-chord
for i in range(n_vic):
    t = i / SAMPLE_RATE
    env = math.exp(-2.0 * t)
    val = sum(math.sin(2.0 * math.pi * f * t) for f in chords) * 0.2
    vic.append(val * env)
write_wav(os.path.join(SFX_DIR, "sfx_victory.wav"), vic)

# sfx_defeat
def_samples = []
n_def = int(SAMPLE_RATE * 1.5)
d_chords = [220.00, 261.63, 311.13] # A Minor / Diminished chord
for i in range(n_def):
    t = i / SAMPLE_RATE
    env = math.exp(-2.0 * t)
    val = sum(math.sin(2.0 * math.pi * f * t) for f in d_chords) * 0.25
    def_samples.append(val * env)
write_wav(os.path.join(SFX_DIR, "sfx_defeat.wav"), def_samples)

# Ambient Industrial RTS Loop (12-second synth music track)
print("Generating 12-second ambient industrial music track loop...")
n_music = int(SAMPLE_RATE * 12.0)
music = []
base_freqs = [110.0, 130.81, 146.83, 164.81] # A2, C3, D3, E3
for i in range(n_music):
    t = i / SAMPLE_RATE
    measure = int(t / 3.0) % len(base_freqs)
    freq = base_freqs[measure]
    bass = math.sin(2.0 * math.pi * freq * t) * 0.3
    lead = math.sin(2.0 * math.pi * (freq * 2.0) * t + math.sin(2.0 * math.pi * 4.0 * t)) * 0.15
    rhythm = math.exp(-15.0 * (t % 0.5)) * (random.random() * 0.1)
    sample = (bass + lead + rhythm) * 0.5
    music.append(sample)
write_wav(os.path.join(MUSIC_DIR, "music_main_theme.wav"), music)

print("Procedural audio generation complete!")
