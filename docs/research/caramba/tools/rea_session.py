"""Local research MCP client. File queue keeps one REA analysis session open."""
import subprocess,json,pathlib,threading,queue,time,os,sys
base=pathlib.Path(__file__).resolve().parent.parent
qdir=base/'evidence'/'rpc';qdir.mkdir(exist_ok=True)
env=os.environ.copy()
env['JAVA_HOME']='/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home'
env['GHIDRA_INSTALL_DIR']='/Users/manjarqo/.cache/necaramba-tools/ghidra_12.1.4_PUBLIC'
env['REA_GHIDRA_STARTUP_TIMEOUT_MS']='900000'
log=open(base/'evidence'/'rea-server.log','a')
p=subprocess.Popen(['npx','-y','rea-agents@6.4.0','mcp'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=log,text=True,env=env,bufsize=1)
responses=queue.Queue()
def reader():
 for line in p.stdout:
  try: responses.put(json.loads(line))
  except ValueError: pass
threading.Thread(target=reader,daemon=True).start()
seq=0
def rpc(method,params=None):
 global seq
 seq+=1; i=seq
 p.stdin.write(json.dumps(dict(jsonrpc='2.0',id=i,method=method,params=params or {}))+'\n');p.stdin.flush()
 while True:
  r=responses.get(timeout=1200)
  if r.get('id')==i:return r
r=rpc('initialize',dict(protocolVersion='2024-11-05',capabilities={},clientInfo=dict(name='necaramba-research',version='1')))
p.stdin.write(json.dumps(dict(jsonrpc='2.0',method='notifications/initialized'))+'\n');p.stdin.flush()
r=rpc('tools/list')
(base/'evidence'/'rea-tools.json').write_text(json.dumps(r,ensure_ascii=False,indent=2))
print('READY',flush=True)
try:
 while True:
  pending=sorted(x for x in qdir.glob('*.request.json') if not x.with_name(x.name.replace('.request.json','.result.json')).exists())
  if not pending: time.sleep(.25);continue
  for f in pending:
   req=json.loads(f.read_text());print('START',f.name,req.get('name'),flush=True)
   result=rpc('tools/call',req)
   f.with_name(f.name.replace('.request.json','.result.json')).write_text(json.dumps(result,ensure_ascii=False,indent=2))
   print('DONE',f.name,flush=True)
   if req.get('name')=='close_binary':sys.exit(0)
finally:p.terminate();p.wait(timeout=20);log.close()
