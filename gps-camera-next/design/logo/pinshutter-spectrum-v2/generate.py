"""Refine the approved vector concept; render assets with no runtime shader/font."""
from copy import deepcopy
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
SOURCE = OUT.parent / 'pinshutter-stash-reference-v1'
NS = 'http://www.w3.org/2000/svg'
ET.register_namespace('', NS)


def element(tag, **attrs):
    return ET.Element(f'{{{NS}}}{tag}', {k.replace('_', '-'): str(v) for k, v in attrs.items()})


def group(*children, **attrs):
    result = element('g', **attrs)
    result.extend(deepcopy(children))
    return result


original = ET.parse(SOURCE / 'a-icon.svg').getroot()
defs = deepcopy(original[1])
# A broad, continuous bed of colour replaces the four isolated bright spots.
base = element('linearGradient', id='spectrum-base', x1='0', y1='0', x2='1', y2='1')
for offset, colour in [('0', '#2d6e77'), ('.38', '#44536d'), ('.69', '#625279'), ('1', '#41498c')]:
    base.append(element('stop', offset=offset, stop_color=colour))
defs.append(base)
for item in defs.iter():
    if item.tag.endswith('feGaussianBlur') and item.attrib.get('stdDeviation') == '34':
        item.set('stdDeviation', '82')
    if item.attrib.get('id') == 'lens':
        item.clear()
        item.attrib.update(id='lens', cx='.29', cy='.18', r='.94')
        for offset, colour, opacity in [('0', '#c0f5e3', '.42'), ('.5', '#737cb7', '.21'), ('1', '#6a70e1', '.40')]:
            item.append(element('stop', offset=offset, stop_color=colour, stop_opacity=opacity))
    if item.attrib.get('id') == 'cool-word':
        # Pale tints stay readable when the wordmark is only 27 dp high.
        item.clear()
        item.attrib.update(id='cool-word', x1='0', y1='0', x2='1', y2='.35')
        for offset, colour in [('0', '#bff9ed'), ('.33', '#cdcfff'), ('.67', '#ffcec3'), ('1', '#d1e9ff')]:
            item.append(element('stop', offset=offset, stop_color=colour))
background = group(element('rect', width=512, height=512, fill='url(#spectrum-base)'))
blobs = group(filter='url(#blur)')
for colour, x, y, radius, opacity in [('#53dec5', 80, 96, 205, '.68'), ('#f19d9f', 418, 152, 212, '.64'), ('#8585e7', 320, 446, 242, '.73')]:
    blobs.append(element('circle', cx=x, cy=y, r=radius, fill=colour, opacity=opacity))
background.append(blobs)
lens = group(*list(original[2])[2:8])
# Quieter highlights let the blended colour lead.
lens[3].set('opacity', '.58')
lens[4].set('opacity', '.52')
wordmark = deepcopy(ET.parse(SOURCE / 'a-wordmark.svg').getroot()[2])
# Source wordmark uses x=0..1200, y=0..300.


def svg(body, width=512, height=512, viewbox=None):
    root = element('svg', width=width, height=height, viewBox=viewbox or f'0 0 {width} {height}')
    root.append(deepcopy(defs))
    root.append(deepcopy(body))
    return ET.tostring(root, encoding='unicode')


def render(path, body, width, height, viewbox=None):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    source = path.with_suffix('.svg')
    source.write_text(svg(body, width, height, viewbox))
    subprocess.run(['/opt/homebrew/bin/rsvg-convert', str(source), '-o', str(path)], check=True)
    if path.parent != OUT:
        source.unlink()


