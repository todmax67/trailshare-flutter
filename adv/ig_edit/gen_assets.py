import math
from PIL import Image, ImageDraw, ImageFont, ImageFilter

W, H = 1080, 1920
BASE = "/Volumes/Lexar/Sviluppo/trailshare_flutter"
OUT = f"{BASE}/adv/ig_edit"
FONT_DIR = "/System/Library/Fonts/Supplemental"

GREEN = (13, 92, 63)
ORANGE = (237, 111, 45)

def font(path, size):
    return ImageFont.truetype(f"{FONT_DIR}/{path}", size)

def text_size(draw, txt, f):
    b = draw.textbbox((0, 0), txt, font=f)
    return b[2] - b[0], b[3] - b[1]

# ---------- 1. Transparent logo (for watermark) ----------
logo = Image.open(f"{BASE}/assets/icons/store_logo.png").convert("RGBA")
datas = logo.getdata()
new_data = []
for r, g, b, a in datas:
    if r > 240 and g > 240 and b > 240:
        new_data.append((r, g, b, 0))
    else:
        new_data.append((r, g, b, a))
logo.putdata(new_data)
logo.save(f"{OUT}/logo_transparent.png")

# watermark version: small, bottom-right, ~70% opacity, with subtle drop shadow
wm_size = 190
wm = logo.resize((wm_size, wm_size), Image.LANCZOS)
r, g, b, a = wm.split()
a = a.point(lambda v: int(v * 0.82))
wm.putalpha(a)
wm.save(f"{OUT}/watermark.png")

# ---------- helper: rounded translucent banner with bold centered text (multi-line) ----------
def make_caption(lines, filename, font_size=64, pad_x=48, pad_y=30, line_gap=10,
                  fill=(255, 255, 255, 255), banner_color=(10, 20, 15, 150)):
    f = font("Arial Bold.ttf", font_size)
    tmp = Image.new("RGBA", (10, 10))
    d = ImageDraw.Draw(tmp)
    sizes = [text_size(d, ln, f) for ln in lines]
    max_w = max(s[0] for s in sizes)
    total_h = sum(s[1] for s in sizes) + line_gap * (len(lines) - 1)
    box_w = max_w + pad_x * 2
    box_h = total_h + pad_y * 2
    img = Image.new("RGBA", (int(box_w), int(box_h)), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    radius = 28
    draw.rounded_rectangle([0, 0, box_w, box_h], radius=radius, fill=banner_color)
    y = pad_y
    for ln, (w_, h_) in zip(lines, sizes):
        x = (box_w - w_) / 2
        draw.text((x, y), ln, font=f, fill=fill)
        y += h_ + line_gap
    img.save(f"{OUT}/{filename}")
    return img.size

s1 = make_caption(["Un sentiero nel bosco..."], "caption1.png", font_size=58)
s2 = make_caption(["...porta a questa cascata"], "caption2.png", font_size=58)
print("caption sizes", s1, s2)

# ---------- 2. End card ----------
card = Image.new("RGB", (W, H), (250, 250, 248))
draw = ImageDraw.Draw(card)

# soft diagonal gradient green -> orange, subtle (low saturation wash top->bottom)
grad = Image.new("RGB", (1, H), (0, 0, 0))
for y in range(H):
    t = y / H
    r = int(GREEN[0] * (1 - t) + ORANGE[0] * t)
    g = int(GREEN[1] * (1 - t) + ORANGE[1] * t)
    b = int(GREEN[2] * (1 - t) + ORANGE[2] * t)
    grad.putpixel((0, y), (r, g, b))
grad = grad.resize((W, H))
grad = Image.blend(Image.new("RGB", (W, H), (255, 255, 255)), grad, 0.10)
card = grad

draw = ImageDraw.Draw(card)
f_sub = font("Futura.ttc", 42)
f_cta = font("Arial Bold.ttf", 46)

logo_size = 460
sub_lines = ["Scopri sentieri come questo,", "traccia e condividi le tue avventure"]
sub_h = 0
tmp_sizes = []
for ln in sub_lines:
    w_, h_ = text_size(draw, ln, f_sub)
    tmp_sizes.append((w_, h_))
    sub_h += h_ + 20

cta = "Scaricala gratis →"
cw, ch = text_size(draw, cta, f_cta)
btn_pad_x, btn_pad_y = 46, 26
btn_w, btn_h = cw + btn_pad_x * 2, ch + btn_pad_y * 2

gap_logo_sub = 70
gap_sub_btn = 70
block_h = logo_size + gap_logo_sub + sub_h + gap_sub_btn + btn_h
top = (H - block_h) / 2

card_rgba = card.convert("RGBA")
logo_big = logo.resize((logo_size, logo_size), Image.LANCZOS)
card_rgba.alpha_composite(logo_big, (int((W - logo_size) / 2), int(top)))
draw = ImageDraw.Draw(card_rgba)

y = top + logo_size + gap_logo_sub
for ln, (w_, h_) in zip(sub_lines, tmp_sizes):
    draw.text(((W - w_) / 2, y), ln, font=f_sub, fill=(55, 65, 60, 255))
    y += h_ + 20

btn_x = (W - btn_w) / 2
btn_y = y + gap_sub_btn - 20
draw.rounded_rectangle([btn_x, btn_y, btn_x + btn_w, btn_y + btn_h], radius=btn_h / 2, fill=(224, 96, 34, 255))
draw.text((btn_x + btn_pad_x, btn_y + btn_pad_y - 4), cta, font=f_cta, fill=(255, 255, 255, 255))

card_rgba.convert("RGB").save(f"{OUT}/endcard.png", quality=95)
print("done")
