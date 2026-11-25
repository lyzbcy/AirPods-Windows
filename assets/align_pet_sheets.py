"""Prepare aligned transparent 7x7 animation sheets (128px cells).
Usage: python assets/align_pet_sheets.py --output webui/assets --on <png> --fail <png> --wait <png> --idle <png>
No personal paths or raw user images are stored in output metadata.
"""
from pathlib import Path
import argparse, json
from PIL import Image
import numpy as np
from scipy import ndimage
SIZE, PAD, ANCHOR_X, ANCHOR_Y = 128, 3, 64, 119

def core_mask(alpha):
    labels,n=ndimage.label(alpha>=128,structure=np.ones((3,3),dtype=int))
    if not n: raise ValueError("Empty frame")
    counts=np.bincount(labels.ravel());counts[0]=0
    return labels==counts.argmax()

def pose(core):
    ys,xs=np.where(core); y0,y1=int(ys.min()),int(ys.max()); x0,x1=int(xs.min()),int(xs.max())
    foot=xs[ys>=y1-max(2,round((y1-y0)*.07))]
    return x0,y0,x1,y1,float(foot.mean())

def frames(path):
    sheet=Image.open(path).convert("RGBA");w,h=sheet.size
    for i in range(49):
        x,y=i%7,i//7
        image=np.array(sheet.crop((round(x*w/7),round(y*h/7),round((x+1)*w/7),round((y+1)*h/7))))
        core=core_mask(image[:,:,3]);x0,y0,x1,y1,ax=pose(core)
        # Keep the body + its anti-aliased edge, not neighboring frame fragments.
        keep=ndimage.binary_dilation(core,iterations=3)
        alpha=image[:,:,3];red=(image[:,:,0]>180)&(image[:,:,1]<60)&(image[:,:,2]<70)&(alpha<128)
        alpha[~keep|red]=0
        bounds=(max(0,x0-PAD),max(0,y0-PAD),min(image.shape[1],x1+PAD+1),min(image.shape[0],y1+PAD+1))
        yield Image.fromarray(image).crop(bounds),(x0,y0,x1,y1,ax),bounds

def align(frameset,target_height):
    output=[]; measured=[]
    for frame,(x0,y0,x1,y1,ax),(cx,cy,_,_) in frameset:
        scale=target_height/(y1-y0+1)
        size=(max(1,round(frame.width*scale)),max(1,round(frame.height*scale)))
        left=round(ANCHOR_X-(ax-cx)*scale);top=round(ANCHOR_Y-(y1-cy)*scale)
        if left<0 or top<0 or left+size[0]>SIZE or top+size[1]>SIZE: raise ValueError("Frame exceeds aligned cell")
        canvas=Image.new("RGBA",(SIZE,SIZE));canvas.alpha_composite(frame.resize(size,Image.Resampling.LANCZOS),(left,top))
        x0,y0,x1,y1,ax=pose(core_mask(np.asarray(canvas)[:,:,3]));measured.append((ax,y1,y1-y0+1));output.append(canvas)
    return output,measured

def save_sheet(output,frames):
    sheet=Image.new("RGBA",(SIZE*7,SIZE*7))
    for i,frame in enumerate(frames):sheet.alpha_composite(frame,(i%7*SIZE,i//7*SIZE))
    sheet.save(output,lossless=True)

def main():
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True)
    for name in ('on','fail','wait','idle'):p.add_argument('--'+name,type=Path,required=True)
    a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
    inputs={name:list(frames(getattr(a,name))) for name in ('on','fail','wait','idle')}
    # One common target height, constrained by both horizontal distances from feet.
    safe_height=110
    for rows in inputs.values():
        for _,(x0,y0,x1,y1,ax),_ in rows:
            h=y1-y0+1;safe_height=min(safe_height, int(57*h/max(ax-x0,x1-ax,1)))
    outputs={'on':'headphones-49.webp','fail':'headphones-fail-49.webp','wait':'headphones-wait-49.webp','idle':'headphones-idle-49.webp'}
    result={}
    for name,rows in inputs.items():
        aligned,values=align(rows,safe_height);save_sheet(a.output/outputs[name],aligned)
        unique=len({f.tobytes() for f in aligned});xs,ys,hs=zip(*values)
        if unique!=49 or max(xs)-min(xs)>4.5 or max(ys)-min(ys)>3: raise ValueError(f"Unstable frames {name}")
        result[name]={"frames":49,"unique":unique,"cell":128,"fps":20,"footXRange":[round(min(xs),2),round(max(xs),2)],"baselineYRange":[min(ys),max(ys)],"bodyHeightRange":[min(hs),max(hs)]}
    print(json.dumps(result,indent=2))
if __name__=='__main__':main()
