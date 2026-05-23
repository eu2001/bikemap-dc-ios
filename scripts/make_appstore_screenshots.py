#!/usr/bin/env python3
"""
Generates App Store marketing screenshots from raw simulator captures.
Output: 1320 x 2868 PNGs with a colored background, headline, subtitle,
and the device screenshot tucked in below.

Run:
    python3 scripts/make_appstore_screenshots.py
"""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

# ---------------------------------------------------------------------------
# Tweakables
# ---------------------------------------------------------------------------
ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "screenshots" / "ios"
OUT = ROOT / "screenshots" / "ios_appstore"
OUT.mkdir(parents=True, exist_ok=True)

CANVAS = (1284, 2778)            # 6.5" iPhone — what App Store Connect demands
BG = (15, 76, 129)               # deep DC blue (#0F4C81)
TITLE_COLOR = (255, 255, 255)
SUBTITLE_COLOR = (210, 230, 250)
DEVICE_CORNER_RADIUS = 56        # rounded corners on the device shot
DEVICE_SCALE = 0.78              # how big the phone shot is, relative to canvas width

# Headline + subtitle for each source file. File names must match.
SLIDES = [
    ("01-welcome.png",
        "Join DC's cycling community",
        "Create an account with our local-fauna avatars"),
    ("02-map-poi-detail.png",
        "5,700+ points of interest",
        "Bike parking, Capital Bikeshare, fix-it stands, fountains and more"),
    ("03-layers-infra.png",
        "9 types of bike infrastructure",
        "Protected lanes, trails, sharrows — toggle every category"),
    ("04-layers-pois.png",
        "Find what matters to you",
        "Filter Metro, restrooms, rec centers, landmarks, crashes…"),
    ("05-add-point.png",
        "Add your own points",
        "Drop a bike rack, fix-it stand, or water fountain anywhere"),
    ("06-report-theft.png",
        "Report bike thefts",
        "Alert the community and help keep DC's cyclists safer"),
    ("07-edit-profile.png",
        "Your account, your way",
        "Avatars, language, password, full data control"),
]

# ---------------------------------------------------------------------------
# Font loading
# ---------------------------------------------------------------------------
def load_font(size, bold=True):
    candidates = [
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/SFNSDisplay.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/Library/Fonts/Arial Bold.ttf",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    ]
    for path in candidates:
        try:
            return ImageFont.truetype(path, size)
        except (OSError, IOError):
            continue
    return ImageFont.load_default()

TITLE_FONT = load_font(96, bold=True)
SUBTITLE_FONT = load_font(48, bold=False)


# ---------------------------------------------------------------------------
# Text helpers
# ---------------------------------------------------------------------------
def wrap_text(draw, text, font, max_width):
    words = text.split()
    lines, cur = [], ""
    for w in words:
        test = (cur + " " + w).strip()
        if draw.textlength(test, font=font) <= max_width:
            cur = test
        else:
            if cur:
                lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def draw_centered_block(draw, lines, font, fill, y, line_spacing=12):
    for line in lines:
        w = draw.textlength(line, font=font)
        x = (CANVAS[0] - w) // 2
        draw.text((x, y), line, font=font, fill=fill)
        bbox = font.getbbox(line)
        y += (bbox[3] - bbox[1]) + line_spacing
    return y


# ---------------------------------------------------------------------------
# Device frame helper
# ---------------------------------------------------------------------------
def rounded_device(img, radius):
    img = img.convert("RGBA")
    mask = Image.new("L", img.size, 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle((0, 0, img.size[0], img.size[1]), radius=radius, fill=255)
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


# ---------------------------------------------------------------------------
# Composer
# ---------------------------------------------------------------------------
def compose(src_path: Path, title: str, subtitle: str, out_path: Path):
    canvas = Image.new("RGB", CANVAS, BG)
    draw = ImageDraw.Draw(canvas)

    # --- text block ---
    margin_x = 80
    max_text_w = CANVAS[0] - 2 * margin_x

    title_lines = wrap_text(draw, title, TITLE_FONT, max_text_w)
    subtitle_lines = wrap_text(draw, subtitle, SUBTITLE_FONT, max_text_w)

    y = 150
    y = draw_centered_block(draw, title_lines, TITLE_FONT, TITLE_COLOR, y, 12)
    y += 40
    y = draw_centered_block(draw, subtitle_lines, SUBTITLE_FONT, SUBTITLE_COLOR, y, 8)

    # --- device shot ---
    device = Image.open(src_path)
    target_w = int(CANVAS[0] * DEVICE_SCALE)
    ratio = target_w / device.size[0]
    target_h = int(device.size[1] * ratio)
    device = device.resize((target_w, target_h), Image.LANCZOS)
    device = rounded_device(device, DEVICE_CORNER_RADIUS)

    # Position so the phone sits in the lower portion, with a comfy gap to text.
    device_x = (CANVAS[0] - target_w) // 2
    device_y = max(y + 80, CANVAS[1] - target_h - 80)

    # If the phone would overflow the canvas, shrink it.
    if device_y + target_h > CANVAS[1] - 60:
        overflow = (device_y + target_h) - (CANVAS[1] - 60)
        new_h = target_h - overflow
        new_w = int(target_w * (new_h / target_h))
        device = Image.open(src_path).resize((new_w, new_h), Image.LANCZOS)
        device = rounded_device(device, DEVICE_CORNER_RADIUS)
        device_x = (CANVAS[0] - new_w) // 2

    canvas.paste(device, (device_x, device_y), device)
    canvas.save(out_path, "PNG", optimize=True)
    print(f"  wrote {out_path.name}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    print(f"Reading from {SRC}")
    print(f"Writing to   {OUT}")
    for i, (fname, title, subtitle) in enumerate(SLIDES, start=1):
        src = SRC / fname
        if not src.exists():
            print(f"  ⚠️  missing {fname} — skipping")
            continue
        out_name = f"{i:02d}_appstore.png"
        compose(src, title, subtitle, OUT / out_name)
    print("Done.")


if __name__ == "__main__":
    main()
