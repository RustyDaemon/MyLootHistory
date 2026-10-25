"""
Builds kit/fonts/RustyPixel.ttf, the kit's pixel font, from the glyph art below.

Every glyph is drawn on a pixel grid: '#' is ink, '.' is empty. Art rows run top to bottom
starting at the cap height (y = 6), so a 7-row glyph sits on the baseline and rows 8 and 9 of a
9-row glyph are its descender. Accented letters are not drawn; they are composed from a base
letter and a mark.

Grid: cap height 7, x-height 5, descender 2, accents on capitals reach y = 9. The em is 12 pixels,
so at font size 12 one grid pixel is one screen pixel.

    pip install fonttools pillow
    python tools/font/build_font.py            # writes kit/fonts/RustyPixel.ttf
    python tools/font/build_font.py --preview  # also writes tools/font/preview.png
"""

import os
import sys

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

FAMILY = "Rusty Pixel"
PX = 100                  # font units per grid pixel
EM = 12                   # grid pixels per em
ASCENT, DESCENT = 10, 2   # grid pixels above / below the baseline
CAP_TOP = 6               # y of the first art row
SPACING = 1               # empty grid pixels after every glyph

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "kit", "fonts", "RustyPixel.ttf")

GLYPHS = {
    # --- capitals -----------------------------------------------------------
    "A": """
.###.
#...#
#...#
#####
#...#
#...#
#...#""",
    "B": """
####.
#...#
#...#
####.
#...#
#...#
####.""",
    "C": """
.###.
#...#
#....
#....
#....
#...#
.###.""",
    "D": """
####.
#...#
#...#
#...#
#...#
#...#
####.""",
    "E": """
#####
#....
#....
####.
#....
#....
#####""",
    "F": """
#####
#....
#....
####.
#....
#....
#....""",
    "G": """
.###.
#...#
#....
#.###
#...#
#...#
.####""",
    "H": """
#...#
#...#
#...#
#####
#...#
#...#
#...#""",
    "I": """
###
.#.
.#.
.#.
.#.
.#.
###""",
    "J": """
..###
...#.
...#.
...#.
...#.
#..#.
.##..""",
    "K": """
#...#
#..#.
#.#..
##...
#.#..
#..#.
#...#""",
    "L": """
#....
#....
#....
#....
#....
#....
#####""",
    "M": """
#...#
##.##
#.#.#
#.#.#
#...#
#...#
#...#""",
    "N": """
#...#
#...#
##..#
#.#.#
#..##
#...#
#...#""",
    "O": """
.###.
#...#
#...#
#...#
#...#
#...#
.###.""",
    "P": """
####.
#...#
#...#
####.
#....
#....
#....""",
    "Q": """
.###.
#...#
#...#
#...#
#.#.#
#..#.
.##.#""",
    "R": """
####.
#...#
#...#
####.
#.#..
#..#.
#...#""",
    "S": """
.###.
#...#
#....
.###.
....#
#...#
.###.""",
    "T": """
#####
..#..
..#..
..#..
..#..
..#..
..#..""",
    "U": """
#...#
#...#
#...#
#...#
#...#
#...#
.###.""",
    "V": """
#...#
#...#
#...#
#...#
#...#
.#.#.
..#..""",
    "W": """
#...#
#...#
#...#
#.#.#
#.#.#
##.##
#...#""",
    "X": """
#...#
#...#
.#.#.
..#..
.#.#.
#...#
#...#""",
    "Y": """
#...#
#...#
.#.#.
..#..
..#..
..#..
..#..""",
    "Z": """
#####
....#
...#.
..#..
.#...
#....
#####""",
    "Æ": """
.######
#..#...
#..#...
#####..
#..#...
#..#...
#..####""",
    "Œ": """
.######
#..#...
#..#...
#..####
#..#...
#..#...
.######""",
    "Ø": """
.###.
#..##
#.#.#
#.#.#
#.#.#
##..#
.###.""",

    # --- small letters ------------------------------------------------------
    "a": """
.....
.....
.###.
....#
.####
#...#
.####""",
    "b": """
#....
#....
####.
#...#
#...#
#...#
####.""",
    "c": """
.....
.....
.###.
#....
#....
#....
.###.""",
    "d": """
....#
....#
.####
#...#
#...#
#...#
.####""",
    "e": """
.....
.....
.###.
#...#
#####
#....
.###.""",
    "f": """
..##
.#..
####
.#..
.#..
.#..
.#..""",
    "g": """
.....
.....
.####
#...#
#...#
#...#
.####
....#
.###.""",
    "h": """
#....
#....
####.
#...#
#...#
#...#
#...#""",
    "i": """
#
.
#
#
#
#
#""",
    "ı": """
.
.
#
#
#
#
#""",
    "j": """
..#
...
..#
..#
..#
..#
..#
..#
##.""",
    "k": """
#...
#...
#..#
#.#.
##..
#.#.
#..#""",
    "l": """
#.
#.
#.
#.
#.
#.
.#""",
    "m": """
.....
.....
####.
#.#.#
#.#.#
#.#.#
#.#.#""",
    "n": """
.....
.....
####.
#...#
#...#
#...#
#...#""",
    "o": """
.....
.....
.###.
#...#
#...#
#...#
.###.""",
    "p": """
.....
.....
####.
#...#
#...#
#...#
####.
#....
#....""",
    "q": """
.....
.....
.####
#...#
#...#
#...#
.####
....#
....#""",
    "r": """
....
....
#.##
##..
#...
#...
#...""",
    "s": """
.....
.....
.####
#....
.###.
....#
####.""",
    "t": """
.#..
.#..
####
.#..
.#..
.#..
..##""",
    "u": """
.....
.....
#...#
#...#
#...#
#...#
.####""",
    "v": """
.....
.....
#...#
#...#
#...#
.#.#.
..#..""",
    "w": """
.....
.....
#...#
#...#
#.#.#
#.#.#
.#.#.""",
    "x": """
.....
.....
#...#
.#.#.
..#..
.#.#.
#...#""",
    "y": """
.....
.....
#...#
#...#
#...#
#...#
.####
....#
.###.""",
    "z": """
.....
.....
#####
...#.
..#..
.#...
#####""",
    "ß": """
.###.
#...#
#..#.
#.#..
#..#.
#...#
#.##.""",
    "æ": """
.......
.......
.##.##.
...#..#
.######
#..#...
.##.###""",
    "œ": """
.......
.......
.##.##.
#..#..#
#..####
#..#...
.##.###""",
    "ø": """
.....
.....
.###.
#..##
#.#.#
##..#
.###.""",

    # --- digits: all one width, so columns of numbers line up -----------------
    "0": """
.###.
#...#
#..##
#.#.#
##..#
#...#
.###.""",
    "1": """
..#..
.##..
..#..
..#..
..#..
..#..
.###.""",
    "2": """
.###.
#...#
....#
...#.
..#..
.#...
#####""",
    "3": """
.###.
#...#
....#
..##.
....#
#...#
.###.""",
    "4": """
...#.
..##.
.#.#.
#..#.
#####
...#.
...#.""",
    "5": """
#####
#....
####.
....#
....#
#...#
.###.""",
    "6": """
..##.
.#...
#....
####.
#...#
#...#
.###.""",
    "7": """
#####
....#
...#.
..#..
.#...
.#...
.#...""",
    "8": """
.###.
#...#
#...#
.###.
#...#
#...#
.###.""",
    "9": """
.###.
#...#
#...#
.####
....#
...#.
.##..""",

    # --- punctuation and symbols -----------------------------------------------
    "!": """
#
#
#
#
#
.
#""",
    '"': """
#.#
#.#""",
    "#": """
.....
.#.#.
#####
.#.#.
#####
.#.#.""",
    "$": """
..#..
.####
#.#..
.###.
..#.#
####.
..#..""",
    "%": """
##...
##..#
...#.
..#..
.#...
#..##
...##""",
    "&": """
.##..
#..#.
#.#..
.#...
#.#.#
#..#.
.##.#""",
    "'": """
#
#""",
    "(": """
..#
.#.
#..
#..
#..
.#.
..#""",
    ")": """
#..
.#.
..#
..#
..#
.#.
#..""",
    "*": """
.....
..#..
#.#.#
.###.
#.#.#
..#..""",
    "+": """
.....
.....
..#..
..#..
#####
..#..
..#..""",
    ",": """
..
..
..
..
..
..
.#
#.""",
    "-": """
....
....
....
....
####""",
    ".": """
.
.
.
.
.
.
#""",
    "/": """
....#
....#
...#.
..#..
.#...
#....
#....""",
    ":": """
.
.
.
#
.
.
#""",
    ";": """
..
..
..
.#
..
..
.#
#.""",
    "<": """
...
...
..#
.#.
#..
.#.
..#""",
    "=": """
....
....
....
####
....
####""",
    ">": """
...
...
#..
.#.
..#
.#.
#..""",
    "?": """
.###.
#...#
....#
...#.
..#..
.....
..#..""",
    "@": """
.###.
#...#
#.###
#.#.#
#.###
#....
.###.""",
    "[": """
###
#..
#..
#..
#..
#..
###""",
    "\\": """
#....
#....
.#...
..#..
...#.
....#
....#""",
    "]": """
###
..#
..#
..#
..#
..#
###""",
    "^": """
..#..
.#.#.
#...#""",
    "_": """
.....
.....
.....
.....
.....
.....
.....
#####""",
    "`": """
#.
.#""",
    "{": """
..##
.#..
.#..
#...
.#..
.#..
..##""",
    "|": """
#
#
#
#
#
#
#
#""",
    "}": """
##..
..#.
..#.
...#
..#.
..#.
##..""",
    "~": """
.....
.....
.....
.#...
#.#.#
...#.""",
    "·": """
.
.
.
.
#""",
    "•": """
...
...
...
###
###
###""",
    "…": """
.....
.....
.....
.....
.....
.....
#.#.#""",
    "–": """
.....
.....
.....
.....
#####""",
    "—": """
.......
.......
.......
.......
#######""",
    "×": """
.....
.....
#...#
.#.#.
..#..
.#.#.
#...#""",
    "°": """
.#.
#.#
.#.""",
}

