#!/bin/bash
cd /c/Users/RuiZh/Desktop/photo_manager || exit 9
P=artifacts/audit/2026-11-12
echo "== run1 =="
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/audit-m16.ps1 -FailOnRedline 2>&1 | tail -6
echo "run1 exit: ${PIPESTATUS[0]}"
rm -rf /tmp/audit-run1 && mkdir -p /tmp/audit-run1
cp "$P/audit.md" "$P/audit.json" "$P/root-cause.md" "$P/test-gap.md" /tmp/audit-run1/ || { echo "run1 outputs missing"; exit 3; }
echo "== run2 =="
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/audit-m16.ps1 -FailOnRedline 2>&1 | tail -6
echo "run2 exit: ${PIPESTATUS[0]}"
echo "== diff (timestamp-normalized) =="
for f in audit.md audit.json root-cause.md test-gap.md; do
  n=$(sed -E 's/generatedAt [0-9T:+.-]+//g; s/（generatedAt [^）]+）//g' /tmp/audit-run1/$f | diff - <(sed -E 's/generatedAt [0-9T:+.-]+//g; s/（generatedAt [^）]+）//g' "$P/$f") | wc -l)
  echo "$f diff-lines=$n"
done
