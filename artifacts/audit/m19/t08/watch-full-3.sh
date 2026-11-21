#!/bin/bash
# T08 full-suite run watcher round 3 (9d469ab: long-press band + cross-month fixes)
cd /c/Users/RuiZh/Desktop/photo_manager
RUN=$1
for i in $(seq 1 120); do
  ST=$(gh run view "$RUN" --json status,conclusion --jq '.status + ":" + (.conclusion // "-")' 2>/dev/null)
  echo "poll$i $ST"
  case "$ST" in completed:*) break ;; esac
  sleep 60
done
echo "FINAL $ST"
mkdir -p artifacts/ci-evidence/m19-t08/$RUN
gh run view "$RUN" --json conclusion,headSha,status,event --jq '{conclusion,headSha,status,event}' > artifacts/ci-evidence/m19-t08/$RUN/full3-meta.json
JOBID=$(gh run view "$RUN" --json jobs --jq '.jobs[] | select(.name=="build") | .databaseId')
gh run view "$RUN" --job "$JOBID" --log > artifacts/ci-evidence/m19-t08/$RUN/full3-build.log 2>&1 || true
grep -nE "Test Case.*failed|Test Suite 'RowBandSelectUITests'|Executed [0-9]+ tests|TEST SUCCEEDED|TEST FAILED" artifacts/ci-evidence/m19-t08/$RUN/full3-build.log | head -60
