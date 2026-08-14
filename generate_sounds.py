import wave
import math
import random
import struct
import os

SAMPLE_RATE = 44100

def clamp(v, min_v=-1.0, max_v=1.0):
    return max(min_v, min(max_v, v))

def write_wav(filename, samples):
    with wave.open(filename, 'w') as wav:
        wav.setnchannels(1) # Mono
        wav.setsampwidth(2) # 16-bit
        wav.setframerate(SAMPLE_RATE)
        max_amp = max(max(abs(s) for s in samples), 0.0001)
        normalized = [s / max_amp * 0.88 for s in samples]
        packed = struct.pack(f'<{len(normalized)}h', *[int(clamp(s) * 32767) for s in normalized])
        wav.writeframes(packed)

class BiquadFilter:
    def __init__(self, filter_type, freq, q=1.0):
        w0 = 2 * math.pi * freq / SAMPLE_RATE
        alpha = math.sin(w0) / (2 * q)
        cos_w0 = math.cos(w0)
        
        if filter_type == 'bandpass':
            self.b0 = math.sin(w0) / 2
            self.b1 = 0
            self.b2 = -math.sin(w0) / 2
            self.a0 = 1 + alpha
            self.a1 = -2 * cos_w0
            self.a2 = 1 - alpha
        elif filter_type == 'lowpass':
            self.b0 = (1 - cos_w0) / 2
            self.b1 = 1 - cos_w0
            self.b2 = (1 - cos_w0) / 2
            self.a0 = 1 + alpha
            self.a1 = -2 * cos_w0
            self.a2 = 1 - alpha
        elif filter_type == 'highpass':
            self.b0 = (1 + cos_w0) / 2
            self.b1 = -(1 + cos_w0)
            self.b2 = (1 + cos_w0) / 2
            self.a0 = 1 + alpha
            self.a1 = -2 * cos_w0
            self.a2 = 1 - alpha

        self.b0 /= self.a0
        self.b1 /= self.a0
        self.b2 /= self.a0
        self.a1 /= self.a0
        self.a2 /= self.a0
        
        self.x1 = 0.0
        self.x2 = 0.0
        self.y1 = 0.0
        self.y2 = 0.0

    def process(self, x):
        y = self.b0 * x + self.b1 * self.x1 + self.b2 * self.x2 - self.a1 * self.y1 - self.a2 * self.y2
        self.x2 = self.x1
        self.x1 = x
        self.y2 = self.y1
        self.y1 = y
        return y

# ==========================================
# 1. PENCIL STRIKETHROUGH (ASMR Graphite on Paper)
# ==========================================

# A: Single decisive, authentic ASMR pencil line across paper (260ms)
def make_pencil_single_stroke(duration=0.26):
    num_samples = int(SAMPLE_RATE * duration)
    samples = []
    
    # Paper & Graphite Resonators
    bp_paper_body = BiquadFilter('bandpass', 1450, q=2.0)
    bp_lead_grain = BiquadFilter('bandpass', 3400, q=3.2)
    bp_lead_hiss = BiquadFilter('bandpass', 5800, q=4.0)
    lp_master = BiquadFilter('lowpass', 7800, q=0.7)
    lp_contact = BiquadFilter('lowpass', 320, q=1.5)
    
    # Random fiber micro-bumps along the line
    fiber_bumps = [0.0] * num_samples
    for _ in range(35):
        idx = int(random.uniform(0.08, 0.85) * num_samples)
        amp = random.uniform(0.2, 0.6)
        for k in range(min(80, num_samples - idx)):
            fiber_bumps[idx + k] += amp * math.exp(-k / 20) * random.choice([-1, 1])

    for i in range(num_samples):
        progress = i / num_samples
        t = i / SAMPLE_RATE
        
        # Velocity curve: initial lead touch -> fast acceleration -> steady slide -> smooth lift-off
        if progress < 0.12:
            env = math.sin((progress / 0.12) * (math.pi / 2)) * 1.1
        elif progress < 0.75:
            # Subtle natural pressure micro-flutter
            env = 1.0 - (progress - 0.12) * 0.25 + math.sin(2 * math.pi * 95 * t) * 0.08
        else:
            env = 0.84 * math.exp(-(progress - 0.75) * 16)
            
        noise = random.uniform(-1, 1) + fiber_bumps[i]
        
        # Lead touch impact transient at t=0
        touch_thud = lp_contact.process(random.uniform(-1, 1)) * (math.exp(-progress * 45) if progress < 0.15 else 0)
        
        # Multilayer graphite friction
        grain = bp_lead_grain.process(noise) * 0.75
        hiss = bp_lead_hiss.process(noise) * 0.45
        body = bp_paper_body.process(noise) * 0.6
        
        sig = lp_master.process(grain + hiss + body + touch_thud * 0.9) * max(0.0, env)
        samples.append(sig)
    return samples

