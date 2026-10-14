"""Export every discovered in-image non-thunk function through the live REA session."""
import json,pathlib,time
base=pathlib.Path(__file__).resolve().parent.parent
rpc=base/'evidence'/'rpc';out=base/'decompiled'/'main-arm64';out.mkdir(parents=True,exist_ok=True)
xs=json.loads((base/'evidence'/'procedures.json').read_text())
selected=[x for x in xs if x['address'].startswith('0x') and 0x100002328<=int(x['address'],16)<0x1003c0cd0 and not x['procedure']['external'] and not x['procedure']['thunk']]
selected.sort(key=lambda x:int(x['address'],16))
(out/'inventory.json').write_text(json.dumps(selected,ensure_ascii=False,indent=2))
status={'discovered_total':len(xs),'selected_text_functions':len(selected),'attempted':0,'succeeded':0,'failed':0,'batches':0,'complete':False,'errors':[]}
for offset in range(0,len(selected),64):
 batch=selected[offset:offset+64];stem=f'z{offset//64:04}-decompile';request=rpc/(stem+'.request.json');result=rpc/(stem+'.result.json')
 if not result.exists():
  request.write_text(json.dumps({'name':'batch_decompile','arguments':{'addresses':[x['address'] for x in batch]}}))
  start=time.monotonic()
  while not result.exists():
   if time.monotonic()-start>1200:raise RuntimeError('batch wait deadline')
   time.sleep(.5)
 r=json.loads(result.read_text())['result'];e=r.get('structuredContent') or json.loads(r['content'][0]['text'])
 if 'normalized_result' not in e:
  status['errors'].append({'batch':stem,'error':e});(out/'coverage.json').write_text(json.dumps(status,indent=2));raise RuntimeError(str(e)[:500])
 values=e['normalized_result'];(out/(stem+'.evidence.json')).write_text(json.dumps(e,ensure_ascii=False))
 for item in values['items']:
  addr=item['address'];status['attempted']+=1
  if item['status']=='ok':
   status['succeeded']+=1
   (out/(addr+'.c')).write_text('// Ghidra pseudocode; not original source.\n// REA Evidence: '+e['evidence_id']+'\n// Canonical procedure: '+json.dumps(item['procedure'])+'\n'+item['pseudocode'])
  else:status['failed']+=1;status['errors'].append(item)
 status['batches']+=1;(out/'coverage.json').write_text(json.dumps(status,ensure_ascii=False,indent=2));print(json.dumps({k:v for k,v in status.items() if k!='errors'}),flush=True)
status['complete']=True;(out/'coverage.json').write_text(json.dumps(status,ensure_ascii=False,indent=2))
