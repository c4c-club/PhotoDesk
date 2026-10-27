# /// script
# requires-python = ">=3.9"
# dependencies = ["pillow"]
# ///
# App Icon 正式版生成器（P9）：照片卡片（山 + 日）+ 上下滑箭头，品牌蓝渐变底。
# 用法（Windows，Docker）：docker run --rm -v "%cd%:/repo" -w /repo python:3.12-alpine sh -c "pip install -q pillow && python scripts/gen_icon.py"
# 产物：PhotoDesk/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon1024.png（1024×1024，4× 超采样抗锯齿）

from PIL import Image, ImageDraw, ImageFilter

S = 4                      # 超采样倍率（画布 4096 → 输出 1024）
C = 1024 * S               # 画布边长
OUT = "PhotoDesk/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon1024.png"

# 品牌蓝渐变（DSColor.tint 家族：顶部亮蓝 → 底部深蓝）
GRAD_TOP = (74, 168, 255)
GRAD_BOT = (11, 87, 208)
WHITE = (255, 255, 255, 255)
AMBER = (255, 179, 0, 255)        # 与 accentFavorite 同族
MOUNT_BACK = (142, 201, 255, 255)
MOUNT_FRONT = (10, 132, 255, 255)  # 0x0A84FF

img = Image.new("RGBA", (C, C))
d = ImageDraw.Draw(img)

# 1) 背景垂直渐变
for y in range(C):
    t = y / (C - 1)
    r = round(GRAD_TOP[0] + (GRAD_BOT[0] - GRAD_TOP[0]) * t)
    g = round(GRAD_TOP[1] + (GRAD_BOT[1] - GRAD_TOP[1]) * t)
    b = round(GRAD_TOP[2] + (GRAD_BOT[2] - GRAD_TOP[2]) * t)
    d.line([(0, y), (C, y)], fill=(r, g, b))

# 2) 照片卡片（居中白色圆角矩形）
card_l, card_t, card_r, card_b = 282 * S, 342 * S, 742 * S, 682 * S
radius = 110 * S

# 卡片投影
shadow = Image.new("RGBA", (C, C), (0, 0, 0, 0))
sd = ImageDraw.Draw(shadow)
sd.rounded_rectangle([card_l, card_t + 14 * S, card_r, card_b + 14 * S],
                     radius=radius, fill=(0, 20, 60, 90))
shadow = shadow.filter(ImageFilter.GaussianBlur(18 * S))
img.alpha_composite(shadow)

# 卡片本体 + 内容（先画在独立图层再按圆角裁剪，避免山形溢出圆角）
card = Image.new("RGBA", (C, C), (0, 0, 0, 0))
cd = ImageDraw.Draw(card)
cd.rounded_rectangle([card_l, card_t, card_r, card_b], radius=radius, fill=WHITE)
# 太阳
cd.ellipse([card_l + 130 * S, card_t + 100 * S,
            card_l + 130 * S + 90 * S, card_t + 100 * S + 90 * S], fill=AMBER)
# 山（后山浅蓝 / 前山品牌蓝；顶点全部落在卡片界内，避免圆角裁剪出尖角）
cd.polygon([(card_l + 50 * S, card_b), (card_l + 240 * S, card_t + 140 * S),
            (card_l + 430 * S, card_b)], fill=MOUNT_BACK)
cd.polygon([(card_l + 170 * S, card_b), (card_l + 340 * S, card_t + 120 * S),
            (card_l + 450 * S, card_b)], fill=MOUNT_FRONT)

mask = Image.new("L", (C, C), 0)
ImageDraw.Draw(mask).rounded_rectangle([card_l, card_t, card_r, card_b],
                                       radius=radius, fill=255)
img.paste(card, (0, 0), mask)


def arrow(tip_x, tip_y, shaft_other_y, wing_dy):
    """白色箭头：V 形头 + 竖干，圆角线帽。wing_dy 为翼端相对尖点的纵向偏移
    （上箭头翼在尖点下方 +head_dy，下箭头翼在尖点上方 -head_dy）。"""
    w = 46 * S            # 线宽
    r = w // 2
    head_dx = 92 * S      # V 形半宽
    head_dy = 96 * S      # V 形深度（从尖点到翼端）
    wing_y = tip_y + wing_dy
    # V 形（joint="curve" 平滑转折）
    d.line([(tip_x - head_dx, wing_y), (tip_x, tip_y), (tip_x + head_dx, wing_y)],
           fill=WHITE, width=w, joint="curve")
    # 竖干
    d.line([(tip_x, tip_y), (tip_x, shaft_other_y)], fill=WHITE, width=w)
    # 圆角线帽（V 形两翼端 + 竖干末端）
    for cx, cy in [(tip_x - head_dx, wing_y), (tip_x + head_dx, wing_y),
                   (tip_x, shaft_other_y)]:
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=WHITE)


# 3) 上箭头（卡片上方，尖点朝上）与下箭头（卡片下方，尖点朝下）
arrow(512 * S, 158 * S, 296 * S, +96 * S)
arrow(512 * S, 866 * S, 728 * S, -96 * S)

img.resize((1024, 1024), Image.LANCZOS).save(OUT, "PNG")
print("written", OUT)