# Same shapes under other code points.
ALIASES = {
    "‘": "'", "’": "'", "“": '"', "”": '"',
    " ": " ", "−": "-",
}

# Marks, drawn top row first; "bottom" is the y of their lowest row over a small letter and
# over a capital.
MARKS = {
    "grave":      ("#.\n.#",       6, 8),
    "acute":      (".#\n#.",       6, 8),
    "circumflex": (".#.\n#.#",     6, 8),
    "caron":      ("#.#\n.#.",     6, 8),
    "tilde":      (".#.#\n#.#.",   6, 8),
    "diaeresis":  ("#.#",          6, 8),
    "ring":       (".#.\n#.#\n.#.", 5, 7),
    "cedilla":    (".#\n#.",       -1, -1),
}

# Marks lean: an acute sits a pixel right of center, a grave a pixel left.
LEAN = {"acute": 1, "grave": 0}

COMPOSED = {
    "À": ("A", "grave"), "Á": ("A", "acute"), "Â": ("A", "circumflex"),
    "Ã": ("A", "tilde"), "Ä": ("A", "diaeresis"), "Å": ("A", "ring"),
    "Ç": ("C", "cedilla"),
    "È": ("E", "grave"), "É": ("E", "acute"), "Ê": ("E", "circumflex"), "Ë": ("E", "diaeresis"),
    "Ì": ("I", "grave"), "Í": ("I", "acute"), "Î": ("I", "circumflex"), "Ï": ("I", "diaeresis"),
    "Ñ": ("N", "tilde"),
    "Ò": ("O", "grave"), "Ó": ("O", "acute"), "Ô": ("O", "circumflex"),
    "Õ": ("O", "tilde"), "Ö": ("O", "diaeresis"),
    "Ù": ("U", "grave"), "Ú": ("U", "acute"), "Û": ("U", "circumflex"), "Ü": ("U", "diaeresis"),
    "Ý": ("Y", "acute"), "Ÿ": ("Y", "diaeresis"),
    "à": ("a", "grave"), "á": ("a", "acute"), "â": ("a", "circumflex"),
    "ã": ("a", "tilde"), "ä": ("a", "diaeresis"), "å": ("a", "ring"),
    "ç": ("c", "cedilla"),
    "è": ("e", "grave"), "é": ("e", "acute"), "ê": ("e", "circumflex"), "ë": ("e", "diaeresis"),
    "ì": ("ı", "grave"), "í": ("ı", "acute"), "î": ("ı", "circumflex"),
    "ï": ("ı", "diaeresis"),
    "ñ": ("n", "tilde"),
    "ò": ("o", "grave"), "ó": ("o", "acute"), "ô": ("o", "circumflex"),
    "õ": ("o", "tilde"), "ö": ("o", "diaeresis"),
    "ù": ("u", "grave"), "ú": ("u", "acute"), "û": ("u", "circumflex"), "ü": ("u", "diaeresis"),
    "ý": ("y", "acute"), "ÿ": ("y", "diaeresis"),
    # Central European names
    "Ć": ("C", "acute"), "ć": ("c", "acute"), "Č": ("C", "caron"), "č": ("c", "caron"),
    "Ě": ("E", "caron"), "ě": ("e", "caron"), "Ń": ("N", "acute"), "ń": ("n", "acute"),
    "Ň": ("N", "caron"), "ň": ("n", "caron"), "Ř": ("R", "caron"), "ř": ("r", "caron"),
    "Ś": ("S", "acute"), "ś": ("s", "acute"), "Š": ("S", "caron"), "š": ("s", "caron"),
    "Ź": ("Z", "acute"), "ź": ("z", "acute"), "Ž": ("Z", "caron"), "ž": ("z", "caron"),
}

