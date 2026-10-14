#!/usr/bin/env python3
"""Frozen deterministic corpus v1. Regeneration is a corpus revision, never holdout tuning."""
import collections,hashlib,json,pathlib,re,unicodedata
ROOT=pathlib.Path(__file__).resolve().parent.parent
sha=lambda b:hashlib.sha256(b).hexdigest()
def write(path,value):
 p=ROOT/path;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(value,ensure_ascii=False,sort_keys=True,indent=2)+'\n')
def words(path,pattern):
 text=(ROOT/path).read_text(encoding='utf-8-sig')
 return sorted(set(unicodedata.normalize('NFC',line.split('/')[0]) for line in text.splitlines()[1:] if re.fullmatch(pattern,line.split('/')[0]) and 4<=len(line.split('/')[0])<=20))
en=words('Corpora/Sources/en/en_US.dic',r'[a-z]+')
ru=words('Corpora/Sources/ru_RU/ru_RU.dic',r'[а-яё]+')
# Exact word membership only: Hunspell affixes are intentionally not expanded.
english="`qwertyuiop[]asdfghjkl;'zxcvbnm,."
russian="ёйцукенгшщзхъфывапролджэячсмитьбю"
forward=dict(zip(english,russian));reverse={v:k for k,v in forward.items()}
assert len(forward)==len(reverse)==33
lexicon=[dict(word=w,language=lang,frequencyBand=1) for lang,ws in [('english',en),('russian',ru)] for w in ws]
# Own narrowly scoped exact rules, not recovered constants or learned holdout rules.
typos=[('teh','the'),('recieve','receive'),('adress','address'),('wierd','weird')]
yo=[('елка','ёлка'),('ежик','ёжик'),('береза','берёза')]
for w in ['the','receive','address','weird','ёлка','ёжик','берёза']:
 if not any(x['word']==w for x in lexicon):lexicon.append(dict(word=w,language='russian' if 'а'<=w[0]<='я' or w[0]=='ё' else 'english',frequencyBand=1))
snapshot=dict(modelVersion=1,lexicon=lexicon,typos=[dict(source=a,target=b,caseSensitive=False) for a,b in typos],yoRules=[dict(source=a,target=b,caseSensitive=False) for a,b in yo],protectedTokens=['API','HTTP','все','всё'],mappings=[dict(source='US',target='RU',pairs=forward),dict(source='RU',target='US',pairs=reverse)])
(ROOT/'Resources/Rules/independent-v1.json').write_text(json.dumps(snapshot,ensure_ascii=False,sort_keys=True,separators=(',',':'))+'\n')
# Coarse first-four-character families keep likely related roots/inflections in one split.
# Full lexicon is a fixed external prior, not corpus-trained; it is not a train split.
buckets={s:[] for s in ['train','calibration','holdout']}
allwords=set(en+ru)
groups=collections.defaultdict(list)
for lang,ws in [('english',en),('russian',ru)]:
 for w in ws:
  if w.replace('ё','е')[:4] in {x.replace('ё','е')[:4] for pair in typos+yo+[('превет','привет'),('helllo','hello'),('ght;lt','прежде')] for x in pair} or w in {'все','всё'}:continue
  family=lang+':'+w.replace('ё','е')[:4]
  groups[family].append((lang,w))
for family,entries in sorted(groups.items(),key=lambda x:sha(x[0].encode())):
 split=['train','calibration','holdout'][int(sha(family.encode())[:8],16)%3]
 if len(buckets[split])<1200:buckets[split].append((family,entries[0]))
assert all(len(v)==1200 for v in buckets.values())
rows=[]
def add(split,family,input,expected,layout,category,license):
 rows.append(dict(id=f'{split}-{len(rows):05d}',input=input,expected=expected,layout=layout,shouldChange=input!=expected,split=split,sourceLicense=license,category=category,family=family))
