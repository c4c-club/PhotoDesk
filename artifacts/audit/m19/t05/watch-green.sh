#!/bin/bash
# T05 green watcher: poll run 44615607748 until completed, capture evidence
cd /c/Users/RuiZh/Desktop/photo_manager
RUN=44615607748
for i in $(seq 1 45); do
  ST=$(gh run view "$RUN" --json status,conclusion --jq '.status + ":" + (.conclusion // "-")' 2>/dev/null)
  echo "poll$i $ST"
  case "$ST" in completed:*) break ;; esac
  sleep 60
done
echo "FINAL $ST"
mkdir -p artifacts/ci-evidence/m19-t05/$RUN
gh run view "$RUN" --json conclusion,headSha,status --jq '{conclusion,headSha,status}' > artifacts/ci-evidence/m19-t05/$RUN/green-meta.json
JOBID=$(gh run view "$RUN" --json jobs --jq '.jobs[] | select(.name=="build") | .databaseId')
gh run view "$RUN" --job "$JOBID" --log > artifacts/ci-evidence/m19-t05/$RUN/green-build.log 2>&1 || true
grep -nE "Test Suite 'LibraryGridGeometryTests'|Executed [0-9]+ tests|TEST SUCCEEDED|TEST FAILED|warning:" artifacts/ci-evidence/m19-t05/$RUN/green-build.log | head -40
