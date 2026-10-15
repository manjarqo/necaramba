#!/usr/bin/env python3
"""Seal deterministic hashes of independent runtime files; not a signing service."""
import hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
folder=ROOT/'Resources/OpenModel'
if __name__=='__main__':
 rules=json.loads((folder/'corrections.json').read_text())
 files={}
 for name in ['en.words','ru.words','corrections.json']:
  data=(folder/name).read_bytes();files[name]={'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}
 (folder/'manifest.json').write_text(json.dumps({'schemaVersion':1,'version':rules['version'],'files':files},sort_keys=True,indent=2)+'\n')
