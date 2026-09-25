"""Offline preview renders for the README (not in-game screenshots).

Builds PNGs in docs/screenshots from the real IchaUI media TGAs plus Blizzard
UI textures (PNG exports, default F:\\wow-ui-textures, override with the
WOW_UI_TEXTURES environment variable). Geometry follows DrawerStyle.lua,
Totems.lua, MinimapSkin.lua and XPBar.lua.

    python tools/render_previews.py

Only preview-*.png files are written; the in-game screenshots are never touched.

Requires Pillow.
"""
import math
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
MEDIA = os.path.join(REPO, "IchaUI", "media")
SHAPES = os.path.join(MEDIA, "minimapshapes")
BLIZ = os.environ.get("WOW_UI_TEXTURES", r"F:\wow-ui-textures")
OUT = os.path.join(REPO, "docs", "screenshots")

GOLD = (0.75, 0.52, 0.04)          # Gold.lua dark gold
MM_GOLD = (0.78, 0.58, 0.16)       # MinimapSkin.lua GOLD
BG = (18, 18, 21, 255)
LABEL = (236, 200, 90)
MUTED = (170, 165, 150)
K = 2                              # render scale (1 WoW pixel = K image pixels)

_cache = {}


def tex(path):
    if path not in _cache:
        _cache[path] = Image.open(path).convert("RGBA")
    return _cache[path]


def media(*parts):
    return tex(os.path.join(MEDIA, *parts))


def shape_tex(*parts):
    return tex(os.path.join(SHAPES, *parts))


_bliz_index = {}


def bliz(folder, name):
    d = os.path.join(BLIZ, folder)
    if d not in _bliz_index:
        _bliz_index[d] = {f.lower(): f for f in os.listdir(d)} if os.path.isdir(d) else {}
    f = _bliz_index[d].get((name + ".png").lower())
    return tex(os.path.join(d, f)) if f else None


def icon(*names):
    for n in names:
        im = bliz("ICONS", n)
        if im is not None:
            return im
    return Image.new("RGBA", (64, 64), (80, 80, 80, 255))


def font(size, bold=True, serif=False):
    names = (["georgiab.ttf", "georgia.ttf"] if serif else []) + (["arialbd.ttf"] if bold else ["arial.ttf"])
    for n in names:
        p = os.path.join(os.environ.get("WINDIR", r"C:\Windows"), "Fonts", n)
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default(size=size)


def mul(im, rgb, alpha=1.0):
    r, g, b, a = im.split()
    r = r.point(lambda v: int(v * rgb[0]))
    g = g.point(lambda v: int(v * rgb[1]))
    b = b.point(lambda v: int(v * rgb[2]))
    if alpha != 1.0:
        a = a.point(lambda v: int(v * alpha))
    return Image.merge("RGBA", (r, g, b, a))


def desat(im):
    l = im.convert("L")
    return Image.merge("RGBA", (l, l, l, im.split()[3]))


def resized(im, w, h=None):
    h = w if h is None else h
    return im.resize((max(1, int(round(w))), max(1, int(round(h)))), Image.LANCZOS)


def paste(canvas, im, x, y):
    """Alpha-composite im with its top-left at (x, y); clips at the canvas edge."""
    x, y = int(round(x)), int(round(y))
    sx, sy = max(0, -x), max(0, -y)
    if sx or sy:
        im = im.crop((sx, sy, im.width, im.height))
        x, y = x + sx, y + sy
    if im.width <= 0 or im.height <= 0:
        return
    canvas.alpha_composite(im, (x, y))


def paste_c(canvas, im, cx, cy):
    paste(canvas, im, cx - im.width / 2, cy - im.height / 2)


def circle_mask(size, ss=4):
    size = int(round(size))
    m = Image.new("L", (size * ss, size * ss), 0)
    ImageDraw.Draw(m).ellipse((0, 0, size * ss - 1, size * ss - 1), fill=255)
    return m.resize((size, size), Image.LANCZOS)


