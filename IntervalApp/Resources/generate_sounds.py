import wave
import math
import struct
import random
import os

SAMPLE_RATE = 44100
SOUNDS_DIR = "/Users/christopher/Desktop/Vibecoding/Productivity/IntervalApp/IntervalApp/Resources/Sounds"
os.makedirs(SOUNDS_DIR, exist_ok=True)

def write_wav(filename, samples):
    # Normalize and clamp to 16-bit PCM
    filepath = os.path.join(SOUNDS_DIR, filename)
    max_amp = max(max(abs(s) for s in samples), 0.0001)
    scale = 32000.0 / max_amp if max_amp > 1.0 else 32000.0
    
    with wave.open(filepath, 'w') as wav_file:
        wav_file.setnchannels(1) # mono
        wav_file.setsampwidth(2) # 16-bit
        wav_file.setframerate(SAMPLE_RATE)
        
        packed = bytearray()
        for s in samples:
            val = int(max(-32767, min(32767, s * scale)))
            packed.extend(struct.pack('<h', val))
        wav_file.writeframes(packed)
    print(f"Generated {filename} ({len(samples)} samples, {len(samples)/SAMPLE_RATE:.3f}s)")

# Biquad Filter Implementation
class BiquadFilter:
    def __init__(self, filter_type, freq, q=1.0):
        self.x1 = self.x2 = self.y1 = self.y2 = 0.0
        w0 = 2.0 * math.pi * freq / SAMPLE_RATE
        alpha = math.sin(w0) / (2.0 * q)
        cos_w0 = math.cos(w0)
        
        if filter_type == 'lowpass':
            b0 = (1.0 - cos_w0) / 2.0
            b1 = 1.0 - cos_w0
            b2 = (1.0 - cos_w0) / 2.0
            a0 = 1.0 + alpha
            a1 = -2.0 * cos_w0
            a2 = 1.0 - alpha
        elif filter_type == 'bandpass':
            b0 = alpha
            b1 = 0.0
            b2 = -alpha
            a0 = 1.0 + alpha
            a1 = -2.0 * cos_w0
            a2 = 1.0 - alpha
        elif filter_type == 'highpass':
            b0 = (1.0 + cos_w0) / 2.0
            b1 = -(1.0 + cos_w0)
            b2 = (1.0 + cos_w0) / 2.0
            a0 = 1.0 + alpha
            a1 = -2.0 * cos_w0
            a2 = 1.0 - alpha
        else:
            raise ValueError("Unknown filter type")
            
        self.b0 = b0 / a0
        self.b1 = b1 / a0
        self.b2 = b2 / a0
        self.a1 = a1 / a0
        self.a2 = a2 / a0
        
    def process(self, x):
        y = self.b0 * x + self.b1 * self.x1 + self.b2 * self.x2 - self.a1 * self.y1 - self.a2 * self.y2
        self.x2 = self.x1
        self.x1 = x
        self.y2 = self.y1
        self.y1 = y
        return y

# -------------------------------------------------------------
# 1. TASK COMPLETE VARIATIONS
# -------------------------------------------------------------

# A. complete_pencil_single (Clean graphite stroke on thick paper, zero hiss)
def gen_pencil_single():
    duration = 0.09
    num_samples = int(duration * SAMPLE_RATE)
    samples = []
    bp1 = BiquadFilter('bandpass', 1600, q=2.2)
    bp2 = BiquadFilter('bandpass', 750, q=1.8)
    lp = BiquadFilter('lowpass', 3200, q=0.7)
    
    for i in range(num_samples):
        t = i / SAMPLE_RATE
        # Natural double-hump pencil pressure
        env = math.sin(t / duration * math.pi) ** 1.8
        # Micro roughness
        noise = (random.random() * 2.0 - 1.0)
        # Friction tone
        body = math.sin(2.0 * math.pi * 380 * t) * 0.15
        
        filtered = bp1.process(noise) * 0.5 + bp2.process(noise) * 0.35 + body
        val = lp.process(filtered) * env
        samples.append(val)
    return samples

