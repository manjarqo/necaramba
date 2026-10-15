"""Offline CLI contract tests, using only independently authored fixtures."""
import copy
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

BINARY = Path(__file__).resolve().parents[2] / '.build/debug/ModelReplayRunner'

class RunnerTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / 'model.json'
        self.model = {'version': 'synthetic-1', 'kbm': {
            'languages': {'0': 'ru-en'},
            'graph_records': [{'key': '\x02abc\x03', 'value': 7}],
            'index': {'7': [dict(lang=0, weight=0, is_known_word=True, is_case_sensitive=False)]}},
            'autocorrect': {'graph_records': [{'key': '\x02abc\x03', 'value': 0}],
                'rules': [dict(prefix_len=1, suffix_len=1, insert_id=0)], 'insert_pool': ['X']}}

    def invoke(self, *extra, model=None):
        self.path.write_text(json.dumps(self.model if model is None else model))
        return subprocess.run([str(BINARY), '--model', str(self.path), '--pair', 'en-ru',
                               '--text', 'abc', *extra], capture_output=True, text=True)

    def test_resolves_reversed_pair_and_validates_splice(self):
        result = self.invoke('--validate-autocorrect')
        self.assertEqual(result.returncode, 0, result.stderr)
        output = json.loads(result.stdout)
        self.assertEqual(output['results'][0]['status'], 'known')
        self.assertEqual(output['autocorrectSpliceValidation'], {'accepted': 1, 'rejected': 0})

    def test_token_mode_trims_without_guessing_raw_framing(self):
        result = self.invoke('--token', '--text', ' abc ')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['results'][1]['status'], 'known')

    def test_autocorrect_interprets_supplied_synthetic_rule(self):
        result = self.invoke('--autocorrect')
        self.assertEqual(result.returncode, 0, result.stderr)
        correction = json.loads(result.stdout)['autocorrectResults'][0]
        self.assertEqual(correction['status'], 'corrected')
        self.assertEqual(correction['replacement'], 'aXc')

    def test_rejects_unresolved_graph_and_language_references(self):
        for mutation in ('graph', 'language'):
            model = copy.deepcopy(self.model)
            if mutation == 'graph': model['kbm']['graph_records'][0]['value'] = 99
            else: model['kbm']['index']['7'][0]['lang'] = 99
            result = self.invoke(model=model)
            self.assertEqual(result.returncode, 2)
            self.assertEqual(result.stdout, '')

    def test_rejects_unresolved_autocorrect_insertion(self):
        self.model['autocorrect']['rules'][0]['insert_id'] = 9
        result = self.invoke('--validate-autocorrect')
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, '')

    def test_rejects_incomplete_arguments(self):
        result = subprocess.run([str(BINARY), '--model'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn('Usage:', result.stderr)

if __name__ == '__main__':
    unittest.main()
