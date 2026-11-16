"""Compose a native SVG review board without changing app assets."""
from pathlib import Path
import base64,subprocess,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parent
NS='http://www.w3.org/2000/svg'
ET.register_namespace('',NS)
def node(tag,**attrs):return ET.Element('{'+NS+'}'+tag,{k.replace('_','-'):str(v) for k,v in attrs.items()})
word=ET.parse(ROOT.parent/'pinshutter-spectrum-v2/wordmark.svg').getroot()
for gradient in word.iter():
 if gradient.attrib.get('id')=='cool-word':
  for stop,col in zip(gradient,['#78ffe4','#c7daff','#ffb59e','#b4c7ff']):stop.set('stop-color',col)
ET.ElementTree(word).write(ROOT/'wordmark.svg',encoding='unicode')
subprocess.run(['/opt/homebrew/bin/rsvg-convert',str(ROOT/'wordmark.svg'),'-o',str(ROOT/'wordmark.png')],check=True)
board=node('svg',width=1200,height=880,viewBox='0 0 1200 880')
board.append(node('rect',width=1200,height=880,fill='#19151B'))
def text(x,y,label,size=18,fill='#B3ACB8'):
 t=node('text',x=x,y=y,font_family='Arial,sans-serif',font_size=size,fill=fill);t.text=label;board.append(t)
def bitmap(file,x,y,w,h):
 data=base64.b64encode(Path(file).read_bytes()).decode()
 board.append(node('image',href='data:image/png;base64,'+data,x=x,y=y,width=w,height=h))
text(56,57,'PINSHUTTER / ORIGINAL STASH COLOUR + GLASS',15)
text(56,106,'Vivid colour. The original water-drop treatment.',34,'#F2F1EC')
text(86,169,'STASH REFERENCE',15)
text(674,169,'PINSHUTTER / PS MONOGRAM',15)
bitmap('/Volumes/Bitcode/GitHub/Stash/app/src/main/res/mipmap-xxxhdpi/ic_launcher_art.png',70,198,432,432)
bitmap(ROOT/'pinshutter-ps.png',670,198,432,432)
bitmap(ROOT/'wordmark.png',642,652,488,122)
text(70,691,'Original colour field, blur and texture',18)
text(70,723,'Reference from your local Stash project',16)
text(56,830,'APPROVED PS IDENTITY · Original Stash colour and glass · Applied to app assets',16,'#A9B8FF')
ET.ElementTree(board).write(ROOT/'review-board.svg',encoding='unicode')
subprocess.run(['/opt/homebrew/bin/rsvg-convert',str(ROOT/'review-board.svg'),'-o',str(ROOT/'review-board.png')],check=True)
print(ROOT/'review-board.png')
