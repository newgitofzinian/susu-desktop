"""Register six equal-slot generated keyframes with one shared scale and ground.
Requires Pillow and NumPy. Does not modify the original source artwork.
"""
from pathlib import Path
import json
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]
ART=Path(__file__).resolve().parent
PREVIEW=ROOT/'Previews/1.5'
PREVIEW.mkdir(parents=True,exist_ok=True)
def largest_component(pixels):
    mask=pixels[:,:,3]>0
    seen=np.zeros(mask.shape,dtype=bool)
    largest=[]
    h,w=mask.shape
    for y,x in zip(*np.where(mask)):
        if seen[y,x]: continue
        stack=[(int(y),int(x))];seen[y,x]=True;component=[]
        while stack:
            yy,xx=stack.pop(); component.append((yy,xx))
            for y2,x2 in [(yy-1,xx),(yy+1,xx),(yy,xx-1),(yy,xx+1)]:
                if 0<=y2<h and 0<=x2<w and mask[y2,x2] and not seen[y2,x2]:
                    seen[y2,x2]=True;stack.append((y2,x2))
        if len(component)>len(largest): largest=component
    keep=np.zeros(mask.shape,dtype=bool)
    for y,x in largest: keep[y,x]=True
    pixels[~keep]=0
    return pixels

report={}
for state in ['stretch','play']:
    image=Image.open(ART/f'{state}-source.png').convert('RGBA')
    crops=[]
    boxes=[]
    for i in range(6):
        crop=image.crop((round(i*image.width/6),0,round((i+1)*image.width/6),image.height))
        pixels=np.array(crop)
        # Discard near-invisible alpha noise from the generated transparent sheet.
        pixels[pixels[:,:,3]<40]=0
        crop=Image.fromarray(largest_component(pixels))
        bbox=crop.getbbox()
        assert bbox, (state,i)
        crops.append(crop.crop(bbox)); boxes.append(bbox)
    ground=max(box[3] for box in boxes)
    top=min(box[1] for box in boxes)
    factor=min(178/max(c.width for c in crops),190/(ground-top))
    frames=[]
    folder=ROOT/'Assets/frames'/state
    folder.mkdir(parents=True,exist_ok=True)
    for i,crop in enumerate(crops):
        crop=crop.resize((round(crop.width*factor),round(crop.height*factor)),Image.Resampling.LANCZOS)
        frame=Image.new('RGBA',(192,208))
        frame.alpha_composite(crop,((192-crop.width)//2,200-round((ground-boxes[i][1])*factor)))
        frame.save(folder/f'{i:02}.png'); frames.append(frame)
    previews=[]
    sheet=Image.new('RGBA',(192*6,208),(239,243,248,255))
    for i,frame in enumerate(frames):
        sheet.alpha_composite(frame,(192*i,0))
        canvas=Image.new('RGBA',frame.size,(239,243,248,255));canvas.alpha_composite(frame)
        previews.append(canvas.convert('RGB'))
    sheet.convert('RGB').save(PREVIEW/f'{state}-sheet.png')
    previews[0].save(PREVIEW/f'{state}.gif',save_all=True,append_images=previews[1:],duration=480 if state=='stretch' else 240,loop=0,optimize=False)
    report[state]={'frames':6,'canvas':[192,208],'shared_scale':factor,'ground_y':200,'distinct_frames':len({frame.tobytes() for frame in frames})}
    assert report[state]['distinct_frames']==6
manifest=json.loads((ROOT/'Assets/frames/frames-manifest.json').read_text())
manifest['version']='1.5'
manifest['states'].update({'stretch':6,'play':6})
manifest['actions']='Generated six-keyframe stretch and playful pounce; common per-sequence scale and floor registration. Stationary actions are fully onscreen; original idle pixels unchanged.'
(ROOT/'Assets/frames/frames-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
(ART/'asset-check.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
