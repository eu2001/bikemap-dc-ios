#!/usr/bin/env python3
"""Generates 13" iPad App Store screenshots (2064 x 2752) from the same source files."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "screenshots" / "ios"
OUT = ROOT / "screenshots" / "ipad_appstore"
OUT.mkdir(parents=True, exist_ok=True)

CANVAS = (2064, 2752)            # 13" iPad portrait
BG = (15, 76, 129)
TITLE_COLOR = (255, 255, 255)
SUBTITLE_COLOR = (210, 230, 250)
DEVICE_CORNER_RADIUS = 56
DEVICE_SCALE = 0.55              # phone is narrower on the wide iPad canvas

SLIDES = [
    ("01-welcome.png", "Join DC's cycling community", "Create an account with our local-fauna avatars"),
    ("02-map-poi-detail.png", "5,700+ points of interest", "Bike parking, Capital Bikeshare, fix-it stands, fountains and more"),
    ("03-layers-infra.png", "9 types of bike infrastructure", "Protected lanes, trails, sharrows — toggle every category"),
    ("04-layers-pois.png", "Find what matters to you", "Filter Metro, restrooms, rec centers, landmarks, crashes…"),
    ("05-add-point.png", "Add your own points", "Drop a bike rack, fix-it stand, or water fountain anywhere"),
    ("06-report-theft.png", "Report bike thefts", "Alert the community and help keep DC's cyclists safer"),
    ("07-edit-profile.png", "Your account, your way", "Avatars, language, password, full data control"),
]

def load_font(size):
    for path in ["/System/Library/Fonts/SFNS.ttf",
                 "/System/Library/Fonts/SFNSDisplay.ttf",
                 "/System/Library/Fonts/Helvetica.ttc",
                 "/Library/Fonts/Arial Bold.ttf",
                 "/System/Library/Fonts/Supplemental/Arial Bold.ttf"]:
        try: return ImageFont.truetype(path, size)
        except (OSError, IOError): continue
    return ImageFont.load_default()

TITLE_FONT = load_font(120)
SUBTITLE_FONT = load_font(60)

def wrap_text(draw, text, font, max_width):
    words = text.split(); lines, cur = [], ""
    for w in words:
        test = (cur + " " + w).strip()
        if draw.textlength(test, font=font) <= max_width: cur = test
        else:
            if cur: lines.append(cur)
            cur = w
    if cur: lines.append(cur)
    return lines

def draw_centered_block(draw, lines, font, fill, y, line_spacing=14):
    for line in lines:
        w = draw.textlength(line, font=font)
        x = (CANVAS[0] - w) // 2
        draw.text((x, y), line, font=font, fill=fill)
        bbox = font.getbbox(line)
        y += (bbox[3] - bbox[1]) + line_spacing
    return y

def rounded_device(img, radius):
    img = img.convert("RGBA")
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, img.size[0], img.size[1]), radius=radius, fill=255)
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out

def compose(src_path, title, subtitle, out_path):
    canvas = Image.new("RGB", CANVAS, BG)
    draw = ImageDraw.Draw(canvas)
    margin_x = 120
    max_text_w = CANVAS[0] - 2 * margin_x
    title_lines = wrap_text(draw, title, TITLE_FONT, max_text_w)
    subtitle_lines = wrap_text(draw, subtitle, SUBTITLE_FONT, max_text_w)
    y = 180
    y = draw_centered_block(draw, title_lines, TITLE_FONT, TITLE_COLOR, y, 18)
    y += 60
    y = draw_centered_block(draw, subtitle_lines, SUBTITLE_FONT, SUBTITLE_COLOR, y, 12)

    device = Image.open(src_path)
    target_w = int(CANVAS[0] * DEVICE_SCALE)
    ratio = target_w / device.size[0]
    target_h = int(device.size[1] * ratio)
    device = device.resize((target_w, target_h), Image.LANCZOS)
    device = rounded_device(device, DEVICE_CORNER_RADIUS)
    device_x = (CANVAS[0] - target_w) // 2
    device_y = max(y + 100, CANVAS[1] - target_h - 120)
    if device_y + target_h > CANVAS[1] - 80:
        overflow = (device_y + target_h) - (CANVAS[1] - 80)
        new_h = target_h - overflow
        new_w = int(target_w * (new_h / target_h))
        device = Image.open(src_path).resize((new_w, new_h), Image.LANCZOS)
        device = rounded_device(device, DEVICE_CORNER_RADIUS)
        device_x = (CANVAS[0] - new_w) // 2
    canvas.paste(device, (device_x, device_y), device)
    canvas.save(out_path, "PNG", optimize=True)
    print(f"  wrote {out_path.name}")

def main():
    print(f"Writing 13-inch iPad screenshots ({CANVAS[0]}x{CANVAS[1]}) to {OUT}")
    for i, (fname, title, subtitle) in enumerate(SLIDES, start=1):
        src = SRC / fname
        if not src.exists():
            print(f"  ⚠️  missing {fname}"); continue
        compose(src, title, subtitle, OUT / f"{i:02d}_ipad.png")
    print("Done.")

if __name__ == "__main__":
    main()
