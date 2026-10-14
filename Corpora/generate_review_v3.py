#!/usr/bin/env python3
"""Review v3 coverage expansion. Does not write rules or historical corpus/reports."""
import hashlib,json,pathlib,collections
ROOT=pathlib.Path(__file__).resolve().parent.parent
OUT=ROOT/'Corpora/ReviewV3'
sha=lambda b:hashlib.sha256(b).hexdigest()
def read(path):return (ROOT/path).read_bytes()
authored=json.loads(read('Corpora/ReviewV3/authored-families.json'))
manifest=json.loads(read('Corpora/manifest.json'))
assert sha(read(manifest['rules']['path']))==manifest['rules']['sha256']
# Reserve all lexical prefix families touched by new challenges, across every split.
pairs=authored['typo']+authored['yo']
reserved={w.lower().replace('ё','е')[:4] for pair in pairs for w in pair}
def shape(text):
 letters=''.join(c for c in text if c.isalpha())
 if letters==letters.lower():return 'lowercase'
 if letters==letters.upper():return 'uppercase'
 if len(letters)>=3 and letters[:2].isupper() and letters[2:].islower():return 'doubleCaps'
 if letters==letters[:1].upper()+letters[1:].lower():return 'title'
 return 'mixed'
applications=['editor','browser','terminal','office','chat']
rows=[]
def add(row):
 row=dict(row)
 row['id']='review-v3-'+str(len(rows))
 row['language']='russian' if any('а'<=c.lower()<='я' or c.lower()=='ё' for c in row['expected']) and not row['category'].startswith('guard.') else ('russian' if row['family'].startswith('russian:') else 'english')
 row['caseShape']=shape(row['input'])
 row['applicationCategory']=applications[len(rows)%len(applications)]
 row['hostScenarioID']='synthetic.'+row['applicationCategory']+'.token-only'
 rows.append(row)
for file in manifest['files']:
 base=[json.loads(line) for line in read(file['path']).decode().splitlines()]
 for row in base:
  if row['family'].startswith('challenge:') or any(w.lower().replace('ё','е')[:4] in reserved for w in [row['input'],row['expected']]):continue
  add(row)
  if row['category'].startswith('correct.'):
   w=row['input'];caps=w[:2].upper()+w[2:];mixed=''.join(c.upper() if i%2 else c for i,c in enumerate(w))
   add(dict(row,input=caps,expected=w.title(),shouldChange=True,category='doubleCaps'))
   add(dict(row,input=mixed,expected=mixed,shouldChange=False,category='case.mixed.guard'))
# All variants of an authored correction family are assigned to holdout together.
# No authoring based on which rules currently succeed; unsupported rules must remain failures.
for feature in ['typo','yo']:
 for source,target in authored[feature]:
  family=('russian:' if feature=='yo' else 'english:')+target.lower().replace('ё','е')[:4]
  for a,b in [(source,target),(source.title(),target.title()),(source.upper(),source.upper())]:
   add(dict(input=a,expected=b,layout='RU' if feature=='yo' else 'US',shouldChange=a!=b,split='holdout',sourceLicense='CC0-1.0',category=feature,family=family))
files=[]
for split in ['train','calibration','holdout']:
 subset=[r for r in rows if r['split']==split]
 data=''.join(json.dumps(r,ensure_ascii=False,sort_keys=True)+'\n' for r in subset).encode()
 path='Corpora/ReviewV3/'+split+'.jsonl';(ROOT/path).write_bytes(data)
 files.append(dict(path=path,sha256=sha(data),count=len(subset),split=split))
manifest.update(schemaVersion=2,corpusVersion='independent-v3-reviewed-coverage',files=files)
generation=['Corpora/generate_review_v3.py','Corpora/ReviewV3/authored-families.json','Corpora/manifest.json']+[f['path'] for f in json.loads(read('Corpora/manifest.json'))['files']]
manifest['generation']=[dict(path=p,sha256=sha(read(p))) for p in generation]
(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,sort_keys=True,indent=2)+'\n')
print('rows',len(rows),collections.Counter(r['split'] for r in rows))
print('model SHA unchanged:',sha(read(manifest['rules']['path'])))
