"""Offline CLI contracts using an independently authored, deliberately tiny model."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
BINARY = ROOT / '.build/debug/OpenModelRunner'

class RunnerTests(unittest.TestCase):
    def test_reports_calibration_and_regressions_separately_without_release_claim(self):
        with tempfile.TemporaryDirectory() as directory:
            model = Path(directory) / 'model.json'
            output = Path(directory) / 'report.json'
            model.write_text(json.dumps(dict(schemaVersion=1, version='open-1', languages={
                'en': ['connector', 'ground'], 'ru': ['периодически', 'переключилось', 'тоже']})))
            result = subprocess.run([str(BINARY), '--model', str(model), '--output', str(output)], cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads(output.read_text())
            self.assertFalse(report['releaseReady'])
            self.assertEqual(report['split'], 'calibration')
            self.assertEqual(report['calibration']['open']['total'], 6002)
            self.assertIn('baseline', report['calibration'])
            cases = {case['id']: case for case in report['regressions']}
            self.assertEqual(cases['ground-wrong']['actual'], 'ground')
            self.assertEqual(cases['connector-wrong']['actual'], 'connector')
            self.assertEqual(cases['version-ru']['actual'], '1ю3ю166')
            self.assertEqual(cases['url']['actual'], 'https://example.com')
            self.assertIn('not hardware', report['regressionMode'])

    def test_rejects_incomplete_arguments(self):
        result = subprocess.run([str(BINARY), '--model'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn('Usage:', result.stderr)

if __name__ == '__main__':
    unittest.main()
