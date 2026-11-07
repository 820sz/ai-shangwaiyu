export PYTHONIOENCODING=utf-8
#!/bin/bash
q=$(python -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$1")
curl -s -m 25 "https://api.openalex.org/works?search=$q&per-page=3&select=id,doi,title,publication_year,authorships,type,primary_location,biblio" | python -c "
import sys,json
d=json.load(sys.stdin)
for w in d.get('results',[]):
    au='; '.join(a['author'].get('display_name','') for a in w.get('authorships',[])[:3])
    src=(w.get('primary_location') or {}).get('source') or {}
    print(' *',au[:45],'|',(w.get('title') or '')[:70],'|',w.get('publication_year'),'|',w.get('type'),'|',(src.get('display_name') or '')[:40],'| DOI:',w.get('doi'))
"