SPACE_WIDTH = 3


def parse(art, top=CAP_TOP):
    """Art -> (width, set of inked (x, y))."""
    rows = [row for row in art.strip("\n").split("\n")]
    width = max(len(row) for row in rows)
    ink = set()

    for i, row in enumerate(rows):
        for x, cell in enumerate(row):
            if cell == "#":
                ink.add((x, top - i))
            elif cell != ".":
                raise ValueError("bad cell %r in %r" % (cell, art))

    return width, ink


def trim(glyph):
    """Drops empty columns on either side, so spacing is the same SPACING between any two letters."""
    width, ink = glyph
    if not ink: return glyph

    left = min(x for x, _ in ink)
    right = max(x for x, _ in ink)
    return right - left + 1, {(x - left, y) for x, y in ink}


def flip(glyph):
    """Turns a glyph upside down around the x-height's middle, for the Spanish ¡ and ¿."""
    width, ink = glyph
    return width, {(width - 1 - x, 4 - y) for x, y in ink}


def compose(base, mark, upper):
    art, low_bottom, cap_bottom = MARKS[mark]
    base_width, base_ink = base
    rows = art.count("\n") + 1
    bottom = cap_bottom if upper else low_bottom
    mark_width, mark_ink = parse(art, top=bottom + rows - 1)
    width = max(base_width, mark_width)
    lean = LEAN.get(mark)
    base_off = (width - base_width + (1 if lean == 0 else 0)) // 2
    mark_off = (width - mark_width + (lean or 0)) // 2

    if mark == "cedilla":
        mark_off = base_off + (base_width - mark_width) // 2

    return width, {(x + base_off, y) for x, y in base_ink} | {(x + mark_off, y) for x, y in mark_ink}


