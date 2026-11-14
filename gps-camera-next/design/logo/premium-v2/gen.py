import math
PIN='M512 846 C 436 742 276 612 276 436 A 236 236 0 1 1 748 436 C 748 612 588 742 512 846 Z'
def ell(cx,cy,rx,ry,rot):
    # ellipse as path (for evenodd cut-outs)
    a=math.radians(rot); pts=[]
    for i in range(0,73):
        t=2*math.pi*i/72; x=rx*math.cos(t); y=ry*math.sin(t)
        pts.append((cx+x*math.cos(a)-y*math.sin(a), cy+x*math.sin(a)+y*math.cos(a)))
    return 'M'+' L'.join(f'{x:.1f} {y:.1f}' for x,y in pts)+' Z'
# Calligraphic counter: offset, tilted ellipse => thick/thin stroke like a pen-drawn "O".
COUNTER=ell(530,416,120,160,-34)
def svg(body,defs,bg):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024"><defs>{defs}</defs>{bg}{body}</svg>'
def group(inner,s=1.0,cy=512): return f'<g transform="translate(512 {cy}) scale({s}) translate(-512 523)">{inner}</g>'.replace('translate(-512 523)','translate(-512 -523)')
concepts={}
# 1 Calligraphic Pin · Dusk
d1='''<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3B3466"/><stop offset="1" stop-color="#15142B"/></linearGradient>
<linearGradient id="fg" x1="0.2" y1="0" x2="0.8" y2="1"><stop offset="0" stop-color="#FFE3B3"/><stop offset=".55" stop-color="#FDB48A"/><stop offset="1" stop-color="#EE8571"/></linearGradient>'''
b1=group(f'<path d="{PIN} {COUNTER}" fill="url(#fg)" fill-rule="evenodd"/><circle cx="530" cy="416" r="50" fill="#FFF3E2"/>')
concepts['1']=('Calligraphic Pin · Dusk',d1,'<rect width="1024" height="1024" fill="url(#bg)"/>',b1)
# 2 Layered Lens · Ivory
d2='''<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFFBF4"/><stop offset="1" stop-color="#EEDFC8"/></linearGradient>
<linearGradient id="fg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#4A3A63"/><stop offset="1" stop-color="#231A33"/></linearGradient>'''
b2=group(f'<path d="{PIN}" fill="url(#fg)"/><circle cx="512" cy="436" r="150" fill="#F7EEDF"/>'
         f'<circle cx="474" cy="458" r="96" fill="#E7A86B" opacity=".85"/><circle cx="552" cy="458" r="96" fill="#D9738A" opacity=".75"/><circle cx="512" cy="392" r="96" fill="#8E7CC3" opacity=".7"/>'
         f'<circle cx="512" cy="436" r="34" fill="#231A33"/>')
concepts['2']=('Layered Lens · Ivory',d2,'<rect width="1024" height="1024" fill="url(#bg)"/>',b2)
# 3 Aperture Pin · Midnight Teal
blades=''
for k in range(6):
    a=k*60
    blades+=f'<path d="M512 436 L {512+150*math.cos(math.radians(a)):.1f} {436+150*math.sin(math.radians(a)):.1f} A150 150 0 0 1 {512+150*math.cos(math.radians(a+60)):.1f} {436+150*math.sin(math.radians(a+60)):.1f} Z" fill="{'#0E3540' if k%2 else '#2C6E79'}" transform="rotate(14 512 436)"/>'
hexagon='M'+' L'.join(f'{512+52*math.cos(math.radians(30+60*i)):.1f} {436+52*math.sin(math.radians(30+60*i)):.1f}' for i in range(6))+' Z'
d3='''<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1F5C68"/><stop offset="1" stop-color="#0A2329"/></linearGradient>
<linearGradient id="fg" x1="0.2" y1="0" x2="0.8" y2="1"><stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#D9EEF0"/></linearGradient>'''
b3=group(f'<path d="{PIN}" fill="url(#fg)"/>{blades}<path d="{hexagon}" fill="#F3E2B8"/>')
concepts['3']=('Aperture Pin · Midnight Teal',d3,'<rect width="1024" height="1024" fill="url(#bg)"/>',b3)
for k,(name,defs,bg,body) in concepts.items():
    open(f'i{k}.svg','w').write(svg(body,defs,bg))
    # monochrome (themed icon): foreground silhouette only, white on mid grey
    import re
    mono=re.sub(r'fill="(#[0-9A-Fa-f]{6}|\{[^}]*\})"','fill="#5E5E62"',body)
    mono=re.sub(r' opacity="[^"]*"','',mono)
    # Keep the lens centre visible in themed mode.
    for c in ('#FFF3E2','#F3E2B8'):
        mono=mono.replace(body and c, c)
    mono=mono.replace('r="50" fill="#5E5E62"','r="50" fill="#FFFFFF"').replace('Z" fill="#5E5E62"/></g>','Z" fill="#FFFFFF"/></g>').replace('r="34" fill="#5E5E62"','r="34" fill="#FFFFFF"')
    open(f'm{k}.svg','w').write(svg(mono.replace('url(#fg)','#FFFFFF'),'','<rect width="1024" height="1024" fill="#5E5E62"/>'))
    open(f'name{k}.txt','w').write(name)
