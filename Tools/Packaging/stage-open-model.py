#!/usr/bin/env python3
"""Stage only verified independent open model files into the app bundle."""
import hashlib,json,shutil,sys
from pathlib import Path

def stage(source,destination):
 source,destination=Path(source),Path(destination)
 if source.is_symlink() or destination.is_symlink():raise ValueError('Symlink directory')
 manifest_path=source/'manifest.json'
 if manifest_path.is_symlink():raise ValueError('Symlink manifest')
 manifest=json.loads(manifest_path.read_text())
 names={'en.words','ru.words','corrections.json'}
 if manifest.get('schemaVersion')!=1 or set(manifest['files'])!=names:raise ValueError('Invalid manifest')
 declared=0
 for name in names:
  size=manifest['files'][name]['bytes']
  limit=8*1024*1024 if name=='corrections.json' else 64*1024*1024
  if not isinstance(size,int) or not 0<size<=limit or size>64*1024*1024-declared:raise ValueError('Model budget exceeded')
  declared+=size
 verified={}
 for name in sorted(names):
  path=source/name;entry=manifest['files'][name]
  if path.is_symlink() or not path.is_file() or not 0<path.stat().st_size<=64*1024*1024:raise ValueError('Invalid model file')
  data=path.read_bytes()
  if len(data)!=entry['bytes'] or hashlib.sha256(data).hexdigest()!=entry['sha256']:raise ValueError('Model hash mismatch')
  verified[name]=data
 for name in ['SCOWL-en_US.txt','Lebedev-ru_RU.txt','Necaramba-GPL-3.0.txt']:
  path=source/'Licenses'/name
  if path.is_symlink() or not path.is_file():raise ValueError('Missing license')
  verified['Licenses/'+name]=path.read_bytes()
 verified['manifest.json']=manifest_path.read_bytes()
 for name in ['README.md','corrections-provenance.json','CORRECTIONS.md','provenance.json']:
  path=source/name
  if path.is_file() and not path.is_symlink():verified[name]=path.read_bytes()
 destination.mkdir(parents=True,exist_ok=True)
 for name,data in verified.items():
  path=destination/name
  if path.is_symlink() or path.parent.is_symlink():raise ValueError('Symlink destination')
  path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)

if __name__=='__main__':
 try:
  if len(sys.argv)!=3:raise ValueError('Usage: stage-open-model.py source destination')
  stage(*sys.argv[1:])
 except (OSError,ValueError,KeyError,TypeError) as error:sys.exit(str(error))
