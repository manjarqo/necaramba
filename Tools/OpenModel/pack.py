#!/usr/bin/env python3
"""Pack independently generated lexemes into deterministic UTF-8 search tables."""
import argparse
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]

def pack(source, destination):
    if source.stat().st_size > 64 * 1024 * 1024: raise ValueError('Source exceeds 64 MiB')
    source_bytes = source.read_bytes()
    model = json.loads(source_bytes)
    if model.get('schemaVersion') != 1 or not re.fullmatch(r'[A-Za-z0-9_.-]{1,64}',model.get('version','')):
        raise ValueError('Unsupported model header')
    languages = model.get('languages',{})
    if set(languages) != {'en','ru'}: raise ValueError('Expected both languages')
    packed = {}
    counts = {}
    for lang in ['en','ru']:
        words = languages[lang]
        alphabet = r'[a-z]{1,128}' if lang == 'en' else r'[а-яё]{1,128}'
        if not isinstance(words,list) or not words or any(not isinstance(word,str) or not re.fullmatch(alphabet,word) for word in words):
            raise ValueError('Invalid word alphabet')
        if len(set(words)) != len(words): raise ValueError('Duplicate words')
        counts[lang] = len(words)
        packed[lang] = (''.join(word+'\n' for word in sorted(words))).encode('utf-8')
    if sum(counts.values()) > 2_000_000 or sum(map(len,packed.values())) > 64*1024*1024:
        raise ValueError('Packed model exceeds bounds')
    report = {'schemaVersion':1,'version':model['version'], 'sourceSHA256':hashlib.sha256(source_bytes).hexdigest(),
              'wordCounts':counts,'files':{lang:{'path':lang+'.words','bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()} for lang,data in packed.items()}}
    destination.mkdir(parents=True,exist_ok=True)
    for lang,data in packed.items(): (destination/(lang+'.words')).write_bytes(data)
    return report

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--source',type=Path,default=ROOT/'Resources/OpenModel/open-v1.json')
    parser.add_argument('--output',type=Path,default=ROOT/'Resources/OpenModel')
    args=parser.parse_args()
    print(json.dumps(pack(args.source,args.output),indent=2))
