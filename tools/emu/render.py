#!/usr/bin/env python3
"""Рендер дампа экрана эмулятора (или .pic OCIF) в PNG. Брайль рисуется точками 2x4."""
import sys, re, os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
_src = open(os.path.join(HERE, '..', '..', 'lib', 'color.lua'), encoding='utf-8').read()
PALETTE = [int(x, 16) for x in re.search(r'local palette = \{(.*?)\}', _src, re.S).group(1).replace('0x', '').split(',')]

def quantize(c):
    """Приближение к палитре GPU 3 уровня (как color.to8Bit)."""
    if c in _qcache: return _qcache[c]
    r, g, b = c >> 16 & 255, c >> 8 & 255, c & 255
    best = min(PALETTE, key=lambda p: ((p >> 16 & 255) - r) ** 2 + ((p >> 8 & 255) - g) ** 2 + ((p & 255) - b) ** 2)
    _qcache[c] = best
    return best
_qcache = {}

def rgb(c): return (c >> 16 & 255, c >> 8 & 255, c & 255)

FONT_URL = 'https://raw.githubusercontent.com/MightyPirates/OpenComputers/master-MC1.12/src/main/resources/assets/opencomputers/font.hex'
FONT_PATH = os.path.join(HERE, '.cache', 'font.hex')
_font = None

def font():
    """Настоящий шрифт OC: codepoint -> (width_cells, rows). 8x16 или 16x16 пикселей."""
    global _font
    if _font is None:
        if not os.path.exists(FONT_PATH):
            import urllib.request
            os.makedirs(os.path.dirname(FONT_PATH), exist_ok=True)
            urllib.request.urlretrieve(FONT_URL, FONT_PATH)
        _font = {}
        with open(FONT_PATH) as f:
            for line in f:
                cp, bits = line.strip().split(':')
                wide = len(bits) == 64
                step = 4 if wide else 2
                rows = [int(bits[i:i + step], 16) for i in range(0, len(bits), step)]
                _font[int(cp, 16)] = (2 if wide else 1, rows)
    return _font

def render(w, h, cells, out, scale=1, quant=True):
    cw, ch = 8, 16
    im = Image.new('RGB', (w * cw, h * ch))
    px = im.load()
    fnt = font()
    # сначала фон всех ячеек, потом глифы (широкий глиф ложится на соседнюю ячейку)
    for (x, y), (bg, fg, s) in cells.items():
        bg = quantize(bg) if quant else bg
        c = rgb(bg)
        X, Y = (x - 1) * cw, (y - 1) * ch
        for yy in range(ch):
            for xx in range(cw):
                px[X + xx, Y + yy] = c
    for (x, y), (bg, fg, s) in cells.items():
        if not s or s == ' ': continue
        g = fnt.get(ord(s)) or fnt.get(ord('?'))
        width, rows = g
        fg = rgb(quantize(fg) if quant else fg)
        X, Y = (x - 1) * cw, (y - 1) * ch
        bw = width * 8
        for yy, row in enumerate(rows):
            for xx in range(bw):
                if row >> (bw - 1 - xx) & 1 and X + xx < w * cw:
                    px[X + xx, Y + yy] = fg
    if scale != 1:
        im = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
    im.save(out)

def load_dump(path):
    with open(path, encoding='utf-8') as f:
        w, h = map(int, f.readline().split())
        cells = {}
        for i in range(w * h):
            line = f.readline().rstrip('\n')
            bg, fg, s = line[:6], line[7:13], line[14:]
            cells[(i % w + 1, i // w + 1)] = (int(bg, 16), int(fg, 16), s or ' ')
    return w, h, cells

def load_pic(path):
    d = open(path, 'rb').read(); assert d[:4] == b'OCIF' and d[4] == 6
    w, h = d[5], d[6]; i = 7; cells = {}
    def rc(i):
        b = d[i]; n = 4 if b >= 0xF0 else 3 if b >= 0xE0 else 2 if b >= 0xC0 else 1
        return d[i:i + n].decode('utf-8'), i + n
    na = d[i]; i += 1
    for _ in range(na):
        i += 1; ns = d[i] * 256 + d[i + 1]; i += 2
        for _ in range(ns):
            s, i = rc(i); nb = d[i]; i += 1
            for _ in range(nb):
                bg = PALETTE[d[i]]; i += 1; nf = d[i]; i += 1
                for _ in range(nf):
                    fg = PALETTE[d[i]]; i += 1; ny = d[i]; i += 1
                    for _ in range(ny):
                        y = d[i]; i += 1; nx = d[i]; i += 1
                        for _ in range(nx):
                            cells[(d[i], y)] = (bg, fg, s); i += 1
    return w, h, cells

if __name__ == '__main__':
    src, out = sys.argv[1], sys.argv[2]
    w, h, cells = load_pic(src) if src.endswith('.pic') else load_dump(src)
    render(w, h, cells, out)