# B. complete_click_wood (Crisp wooden switch / tactile pop)
def gen_click_wood():
    duration = 0.045
    num_samples = int(duration * SAMPLE_RATE)
    samples = []
    
    for i in range(num_samples):
        t = i / SAMPLE_RATE
        env = math.exp(-t * 85.0)
        # Frequency drop
        freq = 620.0 * math.exp(-t * 30.0)
        sine = math.sin(2.0 * math.pi * freq * t)
        sine2 = math.sin(2.0 * math.pi * (freq * 2.6) * t) * 0.25
        # Soft click transient at t=0
        click = (random.random() * 2.0 - 1.0) * math.exp(-t * 350.0) * 0.3
        val = (sine + sine2 + click) * env
        samples.append(val)
    return samples

# C. complete_ding_glass (Pure harmonic glass ping)
def gen_ding_glass():
    duration = 0.14
    num_samples = int(duration * SAMPLE_RATE)
    samples = []
    
    for i in range(num_samples):
        t = i / SAMPLE_RATE
        env1 = math.exp(-t * 22.0)
        env2 = math.exp(-t * 40.0)
        f1 = 1320.0 # E6
        f2 = 2640.0 # Harmonic
        f3 = 3960.0 # Upper bell
        s1 = math.sin(2.0 * math.pi * f1 * t) * env1 * 0.7
        s2 = math.sin(2.0 * math.pi * f2 * t) * env2 * 0.25
        s3 = math.sin(2.0 * math.pi * f3 * t) * math.exp(-t * 80.0) * 0.08
        samples.append(s1 + s2 + s3)
    return samples

# D. complete_kalimba_pluck (Warm acoustic kalimba / marimba pluck)
def gen_kalimba_pluck():
    duration = 0.12
    num_samples = int(duration * SAMPLE_RATE)
    samples = []
    
    for i in range(num_samples):
        t = i / SAMPLE_RATE
        env = math.exp(-t * 28.0)
        f0 = 784.0 # G5
        f1 = f0 * 2.76 # Tine harmonic
        s0 = math.sin(2.0 * math.pi * f0 * t) * 0.75
        s1 = math.sin(2.0 * math.pi * f1 * t) * 0.25 * math.exp(-t * 60.0)
        warmth = math.sin(2.0 * math.pi * (f0 / 2.0) * t) * 0.15 * math.exp(-t * 40.0)
        samples.append((s0 + s1 + warmth) * env)
    return samples

# E. complete_sub_thud (Deep soft rounded tick)
def gen_sub_thud():
    duration = 0.04
    num_samples = int(duration * SAMPLE_RATE)
    samples = []
    
    for i in range(num_samples):
        t = i / SAMPLE_RATE
        env = math.exp(-t * 90.0)
        freq = 240.0 * math.exp(-t * 45.0)
        sine = math.sin(2.0 * math.pi * freq * t)
        samples.append(sine * env)
    return samples


# -------------------------------------------------------------
# 2. TASK DELETION VARIATIONS (No mechanical artifacts)
# -------------------------------------------------------------

# A. delete_paper_sweep (Silky clean paper whoosh across desk)
def gen_paper_sweep():
    duration = 0.11
    num_samples = int(duration * SAMPLE_RATE)
    samples = []
    bp = BiquadFilter('bandpass', 1100, q=1.2)
    lp = BiquadFilter('lowpass', 2400, q=0.7)
    
    for i in range(num_samples):
        t = i / SAMPLE_RATE
        # Asymmetric smooth swell and fade
        if t < 0.03:
            env = math.sin((t / 0.03) * (math.pi / 2.0))
        else:
            env = math.exp(-(t - 0.03) * 35.0)
            
        noise = (random.random() * 2.0 - 1.0)
        # Gentle dynamic filter sweep
        val = lp.process(bp.process(noise)) * env * 0.7
        samples.append(val)
    return samples

