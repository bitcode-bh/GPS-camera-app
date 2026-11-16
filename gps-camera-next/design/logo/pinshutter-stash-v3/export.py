"""Build native canvas export instructions for the approved PS identity."""
from pathlib import Path
import base64,json
ROOT=Path(__file__).resolve().parent
source=(ROOT/'pinshutter-ps.html').read_text()
word=base64.b64encode((ROOT/'wordmark.svg').read_bytes()).decode()
script=r'''
<script>
window.exportAssets = async () => {
  await window.iconReady;
  const icon = document.getElementById('o');
  const word = new Image(); word.src = WORD_URI;
  await word.decode();
  const files = {};
  function canvas(width, height) {
    const c=document.createElement('canvas');c.width=width;c.height=height;return c;
  }
  function save(name, c) { files[name]=c.toDataURL('image/png'); }
  const full=canvas(1024,1024);full.getContext('2d').drawImage(icon,0,0,1024,1024);
  save('assets/icons/app_icon.png',full);
  save('assets/icons/app_icon_bg.png',full);
  // Same adaptive layering as Stash: the full artwork is the background layer.
  save('assets/icons/app_icon_fg.png',canvas(1024,1024));
  const mono=canvas(1024,1024), m=mono.getContext('2d');
  m.scale(1024/432,1024/432);m.translate(216,216);m.scale(1.24,1.24);m.translate(-216,-216);
  m.strokeStyle='#fff';m.lineWidth=8;m.beginPath();m.arc(216,216,128,0,Math.PI*2);m.stroke();
  m.font='80px P';m.fillStyle='#fff';m.textAlign='center';m.fillText('PS',213,240);
  save('assets/icons/app_icon_mono.png',mono);
  function iconAt(c,x,y,size) {
    c.save();c.beginPath();c.roundRect(x,y,size,size,size*.22);c.clip();c.drawImage(icon,x,y,size,size);c.restore();
  }
  function lockup(scale) {
    const c=canvas(240*scale,176*scale),g=c.getContext('2d');g.scale(scale,scale);
    iconAt(g,72,0,96);g.drawImage(word,0,116,240,60);return c;
  }
  for (const scale of [1,2,3]) {
    const folder='assets/branding/'+(scale>1?scale+'.0x/':'');
    const mark=canvas(96*scale,96*scale);iconAt(mark.getContext('2d'),0,0,96*scale);save(folder+'pinshutter-icon.png',mark);
    const type=canvas(240*scale,60*scale);type.getContext('2d').drawImage(word,0,0,type.width,type.height);save(folder+'pinshutter-wordmark.png',type);
    save('ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage'+(scale>1?'@'+scale+'x':'')+'.png',lockup(scale));
  }
  for (const [scale,density] of [[1,'mdpi'],[1.5,'hdpi'],[2,'xhdpi'],[3,'xxhdpi'],[4,'xxxhdpi']]) {
    save('android/app/src/main/res/drawable-'+density+'/pinshutter_launch.png',lockup(scale));
  }
  return files;
};
</script>
'''.replace('WORD_URI',json.dumps('data:image/svg+xml;base64,'+word))
(ROOT/'assets-export.html').write_text(source+script)
print(ROOT/'assets-export.html')