for split,entries in buckets.items():
 for i,(family,(lang,w)) in enumerate(entries):
  layout='US' if lang=='english' else 'RU';wronglayout='RU' if lang=='english' else 'US'
  license='LicenseRef-SCOWL' if lang=='english' else 'LicenseRef-Lebedev-BSD'
  transform=reverse if lang=='russian' else forward
  wrong=''.join(transform.get(c,c) for c in w)
  # Label genuinely ambiguous known source tokens as no-change, rather than guessing.
  ambiguous=wrong in allwords
  add(split,family,w,w,layout,'correct.'+lang,license)
  add(split,family,w.upper(),w.upper(),layout,'acronym.'+lang,license)
  add(split,family,wrong,wrong if ambiguous else w,wronglayout,'ambiguous' if ambiguous else 'layout.'+lang,license)
  # Layout punctuation is deliberately represented, without removing difficult cases.
  titlewrong=wrong[0].upper()+wrong[1:];title=w[0].upper()+w[1:]
  add(split,family,titlewrong,titlewrong if ambiguous else title,wronglayout,'ambiguous' if ambiguous else 'layout.title.'+lang,license)
  # Various app-like contexts are synthetic guard tokens, never actual user documents.
  guards=[('url','https://'+w+'.example/path'),('email',w+'@example.test'),('path','/tmp/'+w+'.txt'),('code',w+'_value'),('mixed',w+'а' if lang=='english' else w+'a'),('number',w+'42')]
  category,text=guards[i%len(guards)]
  add(split,family,text,text,layout,'guard.'+category,'CC0-1.0')
# Dedicated disjoint, own challenge examples. None was selected from observed predictions.
challenges=[('train','teh','the','US','typo'),('calibration','recieve','receive','US','typo'),('holdout','adress','address','US','typo'),('holdout','wierd','weird','US','typo'),('train','елка','ёлка','RU','yo'),('calibration','ежик','ёжик','RU','yo'),('holdout','береза','берёза','RU','yo'),('holdout','превет','привет','RU','unsupported.typo'),('holdout','helllo','hello','US','unsupported.typo'),('holdout','ght;lt','прежде','US','layout.punctuation')]
for split,a,b,layout,cat in challenges:add(split,'challenge:'+b,a,b,layout,cat,'CC0-1.0')
# Explicit punctuation challenge comes from independently spelled прежде.
files=[]
for split in buckets:
 subset=[r for r in rows if r['split']==split]
 data=''.join(json.dumps(r,ensure_ascii=False,sort_keys=True)+'\n' for r in subset).encode()
 path=f'Corpora/{split}.jsonl';(ROOT/path).write_bytes(data)
 files.append(dict(path=path,sha256=sha(data),count=len(subset),split=split))
provenance=json.loads((ROOT/'Corpora/Sources/provenance.json').read_text())
sources=[dict(id='LicenseRef-SCOWL',licensePath='Corpora/Sources/en/README_en_US.txt',description='SCOWL-derived en_US Hunspell base words; all upstream notices retained'),dict(id='LicenseRef-Lebedev-BSD',licensePath='Corpora/Sources/ru_RU/README_ru_RU.txt',description='Russian Hunspell base words; modified selection marked'),dict(id='CC0-1.0',licensePath='Corpora/LICENSE.synthetic',description='Own synthetic transformations, guards, and narrow exact rules')]
for source in sources:source['licenseSHA256']=sha((ROOT/source['licensePath']).read_bytes())
write('Corpora/manifest.json',dict(schemaVersion=1,corpusVersion='independent-v1-frozen',rules=dict(path='Resources/Rules/independent-v1.json',sha256=sha((ROOT/'Resources/Rules/independent-v1.json').read_bytes())),files=files,sources=sources,provenance=provenance,minimumTotal=10000))
print('lexicon',len(lexicon),'rows',len(rows),collections.Counter(r['split'] for r in rows))