# B: Double-stroke ASMR pencil cross-out (Zzh-Zzh, 320ms)
def make_pencil_double_stroke(duration=0.32):
    num_samples = int(SAMPLE_RATE * duration)
    samples = []
    
    bp1 = BiquadFilter('bandpass', 3200, q=3.0)
    bp2 = BiquadFilter('bandpass', 5400, q=3.8)
    lp = BiquadFilter('lowpass', 7500, q=0.8)
    
    stroke1_end = 0.42
    stroke2_start = 0.48
    
    for i in range(num_samples):
        progress = i / num_samples
        
        if progress < stroke1_end:
            p = progress / stroke1_end
            env = math.sin(p * math.pi) * 0.95
        elif progress < stroke2_start:
            env = 0.03 # Brief micro-gap
        else:
            p = (progress - stroke2_start) / (1.0 - stroke2_start)
            env = (math.sin(p * math.pi) ** 1.1) * 1.05
            
        noise = random.uniform(-1, 1)
        friction = bp1.process(noise) * 0.7 + bp2.process(noise) * 0.5
        sig = lp.process(friction) * env
        samples.append(sig)
    return samples

# C: Soft velvety graphite sweep (220ms)
def make_pencil_soft_sweep(duration=0.22):
    num_samples = int(SAMPLE_RATE * duration)
    samples = []
    
    bp_warm = BiquadFilter('bandpass', 2200, q=2.2)
    bp_crisp = BiquadFilter('bandpass', 4100, q=2.8)
    lp = BiquadFilter('lowpass', 6000, q=0.7)
    
    for i in range(num_samples):
        progress = i / num_samples
        env = (math.sin(progress * math.pi) ** 1.2)
        noise = random.uniform(-1, 1)
        friction = bp_warm.process(noise) * 0.65 + bp_crisp.process(noise) * 0.45
        sig = lp.process(friction) * env
        samples.append(sig)
    return samples


# ==========================================
# 2. PAPER CRUMPLE / TRASH (Task Delete)
# ==========================================

# A: Realistic quiet paper ball crumple (multi-crease crunch, 300ms)
def make_paper_crumple_rich(duration=0.30):
    num_samples = int(SAMPLE_RATE * duration)
    samples = []
    
    lp_air = BiquadFilter('lowpass', 240, q=2.0)
    bp_crunch1 = BiquadFilter('bandpass', 1100, q=2.2)
    bp_crunch2 = BiquadFilter('bandpass', 2400, q=3.0)
    bp_crease = BiquadFilter('bandpass', 4200, q=3.5)
    
    # 18 distinct paper fold crackle events
    crackles = [0.0] * num_samples
    for _ in range(18):
        pos = int(random.uniform(0.04, 0.70) * num_samples)
        amp = random.uniform(0.4, 1.0)
        decay = int(random.uniform(0.004, 0.016) * SAMPLE_RATE)
        for k in range(min(decay, num_samples - pos)):
            crackles[pos + k] += amp * math.exp(-k / (decay * 0.25)) * random.uniform(-1, 1)

    for i in range(num_samples):
        progress = i / num_samples
        env = math.sin(progress * math.pi) if progress < 0.65 else math.exp(-(progress - 0.65) * 11)
        noise = random.uniform(-1, 1)
        
        air_body = lp_air.process(noise) * 0.7
        fold_body = bp_crunch1.process(noise) * 0.35 + bp_crunch2.process(crackles[i]) * 0.65
        crisp_snap = bp_crease.process(crackles[i]) * 0.55
        
        sig = (air_body + fold_body + crisp_snap) * env
        samples.append(sig)
    return samples

