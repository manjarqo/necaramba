"""Independent REA stdio session; read-only nested binary analysis and bounded exports."""
import subprocess,json,pathlib,threading,queue,os,struct,hashlib,sys
base=pathlib.Path(__file__).resolve().parent.parent
env=os.environ.copy();env['JAVA_HOME']='/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home';env['GHIDRA_INSTALL_DIR']='/Users/manjarqo/.cache/necaramba-tools/ghidra_12.1.4_PUBLIC';env['REA_GHIDRA_STARTUP_TIMEOUT_MS']='900000'
ev=base/'evidence'/'nested';ev.mkdir(parents=True,exist_ok=True)
log=open(ev/'server.log','a');p=subprocess.Popen(['npx','-y','rea-agents@6.4.0','mcp'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=log,text=True,env=env,bufsize=1)
responses=queue.Queue()
def reader():
 for line in p.stdout:
  try:responses.put(json.loads(line))
  except ValueError:pass
threading.Thread(target=reader,daemon=True).start();seq=0

def rpc(method,params=None):
 global seq
 seq+=1;i=seq;p.stdin.write(json.dumps(dict(jsonrpc='2.0',id=i,method=method,params=params or {}))+'\n');p.stdin.flush()
 while True:
  r=responses.get(timeout=1200)
  if r.get('id')==i:return r

def call(name,args,label):
 print('CALL',label,flush=True);r=rpc('tools/call',dict(name=name,arguments=args));(ev/(label+'.json')).write_text(json.dumps(r,ensure_ascii=False,indent=2))
 if 'error' in r:raise RuntimeError(r['error'])
 r=r['result'];v=r.get('structuredContent') or json.loads(r['content'][0]['text'])
 if r.get('isError'):raise RuntimeError(v)
 return v

def text_bounds(f):
 b=f.read_bytes();n=struct.unpack_from('<I',b,16)[0];off=32
 for _ in range(n):
  cmd,size=struct.unpack_from('<II',b,off)
  if cmd==0x19:
   ns=struct.unpack_from('<I',b,off+64)[0]
   for i in range(ns):
    s=off+72+i*80
    if b[s:s+16].rstrip(b'\0')==b'__text':
     addr,length=struct.unpack_from('<QQ',b,s+32);return addr,addr+length
  off+=size
 raise RuntimeError('no __text')

rpc('initialize',dict(protocolVersion='2024-11-05',capabilities={},clientInfo=dict(name='necaramba-nested-research',version='1')))
p.stdin.write(json.dumps(dict(jsonrpc='2.0',method='notifications/initialized'))+'\n');p.stdin.flush()
targets=[('helper','Library/LoginItems/LaunchAtLoginHelper.app/Contents/MacOS/LaunchAtLoginHelper'),('ui','Frameworks/CarambaSwitcherUI.framework/Versions/A/CarambaSwitcherUI')]
active=False
try:
 for tag,rel in targets:
  src=pathlib.Path('/Applications/Caramba Switcher Pro.app/Contents')/rel
  thin=base/'evidence'/'binaries'/(tag+'-arm64');thin.parent.mkdir(exist_ok=True)
  if not thin.exists():subprocess.run(['lipo',str(src),'-thin','arm64','-output',str(thin)],check=True)
  lo,hi=text_bounds(thin)
  (ev/(tag+'-identity.json')).write_text(json.dumps({'source':str(src),'source_sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'thin':str(thin),'thin_sha256':hashlib.sha256(thin.read_bytes()).hexdigest(),'text_start':hex(lo),'text_end_exclusive':hex(hi)},indent=2))
  active=True;call('open_binary',dict(path=str(thin),provider_id='ghidra'),tag+'-open')
  e=call('list_procedures',{},tag+'-procedures');xs=e['normalized_result'];out=base/'decompiled'/(tag+'-arm64');out.mkdir(exist_ok=True)
  selected=[x for x in xs if x['address'].startswith('0x') and lo<=int(x['address'],16)<hi and not x['procedure']['external'] and not x['procedure']['thunk']];selected.sort(key=lambda x:int(x['address'],16))
  (out/'inventory.json').write_text(json.dumps(selected,ensure_ascii=False,indent=2))
  status=dict(discovered_total=len(xs),selected_text_functions=len(selected),attempted=0,succeeded=0,failed=0,batches=0,complete=False,errors=[])
  for off in range(0,len(selected),64):
   label=f'{tag}-batch-{off//64:04}';v=call('batch_decompile',dict(addresses=[x['address'] for x in selected[off:off+64]]),label)
   (out/(label+'.evidence.json')).write_text(json.dumps(v,ensure_ascii=False))
   for item in v['normalized_result']['items']:
    status['attempted']+=1
    if item['status']=='ok':
     status['succeeded']+=1;(out/(item['address']+'.c')).write_text('// Ghidra pseudocode; not original source.\n// REA Evidence: '+v['evidence_id']+'\n// Canonical procedure: '+json.dumps(item['procedure'])+'\n'+item['pseudocode'])
    else:status['failed']+=1;status['errors'].append(item)
   status['batches']+=1;(out/'coverage.json').write_text(json.dumps(status,ensure_ascii=False,indent=2));print(tag,json.dumps({k:v for k,v in status.items() if k!='errors'}),flush=True)
  status['complete']=True;(out/'coverage.json').write_text(json.dumps(status,ensure_ascii=False,indent=2))
  call('close_binary',{},tag+'-close');active=False
finally:
 if active:
  try:call('close_binary',{},'cleanup-close')
  except Exception as e:print('Close error',repr(e),flush=True)
 p.terminate();p.wait(timeout=30);log.close()
