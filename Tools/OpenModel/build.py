#!/usr/bin/env python3
"""Reproducible independent lexical selection, never reads installed applications."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
MODEL = ROOT / 'Resources/OpenModel'

def parse_affixes(text):
    groups, compound_only = {}, set()
    ignored = {'SET', 'TRY', 'REP', 'ICONV', 'NOSUGGEST', 'COMPOUNDMIN', 'COMPOUNDRULE', 'WORDCHARS'}
    for raw in text.splitlines():
        row = raw.split('#', 1)[0].split()
        if not row: continue
        kind = row[0]
        if kind == 'ONLYINCOMPOUND': compound_only.add(row[1]); continue
        if kind in ignored: continue  # suggestion/compound generation explicitly excluded
        if kind not in {'PFX', 'SFX'}: raise ValueError(f'Unsupported directive: {kind}')
        if len(row) == 4:
            _, flag, cross, count = row
            if len(flag) != 1 or cross not in {'Y','N'} or (kind,flag) in groups:
                raise ValueError('Invalid affix header')
            groups[kind,flag] = {'cross':cross == 'Y', 'count':int(count), 'rules':[]}
        elif len(row) == 5:
            _, flag, strip, add, condition = row
            if '/' in add or (kind,flag) not in groups: raise ValueError('Unsupported continuation or missing header')
            pattern = re.compile(('^' + condition) if kind == 'PFX' else (condition + '$'))
            groups[kind,flag]['rules'].append(('' if strip == '0' else strip, '' if add == '0' else add, pattern))
        else: raise ValueError('Malformed affix row')
    if any(len(g['rules']) != g['count'] for g in groups.values()): raise ValueError('Affix count mismatch')
    return groups, compound_only

def apply(word, kind, group):
    for strip, add, pattern in group['rules']:
        if not pattern.search(word): continue
        if kind == 'PFX' and word.startswith(strip): yield add + word[len(strip):]
        elif kind == 'SFX' and word.endswith(strip): yield (word[:-len(strip)] if strip else word) + add

def expand_entry(word, flags, affixes):
    groups, compound_only = affixes
    if compound_only.intersection(flags): return set()
    output = {word}
    prefixes = [g for (kind,flag),g in groups.items() if kind == 'PFX' and flag in flags]
    suffixes = [g for (kind,flag),g in groups.items() if kind == 'SFX' and flag in flags]
    for group in prefixes: output.update(apply(word, 'PFX', group))
    for group in suffixes: output.update(apply(word, 'SFX', group))
    for prefix in prefixes:
        if not prefix['cross']: continue
        for suffix in suffixes:
            if suffix['cross']:
                for prefixed in apply(word,'PFX',prefix): output.update(apply(prefixed,'SFX',suffix))
    return output

def build_words(dictionary, affixes, language):
    alphabet = re.compile(r'[a-z]{2,48}' if language == 'en' else r'[а-яё]{2,48}')
    rows = dictionary.lstrip('\ufeff').splitlines()
    if not rows or int(rows[0]) != len(rows)-1: raise ValueError('Dictionary count mismatch')
    output = set()
    original_words = set()
    for row in rows[1:]:
        entry = row.split()[0]
        word, _, flags = entry.partition('/')
        if not alphabet.fullmatch(word): continue
        original_words.add(word)
        output.update(w for w in expand_entry(word, flags, affixes) if alphabet.fullmatch(w))
    if language == 'ru':
        # Legacy upstream negative classes may omit ё beside corrected duplicate
        # rules. Require independent е support for derived ё forms; original
        # dictionary stems remain authoritative. This is a conservative filter,
        # not a claim that every Hunspell-derived form is linguistically valid.
        output = {w for w in output if 'ё' not in w or w in original_words
                  or w.replace('ё', 'е') in output}
    return sorted(output)

def sha(data): return hashlib.sha256(data).hexdigest()

def build(fetch=False):
    manifest = json.loads((MODEL/'provenance.json').read_text())
    for source in manifest['files']:
        path = ROOT / source['path']
        if fetch:
            data = urllib.request.urlopen(source['url'],timeout=60).read()
            if sha(data) != source['sha256']: raise ValueError('Downloaded source hash mismatch')
            path.parent.mkdir(parents=True,exist_ok=True); path.write_bytes(data)
        if sha(path.read_bytes()) != source['sha256']: raise ValueError(f'Source hash mismatch: {path}')
    languages = {}
    for lang, folder, stem in [('en','en','en_US'),('ru','ru_RU','ru_RU')]:
        dictionary = (ROOT/f'Corpora/Sources/{folder}/{stem}.dic').read_text()
        affixes = parse_affixes((MODEL/f'Sources/{folder}/{stem}.aff').read_text())
        languages[lang] = build_words(dictionary,affixes,lang)
    artifact = {'schemaVersion':1,'version':'open-1','languages':languages}
    data = (json.dumps(artifact,ensure_ascii=False,sort_keys=True,separators=(',',':'))+'\n').encode()
    (MODEL/'open-v1.json').write_bytes(data)
    report = {'artifact':'open-v1.json','sha256':sha(data),'bytes':len(data),
              'wordCounts':{lang:len(words) for lang,words in languages.items()}}
    (MODEL/'build-report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))

if __name__ == '__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--fetch',action='store_true');args=parser.parse_args()
    build(args.fetch)