# B: macOS-inspired gentle paper sweep into soft trash drop (260ms)
def make_trash_woosh_sub(duration=0.26):
    num_samples = int(SAMPLE_RATE * duration)
    samples = []
    
    lp_sub = BiquadFilter('lowpass', 180, q=2.2)
    bp_woosh = BiquadFilter('bandpass', 950, q=1.5)
    bp_paper = BiquadFilter('bandpass', 2200, q=2.5)
    
    for i in range(num_samples):
        progress = i / num_samples
        t = i / SAMPLE_RATE
        env = math.sin(progress * math.pi) ** 1.6
        noise = random.uniform(-1, 1)
        
        # Soft sub-drop near the end (trash can bottom)
        sub_env = math.exp(-((progress - 0.5) ** 2) * 25)
        sub_tone = math.sin(2 * math.pi * 92 * t) * sub_env * 0.6
        
        woosh = bp_woosh.process(noise) * 0.55
        sub = lp_sub.process(noise) * 0.5 + sub_tone
        paper = bp_paper.process(noise) * 0.35
        
        sig = (sub + woosh + paper) * env
        samples.append(sig)
    return samples


# ==========================================
# 3. ZEN TRANSITION CHIMES ("It's 14:00" / "New Day")
# ==========================================

# A: Tibetan Singing Bowl / Warm Rhodes chord (D major pentatonic, rich, 600ms)
def make_chime_zen_bowl(duration=0.60):
    num_samples = int(SAMPLE_RATE * duration)
    samples = []
    
    # D5, F#5, A5, D6
    tones = [
        (587.33, 0.50, 4.5), # D5
        (739.99, 0.35, 5.5), # F#5
        (880.00, 0.30, 6.5), # A5
        (1174.66, 0.18, 9.0) # D6
    ]
    
    for i in range(num_samples):
        t = i / SAMPLE_RATE
        sig = 0.0
        for freq, weight, decay in tones:
            env = math.exp(-t * decay)
            # Subtle warm chorus / beating
            sig += (math.sin(2 * math.pi * freq * t) + 0.3 * math.sin(2 * math.pi * (freq * 1.002) * t)) * env * weight
        samples.append(sig)
    return samples

# B: Acoustic Kalimba / Wooden Marimba 3-note arpeggio (450ms)
def make_chime_kalimba(duration=0.45):
    num_samples = int(SAMPLE_RATE * duration)
    samples = []
    
    notes = [
        (0.00, 659.25), # E5
        (0.06, 880.00), # A5
        (0.12, 1318.51) # E6
    ]
    
    for i in range(num_samples):
        t = i / SAMPLE_RATE
        sig = 0.0
        for start_t, freq in notes:
            if t >= start_t:
                dt = t - start_t
                env = math.exp(-dt * 9.0)
                # Fundamental + 2nd harmonic (warm wood tine)
                tone = math.sin(2 * math.pi * freq * dt) + 0.25 * math.sin(2 * math.pi * (freq * 2.75) * dt) * math.exp(-dt * 20)
                sig += tone * env * 0.4
        samples.append(sig)
    return samples

