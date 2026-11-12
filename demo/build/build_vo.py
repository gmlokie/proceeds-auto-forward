"""AI voiceover (edge-tts, en-US-AndrewNeural) fitted to the slides.
1) synthesize one clip per scene from vo_script.json -> vo/<scene>.mp3
2) write timing.json (slide durations = narration + padding) for render.py
3) after render.py + assemble.sh: build vo/narration.wav at the scene offsets (run with --mix)
Needs network for edge-tts. Proxy env vars are dropped for the TTS call (aiohttp rejects them)."""
import json, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
VOICE, RATE = "en-US-AndrewNeural", os.environ.get("VO_RATE", "+10%")
LEAD, TAIL = 0.25, 0.40            # silence before / after each clip inside its scene
SCRIPT = json.load(open(os.path.join(HERE, "vo_script.json")))
VO = os.path.join(HERE, "vo"); os.makedirs(VO, exist_ok=True)
MINS = {"closing": 7.5, "verified": 6.0}
TEST_FIXED = {"test_a": 1.2, "test_0": 1.0, "test_1": 1.0, "test_2": 1.0, "test_3": 1.0, "test_4": 1.0, "test_5": 1.0}

def dur(p):
    return float(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", p]).decode())

def tts(scene, text):
    out = os.path.join(VO, scene + ".mp3"); tag = out + ".txt"
    key = f"{VOICE}|{RATE}|{text}"
    if os.path.exists(out) and os.path.exists(tag) and open(tag).read() == key:
        return out
    env = {k: v for k, v in os.environ.items() if "proxy" not in k.lower()}
    import time
    for attempt in range(4):  # edge-tts occasionally returns NoAudioReceived; retry
        r = subprocess.run([sys.executable, "-m", "edge_tts", "--voice", VOICE, f"--rate={RATE}", "--text", text,
                            "--write-media", out], env=env, timeout=90, capture_output=True)
        if r.returncode == 0 and os.path.getsize(out) > 1000: break
        time.sleep(2 + attempt * 3)
    else:
        raise RuntimeError(f"tts failed for {scene}: {r.stderr.decode()[-300:]}")
    open(tag, "w").write(key)
    return out

def plan():
    timing, scenes, t = {}, [], 0.0
    for scene, frames, text in SCRIPT:
        a = dur(tts(scene, text))
        need = LEAD + a + TAIL
        if len(frames) == 1:
            timing[frames[0]] = round(max(need, MINS.get(frames[0], 5.0)), 2)  # cards need a few seconds to read
        else:  # typewriter: fixed steps, last frame absorbs the rest
            fixed = sum(TEST_FIXED[f] for f in frames[:-1])
            timing.update({f: TEST_FIXED[f] for f in frames[:-1]})
            timing[frames[-1]] = round(max(need - fixed, 3.0), 2)
        sd = sum(timing[f] for f in frames)
        scenes.append({"scene": scene, "start": round(t, 3), "dur": sd, "audio": round(a, 3), "text": text})
        t += sd
    json.dump(timing, open(os.path.join(HERE, "timing.json"), "w"), indent=1)
    json.dump(scenes, open(os.path.join(VO, "scenes.json"), "w"), indent=1)
    print(f"total {t:.2f}s")
    for s in scenes:
        print(f"{s['start']:7.2f} {s['dur']:6.2f} audio {s['audio']:5.2f}  {s['scene']}")

def mix():
    scenes = json.load(open(os.path.join(VO, "scenes.json")))
    # use the real encoded segment lengths (30 fps rounding) so clips stay on their slides
    segs = json.load(open(os.path.join(HERE, "segments.json")))
    real, t = {}, 0.0
    for i, (pth, _) in enumerate(segs):
        name = os.path.basename(pth)[3:-4]; real[name] = t
        t += dur(os.path.join(HERE, "seg", f"{i:02d}.mp4"))
    total = t
    for (scene, frames, _), s in zip(SCRIPT, scenes):
        s["start"] = real[frames[0]]
    args, fl = ["ffmpeg", "-y", "-v", "error"], []
    for i, s in enumerate(scenes):
        args += ["-i", os.path.join(VO, s["scene"] + ".mp3")]
        ms = int(round((s["start"] + LEAD) * 1000))
        fl.append(f"[{i}:a]aresample=48000,aformat=channel_layouts=mono,adelay={ms}[a{i}]")
    n = len(scenes)
    fl.append("".join(f"[a{i}]" for i in range(n)) + f"amix=inputs={n}:normalize=0,apad=whole_dur={total:.3f},atrim=0:{total:.3f}[out]")
    args += ["-filter_complex", ";".join(fl), "-map", "[out]", "-ac", "1", "-ar", "48000", os.path.join(VO, "narration.wav")]
    subprocess.run(args, check=True)
    print("narration.wav", dur(os.path.join(VO, "narration.wav")))

if __name__ == "__main__":
    mix() if "--mix" in sys.argv else plan()
