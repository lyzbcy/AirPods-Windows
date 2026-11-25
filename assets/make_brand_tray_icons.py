"""Derive small tray state indicators from the approved AirPods brand artwork."""
from pathlib import Path
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parent
SOURCE=Image.open(ROOT/"airpods-brand.png").convert("RGBA")
SIZES=[(16,16),(24,24),(32,32),(48,48),(64,64),(128,128),(256,256)]

def canvas():
    image=Image.new("RGBA",(256,256))
    image.alpha_composite(SOURCE.resize((238,238),Image.Resampling.LANCZOS),(9,9))
    return image

def write(name,image):
    image.save(ROOT/name,sizes=SIZES)

write("brand-tray-off.ico",canvas())
image=canvas();draw=ImageDraw.Draw(image)
draw.ellipse((179,179,255,255),fill="#FFFDF0")
draw.ellipse((190,190,244,244),fill="#4F9D72")
write("brand-tray-on.ico",image)
for frame in range(6):
    image=canvas();draw=ImageDraw.Draw(image)
    draw.ellipse((1,1,254,254),outline="#FFF9DF",width=12)
    draw.arc((4,4,251,251),frame*60,frame*60+145,fill="#CC8600",width=15)
    write(f"brand-tray-loading-{frame}.ico",image)