def round_icon(im, size):
    """SetPortraitToTexture look: whole icon, clipped to a circle."""
    ic = resized(im, size)
    a = Image.new("L", ic.size, 0)
    a.paste(circle_mask(ic.width), (0, 0))
    ic.putalpha(a)
    return ic


def square_icon(im, w, h, u0=0.08, u1=0.92, crop_v=0.0):
    span = u1 - u0
    x0, x1 = u0 * im.width, u1 * im.width
    y0 = (u0 + crop_v * span) * im.height
    y1 = (u1 - crop_v * span) * im.height
    return resized(im.crop((int(x0), int(y0), int(x1), int(y1))), w, h)


def backdrop_edge(w, h, edge_img, e, rgb=None):
    """WoW SetBackdrop edge: 8 pieces L, R, T, B, TL, TR, BL, BR (T/B stored rotated)."""
    w, h, e = int(round(w)), int(round(h)), int(round(e))
    pw = edge_img.width // 8
    pieces = [edge_img.crop((i * pw, 0, (i + 1) * pw, edge_img.height)) for i in range(8)]
    if rgb:
        pieces = [mul(p, rgb) for p in pieces]
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    left = resized(pieces[0], e, e)
    right = resized(pieces[1], e, e)
    top = resized(pieces[2].rotate(-90, expand=True), e, e)
    bottom = resized(pieces[3].rotate(-90, expand=True), e, e)
    for y in range(e, h - e, e):
        seg = min(e, h - e - y)
        out.alpha_composite(left.crop((0, 0, e, seg)), (0, y))
        out.alpha_composite(right.crop((0, 0, e, seg)), (w - e, y))
    for x in range(e, w - e, e):
        seg = min(e, w - e - x)
        out.alpha_composite(top.crop((0, 0, seg, e)), (x, 0))
        out.alpha_composite(bottom.crop((0, 0, seg, e)), (x, h - e))
    out.alpha_composite(resized(pieces[4], e, e), (0, 0))
    out.alpha_composite(resized(pieces[5], e, e), (w - e, 0))
    out.alpha_composite(resized(pieces[6], e, e), (0, h - e))
    out.alpha_composite(resized(pieces[7], e, e), (w - e, h - e))
    return out


def tooltip_border():
    return bliz("Tooltips", "UI-Tooltip-Border")


# DrawerStyle.lua FORM_DEF (ring frames and pfUI edges)
FORM_DEF = {
    "pfsquare": {"label": "pfUI Square", "edge": ("pfui", "border.tga"), "outset": 0, "inset": 1},
    "pfblizz": {"label": "pfUI Blizz", "edge": ("pfui", "border_blizz.tga"), "outset": 2, "inset": 2},
    "metalplain": {"label": "Metal Plain", "ring": "MetalPlain_Circular_Frame.tga", "outer": 0.619, "hole": 0.748},
    "eternium": {"label": "Metal Eternium", "ring": "MetalEternium_Circular_Frame.tga", "outer": 0.619, "hole": 0.748},
    "bronze": {"label": "Metal Bronze", "ring": "MetalBronze_Circular_Frame.tga", "outer": 0.618, "hole": 0.752},
    "wowui": {"label": "WoWUI", "ring": "WowUI_Circular_Frame.tga", "outer": 0.636, "hole": 0.689},
    "wood": {"label": "Wood Boards", "ring": "WoodBoards_Circular_Frame.tga", "outer": 0.618, "hole": 0.751},
    "target": {"label": "Generic Target", "ring": "Generic1Target_Circular_Frame.tga", "outer": 0.888, "hole": 0.702},
}
FORM_SHAPES = ["rect", "square", "circle", "tooltip", "portrait", "pfsquare", "pfblizz",
               "metalplain", "eternium", "bronze", "wowui", "wood", "target"]
FORM_LABEL = {"rect": "Rectangle", "square": "Square", "circle": "Circle",
              "tooltip": "Tooltip Ring", "portrait": "Portrait"}