# C: Pure Crystalline Glass Chime (480ms)
def make_chime_crystal(duration=0.48):
    num_samples = int(SAMPLE_RATE * duration)
    samples = []
    
    freq1 = 1046.50 # C6
    freq2 = 1567.98 # G6
    freq3 = 2093.00 # C7
    
    for i in range(num_samples):
        t = i / SAMPLE_RATE
        env1 = math.exp(-t * 6.5)
        env2 = math.exp(-t * 8.5)
        env3 = math.exp(-t * 12.0)
        
        s1 = math.sin(2 * math.pi * freq1 * t) * env1 * 0.5
        s2 = math.sin(2 * math.pi * freq2 * t) * env2 * 0.35
        s3 = math.sin(2 * math.pi * freq3 * t) * env3 * 0.2
        samples.append(s1 + s2 + s3)
    return samples


# ==========================================
# 4. TASK DROP / REORDER (Tactile Thock)
# ==========================================

# A: Deep wooden block "thock" (50ms)
def make_drop_wood_thock(duration=0.055):
    num_samples = int(SAMPLE_RATE * duration)
    samples = []
    lp = BiquadFilter('lowpass', 480, q=2.5)
    
    for i in range(num_samples):
        t = i / SAMPLE_RATE
        pitch = 320.0 * math.exp(-t * 110) + 110.0
        env = math.exp(-t * 90)
        tone = math.sin(2 * math.pi * pitch * t) * env * 0.75
        noise = lp.process(random.uniform(-1, 1)) * env * 0.35
        samples.append(tone + noise)
    return samples

# B: Creamy mechanical keyboard switch tap (45ms)
def make_drop_creamy_switch(duration=0.045):
    num_samples = int(SAMPLE_RATE * duration)
    samples = []
    bp = BiquadFilter('bandpass', 1250, q=3.0)
    lp = BiquadFilter('lowpass', 600, q=1.8)
    
    for i in range(num_samples):
        t = i / SAMPLE_RATE
        pitch = 440.0 * math.exp(-t * 140) + 180.0
        env = math.exp(-t * 105)
        
        pop = math.sin(2 * math.pi * pitch * t) * env * 0.6
        click = bp.process(random.uniform(-1, 1)) * env * 0.4
        body = lp.process(random.uniform(-1, 1)) * env * 0.4
        samples.append(pop + click + body)
    return samples

# C: Minimalist Apple-like magnetic snap / haptic tap (35ms)
def make_drop_magnetic_snap(duration=0.038):
    num_samples = int(SAMPLE_RATE * duration)
    samples = []
    bp = BiquadFilter('bandpass', 2100, q=2.8)
    lp = BiquadFilter('lowpass', 350, q=2.0)
    
    for i in range(num_samples):
        t = i / SAMPLE_RATE
        env = math.exp(-t * 130)
        click = bp.process(random.uniform(-1, 1)) * env * 0.6
        thump = lp.process(random.uniform(-1, 1)) * env * 0.6
        samples.append(click + thump)
    return samples


# ==========================================
# 5. TRANSFER TO MAIN (Paper Glide / Deal)
# ==========================================

# A: Smooth sheet sliding across wood (180ms)
def make_transfer_paper_glide(duration=0.18):
    num_samples = int(SAMPLE_RATE * duration)
    samples = []
    bp_slide = BiquadFilter('bandpass', 2600, q=2.0)
    lp_body = BiquadFilter('lowpass', 5200, q=0.8)
    
    for i in range(num_samples):
        progress = i / num_samples
        env = math.sin(progress * math.pi) ** 1.3
        noise = random.uniform(-1, 1)
        slide = bp_slide.process(noise) * 0.7
        sig = lp_body.process(slide) * env
        samples.append(sig)
    return samples


# ==========================================
# 6. HABIT CHECK (Organic Woodblock / Stamp)
# ==========================================

