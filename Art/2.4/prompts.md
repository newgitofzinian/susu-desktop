# Susu 毯子动作素材

使用内置 imagegen 工具，透明背景。以既有溯溯、卷垫和趴卧图为外观参考，生成整个狐狸与毯子共同受力的连续姿态，而非在走路图片上叠加一个道具。

## 8 帧叼毯慢走

原始输出：carry-source.png

```text
Use case: identity-preserve. Asset type: GAME ANIMATION SPRITE SHEET for an existing macOS desktop fox companion. Reference image 1 is Susu, preserve EXACT navy fluffy fox, huge cream-tipped tail with three linked amber marks, cream face/chest/paws, amber eye, soft polished chibi illustration. Reference image 2 is its muted teal rolled sleeping blanket, cream piping and amber paw embroidery. Create ONE landscape sprite sheet in exactly 4 columns x 2 rows, 8 equal cells, read left-to-right top-to-bottom. Each cell contains the same full-body fox FACING RIGHT carrying a SMALL rolled teal blanket firmly BETWEEN ITS TEETH by a pinched cream fabric edge; jaw, lip and little cloth folds visibly interlock, blanket weight pulls fabric slightly down, fox neck leans forward. The blanket is a small compact load held beside and below the muzzle, NOT a tube pasted across eyes or nose. A cohesive single painted character-and-cloth pose in every cell with shared soft shading and contact shadow. Eight consecutive subtle slow FOUR-PAW WALK phases: alternating fore/hind paw contacts, lifted stepping paws, gentle neck compensation and tiny cloth sway, planted ground contacts. NO running or bouncing. Identical fox body/head proportions and roll size across all frames; same camera, feet baseline and overall scale. Entire tail, ears, paws and blanket in every cell, wide transparent gutters; genuine transparent alpha, NO floor, no shadows disconnected from body, no house, no text, numbers, cell borders or UI. No additional loose blanket.
```

## 6 帧放下、铺开与趴卧

原始输出：blanket-source.png

```text
Use case: identity-preserve. Asset type: transparent GAME ACTION SPRITE SHEET, six sequential full-body poses in EXACT 3 columns x 2 rows, landscape, equal cells read left to right then next row. Reference1 is Susu's carrying animation, reference2 the open teal sleeping mat, reference3 the original resting fox. Preserve the exact navy fluffy chibi fox with cream face/chest/paws, amber eyes, big cream-tipped tail bearing three linked amber spots, matching soft painted lighting, body proportions and scale. ACTION: slowly PUTTING DOWN AND UNROLLING its sleeping blanket facing RIGHT. Cell1: fox standing, holding small rolled blanket between its teeth by pinched fabric edge like reference1, weight dangling under chin. Cell2: neck and head bend down lowering that SAME roll to ground, paws planted, muzzle still gripping. Cell3: fox crouches over roll, chin low, one forepaw pressed onto roll. Cell4: fox leans forward, presses and nudges the roll outward with both front paws, mat halfway unrolled toward right. Cell5: mat fully unfurled beneath forelegs and belly, fox lowers chest while hindlegs fold into prone posture. Cell6: fox lies peacefully flat on its belly on that same open mat, chin on forepaws, eyes closed, tail curled beside body like reference3. Keep fox and blanket as a single coherent painted action with contact shadows, pinched cloth and paw pressure. Six different successive stages, not repeated standing poses. Same ground baseline and same fox size throughout the sheet. All paws, entire tail and entire mat visible inside each cell, wide transparent gutters. Genuine transparent alpha, no floor, no house, no detached props, no labels/text/numbers/grid lines/UI. Mat color muted teal with cream stitched piping and tiny amber paw. Do not add scarf, clothes or extra creatures.
```

提取脚本 `extract_blanket.py` 保留主体 alpha，以固定比例注册到 256×240 画布与同一脚底基线。运行素材保存在 `Assets/home/carry/` 和 `Assets/home/blanket-action/`。铺毯使用六个关键姿态，收毯逆向播放同一组接触姿态；向左搬运镜像完整画面。运行时不调用生成服务。
