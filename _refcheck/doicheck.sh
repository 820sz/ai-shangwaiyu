#!/bin/bash
# One DOI per line; print compact verified metadata
for d in "$@"; do
  r=$(curl -s -m 25 "https://api.crossref.org/works/$d")
  st=$(printf '%s' "$r" | grep -c '"status":"ok"')
  if [ "$st" -ge 1 ]; then
    printf '%s\t' "OK"
    printf '%s' "$r" | python -c "
import sys,json
try:
    m=json.load(sys.stdin)['message']
except Exception as e:
    print('PARSEFAIL'); sys.exit()
au='; '.join((a.get('family','')+', '+a.get('given','')) for a in m.get('author',[])[:4])
print('%s | %s | %s | %s | vol %s issue %s pp %s | DOI: %s' % (
  au or '(book)',
  (m.get('title') or [''])[0][:110],
  (m.get('container-title') or [''])[0][:70],
  (m.get('issued',{}).get('date-parts',[['?']])[0][0]),
  m.get('volume','-'), m.get('issue','-'), m.get('page','-'), m.get('DOI','')))
"
  else
    printf 'FAIL\t%s\t%s\n' "$d" "$(printf '%s' "$r" | head -c 120)"
  fi
done