def outline(ink):
    """Traces the inked cells into clockwise outer contours and counter-clockwise holes."""
    out = {}

    def edge(a, b):
        out.setdefault(a, []).append(b)

    for x, y in ink:
        if (x, y + 1) not in ink: edge((x, y + 1), (x + 1, y + 1))
        if (x + 1, y) not in ink: edge((x + 1, y + 1), (x + 1, y))
        if (x, y - 1) not in ink: edge((x + 1, y), (x, y))
        if (x - 1, y) not in ink: edge((x, y), (x, y + 1))

    loops = []

    while out:
        start = next(iter(out))
        loop = [start]
        here, came = start, None

        while True:
            ends = out[here]

            if came and len(ends) > 1:
                # Two cells touching only at a corner: turn right, so each stays its own shape.
                dx, dy = came
                right = (here[0] + dy, here[1] - dx)
                nxt = right if right in ends else ends[0]
            else:
                nxt = ends[0]

            ends.remove(nxt)
            if not ends: del out[here]

            came = (nxt[0] - here[0], nxt[1] - here[1])
            here = nxt

            if here == start: break

            loop.append(here)

        loops.append(simplify(loop))

    return loops


def simplify(loop):
    kept = []
    n = len(loop)

    for i, p in enumerate(loop):
        a, b = loop[i - 1], loop[(i + 1) % n]
        if (p[0] - a[0]) * (b[1] - p[1]) != (p[1] - a[1]) * (b[0] - p[0]):
            kept.append(p)

    return kept


