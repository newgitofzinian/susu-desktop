"""Extract and register generated house, mat and resting-fox runtime sprites."""
from pathlib import Path
from PIL import Image
import numpy as np
ROOT=Path(__file__).resolve().parents[2];ART=Path(__file__).resolve().parent

def clean(image):
    a=np.array(image.convert('RGBA'));a[a[:,:,3]<40]=0
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

def fit(image,width,height):
    scale=min(width/image.width,height/image.height)
    return image.resize((round(image.width*scale),round(image.height*scale)),Image.Resampling.LANCZOS)
house=fit(clean(Image.open(ART/'house-source.png')),720,720);house.save(ROOT/'Assets/home/house.png')
mat=Image.open(ART/'mat-source.png')
for i,name in enumerate(['mat','rolled']):
    part=mat.crop((round(i*mat.width/2),0,round((i+1)*mat.width/2),mat.height))
    fit(clean(part),480,300).save(ROOT/f'Assets/home/{name}.png')
rest=fit(clean(Image.open(ART/'rest-source.png')),178,190)
canvas=Image.new('RGBA',(192,208));canvas.alpha_composite(rest,((192-rest.width)//2,200-rest.height));canvas.save(ROOT/'Assets/home/rest.png')
print('Extracted transparent house, flat and rolled mat, and prone resting fox.')