for _k, _v in FORM_DEF.items():
    FORM_LABEL[_k] = _v["label"]


def draw_button(canvas, cx, cy, shape, ic, side, width=None):
    """IchaUI_ApplyButtonForm. side/width are WoW pixels; returns the ring geometry."""
    S = side * K
    d = FORM_DEF.get(shape)
    geo = {"shape": shape, "S": S, "cx": cx, "cy": cy}
    if shape in ("rect", "square") or (d and "edge" in d):
        w = (width or side) if shape == "rect" else side
        W, H = w * K, S
        if d:
            e, o, inset = 8 * K, d["outset"] * K, d["inset"] * K
            edge, rgb = shape_tex(*d["edge"]), None
        else:
            e_log = min(14, max(8, int(math.floor(w * 0.22 + 0.5))))
            e, o = e_log * K, 0
            inset = max(1, int(math.floor(e_log * 4 / 16 + 0.5))) * K
            edge, rgb = tooltip_border(), GOLD
        crop = 0.0
        if shape == "rect" and W > H:
            crop = min(0.45, (1 - H / W) / 2)
        x0, y0 = cx - W / 2, cy - H / 2
        paste(canvas, square_icon(ic, W - 2 * inset, H - 2 * inset, crop_v=crop), x0 + inset, y0 + inset)
        paste(canvas, backdrop_edge(W + 2 * o, H + 2 * o, edge, e, rgb), x0 - o, y0 - o)
        geo.update(kind="rect", W=W, H=H, e=e)
        return geo
    if shape == "circle":
        bw = S * 64 / 36
        ring = mul(desat(bliz("MINIMAP", "MiniMap-TrackingBorder")), GOLD)
        ring = resized(ring, bw)
        isz = S * 0.62
        ix, iy = cx - S * 0.010, cy - S * 0.031
        paste_c(canvas, round_icon(Image.new("RGBA", (8, 8), (10, 10, 12, 255)), isz * 1.02), ix, iy)
        paste_c(canvas, round_icon(ic, isz), ix, iy)
        rx, ry = cx + S * 0.347, cy + S * 0.347
        paste_c(canvas, ring, rx, ry)
        tlx, tly = rx - bw / 2, ry - bw / 2
        geo.update(kind="round", rcx=tlx + 0.2954 * bw, rcy=tly + 0.2807 * bw, r=0.2520 * bw, thk=S * 0.03)
        return geo
    if shape in ("tooltip", "portrait"):
        if shape == "tooltip":
            ring, frac, rim = shape_tex("tooltip-ring-thick.tga"), 0.96, 0.4766
        else:
            ring, frac, rim = shape_tex("x4", "PortraitFrame-thick2.tga"), 0.94, 0.4795
        paste_c(canvas, round_icon(ic, S * frac), cx, cy)
        paste_c(canvas, mul(resized(ring, S), GOLD), cx, cy)
        geo.update(kind="round", rcx=cx, rcy=cy, r=rim * S, thk=S * 0.06)
        return geo
    rw = S / d["outer"]
    paste_c(canvas, round_icon(ic, S * d["hole"] * 1.13), cx, cy)
    paste_c(canvas, resized(shape_tex("x4", d["ring"]), rw), cx, cy)
    geo.update(kind="round", rcx=cx, rcy=cy, r=0.31 * rw, thk=S * 0.06)
    return geo


