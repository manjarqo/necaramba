"""Offline contract tests; no proprietary reference needed."""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[2]
BINARY = ROOT / '.build/debug/OpenModelV2Runner'

class RunnerTests(unittest.TestCase):
    def test_tiny_fixture_report_is_not_a_release_claim(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            data = {'en.words': b'connector\nground\nhello\n',
                    'ru.words': ''.join(w + '\n' for w in sorted(['бывало', 'женский', 'не', 'периодически', 'переключилось', 'тоже'])).encode(),
                    'corrections.json': json.dumps(dict(schemaVersion=1, version='open-2', typos=[], yo=[], protectedWords=['ру'])).encode()}
            for name, content in data.items(): (folder / name).write_bytes(content)
            (folder / 'manifest.json').write_text(json.dumps(dict(schemaVersion=1, version='open-2', files={name: dict(bytes=len(content), sha256=hashlib.sha256(content).hexdigest()) for name, content in data.items()})))
            output = folder / 'report.json'
            result = subprocess.run([str(BINARY), '--directory', str(folder), '--output', str(output)], cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads(output.read_text())
            self.assertFalse(report['releaseReady'])
            self.assertEqual(report['split'], 'calibration')
            self.assertEqual(report['open']['total'], 6002)
            self.assertNotIn('reference', report)
            cases = {c['id']: c for c in report['regressions']}
            self.assertEqual(cases['also-wrong']['actual'], 'тоже')
            self.assertEqual(cases['switched-wrong']['actual'], 'переключилось')
            self.assertEqual(cases['not-wrong']['actual'], 'не')
            self.assertEqual(cases['title-colon']['actual'], 'Женский')
            self.assertEqual(cases['title-comma']['actual'], 'Бывало')
            self.assertGreater(report['openInitializationSeconds'], 0)
            reference = folder / 'reference.json'
            reference.write_text(json.dumps({'version': 'synthetic-reference', 'kbm': {
                'languages': {'0': 'ru-en'}, 'graph_records': [{'key': '\u0002abc\u0003', 'value': 7}],
                'index': {'7': [{'lang': 0, 'weight': 0, 'is_known_word': True, 'is_case_sensitive': False}]}},
                'autocorrect': {'graph_records': [], 'rules': [], 'insert_pool': []}}))
            compared = subprocess.run([str(BINARY), '--directory', str(folder), '--output', str(output), '--reference', str(reference)], cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(compared.returncode, 0, compared.stderr)
            aggregate = json.loads(output.read_text())['reference']
            self.assertEqual(aggregate['total'], 6002)
            self.assertNotIn('mismatches', aggregate)
            self.assertNotIn('perCategory', aggregate)
            self.assertNotIn(str(reference), output.read_text())

    def test_rejects_arguments(self):
        for args in [[], ['--directory'], ['--directory', '.', '--output', '/tmp/unused', '--split', 'train']]:
            result = subprocess.run([str(BINARY), *args], cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertIn('Usage:', result.stderr)

if __name__ == '__main__': unittest.main()
