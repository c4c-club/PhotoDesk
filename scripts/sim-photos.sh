#!/usr/bin/env bash
# scripts/sim-photos.sh —— 生成 300 张尺寸/内容各异的测试图并导入模拟器照片库（docs/06 §3.1）。
# 前置：模拟器已启动（booted）。Pillow 缺失时自动装：优先 venv（PEP 668 受管 Python，如 GitHub runner），
#       回退 --break-system-packages（本地 Mac 的系统 Python）。
# 用法：bash scripts/sim-photos.sh
set -euo pipefail

PY=python3
if ! python3 -c "import PIL" 2>/dev/null; then
  if python3 -m venv /tmp/photo-tools-venv 2>/dev/null; then
    /tmp/photo-tools-venv/bin/pip install --quiet Pillow
    PY=/tmp/photo-tools-venv/bin/python3
  else
    python3 -m pip install --quiet --break-system-packages Pillow
  fi
fi

mkdir -p /tmp/simphotos
"$PY" - <<'PYEOF'
from PIL import Image, ImageDraw
import random, os
os.makedirs('/tmp/simphotos', exist_ok=True)
for i in range(300):
    w,h = random.choice([(4032,3024),(3024,4032),(2048,2048),(1920,1080)])
    im = Image.new('RGB',(w,h),(random.randint(0,255),random.randint(0,255),random.randint(0,255)))
    d = ImageDraw.Draw(im); d.ellipse([w*0.2,h*0.2,w*0.8,h*0.8], fill=(255,255,255))
    im.save(f'/tmp/simphotos/p{i:04d}.jpg', quality=85)
PYEOF

xcrun simctl addmedia booted /tmp/simphotos/*.jpg
echo "已导入 300 张测试图到模拟器照片库"
