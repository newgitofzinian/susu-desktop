# 四季外观制作记录

模式：内置 imagegen，透明背景。参考既有固定身体层与向右慢走姿态，分别生成春、夏、秋、冬整套角色图；围巾只属于冬季。

## 春季花叶胸饰

原始输出：spring-source.png。

```text
Use case: identity-preserve. Asset type: production sprite sheet for Susu desktop pet, square canvas, EXACT 3 columns x 3 rows with 9 equal cells, generous transparent gutters. Reference1 is the original FRONT SITTING FOX BODY WITHOUT TAIL, reference2 its RIGHT-FACING WALK pose. Preserve navy fluffy fox, cream muzzle chest paws, amber eyes, triangular ears, same head/body proportions, polished soft chibi illustration, cream tail tip with exactly three linked amber spots on walk poses. Cell 1 (top left): FRONT FACING seated motionless body, tail OMITTED as in reference1 (tail is a separate existing runtime layer). Cells 2 through 9: eight consecutive distinct gentle FOUR-PAW WALK poses FACING RIGHT, FULL tail visible to left, alternating leg phases, not running. All walking cells identical camera and scale, constant feet baseline, no global bounce. Outfit must be painted as part of the WHOLE fox in each cell, wraps around the neck/torso naturally, correct perspective, fur occlusion and contact shadows; never a sticker floating over body. Show all ears, paws and accessories unclipped in each cell. Genuine transparent alpha. No ground, house, UI, labels, numbers, grid lines, text or disconnected props. SPRING DESIGN: one delicate small ivory five-petal blossom with an amber center and two fresh sage leaves pinned into a narrow cream linen chest strap, on the fox's left upper chest. A small hand-crafted botanical brooch, no scarf, no neck wrap, no dangling ribbon. The spring outfit should feel light, gentle and airy, leaving the cream chest fur visible. Keep the flower and leaves small and fitted, with little soft shadows where they touch fur; same brooch and strap design through all walking frames.
```

## 夏季海蓝水手领

原始输出：summer-source.png。

```text
Use case: identity-preserve. Asset type: production sprite sheet for Susu desktop pet, square canvas, EXACT 3 columns x 3 rows with 9 equal cells, generous transparent gutters. Reference1 is the original FRONT SITTING FOX BODY WITHOUT TAIL, reference2 its RIGHT-FACING WALK pose. Preserve navy fluffy fox, cream muzzle chest paws, amber eyes, triangular ears, same head/body proportions, polished soft chibi illustration, cream tail tip with exactly three linked amber spots on walk poses. Cell 1 (top left): FRONT FACING seated motionless body, tail OMITTED as in reference1 (tail is a separate existing runtime layer). Cells 2 through 9: eight consecutive distinct gentle FOUR-PAW WALK poses FACING RIGHT, FULL tail visible to left, alternating leg phases, not running. All walking cells identical camera and scale, constant feet baseline, no global bounce. Outfit must be painted as part of the WHOLE fox in each cell, wraps around the neck/torso naturally, correct perspective, fur occlusion and contact shadows; never a sticker floating over body. Show all ears, paws and accessories unclipped in each cell. Genuine transparent alpha. No ground, house, UI, labels, numbers, grid lines, text or disconnected props. SUMMER DESIGN: a neat lightweight sea-blue SAILOR COLLAR lying flat over the shoulders and upper chest, double ivory piping following its fabric edge, a tiny amber wooden toggle at the V. Breathable crisp cotton, no hanging ends, NO SCARF, no neck wrap, no thick winter fabric, no bow tie. The collar wraps behind the neck and around the shoulder, cream chest fur remains visible inside the V. Tail remains bare. Same collar shape and stitching across front seated and all side walking poses. Summer should feel fresh and cool. Keep the fox as in references, fully integrated fabric shading and fur contact.
```

## 秋季枫叶小挎包

原始输出：autumn-source.png。