# B. delete_velvet_poof (Warm breathy vacuum poof)
def gen_velvet_poof():
    duration = 0.12
    num_samples = int(duration * SAMPLE_RATE)
    samples = []
    lp = BiquadFilter('lowpass', 450, q=0.9)
    
    for i in range(num_samples):
        t = i / SAMPLE_RATE
        env = math.exp(-t * 32.0)
        freq = 160.0 * math.exp(-t * 24.0)
        sine = math.sin(2.0 * math.pi * freq * t) * 0.7
        noise = (random.random() * 2.0 - 1.0) * math.exp(-t * 40.0) * 0.3
        filtered_noise = lp.process(noise)
        samples.append((sine + filtered_noise) * env)
    return samples

# C. delete_leaf_flick (Clean organic paper flick)
def gen_leaf_flick():
    duration = 0.08
    num_samples = int(duration * SAMPLE_RATE)
    samples = []
    bp = BiquadFilter('bandpass', 1400, q=1.8)
    
    for i in range(num_samples):
        t = i / SAMPLE_RATE
        # Two micro pulses (flick + snap)
        p1 = math.exp(-t * 120.0)
        p2 = math.exp(-max(0.0, t - 0.015) * 80.0) * 0.6 if t >= 0.015 else 0.0
        env = p1 + p2
        noise = (random.random() * 2.0 - 1.0)
        body = math.sin(2.0 * math.pi * 320 * t) * 0.2 * math.exp(-t * 60.0)
        samples.append((bp.process(noise) * 0.7 + body) * env)
    return samples

# D. delete_drop_sub (Warm sub-harmonic dissolve)
def gen_drop_sub():
    duration = 0.10
    num_samples = int(duration * SAMPLE_RATE)
    samples = []
    
    for i in range(num_samples):
        t = i / SAMPLE_RATE
        env = math.exp(-t * 30.0)
        f = 260.0 * (1.0 - t / duration * 0.8) # Pitch sweep downwards
        sine = math.sin(2.0 * math.pi * f * t) * 0.8
        sub = math.sin(2.0 * math.pi * (f / 2.0) * t) * 0.3
        samples.append((sine + sub) * env)
    return samples


# -------------------------------------------------------------
# 3. TRANSFER VARIATIONS (Liste zu Main / Scratchpad)
# -------------------------------------------------------------

# A. transfer_velvet_glide (Smooth silky glide)
def gen_transfer_glide():
    duration = 0.12
    num_samples = int(duration * SAMPLE_RATE)
    samples = []
    bp = BiquadFilter('bandpass', 850, q=1.4)
    
    for i in range(num_samples):
        t = i / SAMPLE_RATE
        env = math.sin(t / duration * math.pi) ** 1.5
        noise = (random.random() * 2.0 - 1.0)
        # Rising tone
        tone_freq = 440.0 + (t / duration) * 380.0
        tone = math.sin(2.0 * math.pi * tone_freq * t) * 0.25
        val = (bp.process(noise) * 0.5 + tone) * env
        samples.append(val)
    return samples

# B. transfer_wood_chime (Ascending warm wooden two-tone C5 -> G5)
def gen_transfer_wood_chime():
    duration = 0.15
    num_samples = int(duration * SAMPLE_RATE)
    samples = []
    
    t_split = 0.05
    for i in range(num_samples):
        t = i / SAMPLE_RATE
        # Note 1: 523Hz (C5)
        env1 = math.exp(-t * 40.0)
        s1 = math.sin(2.0 * math.pi * 523.25 * t) * env1 * 0.6
        
        # Note 2: 784Hz (G5) at t >= 0.05
        if t >= t_split:
            t2 = t - t_split
            env2 = math.exp(-t2 * 35.0)
            s2 = math.sin(2.0 * math.pi * 783.99 * t2) * env2 * 0.6
        else:
            s2 = 0.0
            
        samples.append(s1 + s2)
    return samples

