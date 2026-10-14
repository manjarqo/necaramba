#!/usr/bin/env python3
"""Fetch pinned independently licensed lexical sources; never reads installed apps."""
import hashlib,json,pathlib,urllib.request
root=pathlib.Path(__file__).resolve().parent
commit='67032ee957631908098a72edf48dc81cac27e369' # Explicitly pinned; changing creates a new source revision.
files=['en/en_US.dic','en/README_en_US.txt','ru_RU/ru_RU.dic','ru_RU/README_ru_RU.txt']
metadata=[]
for name in files:
 url=f'https://raw.githubusercontent.com/LibreOffice/dictionaries/{commit}/{name}'
 data=urllib.request.urlopen(url).read()
 path=root/'Sources'/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
 metadata.append(dict(path='Corpora/Sources/'+name,url=url,sha256=hashlib.sha256(data).hexdigest()))
(root/'Sources'/'provenance.json').write_text(json.dumps(dict(repository='https://github.com/LibreOffice/dictionaries',revision=commit,files=metadata),indent=2)+'\n')
print(commit)
