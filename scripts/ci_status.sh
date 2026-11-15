#!/bin/sh
RUN="$1"
curl -s -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/yoyo520956/GlobalIAPRadar/actions/runs/$RUN" \
| python3 -c "
import json,sys
r=json.load(sys.stdin)
print('RUN',r['id'],r['status'],r['conclusion'],r['head_sha'][:7])
"
curl -s -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/yoyo520956/GlobalIAPRadar/actions/runs/$RUN/jobs" \
| python3 -c "
import json,sys
d=json.load(sys.stdin)
for j in d.get('jobs',[]):
    print(' JOB',j['name'],j['status'],j['conclusion'])
    for s in j.get('steps',[]):
        if s.get('conclusion') not in (None,'success'):
            print('   step:',s['name'],s['status'],s['conclusion'])
"