def cast_ring(canvas, geo, pct, rgb):
    """Totems.lua cast/tick ring: faint full track, solid arc from 12 o'clock clockwise, spark at the tip."""
    ss = 4
    col = tuple(int(c * 255) for c in rgb)
    layer = Image.new("RGBA", (canvas.width * ss, canvas.height * ss), (0, 0, 0, 0))
    dr = ImageDraw.Draw(layer)
    if geo["kind"] == "round":
        thk = geo["thk"]
        r = geo["r"] + thk / 2
        cx, cy = geo["rcx"], geo["rcy"]
        box = [(cx - r) * ss, (cy - r) * ss, (cx + r) * ss, (cy + r) * ss]
        wpx = max(1, int(round(thk * ss)))
        dr.arc(box, 0, 360, fill=col + (70,), width=wpx)
        dr.arc(box, -90, -90 + 360 * pct, fill=col + (255,), width=wpx)
        a = math.pi / 2 - pct * 2 * math.pi
        tip = (cx + math.cos(a) * r, cy - math.sin(a) * r)
    else:
        W, H = geo["W"], geo["H"]
        thk = max(K, geo["S"] * 0.03 * 2)
        vis = -geo["e"] * 3 / 16
        hx, hy = W / 2 + vis + thk / 2, H / 2 + vis + thk / 2
        cx, cy = geo["cx"], geo["cy"]
        pts = [(cx, cy - hy), (cx + hx, cy - hy), (cx + hx, cy + hy), (cx - hx, cy + hy), (cx - hx, cy - hy), (cx, cy - hy)]
        segs = list(zip(pts, pts[1:]))
        total = sum(math.dist(p, q) for p, q in segs)
        for (p, q) in segs:
            dr.line([(p[0] * ss, p[1] * ss), (q[0] * ss, q[1] * ss)], fill=col + (70,), width=int(thk * ss))
        left = total * pct
        tip = pts[0]
        for (p, q) in segs:
            L = math.dist(p, q)
            if left <= 0:
                break
            t = min(1.0, left / L)
            end = (p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t)
            dr.line([(p[0] * ss, p[1] * ss), (end[0] * ss, end[1] * ss)], fill=col + (255,), width=int(thk * ss))
            tip = end
            left -= L
    canvas.alpha_composite(layer.resize(canvas.size, Image.LANCZOS))
    spark = resized(media("TotemCastSpark.tga"), geo["S"] * 0.55)
    spark = mul(spark, (1, 1, 1))
    paste_c(canvas, spark, tip[0], tip[1])


