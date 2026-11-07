export PYTHONIOENCODING=utf-8
#!/bin/bash
# $1 = bibliographic query ; prints top 3 candidates
q=$(printf '%s' "$1" | sed 's/ /+/g')
curl -s -m 30 "https://api.crossref.org/works?query.bibliographic=$q&rows=3&select=DOI,title,author,issued,container-title,type,publisher" | python -c "
import sys,json
try: items=json.load(sys.stdin)['message']['items']
except Exception as e: print('PARSEFAIL',e); sys.exit()
for m in items:
    au='; '.join((a.get('family','')+', '+a.get('given','')) for a in m.get('author',[])[:3]) or '(book/ed)'
    print('  *', au, '|', (m.get('title') or [''])[0][:95], '|', (m.get('container-title') or [''])[0][:40], '|', m.get('issued',{}).get('date-parts',[['?']])[0][0], '|', m.get('type',''), '|', m.get('publisher','')[:30], '| DOI:', m.get('DOI'))
"
