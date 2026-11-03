#!/usr/bin/env python3
"""Рендер дампа экрана эмулятора (или .pic OCIF) в PNG. Брайль рисуется точками 2x4."""
import sys, re, os
from PIL import Image, ImageDraw, ImageFont

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

FONT = None
for f in ['/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf', '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf']:
    if os.path.exists(f): FONT = ImageFont.truetype(f, 13); break
FONT = FONT or ImageFont.load_default()
BITS = [(0, 0), (0, 1), (0, 2), (1, 0), (1, 1), (1, 2), (0, 3), (1, 3)]

def render(w, h, cells, out, cw=8, ch=16, quant=True):
    im = Image.new('RGB', (w * cw, h * ch)); dr = ImageDraw.Draw(im)
    for (x, y), (bg, fg, s) in cells.items():
        if quant: bg, fg = quantize(bg), quantize(fg)
        X, Y = (x - 1) * cw, (y - 1) * ch
        dr.rectangle([X, Y, X + cw - 1, Y + ch - 1], fill=rgb(bg))
        o = ord(s) if s else 32
        if 0x2800 <= o <= 0x28FF:
            m = o - 0x2800
            for k, (bx, by) in enumerate(BITS):
                if m >> k & 1:
                    dr.rectangle([X + bx * cw // 2, Y + by * ch // 4, X + (bx + 1) * cw // 2 - 1, Y + (by + 1) * ch // 4 - 1], fill=rgb(fg))
        elif s.strip():
            dr.text((X, Y), s, fill=rgb(fg), font=FONT)
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