# C. transfer_magnetic_slide (Ceramic slide & lock click)
def gen_transfer_magnetic():
    duration = 0.09
    num_samples = int(duration * SAMPLE_RATE)
    samples = []
    bp = BiquadFilter('bandpass', 1200, q=2.0)
    
    for i in range(num_samples):
        t = i / SAMPLE_RATE
        # Slide in first 60ms
        slide_env = math.sin((min(0.06, t) / 0.06) * math.pi) if t < 0.06 else 0.0
        slide = bp.process(random.random() * 2.0 - 1.0) * slide_env * 0.4
        
        # Lock click at 0.055s
        if t >= 0.055:
            tc = t - 0.055
            click_env = math.exp(-tc * 140.0)
            click_tone = math.sin(2.0 * math.pi * 880.0 * tc) * 0.7 * click_env
        else:
            click_tone = 0.0
            
        samples.append(slide + click_tone)
    return samples

# D. transfer_air_swell (Serene gentle harmonic swell)
def gen_transfer_air_swell():
    duration = 0.13
    num_samples = int(duration * SAMPLE_RATE)
    samples = []
    
    for i in range(num_samples):
        t = i / SAMPLE_RATE
        env = math.sin(t / duration * math.pi) ** 1.6
        f = 587.33 # D5
        s = math.sin(2.0 * math.pi * f * t) * 0.5
        h = math.sin(2.0 * math.pi * (f * 2) * t) * 0.15
        samples.append((s + h) * env)
    return samples


# -------------------------------------------------------------
# 4. UNDO / RESTORE VARIATIONS (Completed zurückholen)
# -------------------------------------------------------------

# A. undo_reverse_whoosh (Clean reverse suction & gentle landing)
def gen_undo_reverse_whoosh():
    duration = 0.11
    num_samples = int(duration * SAMPLE_RATE)
    samples = []
    bp = BiquadFilter('bandpass', 950, q=1.5)
    
    for i in range(num_samples):
        t = i / SAMPLE_RATE
        # Reverse swell: rises gently and drops quickly at the end
        if t < 0.085:
            env = (t / 0.085) ** 2.2
        else:
            env = math.exp(-(t - 0.085) * 80.0)
            
        noise = (random.random() * 2.0 - 1.0)
        tone_freq = 600.0 * (1.0 - (t / duration) * 0.4)
        tone = math.sin(2.0 * math.pi * tone_freq * t) * 0.25
        val = (bp.process(noise) * 0.55 + tone) * env
        samples.append(val)
    return samples

# B. undo_rebound_pop (Cheerful bouncy pitch rebound)
def gen_undo_rebound_pop():
    duration = 0.075
    num_samples = int(duration * SAMPLE_RATE)
    samples = []
    
    for i in range(num_samples):
        t = i / SAMPLE_RATE
        env = math.exp(-t * 55.0)
        # Pitch rises upward (rebound effect): 320Hz -> 640Hz
        freq = 320.0 + (t / duration) * 320.0
        sine = math.sin(2.0 * math.pi * freq * t) * 0.8
        warmth = math.sin(2.0 * math.pi * (freq / 2.0) * t) * 0.2
        samples.append((sine + warmth) * env)
    return samples

# C. undo_paper_unfold (Clean organic paper un-crease)
def gen_undo_paper_unfold():
    duration = 0.09
    num_samples = int(duration * SAMPLE_RATE)
    samples = []
    bp = BiquadFilter('bandpass', 1250, q=1.6)
    
    for i in range(num_samples):
        t = i / SAMPLE_RATE
        env = math.sin(t / duration * math.pi) * math.exp(-t * 25.0)
        noise = (random.random() * 2.0 - 1.0)
        tone = math.sin(2.0 * math.pi * 420.0 * t) * 0.2
        samples.append((bp.process(noise) * 0.65 + tone) * env)
    return samples