def draw(ink):
    pen = TTGlyphPen(None)

    for loop in outline(ink):
        pen.moveTo((loop[0][0] * PX, loop[0][1] * PX))
        for x, y in loop[1:]:
            pen.lineTo((x * PX, y * PX))
        pen.closePath()

    return pen.glyph()


def glyph_name(char):
    return "space" if char == " " else "uni%04X" % ord(char)


def collect():
    glyphs = {char: parse(art) if char.isdigit() else trim(parse(art)) for char, art in GLYPHS.items()}
    glyphs[" "] = (SPACE_WIDTH, set())
    glyphs["¡"] = flip(glyphs["!"])
    glyphs["¿"] = flip(glyphs["?"])

    for char, (base, mark) in COMPOSED.items():
        glyphs[char] = compose(glyphs[base], mark, base.isupper())

    for char, source in ALIASES.items():
        glyphs[char] = glyphs[source]

    return glyphs


def build():
    glyphs = collect()
    missing = [chr(c) for c in range(0x20, 0x7F) if chr(c) not in glyphs]
    if missing: raise SystemExit("no glyph for: " + " ".join(missing))

    order = [".notdef"] + [glyph_name(c) for c in sorted(glyphs)]
    notdef = parse("""
#####
#...#
#...#
#...#
#...#
#...#
#####""")

    outlines = {".notdef": draw(notdef[1])}
    metrics = {".notdef": ((notdef[0] + SPACING) * PX, 0)}

    for char, (width, ink) in glyphs.items():
        name = glyph_name(char)
        outlines[name] = draw(ink)
        metrics[name] = ((width + SPACING) * PX, min((x for x, _ in ink), default=0) * PX)

    fb = FontBuilder(EM * PX, isTTF=True)
    fb.setupGlyphOrder(order)
    fb.setupCharacterMap({ord(c): glyph_name(c) for c in glyphs})
    fb.setupGlyf(outlines)
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=ASCENT * PX, descent=-DESCENT * PX)
    fb.setupNameTable({
        "familyName": FAMILY,
        "styleName": "Regular",
        "uniqueFontIdentifier": FAMILY + " Regular",
        "fullName": FAMILY,
        "psName": FAMILY.replace(" ", "") + "-Regular",
        "copyright": "Copyright (C) 2026 RustyDaemon",
        "version": "Version 1.000",
    })
    fb.setupOS2(
        sTypoAscender=ASCENT * PX, sTypoDescender=-DESCENT * PX, sTypoLineGap=0,
        usWinAscent=ASCENT * PX, usWinDescent=DESCENT * PX,
        sxHeight=5 * PX, sCapHeight=7 * PX, achVendID="RSTY",
    )
    fb.setupPost()

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    fb.save(OUT)
    print("wrote %s (%d glyphs)" % (OUT, len(order)))


def preview():
    from PIL import Image, ImageDraw, ImageFont

    lines = [
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ  abcdefghijklmnopqrstuvwxyz",
        "0123456789  !\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~",
        "Zoë Ålmo José ßæøœ Čšž ¿Qué? ¡Olé!",
        "[Ashen Blade] x2  ·  12,450g  ·  1h 24m  (3,120/h)",
        "Session 42m  ·  318 items  ·  98.6%  —  done…",
    ]
    scale = 3
    sizes = [12, 13, 15]
    height = sum((s + 6) * len(lines) + 10 for s in sizes)
    img = Image.new("RGB", (560, height), (11, 12, 14))
    pen = ImageDraw.Draw(img)
    y = 6

    for size in sizes:
        font = ImageFont.truetype(OUT, size)
        for line in lines:
            pen.text((6, y), line, font=font, fill=(234, 236, 241))
            y += size + 6
        y += 10

    img = img.resize((img.width * scale, img.height * scale), Image.NEAREST)
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "preview.png")
    img.save(path)
    print("wrote " + path)


if __name__ == "__main__":
    build()
    if "--preview" in sys.argv: preview()
