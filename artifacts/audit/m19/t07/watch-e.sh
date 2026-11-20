#!/bin/bash
# T07 run E watcher (2 UI cases after anchor occlusion fix)
cd /c/Users/RuiZh/Desktop/photo_manager
RUN=$1
for i in $(seq 1 55); do
  ST=$(gh run view "$RUN" --json status,conclusion --jq '.status + ":" + (.conclusion // "-")' 2>/dev/null)
  echo "poll$i $ST"
  case "$ST" in completed:*) break ;; esac
  sleep 60
done
echo "FINAL $ST"
mkdir -p artifacts/ci-evidence/m19-t07/$RUN
gh run view "$RUN" --json conclusion,headSha,status --jq '{conclusion,headSha,status}' > artifacts/ci-evidence/m19-t07/$RUN/e-meta.json
JOBID=$(gh run view "$RUN" --json jobs --jq '.jobs[] | select(.name=="build") | .databaseId')
gh run view "$RUN" --job "$JOBID" --log > artifacts/ci-evidence/m19-t07/$RUN/e-build.log 2>&1 || true
grep -nE "Test Case.*(passed|failed)|Test Suite 'SlideSelectTrailUITests'|Executed [0-9]+ tests|TEST SUCCEEDED|TEST FAILED" artifacts/ci-evidence/m19-t07/$RUN/e-build.log | head -40
