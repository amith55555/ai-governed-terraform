"""Renders the output of demo.sh as an animated GIF, like a terminal recording.

Usage (needs Pillow, ffmpeg and the DejaVu fonts; not part of make check):
  bash docs/demo/demo.sh > /tmp/demo.txt && python3 docs/demo/render.py /tmp/demo.txt docs/demo/demo.gif
The text is shown exactly as demo.sh printed it; only colours and timing are added.
Pillow draws the frames; ffmpeg encodes only the changed part of each frame, which keeps
the file small (the repo's pre-commit hook rejects files over 500 KB).
"""
import os
import subprocess
import sys
import tempfile
from PIL import Image, ImageDraw, ImageFont
lines = open(sys.argv[1]).read().rstrip("\n").split("\n")
out = sys.argv[2]
F = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 15)
FB = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf", 15)
CW = F.getbbox("M")[2]; LH = 21; PAD = 18
cols = max(len(l) for l in lines) + 2
W = PAD * 2 + CW * cols; H = PAD * 2 + LH * (len(lines) + 1) + 26
BG, FG, DIM = (15, 20, 28), (220, 226, 234), (120, 132, 150)
RED, GREEN, CYAN, YEL, BAR = (255, 123, 114), (111, 211, 160), (138, 166, 255), (242, 189, 90), (28, 37, 51)

def style(line):
    if line.startswith("== "): return [(line, CYAN, FB)]
    if line.startswith("$ agent: "): return [("$ ", GREEN, FB), ("agent: ", DIM, F), (line[9:], FG, FB)]
    if line.startswith("  BLOCKED"): return [("  BLOCKED", RED, FB), (line[9:], RED, F)]
    if line.strip() == "allowed": return [(line, GREEN, FB)]
    if line.startswith("  risk level: high"): return [("  risk level: ", YEL, F), ("high", RED, FB)]
    if line.startswith("  ->"): return [(line, YEL, FB)]
    if line.startswith("  "): return [(line, YEL, F)]
    return [(line, FG, F)]

def frame(shown, partial=None):
    img = Image.new("RGB", (W, H), BG); d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W, 26], fill=BAR)
    for i, c in enumerate([(255, 95, 87), (254, 188, 46), (40, 200, 64)]):
        d.ellipse([12 + i * 20, 8, 24 + i * 20, 20], fill=c)
    d.text((W // 2 - CW * 11, 5), "bash docs/demo/demo.sh", font=F, fill=DIM)
    y = 26 + PAD
    rows = shown + ([partial] if partial is not None else [])
    for line in rows:
        x = PAD
        for text, color, font in style(line):
            d.text((x, y), text, font=font, fill=color); x += CW * len(text)
        y += LH
    if partial is not None:
        d.rectangle([PAD + CW * len(partial), y - LH + 2, PAD + CW * len(partial) + CW - 2, y - 3], fill=FG)
    return img

frames, durs, shown = [], [], []
frames.append(frame([])); durs.append(600)
for line in lines:
    if line.startswith("$ agent: "):
        for n in range(9, len(line) + 1, 2):
            frames.append(frame(shown, line[:n])); durs.append(35)
        frames.append(frame(shown, line)); durs.append(350)
        shown.append(line)
    else:
        shown.append(line)
        frames.append(frame(shown)); durs.append(1100 if line.strip() and not line.startswith("==") else 250)
frames.append(frame(shown)); durs.append(5000)
with tempfile.TemporaryDirectory() as tmp:
    with open(os.path.join(tmp, "list.txt"), "w", encoding="utf-8") as f:
        for i, (img, ms) in enumerate(zip(frames, durs)):
            img.save(os.path.join(tmp, f"{i:04d}.png"))
            f.write(f"file '{i:04d}.png'\nduration {ms / 1000}\n")
        f.write(f"file '{len(frames) - 1:04d}.png'\n")
    subprocess.run(["ffmpeg", "-v", "error", "-f", "concat", "-i", os.path.join(tmp, "list.txt"), "-vf",
                    "split[a][b];[a]palettegen=max_colors=32:stats_mode=full[p];"
                    "[b][p]paletteuse=dither=none:diff_mode=rectangle", "-y", os.path.abspath(out)], check=True)
print(len(frames), "frames", W, "x", H, sum(durs) / 1000, "s")