```text
Use case: identity-preserve. Asset type: production sprite sheet for Susu desktop pet, square canvas, EXACT 3 columns x 3 rows with 9 equal cells, generous transparent gutters. Reference1 is the original FRONT SITTING FOX BODY WITHOUT TAIL, reference2 its RIGHT-FACING WALK pose. Preserve navy fluffy fox, cream muzzle chest paws, amber eyes, triangular ears, same head/body proportions, polished soft chibi illustration, cream tail tip with exactly three linked amber spots on walk poses. Cell 1 (top left): FRONT FACING seated motionless body, tail OMITTED as in reference1 (tail is a separate existing runtime layer). Cells 2 through 9: eight consecutive distinct gentle FOUR-PAW WALK poses FACING RIGHT, FULL tail visible to left, alternating leg phases, not running. All walking cells identical camera and scale, constant feet baseline, no global bounce. Outfit must be painted as part of the WHOLE fox in each cell, wraps around the neck/torso naturally, correct perspective, fur occlusion and contact shadows; never a sticker floating over body. Show all ears, paws and accessories unclipped in each cell. Genuine transparent alpha. No ground, house, UI, labels, numbers, grid lines, text or disconnected props. AUTUMN DESIGN: a tiny warm chestnut-brown crossbody FORAGING SATCHEL, rounded canvas bag with a honey-colored clasp and a small amber maple-leaf motif stitched on its flap. Narrow cream canvas strap lies diagonally against upper chest and goes over opposite shoulder, mini bag sits at the fox's LEFT flank just behind foreleg, leaving paws free. On side-view right-facing walk the bag is on camera-facing flank; on seated front it appears snug beside left foreleg. Bag is small, soft and practical, subtle fabric grain and contact shadow, strap follows shoulder and moves with body, no stiff rectangle glued over chest. NO SCARF or neck wrap. No hat or extra clothes. Same satchel size and design in all frames, slight natural bag weight and sway between paw steps.
```

## 冬季针织围巾

原始输出：winter-source.png。

```text
Use case: identity-preserve. Asset type: production sprite sheet for Susu desktop pet, square canvas, EXACT 3 columns x 3 rows with 9 equal cells, generous transparent gutters. Reference1 is the original FRONT SITTING FOX BODY WITHOUT TAIL, reference2 its RIGHT-FACING WALK pose. Preserve navy fluffy fox, cream muzzle chest paws, amber eyes, triangular ears, same head/body proportions, polished soft chibi illustration, cream tail tip with exactly three linked amber spots on walk poses. Cell 1 (top left): FRONT FACING seated motionless body, tail OMITTED as in reference1 (tail is a separate existing runtime layer). Cells 2 through 9: eight consecutive distinct gentle FOUR-PAW WALK poses FACING RIGHT, FULL tail visible to left, alternating leg phases, not running. All walking cells identical camera and scale, constant feet baseline, no global bounce. Outfit must be painted as part of the WHOLE fox in each cell, wraps around the neck/torso naturally, correct perspective, fur occlusion and contact shadows; never a sticker floating over body. Show all ears, paws and accessories unclipped in each cell. Genuine transparent alpha. No ground, house, UI, labels, numbers, grid lines, text or disconnected props. WINTER DESIGN: a beautifully knitted muted CRANBERRY RED wool SCARF, medium thickness, ivory knit ribbing at its ends, wrapped naturally once around lower neck with a soft tucked overlap and one short end resting along upper chest. The scarf has visible fine yarn stitches, small soft folds and contact shadow under jaw and where fur overlaps it. Shoulder portion wraps around the back of neck, follows the body's SIDE VIEW and stays under the head, not painted over throat as a flat rectangle. Cream chest fur and all paws still visible; keep ends short so they never obstruct stepping forelegs. Cozy tasteful winter accessory, no hat, no coat, no extra tassel props. Same scarf design through front seated and all eight walk phases, with subtle end sway that follows the shoulder.
```

## 注册与验证

`extract_seasons.py` 对每张 3×3 图集提取一个无尾巴的正面身体和八个完整慢走姿态。身体按固定尺度和脚底基线注册到 192×208，六帧待机在后面复用既有独立尾巴层，并逐像素锁定身体。八帧慢走使用统一比例，朝左时镜像整套角色与服饰。最终素材：`Assets/seasons/<spring|summer|autumn|winter>/idle/`、`walking/` 与 `body.png`。

`validation.json` 记录每季身体像素、六帧身体差分和双向散步共同可见区域。四季身体差分均为零。运行时读取完整姿态，不绘制内置围巾贴片。范围为待机、左右慢走（含进出小窝的空嘴慢走）和待机合影；跑步、伸懒腰、玩耍、叼毯、趴卧、近看反应使用各自既有专用素材。
