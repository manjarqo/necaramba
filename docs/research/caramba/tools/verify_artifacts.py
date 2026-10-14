"""Verify research artifacts, not product behavior."""
import hashlib,json,pathlib,re,subprocess
base=pathlib.Path(__file__).resolve().parent.parent
root=base.parents[2]
report={'scope':'research artifacts only; no product tests executed','coverage':{},'errors':[]}
manifest=[]
for name in ['main-arm64','ui-arm64','helper-arm64']:
 folder=base/'decompiled'/name
 coverage=json.loads((folder/'coverage.json').read_text())
 files=list(folder.glob('0x*.c'))
 invpath=base/'evidence/procedures.json' if name=='main-arm64' else folder/'inventory.json'
 inv=json.loads(invpath.read_text());addresses={x['address'] for x in inv}
 for f in files:
  s=f.read_text()
  if f.stem not in addresses or 'REA Evidence: ev_' not in s:report['errors'].append(str(f))
  manifest.append((hashlib.sha256(f.read_bytes()).hexdigest(),str(f.relative_to(base))))
 if not coverage['complete'] or coverage['failed'] or len(files)!=coverage['succeeded']:report['errors'].append(name+' coverage mismatch')
 report['coverage'][name]={'files':len(files),'coverage':coverage}
(base/'evidence/decompiled-sha256.txt').write_text(''.join(f'{h}  {p}\n' for h,p in sorted(manifest,key=lambda x:x[1])))
for p in (root/'docs').rglob('*.md'):
 s=p.read_text()
 if s.count('```')%2:report['errors'].append(str(p)+' unbalanced fences')
 for m in re.finditer(r'\[[^\]]*\]\(([^)]+)\)',s):
  t=m[1].split('#')[0]
  if not t or '://' in t or t.startswith('mailto:'):continue
  q=pathlib.Path(t) if t.startswith('/') else p.parent/t
  if not q.exists():report['errors'].append(str(p)+' missing link '+t)
ids=re.findall(r'^\| (AC-\d+) \|',(base/'acceptance-matrix.md').read_text(),re.M)
report['acceptance_criteria']=len(ids)
if len(ids)!=103 or len(set(ids))!=103:report['errors'].append('AC count')
app=pathlib.Path('/Applications/Caramba Switcher Pro.app/Contents/MacOS/Caramba Switcher Pro')
report['original_sha256']=hashlib.sha256(app.read_bytes()).hexdigest()
if report['original_sha256']!='eb77b69bfb9bb6df3231a7ebafe0b9194b53df1c0ff4a673feaa4a5c5b50e051':report['errors'].append('original hash changed')
p=subprocess.run(['ps','-p','32849','-o','pid=,ppid=,stat=,command='],text=True,capture_output=True)
report['main_ghidra_cleanup']={'close_binary':'cleanup_incomplete sysctl_errno_22; preserved raw response','process_observed_after_close':p.stdout.strip(),'ps_exit':p.returncode}
report['pass']=not report['errors']
(base/'evidence/artifact-verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
print(json.dumps(report,ensure_ascii=False,indent=2))
raise SystemExit(0 if report['pass'] else 1)