# A: Satisfying wooden stamp click (85ms)
def make_habit_check_wood_stamp(duration=0.085):
    num_samples = int(SAMPLE_RATE * duration)
    samples = []
    lp = BiquadFilter('lowpass', 850, q=2.8)
    
    for i in range(num_samples):
        t = i / SAMPLE_RATE
        pitch = 520.0 * math.exp(-t * 75) + 240.0
        env = math.exp(-t * 55)
        tone = math.sin(2 * math.pi * pitch * t) * env * 0.8
        wood = lp.process(random.uniform(-1, 1)) * env * 0.3
        samples.append(tone + wood)
    return samples

# B: Warm bamboo droplet pop (75ms)
def make_habit_check_droplet(duration=0.075):
    num_samples = int(SAMPLE_RATE * duration)
    samples = []
    
    for i in range(num_samples):
        t = i / SAMPLE_RATE
        # Upward-sweeping organic water/bamboo droplet pitch
        pitch = 400.0 + 800.0 * math.sin((i / num_samples) * (math.pi / 2))
        env = math.exp(-t * 60)
        tone = math.sin(2 * math.pi * pitch * t) * env * 0.85
        samples.append(tone)
    return samples


# ==========================================
# 7. UNDO / RESTORE (Unfurl / Rise)
# ==========================================

# A: Reverse paper slide with soft rising tone (200ms)
def make_undo_paper_unfurl(duration=0.20):
    num_samples = int(SAMPLE_RATE * duration)
    samples = []
    bp = BiquadFilter('bandpass', 2400, q=2.2)
    
    for i in range(num_samples):
        progress = i / num_samples
        t = i / SAMPLE_RATE
        pitch = 300.0 + 350.0 * progress
        env = math.sin(progress * math.pi) ** 1.2
        tone = math.sin(2 * math.pi * pitch * t) * env * 0.35
        noise = bp.process(random.uniform(-1, 1)) * env * 0.5
        samples.append(tone + noise)
    return samples


if __name__ == '__main__':
    out_dir = "/Users/christopher/Desktop/Vibecoding/Productivity/IntervalApp/IntervalApp/Resources/Sounds"
    os.makedirs(out_dir, exist_ok=True)

    # 1. Complete
    write_wav(f"{out_dir}/complete_pencil_single.wav", make_pencil_single_stroke())
    write_wav(f"{out_dir}/complete_pencil_double.wav", make_pencil_double_stroke())
    write_wav(f"{out_dir}/complete_pencil_soft.wav", make_pencil_soft_sweep())

    # 2. Delete
    write_wav(f"{out_dir}/delete_paper_crumple.wav", make_paper_crumple_rich())
    write_wav(f"{out_dir}/delete_trash_drop.wav", make_trash_woosh_sub())

    # 3. Transitions & Chimes
    write_wav(f"{out_dir}/chime_zen_bowl.wav", make_chime_zen_bowl())
    write_wav(f"{out_dir}/chime_kalimba.wav", make_chime_kalimba())
    write_wav(f"{out_dir}/chime_crystal.wav", make_chime_crystal())

    # 4. Drop
    write_wav(f"{out_dir}/drop_wood_thock.wav", make_drop_wood_thock())
    write_wav(f"{out_dir}/drop_creamy_switch.wav", make_drop_creamy_switch())
    write_wav(f"{out_dir}/drop_magnetic_snap.wav", make_drop_magnetic_snap())

    # 5. Transfer
    write_wav(f"{out_dir}/transfer_paper_glide.wav", make_transfer_paper_glide())

    # 6. Habit Check
    write_wav(f"{out_dir}/habit_check_wood.wav", make_habit_check_wood_stamp())
    write_wav(f"{out_dir}/habit_check_droplet.wav", make_habit_check_droplet())

    # 7. Undo
    write_wav(f"{out_dir}/undo_unfurl.wav", make_undo_paper_unfurl())

    print("Successfully generated all new high-fidelity audio assets in Resources/Sounds:")
    for f in sorted(os.listdir(out_dir)):
        p = os.path.join(out_dir, f)
        print(f" - {f}: {os.path.getsize(p)} bytes")