rounded = group(background, lens, clip_path='url(#tile)')
render(OUT / 'icon.png', rounded, 512, 512)
render(OUT / 'wordmark.png', wordmark, 1200, 300)
# Full-bleed masters let the OS apply its own icon mask.
render(ROOT / 'assets/icons/app_icon.png', group(background, lens), 1024, 1024, '0 0 512 512')
render(ROOT / 'assets/icons/app_icon_bg.png', background, 1024, 1024, '0 0 512 512')
# flutter_launcher_icons adds its 16% inset: this keeps the entire lens in the
# adaptive icon's guaranteed central safe circle, with a little breathing room.
foreground = group(lens, transform='translate(256 256) scale(1.24) translate(-256 -256)')
render(ROOT / 'assets/icons/app_icon_fg.png', foreground, 1024, 1024, '0 0 512 512')
mono = group(element('circle', cx=256, cy=256, r=164, fill='none', stroke='#ffffff', stroke_width=12), lens[2],
             transform='translate(256 256) scale(1.24) translate(-256 -256)')
mono[1].attrib.pop('filter', None)
render(ROOT / 'assets/icons/app_icon_mono.png', mono, 1024, 1024, '0 0 512 512')
for scale in [1, 2, 3]:
    folder = ROOT / 'assets/branding' / (f'{scale}.0x' if scale > 1 else '')
    render(folder / 'pinshutter-icon.png', rounded, 96 * scale, 96 * scale, '0 0 512 512')
    render(folder / 'pinshutter-wordmark.png', wordmark, 240 * scale, 60 * scale, '0 0 1200 300')

# Native launch artwork has the same lockup as the Flutter camera loader.
lockup = group(group(rounded, transform='translate(72 0) scale(.1875)'),
               group(wordmark, transform='translate(0 116) scale(.2)'))
for scale, density in [(1, 'mdpi'), (1.5, 'hdpi'), (2, 'xhdpi'), (3, 'xxhdpi'), (4, 'xxxhdpi')]:
    render(ROOT / f'android/app/src/main/res/drawable-{density}/pinshutter_launch.png', lockup,
           int(240 * scale), int(176 * scale), '0 0 240 176')
for scale in [1, 2, 3]:
    suffix = '' if scale == 1 else f'@{scale}x'
    render(ROOT / f'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage{suffix}.png',
           lockup, 240 * scale, 176 * scale, '0 0 240 176')
# A compact review board: actual exported assets, no remote images/fonts.
board = group(element('rect', width=1200, height=760, fill='#121116'))
board.append(group(rounded, transform='translate(86 100) scale(.64)'))
board.append(group(wordmark, transform='translate(36 460) scale(.36)'))
for x, title in [(530, 'LOADING'), (870, 'LIBRARY')]:
    board.append(element('rect', x=x, y=65, width=280, height=610, rx=28, fill='#000000', stroke='#35323c'))
    text = element('text', x=x+20, y=40, fill='#aaa4b3', font_family='Arial', font_size=12, letter_spacing=2)
    text.text = title
    board.append(text)
board.append(group(lockup, transform='translate(550 250)'))
board.append(element('circle', cx=670, cy=458, r=7, fill='none', stroke='#bcc2e6', stroke_width=2))
board.append(group(wordmark, transform='translate(932 88) scale(.13)'))
for x, label in [(940, 'Library'), (1050, 'Map')]:
    text = element('text', x=x, y=145, fill='#e9e6ed', font_family='Arial', font_size=12)
    text.text = label
    board.append(text)
for row in range(4):
    for col in range(3):
        board.append(element('rect', x=880+col*87, y=164+row*100, width=84, height=97, rx=2, fill=['#2c3339', '#3a3440', '#334347'][(row+col)%3]))
text = element('text', x=86, y=672, fill='#aba4b4', font_family='Arial', font_size=16)
text.text = '01 / Spectrum P — brighter colour, smooth blending'
board.append(text)
render(OUT / 'refined-board.png', board, 1200, 760)
# Raster structure/opacity asserts catch bad exports independently of the app.
from PIL import Image
for file in (ROOT / 'assets/branding').rglob('*.png'):
    image = Image.open(file)
    assert image.width == image.height or image.width == image.height * 4
    assert image.getbbox(), file
assert Image.open(ROOT / 'assets/icons/app_icon.png').convert('RGBA').getextrema()[3] == (255, 255)
print(OUT / 'refined-board.png')
