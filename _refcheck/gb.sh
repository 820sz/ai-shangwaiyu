#!/bin/bash
q=$(python -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$1")
curl -s -m 25 "https://www.googleapis.com/books/v1/volumes?q=$q&maxResults=4" | python -c "
import sys,json
try: d=json.load(sys.stdin)
except Exception as e: print('PARSEFAIL'); sys.exit()
for it in d.get('items',[]):
    v=it['volumeInfo']
    print(' *', v.get('title','')[:60],'|',', '.join(v.get('authors',[]))[:50],'|',v.get('publisher',''),'|',v.get('publishedDate',''),'| ISBN13:',', '.join(i['identifier'] for i in v.get('industryIdentifiers',[]) if i['type']=='ISBN_13'),'| pages:',v.get('pageCount',''))
"
