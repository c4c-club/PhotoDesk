#!/usr/bin/env bash
# scripts/sim-photos-dated.sh —— 生成带 EXIF 拍摄日期的测试图并导入模拟器照片库（docs/09 Phase 8）。
# 用途：筛选（年/月/位置记忆）测试需要可控的创建日期分布——2020–2026 每月若干张。
# 前置：模拟器已启动（booted）；Pillow 自动安装（同 sim-photos.sh）。
# 用法：bash scripts/sim-photos-dated.sh [每月张数]   # 默认每月 2 张（2020-01 至 2026-10，约 166 张）
set -euo pipefail

PER_MONTH="${1:-2}"

PY=python3
if ! python3 -c "import PIL" 2>/dev/null; then
  if python3 -m venv /tmp/photo-tools-venv 2>/dev/null; then
    /tmp/photo-tools-venv/bin/pip install --quiet Pillow
    PY=/tmp/photo-tools-venv/bin/python3
  else
    python3 -m pip install --quiet --break-system-packages Pillow
  fi
fi

mkdir -p /tmp/simphotos-dated
PER_MONTH="$PER_MONTH" "$PY" - <<'PYEOF'
from PIL import Image
import os, calendar
per_month = int(os.environ.get('PER_MONTH', '2'))
os.makedirs('/tmp/simphotos-dated', exist_ok=True)
count = 0
# 注意：Pillow 的 piexif 依赖在 Pillow 内置（PIL.Image.Exif），直接写 EXIF DateTimeOriginal
for year in range(2020, 2027):
    for month in range(1, 13):
        if year == 2026 and month > 10:
            break   # 只到 2026-10（当前月）
        for day in (3, 17):
            if day > calendar.monthrange(year, month)[1]:
                continue
            im = Image.new('RGB', (640, 480), ((year * 37) % 255, (month * 61) % 255, (day * 97) % 255))
            exif = im.getexif()
            # 0x9003 = DateTimeOriginal；EXIF 用「YYYY:MM:DD HH:MM:SS」
            exif[0x9003] = f"{year:04d}:{month:02d}:{day:02d} 12:00:00"
            im.save(f'/tmp/simphotos-dated/d{count:05d}.jpg', quality=85, exif=exif.tobytes())
            count += 1
# 极端比例图（docs/13 Phase 0：S01 缩放 / S08 滑动覆盖——长图/宽图/超大全景）
Image.new('RGB', (1200, 3600), (200, 60, 60)).save('/tmp/simphotos-dated/x-long.jpg', quality=85)
Image.new('RGB', (3600, 1200), (60, 200, 60)).save('/tmp/simphotos-dated/x-wide.jpg', quality=85)
Image.new('RGB', (12000, 1000), (60, 60, 200)).save('/tmp/simphotos-dated/x-pano.jpg', quality=85)
count += 3
print(f"generated {count}")
PYEOF

xcrun simctl addmedia booted /tmp/simphotos-dated/*.jpg
echo "已导入带 EXIF 日期（2020–2026 每月 ${PER_MONTH} 张）的测试图到模拟器照片库"
