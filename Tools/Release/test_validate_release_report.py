#!/usr/bin/env python3
"""Isolated fixture checks for the release evidence CLI; no real release evidence is created."""
import hashlib
import json
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
CLI = ROOT / 'Tools/Release/validate-release-report.swift'
KEY = 'AC-001/arm64/12/TextEdit/native'
ARTIFACT = b'isolated fake artifact bytes'
BUILD = hashlib.sha256(ARTIFACT).hexdigest()


class ReleaseEvidenceCLITests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='release-gate-', dir=ROOT / '.build')
        self.addCleanup(self.temp.cleanup)
        self.dir = pathlib.Path(self.temp.name)
        (self.dir / 'artifact.bin').write_bytes(ARTIFACT)
        self.evidence = {
            'tuple': KEY, 'artifactSHA256': BUILD, 'architecture': 'arm64',
            'osMajor': '12', 'osBuild': '21G93', 'host': 'TextEdit', 'adapter': 'native',
            'status': 'passed',
        }
        self.result = {
            'status': 'passed', 'evidencePath': str(self.evidence_path()),
            'evidenceSHA256': '', 'buildSHA': BUILD, 'architecture': 'arm64',
            'osMajor': '12', 'osBuild': '21G93', 'host': 'TextEdit', 'adapter': 'native',
        }

    def evidence_path(self):
        return self.dir / 'evidence.json'

    def run_gate(self):
        data = json.dumps(self.evidence, sort_keys=True).encode()
        self.evidence_path().write_bytes(data)
        self.result['evidenceSHA256'] = hashlib.sha256(data).hexdigest()
        manifest = self.dir / 'manifest.json'
        manifest.write_text(json.dumps({'schemaVersion': 1, 'required': [KEY]}))
        report = self.dir / 'report.json'
        report.write_text(json.dumps({
            'schemaVersion': 1, 'manifest': str(manifest), 'buildSHA': BUILD,
            'artifactPath': str(self.dir / 'artifact.bin'),
            'results': {KEY: self.result},
        }))
        return subprocess.run(['swift', str(CLI), str(report)], cwd=ROOT, capture_output=True, text=True)

    def test_matching_tuple_and_evidence_pass(self):
        self.assertEqual(self.run_gate().returncode, 0)

    def test_wrong_os_is_rejected(self):
        self.evidence['osMajor'] = '13'
        self.assertNotEqual(self.run_gate().returncode, 0)

    def test_wrong_host_is_rejected(self):
        self.evidence['host'] = 'Safari'
        self.assertNotEqual(self.run_gate().returncode, 0)

    def test_wrong_adapter_is_rejected(self):
        self.evidence['adapter'] = 'flutter'
        self.assertNotEqual(self.run_gate().returncode, 0)

    def test_wrong_artifact_is_rejected(self):
        self.evidence['artifactSHA256'] = 'b' * 64
        self.assertNotEqual(self.run_gate().returncode, 0)


if __name__ == '__main__':
    unittest.main()
