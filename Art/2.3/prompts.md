# Susu 2.3 小房子素材制作记录

工具：内置 image_gen，透明背景。小房子、垫子为新生成；休息姿态以既有溯溯为参考保持角色外观。运行时使用本地 PNG，不调用生成服务。

## 小房子

源文件：house-source.png

```text
Use case: stylized-concept. Asset: isolated cozy miniature fox HOUSE for a macOS desktop pet. Match the reference fox's polished soft chibi illustration, navy blue/cream/amber palette. Draw a beautiful small timber cottage viewed almost straight-on with slight 3/4 depth, rounded navy shingle roof, cream plaster and warm honey wood trim, one cozy amber round window and a LARGE OPEN dark arched doorway centered low on the front wall. The opening reaches ground level with a small threshold and can visibly fit a chibi fox. Craftsmanship: wood grain, soft roof edge highlights, warm little porch light. NO fox, NO mat, NO furniture outside, NO scene or ground tile, NO grass garden platform, NO labels or text, NO frame or UI. Entire house isolated with genuine transparent alpha around its silhouette. Full roof and base visible with transparent margins. This is an actual game sprite, centered, crisp soft illustrative render, not a flat icon.
```

## 展开 / 卷起的垫子

源文件：mat-source.png

```text
Use case: stylized-concept. Asset: two-frame horizontal PROP sprite sheet, exactly two equally spaced objects on transparent alpha. Soft polished chibi rendering matching reference navy/cream fox. Frame1 an elegant little oval woven sleeping mat viewed from slight above, muted teal upholstery, warm cream piping, a tiny subtle amber paw embroidery, visibly soft fabric and hand-stitched seams. Frame2 the EXACT same mat rolled loosely into a compact bundle suitable for a little fox to carry in its mouth, teal textile on outside, cream/amber seams, no straps. Both entire isolated objects with generous transparent gutters and margins. No fox, no house, no labels, no floor, no scene, no text, no UI. Real transparent background. Two equal cells in one horizontal row.
```

## 趴卧休息姿态

源文件：rest-source.png

```text
Use case: identity-preserve. Asset: one genuine transparent desktop pet resting sprite of the EXACT reference Susu fox. Preserve navy fluffy fur, cream face chest paws, amber closed eyes, huge tail cream tip with three linked amber markings, same soft polished chibi illustration. Fox is LYING FLAT on its belly facing right, forelegs extended and chin resting gently on front paws, back and rump low, peacefully sleeping, tail curled beside the body. A comfortable fully prone resting fox. NOT stretching, no raised rump, not sitting. Entire body and tail visible, centered, generous transparent margins. NO mat, no house, no prop, no floor, no labels or text. Genuine transparent alpha. Identity must match reference perfectly.
```

## 提取

`extract_home.py` 清理边缘透明像素、提取连通主体并按统一用途缩放。最终素材：`Assets/home/house.png`、`mat.png`、`rolled.png`、`rest.png`。房子和垫子各为独立透明道具；休息转场由运行时交叉淡入完成，进出门使用现有左右慢走帧与门口缩小、淡入淡出。并非三维模型。
