#!/usr/bin/env python3
"""Procedurally synthesizes every sound and music track used by Gridiron Dynasty.

All audio is original (generated from noise, oscillators and envelopes), so the
game ships with no third-party audio. Requires numpy and ffmpeg.

    python3 tools/generate_audio.py            # writes assets/audio/*.ogg
"""
import os
import subprocess
import tempfile
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
rng = np.random.default_rng(20271)


# ---------------------------------------------------------------- helpers

def t_axis(dur):
    return np.arange(int(SR * dur)) / SR


def env_adsr(n, a=0.01, d=0.1, s=0.7, r=0.2):
    a_n, d_n, r_n = int(a * SR), int(d * SR), int(r * SR)
    s_n = max(n - a_n - d_n - r_n, 0)
    e = np.concatenate([
        np.linspace(0, 1, max(a_n, 1)),
        np.linspace(1, s, max(d_n, 1)),
        np.full(s_n, s),
        np.linspace(s, 0, max(r_n, 1)),
    ])
    return np.pad(e, (0, max(0, n - len(e))))[:n]


def exp_decay(n, tau):
    return np.exp(-np.arange(n) / (tau * SR))


def lowpass(x, cutoff):
    """One-pole low-pass (applied twice for a gentler 12 dB slope)."""
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    for _ in range(2):
        acc = 0.0
        for i in range(len(x)):
            acc = (1 - a) * x[i] + a * acc
            y[i] = acc
        x = y.copy()
    return y


def lowpass_fast(x, cutoff):
    """FFT brick-ish low-pass with a smooth roll-off (fast for long signals)."""
    n = len(x)
    f = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(n, 1 / SR)
    resp = 1 / np.sqrt(1 + (freqs / cutoff) ** 4)
    return np.fft.irfft(f * resp, n)


def bandpass_fast(x, lo, hi):
    n = len(x)
    f = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(n, 1 / SR)
    resp = (1 / np.sqrt(1 + (freqs / hi) ** 4)) * (1 / np.sqrt(1 + (lo / np.maximum(freqs, 1e-3)) ** 4))
    return np.fft.irfft(f * resp, n)


def mix(*sigs):
    n = max(len(s) for s in sigs)
    out = np.zeros(n)
    for s in sigs:
        out[:len(s)] += s
    return out


def noise(n):
    return rng.standard_normal(n)


def pink(n):
    w = np.fft.rfft(rng.standard_normal(n))
    freqs = np.fft.rfftfreq(n)
    freqs[0] = freqs[1]
    return np.fft.irfft(w / np.sqrt(freqs), n)


def normalize(x, peak=0.9):
    m = np.max(np.abs(x))
    return x * (peak / m) if m > 0 else x


def loop_crossfade(x, fade):
    """Makes a seamless loop by cross-fading the tail into the head."""
    fn = int(fade * SR)
    head = x[:fn].copy()
    tail = x[-fn:].copy()
    ramp = np.linspace(0, 1, fn)
    if x.ndim == 2:
        ramp = ramp[:, None]
    x = x[:-fn].copy()
    x[:fn] = tail * (1 - ramp) + head * ramp
    return x


