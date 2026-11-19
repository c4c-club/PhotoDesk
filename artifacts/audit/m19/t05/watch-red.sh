#!/bin/bash
# T05 red watcher: poll run 44608129270 until completed, capture failed-step evidence
cd /c/Users/RuiZh/Desktop/photo_manager
RUN=44608129270
for i in $(seq 1 40); do
  ST=$(gh run view "$RUN" --json status,conclusion --jq '.status + ":" + (.conclusion // "-")' 2>/dev/null)
  echo "poll$i $ST"
  case "$ST" in completed:*) break ;; esac
  sleep 60
done
echo "FINAL $ST"
mkdir -p artifacts/ci-evidence/m19-t05/$RUN artifacts/audit/m19/t05
gh run view "$RUN" --json conclusion,headSha,status --jq '{conclusion,headSha,status}' > artifacts/ci-evidence/m19-t05/$RUN/red-meta.json
gh run view "$RUN" --log-failed > artifacts/audit/m19/t05/red-compile-failure.log 2>&1 || true
grep -nE "error:|no member|has been renamed|'trailHitProvider'|BUILD FAILED|Testing failed" artifacts/audit/m19/t05/red-compile-failure.log | head -30
