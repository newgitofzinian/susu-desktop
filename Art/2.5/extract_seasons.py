"""Register full seasonal poses; retain one fixed body and six existing tail layers."""
from pathlib import Path
import json
from PIL import Image
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
ART=Path(__file__).resolve().parent
SEASONS=['spring','summer','autumn','winter']

def clean(cell):
    a=np.array(cell.convert('RGBA'));a[a[:,:,3]<40]=0
    mask=a[:,:,3]>0;seen=np.zeros(mask.shape,dtype=bool);largest=[]
    for y,x in zip(*np.where(mask)):
        if seen[y,x]:continue
        stack=[(int(y),int(x))];seen[y,x]=True;part=[]
        while stack:
            yy,xx=stack.pop();part.append((yy,xx))
            for cy,cx in [(yy-1,xx),(yy+1,xx),(yy,xx-1),(yy,xx+1)]:
                if 0<=cy<mask.shape[0] and 0<=cx<mask.shape[1] and mask[cy,cx] and not seen[cy,cx]:
                    seen[cy,cx]=True;stack.append((cy,cx))
        if len(part)>len(largest):largest=part
    keep=np.zeros(mask.shape,dtype=bool)
    for y,x in largest:keep[y,x]=True
    a[~keep]=0;out=Image.fromarray(a);return out.crop(out.getbbox())

def safety_core(images):
    mask=np.ones((208,192),dtype=bool)
    for image,mirror in images:
        a=np.array(image)[:,:,3]>240;mask &= a
        if mirror:mask &= np.fliplr(a)
    best=(0,0,0);previous=np.zeros(193,dtype=int)
    for y in range(208):
        current=np.zeros(193,dtype=int)
        for x in range(192):
            if mask[y,x]:
                current[x+1]=1+min(current[x],previous[x],previous[x+1])
                if current[x+1]>best[0]:best=(int(current[x+1]),x,y)
        previous=current
    size,x,y=best
    assert size>=8,(size,x,y)
    return dict(x=(x-size+1)/192,y=(208-y-1)/208,width=size/192,height=size/208)

report={};metadata={};sheet=Image.new('RGBA',(192*4,208*2),(240,244,247,255))
for column,season in enumerate(SEASONS):
    source=Image.open(ART/f'{season}-source.png');poses=[]
    for row in range(3):
        for col in range(3):
            poses.append(clean(source.crop((round(col*source.width/3),round(row*source.height/3),round((col+1)*source.width/3),round((row+1)*source.height/3)))))
    folder=ROOT/'Assets/seasons'/season
    for name in ['idle','walking']: (folder/name).mkdir(parents=True,exist_ok=True)
    body=poses[0];scale=min(128/body.width,192/body.height)
    body=body.resize((round(body.width*scale),round(body.height*scale)),Image.Resampling.LANCZOS)
    fixed=Image.new('RGBA',(192,208));fixed.alpha_composite(body,(round(82-body.width/2),200-body.height))
    fixed.save(folder/'body.png');fixed_a=np.array(fixed);body_mask=fixed_a[:,:,3]>0
    idle=[]
    for i in range(6):
        a=np.array(Image.open(ROOT/f'Assets/layers/idle-tail/{i:02}.png').convert('RGBA'))
        a[body_mask]=fixed_a[body_mask]
        image=Image.fromarray(a);image.save(folder/'idle'/f'{i:02}.png');idle.append(image)
    walk=[];scale=min(178/max(p.width for p in poses[1:]),190/max(p.height for p in poses[1:]))
    for i,pose in enumerate(poses[1:]):
        pose=pose.resize((round(pose.width*scale),round(pose.height*scale)),Image.Resampling.LANCZOS)
        frame=Image.new('RGBA',(192,208));frame.alpha_composite(pose,((192-pose.width)//2,200-pose.height))
        frame.save(folder/'walking'/f'{i:02}.png');walk.append(frame)
    changed=[int((np.any(np.array(f)!=np.array(idle[0]),axis=2)&body_mask).sum()) for f in idle]
    assert max(changed)==0
    core=safety_core([(f,False) for f in idle]+[(f,True) for f in walk])
    metadata[season]=core
    report[season]=dict(body_pixels_locked=int(body_mask.sum()),changed_body_pixels=changed,walking_frames=8,safety_core=core)
    sheet.alpha_composite(idle[0],(column*192,0));sheet.alpha_composite(walk[2],(column*192,208))
    for name,frames,duration in [('idle',idle,380),('walk',walk,180)]:
        frames[0].save(ROOT/'Previews/2.5'/f'{season}-{name}.gif',save_all=True,append_images=frames[1:],duration=duration,loop=0,disposal=2)
sheet.convert('RGB').save(ROOT/'Previews/2.5/seasons.png')
(ROOT/'Assets/seasons/visibility.json').write_text(json.dumps(metadata,indent=2))
(ART/'validation.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))
