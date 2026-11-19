"""Register generated whole-fox blanket poses without compositing separate props."""
from pathlib import Path
from PIL import Image
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
ART=Path(__file__).resolve().parent

def clean(cell):
    pixels=np.array(cell.convert('RGBA'))
    pixels[pixels[:,:,3]<40]=0
    mask=pixels[:,:,3]>0
    seen=np.zeros(mask.shape,dtype=bool)
    largest=[]
    for y,x in zip(*np.where(mask)):
        if seen[y,x]: continue
        component=[];stack=[(int(y),int(x))];seen[y,x]=True
        while stack:
            yy,xx=stack.pop();component.append((yy,xx))
            for cy,cx in [(yy-1,xx),(yy+1,xx),(yy,xx-1),(yy,xx+1)]:
                if 0<=cy<mask.shape[0] and 0<=cx<mask.shape[1] and mask[cy,cx] and not seen[cy,cx]:
                    seen[cy,cx]=True;stack.append((cy,cx))
        if len(component)>len(largest): largest=component
    keep=np.zeros(mask.shape,dtype=bool)
    for y,x in largest: keep[y,x]=True
    pixels[~keep]=0
    result=Image.fromarray(pixels)
    return result.crop(result.getbbox())

def extract(name,columns,rows,folder):
    sheet=Image.open(ART/f'{name}-source.png')
    frames=[]
    for row in range(rows):
        for col in range(columns):
            cell=sheet.crop((round(col*sheet.width/columns),round(row*sheet.height/rows),round((col+1)*sheet.width/columns),round((row+1)*sheet.height/rows)))
            frames.append(clean(cell))
    # Fixed group scale and a shared foot baseline; never stretch each frame to fit.
    standing_height=max(f.height for f in frames) if name=='carry' else frames[0].height
    scale=min(190/standing_height,236/max(f.width for f in frames))
    output=ROOT/'Assets/home'/folder;output.mkdir(parents=True,exist_ok=True)
    registered=[]
    for i,frame in enumerate(frames):
        frame=frame.resize((round(frame.width*scale),round(frame.height*scale)),Image.Resampling.LANCZOS)
        canvas=Image.new('RGBA',(256,240))
        canvas.alpha_composite(frame,((256-frame.width)//2,226-frame.height))
        canvas.save(output/f'{i:02}.png');registered.append(canvas)
    return registered

carry=extract('carry',4,2,'carry')
action=extract('blanket',3,2,'blanket-action')
preview=ROOT/'Previews/2.4';preview.mkdir(parents=True,exist_ok=True)
carry[0].save(preview/'carry.gif',save_all=True,append_images=carry[1:],duration=150,loop=0,disposal=2)
action[0].save(preview/'blanket-action.gif',save_all=True,append_images=action[1:]+action[-2:0:-1],duration=240,loop=0,disposal=2)
print('Registered 8 carrying and 6 blanket-action poses at 256×240.')
