"""Vector-only review concepts; does not replace shipped application assets."""
from pathlib import Path
import ctypes as c
import html
import subprocess
import xml.etree.ElementTree as ET

from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.transformPen import TransformPen

OUT = Path(__file__).resolve().parent
FONT = Path('/Volumes/Bitcode/GitHub/Stash/app/src/main/res/font/pacifico.ttf')
font = TTFont(FONT)
glyphs = font.getGlyphSet()
order = font.getGlyphOrder()
upem = font['head'].unitsPerEm
hb = c.CDLL('/opt/homebrew/lib/libharfbuzz.dylib')


class Info(c.Structure):
    _fields_ = [(n, c.c_uint32) for n in ['glyph', 'mask', 'cluster', 'var1', 'var2']]


class Position(c.Structure):
    _fields_ = [(n, c.c_int32) for n in ['advance_x', 'advance_y', 'offset_x', 'offset_y', 'var']]


def api(name, args, result):
    fn = getattr(hb, name)
    fn.argtypes, fn.restype = args, result
    return fn


ptr, uint = c.c_void_p, c.c_uint
blob = api('hb_blob_create', [c.c_char_p, uint, c.c_int, ptr, ptr], ptr)(FONT.read_bytes(), FONT.stat().st_size, 0, None, None)
face = api('hb_face_create', [ptr, uint], ptr)(blob, 0)
hbfont = api('hb_font_create', [ptr], ptr)(face)
api('hb_ot_font_set_funcs', [ptr], None)(hbfont)
api('hb_font_set_scale', [ptr, c.c_int, c.c_int], None)(hbfont, upem, upem)


def outline(text):
    buffer = api('hb_buffer_create', [], ptr)()
    data = text.encode()
    api('hb_buffer_add_utf8', [ptr, c.c_char_p, c.c_int, uint, c.c_int], None)(buffer, data, len(data), 0, len(data))
    api('hb_buffer_guess_segment_properties', [ptr], None)(buffer)
    api('hb_shape', [ptr, ptr, ptr, uint], None)(hbfont, buffer, None, 0)
    count = uint()
    infos = api('hb_buffer_get_glyph_infos', [ptr, c.POINTER(uint)], c.POINTER(Info))(buffer, c.byref(count))
    positions = api('hb_buffer_get_glyph_positions', [ptr, c.POINTER(uint)], c.POINTER(Position))(buffer, c.byref(count))
    pen, bounds = SVGPathPen(glyphs), BoundsPen(glyphs)
    x = y = 0
    for i in range(count.value):
        assert infos[i].glyph != 0, f'Missing glyph: {text}'
        p = positions[i]
        transform = (1, 0, 0, 1, x + p.offset_x, y + p.offset_y)
        glyph = glyphs[order[infos[i].glyph]]
        glyph.draw(TransformPen(pen, transform))
        glyph.draw(TransformPen(bounds, transform))
        x, y = x + p.advance_x, y + p.advance_y
    api('hb_buffer_destroy', [ptr], None)(buffer)
    assert bounds.bounds and count.value > 0
    return pen.getCommands(), bounds.bounds


WORDS = {text: outline(text) for text in ['P', 'PinShutter']}


def lettering(text, cx, cy, width, height, fill, extra=''):
    path, (left, bottom, right, top) = WORDS[text]
    scale = min(width / (right - left), height / (top - bottom))
    tx = cx - (left + right) * scale / 2
    ty = cy + (top + bottom) * scale / 2
    return f'<g transform="matrix({scale} 0 0 {-scale} {tx} {ty})" {extra}><path d="{path}" fill="{fill}"/></g>'