def write(name, x, stereo=False, quality=4):
    os.makedirs(OUT, exist_ok=True)
    if stereo and x.ndim == 1:
        x = np.stack([x, x], axis=1)
    data = np.clip(x, -1, 1)
    pcm = (data * 32767).astype(np.int16)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        path = tmp.name
    with wave.open(path, "wb") as w:
        w.setnchannels(2 if pcm.ndim == 2 else 1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    out = os.path.join(OUT, name + ".ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path, "-c:a", "libvorbis", "-q:a", str(quality), out], check=True)
    os.remove(path)
    print("wrote", out)


# ---------------------------------------------------------------- crowd

def crowd_bed(dur, brightness=1.0, swell=0.2, seed_shift=0):
    n = int(SR * dur)
    chans = []
    for c in range(2):
        base = pink(n)
        # Babble: band-limited noise modulated by many slow random "voices".
        voices = np.zeros(n)
        for v in range(40):
            f0 = rng.uniform(180, 900) * brightness
            ph = rng.uniform(0, 2 * np.pi)
            rate = rng.uniform(1.5, 5.0)
            am = 0.5 + 0.5 * np.sin(2 * np.pi * rate * np.arange(n) / SR + ph)
            carrier = np.sin(2 * np.pi * f0 * np.arange(n) / SR * (1 + 0.02 * np.sin(2 * np.pi * 0.7 * np.arange(n) / SR + ph)))
            voices += carrier * am ** 3 * rng.uniform(0.2, 1.0)
        voices = bandpass_fast(voices * noise(n) * 0.3 + voices * 0.15, 200, 2600 * brightness)
        bed = bandpass_fast(base, 150, 2200 * brightness) * 0.8 + voices * 0.6
        slow = 1 + swell * np.sin(2 * np.pi * np.arange(n) / SR / dur * 2 + c)
        chans.append(bed * slow)
    x = np.stack(chans, axis=1)
    return normalize(x, 0.7)


def make_crowd():
    write("crowd_loop", loop_crossfade(crowd_bed(10.0, 1.0, 0.15), 1.5), stereo=True, quality=3)
    write("crowd_excited", loop_crossfade(crowd_bed(8.0, 1.45, 0.3) * 1.0, 1.5), stereo=True, quality=3)
    # Touchdown roar: fast attack, sustained, slow decay.
    n = int(SR * 5.0)
    roar = crowd_bed(5.0, 1.7, 0.1)
    e = np.minimum(1, np.arange(n) / (0.25 * SR)) * np.exp(-np.maximum(0, np.arange(n) - 1.8 * SR) / (1.6 * SR))
    write("crowd_roar", normalize(roar * e[:, None], 0.95), stereo=True)
    # Groan: descending band-pass "ohhh".
    n = int(SR * 2.6)
    g = pink(n)
    out = np.zeros(n)
    seg = 2048
    for i in range(0, n, seg):
        frac = i / n
        lo = 220 - 80 * frac
        out[i:i + seg] = bandpass_fast(g[i:i + seg] if i + seg <= n else g[i:], lo, lo * 3.2)[:len(out[i:i + seg])]
    e = np.minimum(1, np.arange(n) / (0.15 * SR)) * np.exp(-np.arange(n) / (1.2 * SR))
    write("crowd_groan", normalize(lowpass_fast(out, 1400) * e, 0.85))
    # Short cheer burst for first downs / big gains.
    n = int(SR * 2.2)
    cheer = crowd_bed(2.2, 1.6, 0.0)
    e = np.minimum(1, np.arange(n) / (0.1 * SR)) * np.exp(-np.arange(n) / (0.8 * SR))
    write("crowd_cheer", normalize(cheer * e[:, None], 0.9), stereo=True)


# ---------------------------------------------------------------- sfx

def whistle(dur=0.55, blasts=1):
    out = []
    for b in range(blasts):
        t = t_axis(dur)
        f = 2950 + 40 * np.sin(2 * np.pi * 6 * t)
        trill = 0.55 + 0.45 * np.sign(np.sin(2 * np.pi * 34 * t)) * 0.5 + 0.25
        tone = np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.3 * np.sin(2 * np.pi * 2 * np.cumsum(f) / SR)
        breath = bandpass_fast(noise(len(t)), 2000, 6000) * 0.15
        e = env_adsr(len(t), 0.015, 0.05, 0.85, 0.08)
        out.append((tone * trill + breath) * e)
        out.append(np.zeros(int(0.12 * SR)))
    return normalize(np.concatenate(out), 0.7)


def thump(freq=90, dur=0.35, click=0.3, body_noise=0.4):
    n = int(SR * dur)
    t = np.arange(n) / SR
    f = freq * (1 + 1.5 * np.exp(-t * 30))
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) * exp_decay(n, dur / 4)
    c = lowpass_fast(noise(n), 3500) * exp_decay(n, 0.012) * click
    b = lowpass_fast(noise(n), 900) * exp_decay(n, dur / 6) * body_noise
    return s + c + b


def make_sfx():
    write("whistle", whistle(0.5, 1))
    write("whistle_long", whistle(0.75, 2))
    write("snap", normalize(thump(160, 0.12, 0.7, 0.3), 0.6))
    n = int(SR * 0.4)
    sweep = noise(n)
    out = np.zeros(n)
    seg = 1024
    for i in range(0, n, seg):
        frac = i / n
        c = 600 + 2600 * np.sin(np.pi * frac)
        chunk = sweep[i:i + seg]
        out[i:i + len(chunk)] = bandpass_fast(chunk, c * 0.6, c * 1.4)
    e = np.sin(np.pi * np.linspace(0, 1, n)) ** 1.5
    write("throw", normalize(out * e, 0.5))
    write("catch", normalize(thump(130, 0.2, 0.9, 0.5), 0.7))
    tackle = thump(70, 0.5, 0.5, 0.9)
    crack = bandpass_fast(noise(len(tackle)), 600, 3000) * exp_decay(len(tackle), 0.03) * 0.6
    write("tackle", normalize(tackle + crack, 0.9))
    write("hit_light", normalize(thump(110, 0.25, 0.6, 0.6), 0.6))
    kick = thump(85, 0.45, 1.0, 0.6)
    kick += np.sin(2 * np.pi * 55 * np.arange(len(kick)) / SR) * exp_decay(len(kick), 0.12) * 0.5
    write("kick", normalize(kick, 0.95))
    # Juke: cleats skid.
    n = int(SR * 0.25)
    write("juke", normalize(bandpass_fast(noise(n), 1500, 7000) * exp_decay(n, 0.06), 0.4))
    # Stadium horn for touchdowns.
    t = t_axis(1.8)
    horn = np.zeros(len(t))
    for f in (174.6, 220.0, 261.6, 349.2):
        saw = 2 * (t * f - np.floor(0.5 + t * f))
        horn += saw
    horn = lowpass_fast(horn, 1800) * env_adsr(len(t), 0.05, 0.2, 0.9, 0.5)
    write("horn", normalize(horn, 0.8))


# ---------------------------------------------------------------- ui

def tone(f, dur, shape="sine", decay=0.08):
    t = t_axis(dur)
    if shape == "tri":
        w = 2 * np.abs(2 * (t * f - np.floor(t * f + 0.5))) - 1
    else:
        w = np.sin(2 * np.pi * f * t)
    return w * env_adsr(len(t), 0.003, decay, 0.0, 0.01)


def make_ui():
    write("ui_hover", normalize(tone(1900, 0.05, "sine", 0.03), 0.18))
    write("ui_click", normalize(mix(tone(1250, 0.07, "tri", 0.05), 0.4 * tone(2500, 0.05, "sine", 0.03)), 0.35))
    a = tone(880, 0.12, "tri", 0.1)
    b = tone(1318.5, 0.18, "tri", 0.15)
    write("ui_confirm", normalize(np.concatenate([a, b]), 0.35))
    write("ui_back", normalize(np.concatenate([tone(1046.5, 0.08, "tri", 0.06), tone(784, 0.12, "tri", 0.1)]), 0.3))
    write("ui_error", normalize(np.concatenate([tone(330, 0.12, "tri", 0.1), tone(262, 0.2, "tri", 0.18)]), 0.35))
    chime = np.concatenate([tone(1046.5, 0.1, "sine", 0.1), tone(1568, 0.25, "sine", 0.25)])
    write("first_down", normalize(chime, 0.3))
    sting = np.concatenate([tone(440, 0.18, "tri", 0.15), tone(415.3, 0.18, "tri", 0.15), tone(349.2, 0.4, "tri", 0.35)])
    write("turnover", normalize(sting, 0.4))


# ---------------------------------------------------------------- music

NOTE = {n: 440 * 2 ** ((i - 9) / 12) for i, n in enumerate(["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"])}


def midi(m):
    return 440 * 2 ** ((m - 69) / 12)


def pad(freqs, dur, cutoff=1500, detune=0.004):
    t = t_axis(dur)
    out = np.zeros(len(t))
    for f in freqs:
        for d in (-detune, 0, detune):
            ff = f * (1 + d)
            out += 2 * (t * ff - np.floor(0.5 + t * ff))
    out = lowpass_fast(out, cutoff)
    return out * env_adsr(len(t), 0.4, 0.3, 0.8, 0.6)


def pluck(f, dur, bright=3000):
    t = t_axis(dur)
    w = 2 * (t * f - np.floor(0.5 + t * f)) * 0.6 + np.sin(2 * np.pi * f * t)
    return lowpass_fast(w, bright) * exp_decay(len(t), 0.18)


def kick_drum():
    return thump(55, 0.35, 0.3, 0.1)


def hat(open_=False):
    n = int(SR * (0.18 if open_ else 0.05))
    return bandpass_fast(noise(n), 7000, 14000) * exp_decay(n, 0.04 if open_ else 0.012)


def snare():
    n = int(SR * 0.22)
    return bandpass_fast(noise(n), 1200, 8000) * exp_decay(n, 0.06) * 0.8 + np.sin(2 * np.pi * 190 * np.arange(n) / SR) * exp_decay(n, 0.04) * 0.5


def mix(*sigs):
    n = max(len(s) for s in sigs)
    out = np.zeros(n)
    for s in sigs:
        out[:len(s)] += s
    return out


def place(buf, sig, at):
    i = int(at * SR)
    if i >= len(buf) or i < 0:
        return
    end = min(len(buf), i + len(sig))
    buf[i:end] += sig[:end - i]


def make_music_menu():
    bpm = 88
    beat = 60 / bpm
    bars = 16
    dur = bars * 4 * beat
    n = int(SR * dur) + SR * 2
    music = np.zeros(n)
    # Progression in D major: D - Bm - G - A (warm, restrained).
    prog = [[62, 66, 69, 74], [59, 62, 66, 71], [55, 59, 62, 67], [57, 61, 64, 69]]
    for bar in range(bars):
        ch = prog[bar % 4]
        place(music, pad([midi(m) for m in ch], 4 * beat + 0.5, 1200) * 0.12, bar * 4 * beat)
        place(music, pluck(midi(ch[0] - 24), 2 * beat, 600) * 0.35, bar * 4 * beat)
        place(music, pluck(midi(ch[0] - 24), 2 * beat, 600) * 0.28, bar * 4 * beat + 2 * beat)
        if bar >= 4:
            arp = [ch[1] + 12, ch[2] + 12, ch[3] + 12, ch[2] + 12]
            for k in range(8):
                place(music, pluck(midi(arp[k % 4]), beat, 2500) * 0.06, bar * 4 * beat + k * beat / 2)
        if bar >= 2:
            for b in range(4):
                place(music, kick_drum() * 0.35, bar * 4 * beat + b * beat if b in (0, 2) else -100)
                place(music, hat() * 0.12, bar * 4 * beat + b * beat + beat / 2)
                if b in (1, 3):
                    place(music, snare() * 0.18, bar * 4 * beat + b * beat)
    music = music[:int(SR * dur)]
    st = np.stack([music, np.roll(music, int(0.012 * SR))], axis=1)
    write("music_menu", normalize(st, 0.6), stereo=True, quality=4)


def make_music_victory():
    bpm = 112
    beat = 60 / bpm
    bars = 8
    dur = bars * 4 * beat
    n = int(SR * dur) + SR * 2
    music = np.zeros(n)
    prog = [[60, 64, 67, 72], [65, 69, 72, 77], [67, 71, 74, 79], [60, 64, 67, 72]]
    melody = [72, 76, 79, 84, 81, 79, 77, 79, 76, 72, 74, 76, 79, 77, 76, 72]
    for bar in range(bars):
        ch = prog[bar % 4]
        place(music, pad([midi(m) for m in ch], 4 * beat + 0.3, 2600, 0.006) * 0.12, bar * 4 * beat)
        place(music, pluck(midi(ch[0] - 24), 4 * beat, 700) * 0.4, bar * 4 * beat)
        for b in range(4):
            place(music, kick_drum() * 0.4, bar * 4 * beat + b * beat)
            place(music, snare() * (0.25 if b % 2 else 0.1), bar * 4 * beat + b * beat + (0 if b % 2 else beat / 2))
            place(music, hat(b == 3) * 0.12, bar * 4 * beat + b * beat + beat / 2)
        for k in range(2):
            m = melody[(bar * 2 + k) % len(melody)]
            # Brass-like lead.
            t = t_axis(2 * beat)
            f = midi(m)
            w = 2 * (t * f - np.floor(0.5 + t * f))
            lead = lowpass_fast(w, 2200) * env_adsr(len(t), 0.04, 0.2, 0.7, 0.2)
            place(music, lead * 0.14, bar * 4 * beat + k * 2 * beat)
    music = music[:int(SR * dur)]
    st = np.stack([music, np.roll(music, int(0.015 * SR))], axis=1)
    write("music_victory", normalize(st, 0.65), stereo=True, quality=4)


def make_music_halftime():
    bpm = 96
    beat = 60 / bpm
    bars = 8
    dur = bars * 4 * beat
    n = int(SR * dur) + SR
    music = np.zeros(n)
    prog = [[57, 60, 64, 69], [53, 57, 60, 65], [55, 59, 62, 67], [52, 56, 59, 64]]
    for bar in range(bars):
        ch = prog[bar % 4]
        place(music, pad([midi(m) for m in ch], 4 * beat + 0.3, 1400) * 0.13, bar * 4 * beat)
        for b in range(4):
            place(music, pluck(midi(ch[b % 4] - 12), beat, 1600) * 0.2, bar * 4 * beat + b * beat)
            place(music, hat() * 0.08, bar * 4 * beat + b * beat + beat / 2)
    music = music[:int(SR * dur)]
    st = np.stack([music, np.roll(music, int(0.01 * SR))], axis=1)
    write("music_halftime", normalize(st, 0.55), stereo=True, quality=3)


if __name__ == "__main__":
    make_ui()
    make_sfx()
    make_crowd()
    make_music_menu()
    make_music_victory()
    make_music_halftime()