def outlined(draw, xy, text, fnt, fill=(255, 255, 255), anchor="mm", stroke=None):
    draw.text(xy, text, font=fnt, fill=fill, anchor=anchor,
              stroke_width=stroke if stroke is not None else max(2, fnt.size // 9), stroke_fill=(0, 0, 0))


def new_canvas(w, h, title, subtitle=None):
    im = Image.new("RGBA", (w, h), BG)
    top = Image.new("RGBA", (w, 70), (28, 26, 22, 255))
    im.alpha_composite(top, (0, 0))
    d = ImageDraw.Draw(im)
    d.text((24, 16), title, font=font(26, serif=True), fill=LABEL)
    d.text((24, 48), subtitle or "Preview render from the addon's real textures, not an in-game screenshot.",
           font=font(14, bold=False), fill=MUTED)
    return im


def save(im, name):
    os.makedirs(OUT, exist_ok=True)
    p = os.path.join(OUT, name)
    im.convert("RGB").save(p, optimize=True)
    print("wrote", os.path.relpath(p, REPO))


SAMPLE_ICONS = [
    "Spell_Nature_LightningShield", "Spell_Nature_Lightning", "Spell_Fire_FlameTounge",
    "Spell_Nature_HealingWaveGreater", "Spell_Frost_FrostShock", "Spell_Nature_EarthShock",
    "Spell_Fire_FlameShock", "Spell_Nature_ChainLightning", "Spell_Nature_MagicImmunity",
    "Spell_Nature_Cyclone", "Spell_Nature_RockBiter", "Spell_Nature_Purge", "Spell_Nature_Reincarnation",
]


def render_shapes():
    cols, cw, chh = 5, 190, 180
    rows = int(math.ceil(len(FORM_SHAPES) / cols))
    im = new_canvas(cols * cw + 40, 90 + rows * chh + 30, "IchaUI button & drawer shapes",
                    "Preview render: every Shape option for bars, hero bars, drawers and the totem bar (44 px button, 2x).")
    d = ImageDraw.Draw(im)
    lf = font(15)
    for i, shape in enumerate(FORM_SHAPES):
        col, row = i % cols, i // cols
        cx = 20 + col * cw + cw / 2
        cy = 90 + row * chh + 70
        ic = icon(SAMPLE_ICONS[i % len(SAMPLE_ICONS)], "Spell_Nature_LightningShield")
        draw_button(im, cx, cy, shape, ic, 44 if shape != "rect" else 44, width=60)
        d.text((cx, cy + 72), FORM_LABEL[shape], font=lf, fill=(235, 232, 220), anchor="mm")
    save(im, "preview-button-shapes.png")


TOTEMS = [
    ("earth", "Spell_Nature_StoneSkinTotem", "1:48", None, (0.90, 0.70, 0.28)),
    ("fire", "Spell_Fire_SearingTotem", "34", 0.62, (1.0, 0.55, 0.12)),
    ("water", "Spell_Nature_ManaRegenTotem", "52", 0.30, (0.30, 0.65, 1.0)),
    ("air", "Spell_Nature_Windfury", "1:12", None, (0.55, 0.95, 1.0)),
]


def render_totems():
    rows = [("circle", "Circle (default)"), ("tooltip", "Tooltip Ring"), ("portrait", "Portrait"),
            ("bronze", "Metal Bronze"), ("square", "Square")]
    side, gap = 40, 8
    rowh = 128
    w = 900
    im = new_canvas(w, 90 + rowh * len(rows) + 70, "Shaman totem bar",
                    "Preview render: four element slots, set paging arrows, timers and the cast / tick progress ring in five shapes.")
    d = ImageDraw.Draw(im)
    tf = font(11 * K)
    lf = font(16)
    arrowL = media("Arrow-Left-Up.tga")
    for r, (shape, label) in enumerate(rows):
        cy = 90 + r * rowh + rowh / 2
        x0 = 240
        d.text((24, cy), label, font=lf, fill=(235, 232, 220), anchor="lm")
        paste_c(im, resized(arrowL, 22 * K), x0 - 22, cy)
        for i, (el, ic_name, timer, pct, rgb) in enumerate(TOTEMS):
            cx = x0 + 20 + i * (side + gap) * K + side * K / 2
            ic = icon(ic_name)
            if el == "fire" and r == 1:
                ic = media("firetwist-searing.tga")
            geo = draw_button(im, cx, cy, shape, ic, side)
            if pct is not None:
                cast_ring(im, geo, pct, rgb)
            outlined(d, (cx, cy), timer, tf)
        xr = x0 + 20 + 4 * (side + gap) * K - gap * K + 22 + 20
        paste_c(im, resized(arrowL, 22 * K).transpose(Image.FLIP_LEFT_RIGHT), xr, cy)
    nf = font(14, bold=False)
    d.text((24, im.height - 56), "Fire and water slots show the progress ring (Searing tick / Mana Spring pulse).",
           font=nf, fill=MUTED)
    d.text((24, im.height - 34), "Tooltip Ring row: the Fire Twist icon (Fire Nova, then Searing) on the fire slot.",
           font=nf, fill=MUTED)
    save(im, "preview-totem-bar.png")


def elwynn_map():
    tiles = []
    for i in range(1, 13):
        t = bliz(os.path.join("WorldMap", "Elwynn"), "Elwynn%d" % i)
        if t is None:
            return Image.new("RGBA", (512, 512), (60, 90, 50, 255))
        tiles.append(t)
    tw, th = tiles[0].size
    full = Image.new("RGBA", (tw * 4, th * 3))
    for i, t in enumerate(tiles):
        full.paste(t, ((i % 4) * tw, (i // 4) * th))
    return full.crop((int(tw * 1.3), int(th * 0.7), int(tw * 1.3) + 420, int(th * 0.7) + 420))


MM_FRAMES = [("wowui", "WowUI", "WowUI_Circular_Frame.tga", 2.05),
             ("metalbronze", "Metal Bronze", "MetalBronze_Circular_Frame.tga", 1.94),
             ("metaleternium", "Metal Eternium", "MetalEternium_Circular_Frame.tga", 1.91),
             ("horde", "Horde", "Horde_Circular_Frame.tga", 1.95),
             ("fire", "Fire", "Fire_Circular_Frame.tga", 2.03),
             ("arcane", "Arcane", "Arcane_Circular_Frame.tga", 1.92),
             ("woodboards", "Wood Boards", "WoodBoards_Circular_Frame.tga", 1.95),
             ("generic1target", "Generic Target", "Generic1Target_Circular_Frame.tga", 1.37),
             ("pandarentraining", "Pandaren Training", "PandarenTraining_Circular_Frame.tga", 1.71)]


def draw_minimap(canvas, cx, cy, D, kind, arg=None):
    base = resized(elwynn_map(), D)
    if kind in ("square", "pfui"):
        paste_c(canvas, base, cx, cy)
        if kind == "square":
            e = 16
            paste_c(canvas, backdrop_edge(D + 8, D + 8, tooltip_border(), e, MM_GOLD), cx, cy)
        else:
            file, outset = arg
            e = 8 * K
            paste_c(canvas, backdrop_edge(D + 2 * outset * K, D + 2 * outset * K, shape_tex("pfui", file), e), cx, cy)
        return
    if kind == "mask":
        mask_file, border = arg
        m = resized(shape_tex(mask_file), D).split()[3]
        base.putalpha(m)
        paste_c(canvas, base, cx, cy)
        if border:
            paste_c(canvas, mul(resized(shape_tex(border), D * 560 / 528), MM_GOLD), cx, cy)
        return
    base.putalpha(circle_mask(D))
    paste_c(canvas, base, cx, cy)
    if kind == "circle":
        paste_c(canvas, resized(shape_tex("x4", "PortraitFrame.tga"), D * 1.07), cx, cy)
    elif kind == "tooltipring":
        paste_c(canvas, mul(resized(shape_tex("tooltip-ring.tga"), D * 1.06), MM_GOLD), cx, cy)
    elif kind == "frame":
        file, scale = arg
        paste_c(canvas, resized(shape_tex("x4", file), D * scale), cx, cy)


def render_minimap():
    items = [("Square (default)", "square", None), ("Circle", "circle", None)]
    items += [(lab, "frame", (f, s)) for (_, lab, f, s) in MM_FRAMES]
    items += [("Tooltip Ring", "tooltipring", None),
              ("SM Top Left", "mask", ("sm_topleft.tga", "sm_topleft_border.tga")),
              ("SM Bottom", "mask", ("sm_bottom.tga", "sm_bottom_border.tga")),
              ("pfUI Blizz", "pfui", ("border_blizz.tga", 6))]
    cols, cw, chh, D = 5, 250, 270, 190
    rows = int(math.ceil(len(items) / cols))
    im = new_canvas(cols * cw + 40, 90 + rows * chh + 20, "Minimap shapes",
                    "Preview render: a selection of the 26 minimap shapes (Map tab > Shape). Tint recolors frame art in game.")
    d = ImageDraw.Draw(im)
    lf = font(16)
    for i, (lab, kind, arg) in enumerate(items):
        cx = 20 + (i % cols) * cw + cw / 2
        cy = 90 + (i // cols) * chh + 125
        draw_minimap(im, cx, cy, D, kind, arg)
    for i, (lab, kind, arg) in enumerate(items):
        cx = 20 + (i % cols) * cw + cw / 2
        cy = 90 + (i // cols) * chh + 125
        tw = d.textlength(lab, font=lf)
        d.rounded_rectangle((cx - tw / 2 - 8, cy + 116, cx + tw / 2 + 8, cy + 140), 6, fill=(18, 18, 21, 230))
        d.text((cx, cy + 128), lab, font=lf, fill=(235, 232, 220), anchor="mm")
    save(im, "preview-minimap-shapes.png")


def draw_xp(canvas, x, y, W, H, fill_pct, fill_rgb, rest_pct, text, scale):
    e = int(round(12 * scale))
    inset = int(round(e * 4 / 16))
    tw, th = W - 2 * inset, H - 2 * inset
    bar = bliz("TARGETINGFRAME", "UI-StatusBar")
    track = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    track.alpha_composite(mul(resized(bar, tw, th), (0.15, 0.15, 0.15)))
    fw = int(tw * fill_pct)
    if fw > 0:
        track.alpha_composite(mul(resized(bar, fw, th), fill_rgb), (0, 0))
    rw = int(min(tw - fw, tw * rest_pct))
    if rw > 0:
        track.alpha_composite(mul(resized(bar, rw, th), (0.25, 0.45, 1.0)), (fw, 0))
    td = ImageDraw.Draw(track)
    for i in range(1, 20):
        tx = int(tw * i / 20)
        td.rectangle((tx, 0, tx + max(1, int(scale)) - 1, th), fill=(0, 0, 0, 255))
    paste(canvas, track, x + inset, y + inset)
    paste(canvas, backdrop_edge(W, H, tooltip_border(), e, GOLD), x, y)
    if text:
        outlined(ImageDraw.Draw(canvas), (x + W / 2, y + H / 2), text, font(int(11 * scale * 0.9)))


def render_xp():
    scale = 1.75 * K / 1.4
    W, H = int(400 * scale), int(14 * scale) + 8
    im = new_canvas(W + 80, 330, "XP / reputation bar",
                    "Preview render: 20-segment bar with gold edge. Hover shows the numbers; right-click switches XP and reputation.")
    d = ImageDraw.Draw(im)
    lf = font(16)
    d.text((40, 100), "XP mode (purple XP, blue rested past it)", font=lf, fill=(235, 232, 220))
    draw_xp(im, 40, 128, W, H, 0.42, (0.58, 0.0, 0.55), 0.21, "28350 | 67500 | 21%", scale)
    d.text((40, 200), "Reputation mode (watched faction, standing color)", font=lf, fill=(235, 232, 220))
    draw_xp(im, 40, 228, W, H, 0.66, (0.0, 0.6, 0.1), 0, "Thunder Bluff | Friendly | 3960 / 6000 | 66%", scale)
    save(im, "preview-xp-bar.png")


def render_raid_icons():
    order = [8, 7, 5, 2, 6, 3, 1, 4]
    names = ["Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull"]
    sheet = bliz("TARGETINGFRAME", "UI-RaidTargetingIcons")
    q = sheet.width // 4
    cw = 120
    im = new_canvas(cw * 8 + 60, 290, "Smart Mark icon order",
                    "Preview render: default order for both Smart Mark lists (Mark tab). Reorder with Up / Dn, uncheck to skip an icon.")
    d = ImageDraw.Draw(im)
    for pos, idx in enumerate(order):
        cx = 30 + pos * cw + cw / 2
        i = idx - 1
        ic = sheet.crop(((i % 4) * q, (i // 4) * q, (i % 4 + 1) * q, (i // 4 + 1) * q))
        paste_c(im, resized(ic, 72), cx, 150)
        d.text((cx, 95), str(pos + 1), font=font(20), fill=LABEL, anchor="mm")
        d.text((cx, 205), names[i], font=font(16), fill=(235, 232, 220), anchor="mm")
    d.text((30, 245), "Sweep the mouse over a pack while holding the bind's modifier: each unmarked unit gets the next checked icon.",
           font=font(14, bold=False), fill=MUTED)
    save(im, "preview-raid-icon-order.png")


def main():
    render_shapes()
    render_totems()
    render_minimap()
    render_xp()
    render_raid_icons()


if __name__ == "__main__":
    main()