# D. undo_elastic_thud (Soft elastic rebound snap)
def gen_undo_elastic_thud():
    duration = 0.055
    num_samples = int(duration * SAMPLE_RATE)
    samples = []
    
    for i in range(num_samples):
        t = i / SAMPLE_RATE
        env = math.exp(-t * 70.0)
        # Modulated elastic pitch
        freq = 280.0 + 80.0 * math.sin(2.0 * math.pi * 35.0 * t)
        sine = math.sin(2.0 * math.pi * freq * t) * 0.8
        samples.append(sine * env)
    return samples


# -------------------------------------------------------------
# 5. HABIT CHECK VARIATIONS
# -------------------------------------------------------------

def gen_habit_wood():
    duration = 0.065
    num_samples = int(duration * SAMPLE_RATE)
    samples = []
    for i in range(num_samples):
        t = i / SAMPLE_RATE
        env = math.exp(-t * 55.0)
        s1 = math.sin(2.0 * math.pi * 480.0 * t) * 0.7
        s2 = math.sin(2.0 * math.pi * 1280.0 * t) * 0.25 * math.exp(-t * 90.0)
        samples.append((s1 + s2) * env)
    return samples

def gen_habit_droplet():
    duration = 0.075
    num_samples = int(duration * SAMPLE_RATE)
    samples = []
    for i in range(num_samples):
        t = i / SAMPLE_RATE
        env = math.exp(-t * 50.0)
        # Rising pitch droplet
        freq = 600.0 + (t / duration) * 800.0
        sine = math.sin(2.0 * math.pi * freq * t) * 0.8
        samples.append(sine * env)
    return samples

def gen_habit_bell():
    duration = 0.10
    num_samples = int(duration * SAMPLE_RATE)
    samples = []
    for i in range(num_samples):
        t = i / SAMPLE_RATE
        env = math.exp(-t * 35.0)
        s1 = math.sin(2.0 * math.pi * 1760.0 * t) * 0.7 # A6
        s2 = math.sin(2.0 * math.pi * 3520.0 * t) * 0.2 * math.exp(-t * 70.0)
        samples.append((s1 + s2) * env)
    return samples


# -------------------------------------------------------------
# MAIN GENERATION EXECUTION
# -------------------------------------------------------------
if __name__ == "__main__":
    print("Synthesizing studio-grade organic sound effects...")
    
    # 1. Complete
    write_wav("complete_pencil_single.wav", gen_pencil_single())
    write_wav("complete_click_wood.wav", gen_click_wood())
    write_wav("complete_ding_glass.wav", gen_ding_glass())
    write_wav("complete_kalimba_pop.wav", gen_kalimba_pluck())
    write_wav("complete_sub_thud.wav", gen_sub_thud())
    
    # 2. Delete
    write_wav("delete_paper_sweep.wav", gen_paper_sweep())
    write_wav("delete_velvet_poof.wav", gen_velvet_poof())
    write_wav("delete_leaf_flick.wav", gen_leaf_flick())
    write_wav("delete_drop_sub.wav", gen_drop_sub())
    
    # 3. Transfer
    write_wav("transfer_velvet_glide.wav", gen_transfer_glide())
    write_wav("transfer_wood_chime.wav", gen_transfer_wood_chime())
    write_wav("transfer_magnetic_slide.wav", gen_transfer_magnetic())
    write_wav("transfer_air_swell.wav", gen_transfer_air_swell())
    
    # 4. Undo / Restore
    write_wav("undo_reverse_whoosh.wav", gen_undo_reverse_whoosh())
    write_wav("undo_rebound_pop.wav", gen_undo_rebound_pop())
    write_wav("undo_paper_unfold.wav", gen_undo_paper_unfold())
    write_wav("undo_elastic_thud.wav", gen_undo_elastic_thud())
    
    # 5. Habits
    write_wav("habit_check_wood.wav", gen_habit_wood())
    write_wav("habit_check_droplet.wav", gen_habit_droplet())
    write_wav("habit_check_bell.wav", gen_habit_bell())
    
    print("All sounds synthesized successfully!")
