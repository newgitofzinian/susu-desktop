"""Split the generated three-cell strip into registered runtime reaction sprites."""
from pathlib import Path
from PIL import Image
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
image=Image.open(Path(__file__).with_name('closeup-source.png')).convert('RGBA')
frames=[]
for i in range(3):
    cell=image.crop((round(i*image.width/3),0,round((i+1)*image.width/3),image.height))
    array=np.array(cell);array[array[:,:,3]<40]=0
    mask=array[:,:,3]>0;seen=np.zeros(mask.shape,dtype=bool);largest=[]
    for y,x in zip(*np.where(mask)):
        if seen[y,x]:continue
        stack=[(int(y),int(x))];seen[y,x]=True;component=[]
        while stack:
            yy,xx=stack.pop();component.append((yy,xx))
            for cy,cx in [(yy-1,xx),(yy+1,xx),(yy,xx-1),(yy,xx+1)]:
                if 0<=cy<mask.shape[0] and 0<=cx<mask.shape[1] and mask[cy,cx] and not seen[cy,cx]:
                    seen[cy,cx]=True;stack.append((cy,cx))
        if len(component)>len(largest):largest=component
    keep=np.zeros(mask.shape,dtype=bool)
    for y,x in largest:keep[y,x]=True
    array[~keep]=0
    clean=Image.fromarray(array);frames.append(clean.crop(clean.getbbox()))
scale=min(178/max(f.width for f in frames),190/max(f.height for f in frames))
for i,frame in enumerate(frames):
    frame=frame.resize((round(frame.width*scale),round(frame.height*scale)),Image.Resampling.LANCZOS)
    canvas=Image.new('RGBA',(192,208))
    canvas.alpha_composite(frame,((192-frame.width)//2,200-frame.height))
    canvas.save(ROOT/'Assets/frames/closeup'/f'{i:02}.png')
print('Extracted three transparent 192x208 reaction poses.')