DEFS = '''
<linearGradient id="cool-rim" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#fcffff"/><stop offset=".3" stop-color="#8bf8e6"/><stop offset=".56" stop-color="#8484ff"/><stop offset=".8" stop-color="#ffb69a"/><stop offset="1" stop-color="#fbffff"/></linearGradient>
<linearGradient id="cool-word" x1="0" y1="0" x2="1" y2=".8"><stop stop-color="#8cebd6"/><stop offset=".35" stop-color="#b1a1ff"/><stop offset=".7" stop-color="#ffab97"/><stop offset="1" stop-color="#a8e2fd"/></linearGradient>
<linearGradient id="gold-word" x1="0" y1="0" x2=".8" y2="1"><stop stop-color="#fff5c2"/><stop offset=".34" stop-color="#ffe660"/><stop offset=".7" stop-color="#f4b544"/><stop offset="1" stop-color="#fff3bc"/></linearGradient>
<linearGradient id="white-word" x1="0" y1="0" x2=".7" y2="1"><stop stop-color="#fffdf6"/><stop offset=".55" stop-color="#d3d6fa"/><stop offset="1" stop-color="#fbf6e8"/></linearGradient>
<radialGradient id="lens" cx=".3" cy=".18" r=".9"><stop stop-color="#c8ffef" stop-opacity=".52"/><stop offset=".48" stop-color="#274d83" stop-opacity=".28"/><stop offset="1" stop-color="#3152db" stop-opacity=".6"/></radialGradient>
<radialGradient id="amber-lens" cx=".2" cy=".15" r="1"><stop stop-color="#fff5bc" stop-opacity=".6"/><stop offset=".45" stop-color="#8a6d17" stop-opacity=".42"/><stop offset="1" stop-color="#df8f25" stop-opacity=".5"/></radialGradient>
<linearGradient id="pin-glass" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#ddfff5" stop-opacity=".8"/><stop offset=".35" stop-color="#54c7bc" stop-opacity=".6"/><stop offset=".68" stop-color="#6378e2" stop-opacity=".8"/><stop offset="1" stop-color="#c7b2ff" stop-opacity=".8"/></linearGradient>
<filter id="blur"><feGaussianBlur stdDeviation="34"/></filter>
<filter id="shadow" x="-.3" y="-.3" width="1.6" height="1.8"><feGaussianBlur in="SourceAlpha" stdDeviation="8"/><feOffset dy="12"/><feColorMatrix type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 .38 0"/><feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>
<filter id="word-glass" x="-.1" y="-.3" width="1.2" height="1.6" color-interpolation-filters="sRGB"><feGaussianBlur in="SourceAlpha" stdDeviation="1.7" result="bump"/><feSpecularLighting in="bump" surfaceScale="4" specularConstant=".65" specularExponent="23" lighting-color="#fffef6" result="shine"><feDistantLight azimuth="235" elevation="55"/></feSpecularLighting><feComposite in="shine" in2="SourceAlpha" operator="in" result="edge"/><feMerge><feMergeNode in="SourceGraphic"/><feMergeNode in="edge"/></feMerge></filter>
<clipPath id="tile"><rect width="512" height="512" rx="112"/></clipPath>
'''


def icon(kind):
    gold = kind == 'b'
    blobs = (('#f0ca3c', 70, 95, 125), ('#dc8b26', 440, 190, 125), ('#796426', 290, 490, 150)) if gold else (
        ('#27ceb1', 60, 70, 130), ('#ff886e', 432, 150, 105), ('#414bc9', 310, 480, 160), ('#9d6ce8', 45, 405, 75))
    content = '<rect width="512" height="512" fill="#151b28"/>'
    content += '<g filter="url(#blur)">' + ''.join(
        f'<circle cx="{x}" cy="{y}" r="{r}" fill="{color}" opacity="{.63 if gold else .87}"/>' for color, x, y, r in blobs) + '</g>'
    if kind in ['a', 'b']:
        rim = 'gold-word' if gold else 'cool-rim'
        lens = 'amber-lens' if gold else 'lens'
        content += f'<circle cx="256" cy="256" r="164" fill="url(#{lens})" stroke="url(#{rim})" stroke-width="3" filter="url(#shadow)"/>'
        content += f'<circle cx="256" cy="256" r="155" fill="none" stroke="#fffdf3" stroke-opacity=".12" stroke-width="1"/>'
        content += lettering('P', 248, 244, 220, 242, '#fffdf3', 'filter="url(#shadow)"')
        content += '<path d="M131 170 C171 95 258 82 321 116" fill="none" stroke="#ffffff" stroke-width="5" opacity=".8" stroke-linecap="round"/>'
        content += f'<path d="M154 387 C213 432 318 427 365 364" fill="none" stroke="url(#{rim})" stroke-width="3" opacity=".75" stroke-linecap="round"/>'
        # A small shutter seam makes the lens read as a camera, not a bubble.
        content += '<path d="M346 128 L365 152 M365 152 L373 185" fill="none" stroke="#fff9ef" stroke-width="2" opacity=".38"/>'
    else:
        pin = 'M256 432 C226 391 122 303 122 219 C122 145 182 85 256 85 C330 85 390 145 390 219 C390 303 286 391 256 432Z'
        content += f'<path d="{pin}" fill="url(#pin-glass)" stroke="url(#cool-rim)" stroke-width="3.5" filter="url(#shadow)"/>'
        content += '<circle cx="256" cy="218" r="80" fill="#142640" fill-opacity=".68" stroke="url(#cool-rim)" stroke-width="3"/>'
        content += '<circle cx="256" cy="218" r="65" fill="url(#lens)" stroke="#eefbff" stroke-width="1.5" stroke-opacity=".3"/>'
        content += '<path d="M256 171 L296 195 L296 241 L256 265 L216 241 L216 195Z" fill="none" stroke="#fff9ed" stroke-width="11" stroke-linejoin="round"/>'
        content += '<path d="M150 183 C169 119 233 102 275 114" fill="none" stroke="#fff" stroke-width="5" opacity=".75" stroke-linecap="round"/>'
    content += '<rect x="1" y="1" width="510" height="510" rx="111" fill="none" stroke="#ffffff" stroke-opacity=".10" stroke-width="2"/>'
    return '<g clip-path="url(#tile)">' + content + '</g>'


