"""Assemble generated tail poses behind one fixed body; verify exact body pixels."""
from pathlib import Path
import importlib.util
import json
import subprocess
import tempfile
import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
ART = Path(__file__).resolve().parent
SCRIPTS = Path.home() / '.codex/plugins/cache/openai-curated-remote/work-pets/0.1.6/skills/create-pet/scripts'
spec = importlib.util.spec_from_file_location('pet_extract', SCRIPTS / 'extract_strip_frames.py')
extract = importlib.util.module_from_spec(spec)
spec.loader.exec_module(extract)

body = Image.open(ART / 'body-source.png').convert('RGBA')
components = extract.connected_components(body)
body = extract.component_group_image(body, [max(components, key=lambda c: c['area'])], padding=1)
body = body.crop(body.getbbox())
ratio = min(128/body.width, 192/body.height)
body = body.resize((round(body.width*ratio), round(body.height*ratio)), Image.Resampling.LANCZOS)
fixed = Image.new('RGBA', (192,208))
fixed.alpha_composite(body, (round(82-body.width/2), 200-body.height))
fixed_array = np.array(fixed)
body_mask = fixed_array[:,:,3] > 0
layers = ROOT / 'Assets/layers'
(layers / 'idle-tail').mkdir(parents=True, exist_ok=True)
fixed.save(layers / 'idle-body.png')
images = []
with tempfile.TemporaryDirectory(prefix='susu12-tail-') as work:
    for index, path in enumerate(sorted((ART / 'tail-extracted/idle').glob('*.png'))):
        tail = Image.open(path).convert('RGBA')
        pixels = np.array(tail)
        edge = np.array(tail.getchannel('A').point(lambda a:255 if a==0 else 0).filter(ImageFilter.MaxFilter(7))) > 0
        r,g,b,a = [pixels[:,:,i].astype(float) for i in range(4)]
        pixels[edge & (a>0) & (r>1.5*g) & (b>1.2*g) & (r>.8*b)] = 0
        clean_input = Path(work) / f'{index}-input.png'
        clean_output = Path(work) / f'{index}-clean.png'
        Image.fromarray(pixels).save(clean_input)
        subprocess.run([__import__('sys').executable, str(SCRIPTS/'despill_chroma_edges.py'), str(clean_input),
                        '--output', str(clean_output), '--chroma-key', '#FF00FF', '--strength', '1.0'],
                       check=True, capture_output=True)
        tail = Image.open(clean_output).convert('RGBA').resize((85,92), Image.Resampling.LANCZOS)
        tail_layer = Image.new('RGBA', (192,208))
        tail_layer.alpha_composite(tail, (99,106))
        tail_layer.save(layers / 'idle-tail' / f'{index:02}.png')
        # Copy, rather than alpha-blend, every body pixel. Even semitransparent
        # outline pixels remain identical across all frames.
        composite = np.array(tail_layer)
        composite[body_mask] = fixed_array[body_mask]
        image = Image.fromarray(composite)
        image.save(ROOT/'Assets/frames/idle'/f'{index:02}.png')
        images.append(image)

reference = np.array(images[0])
body_differences = []
tail_differences = []
for image in images:
    diff = np.any(np.array(image) != reference, axis=2)
    body_differences.append(int((diff & body_mask).sum()))
    tail_differences.append(int((diff & ~body_mask).sum()))
assert max(body_differences) == 0
assert max(tail_differences) > 100

# Derive a common opaque body patch for the existing off-screen safety behavior.
mask = np.ones((208,192), dtype=bool)
for state in ['idle','walking-right','running-right']:
    for path in sorted((ROOT/'Assets/frames'/state).glob('*.png')):
        alpha = np.array(Image.open(path).convert('RGBA'))[:,:,3] > 240
        mask &= alpha
        if state != 'idle': mask &= np.fliplr(alpha)
best = (0,0,0)
previous = np.zeros(193,dtype=int)
for y in range(208):
    current = np.zeros(193,dtype=int)
    for x in range(192):
        if mask[y,x]:
            current[x+1] = 1+min(current[x],previous[x],previous[x+1])
            if current[x+1] > best[0]: best = (int(current[x+1]),x,y)
    previous = current
size,x,y = best
assert size >= 12, best
core = {'x':(x-size+1)/192,'y':(208-y-1)/208,'width':size/192,'height':size/208}
(ROOT/'Assets/frames/visibility.json').write_text(json.dumps(core,indent=2))
report = {'version':'1.2','body_pixels_locked':int(body_mask.sum()),
          'changed_body_pixels_per_frame':body_differences,
          'changed_tail_pixels_per_frame':tail_differences,
          'body_stability':'pass: identical RGBA pixels in every idle frame',
          'visibility_core':core}
(ART/'body-stability.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
previews = ROOT/'Previews/1.2'
previews.mkdir(parents=True,exist_ok=True)
preview_images = []
for image in images:
    canvas = Image.new('RGBA', image.size, (239,243,248,255))
    canvas.alpha_composite(image)
    preview_images.append(canvas.convert('RGB'))
preview_images[0].save(previews/'溯溯-身体固定只摇尾巴.gif',save_all=True,
                       append_images=preview_images[1:],duration=380,loop=0,optimize=False)
sheet = Image.new('RGBA',(192*6,208),(239,243,248,255))
for i,image in enumerate(images): sheet.alpha_composite(image,(i*192,0))
sheet.convert('RGB').save(previews/'contact-sheet.png')
print(json.dumps(report,ensure_ascii=False))