def svg(content, width, height, title):
    result = f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}"><title>{html.escape(title)}</title><defs>{DEFS}</defs>{content}</svg>'
    ET.fromstring(result)
    return result


names = {'a': ('01', 'Spectrum P', 'Closest to the Stash glass identity', 'cool-word'),
         'b': ('02', 'Amber P', 'The glass treatment in PinShutter yellow', 'gold-word'),
         'c': ('03', 'Pin Lens', 'A location-first symbol with a shutter core', 'white-word')}
board = '''<rect width="1600" height="1130" fill="#100f14"/>
<text x="54" y="58" fill="#aaa3b2" font-family="Arial,sans-serif" font-size="14" letter-spacing="3">PINSHUTTER / IDENTITY EXPLORATION</text>
<text x="52" y="120" fill="#f5f1e9" font-family="Arial,sans-serif" font-size="40" font-weight="600">The Stash glass language. A new camera identity.</text>
<text x="54" y="155" fill="#aaa3b2" font-family="Arial,sans-serif" font-size="18">Rounded lens forms, flowing script and restrained colour. Three directions for review.</text>'''
for index, (kind, (number, name, description, fill)) in enumerate(names.items()):
    x = 48 + index * 510
    board += f'<rect x="{x}" y="200" width="484" height="780" rx="26" fill="#1a171f" stroke="#342e3b"/>'
    board += f'<text x="{x+28}" y="244" fill="#c4bacb" font-family="Arial,sans-serif" font-size="13" letter-spacing="2">{number} / {name.upper()}</text>'
    board += f'<g transform="translate({x+98} 286) scale(.5625)">{icon(kind)}</g>'
    board += '<g filter="url(#word-glass)">' + lettering('PinShutter', x + 242, 660, 424, 110, f'url(#{fill})') + '</g>'
    board += f'<text x="{x+242}" y="743" text-anchor="middle" fill="#aaa1b3" font-family="Arial,sans-serif" font-size="12" letter-spacing="3">GPS CAMERA</text>'
    board += f'<text x="{x+242}" y="796" text-anchor="middle" fill="#d6cedd" font-family="Arial,sans-serif" font-size="16">{description}</text>'
    board += f'<path d="M{x+28} 826 H{x+456}" stroke="#352e3b"/>'
    for j, size in enumerate([32, 48, 72]):
        px = x + 75 + j * 142
        board += f'<g transform="translate({px-size/2} {875-size/2}) scale({size/512})">{icon(kind)}</g>'
        board += f'<text x="{px}" y="940" text-anchor="middle" fill="#8e8498" font-family="Arial,sans-serif" font-size="12">{size} px</text>'
    (OUT / f'{kind}-icon.svg').write_text(svg(icon(kind), 512, 512, f'PinShutter — {name} icon concept'))
    word = '<g filter="url(#word-glass)">' + lettering('PinShutter', 600, 150, 1080, 220, f'url(#{fill})') + '</g>'
    (OUT / f'{kind}-wordmark.svg').write_text(svg(word, 1200, 300, f'PinShutter — {name} wordmark concept'))
board += '''<text x="54" y="1040" fill="#e9d45c" font-family="Arial,sans-serif" font-size="14" letter-spacing="2">PREVIEW ONLY · NOTHING APPLIED</text>
<text x="54" y="1073" fill="#948a9f" font-family="Arial,sans-serif" font-size="16">Reference: the Stash launcher artwork and Pacifico glass wordmark in your local project.</text>'''
(OUT / 'concept-board.svg').write_text(svg(board, 1600, 1130, 'PinShutter logo and wordmark concepts referencing Stash'))
for file in [OUT / 'concept-board.svg', *(OUT / f'{k}-icon.svg' for k in names), *(OUT / f'{k}-wordmark.svg' for k in names)]:
    subprocess.run(['/opt/homebrew/bin/rsvg-convert', str(file), '-o', str(file.with_suffix('.png'))], check=True)
assert all((OUT / f'{k}-icon.png').stat().st_size > 1000 for k in names)
print(OUT / 'concept-board.png')
