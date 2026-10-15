#!/usr/bin/env python3
"""Local model packaging tests use temporary bundles and stub compiler tools."""
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class LocalPatternPackagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="necaramba-model-package-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.resources = self.root / "build/Necaramba.app/Contents/Resources"
        self.resources.mkdir(parents=True)
        for relative in ["App/macos", "App/NecarambaLoginHelper", "Resources/Sounds", "Tools/Packaging", "bin"]:
            (self.root / relative).mkdir(parents=True, exist_ok=True)
        (self.root / "Resources/Sounds/correction.wav").write_bytes(b"fixture")
        (self.root / "App/NecarambaLoginHelper/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "test", "CFBundleExecutable": "test"}))
        for relative in ["bin/xcrun", "Tools/Packaging/stage-rule-resources.sh"]:
            script = self.root / relative
            script.write_text("#!/bin/bash\nexit 0\n")
            script.chmod(0o755)
        self.model = self.root / "input model.json"
        self.model.write_text('{"synthetic":true}')
        self.destination = self.resources / "LocalPatternModel.json"

    def embed(self, model=None, mode="YES"):
        env = dict(os.environ, SRCROOT=str(self.root / "App/macos"),
                   TARGET_BUILD_DIR=str(self.root / "build"),
                   UNLOCALIZED_RESOURCES_FOLDER_PATH="Necaramba.app/Contents/Resources",
                   CONTENTS_FOLDER_PATH="Necaramba.app/Contents", DERIVED_FILE_DIR=str(self.root / "derived"),
                   PRODUCT_BUNDLE_IDENTIFIER="test.necaramba", SDKROOT="unused", CODE_SIGNING_ALLOWED="NO",
                   NECARAMBA_DEVELOPMENT_RULES=mode, PATH=str(self.root / "bin") + ":" + os.environ["PATH"])
        env.pop("NECARAMBA_LOCAL_PATTERN_MODEL", None)
        if model is not None:
            env["NECARAMBA_LOCAL_PATTERN_MODEL"] = str(model)
        return subprocess.run(["bash", str(ROOT / "Tools/Packaging/embed-native-resources.sh")],
                              env=env, capture_output=True, text=True)

    def test_explicit_local_model_is_copied_only_in_development_mode(self):
        result = self.embed(self.model)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.destination.read_bytes(), self.model.read_bytes())
        self.assertNotEqual(self.embed(self.model, "NO").returncode, 0)

    def test_ordinary_build_removes_stale_owned_model(self):
        self.destination.write_text("stale")
        result = self.embed()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.destination.exists())

    def test_invalid_sources_fail(self):
        link = self.root / "link"
        link.symlink_to(self.model)
        huge = self.root / "huge"
        with huge.open("wb") as stream:
            stream.truncate(64 * 1024 * 1024 + 1)
        for source in [link, huge, self.root, self.root / "missing"]:
            with self.subTest(source=source.name):
                self.assertNotEqual(self.embed(source).returncode, 0)

    def test_public_artifact_verifier_rejects_local_model_including_dangling_link(self):
        for link in [False, True]:
            if link:
                self.destination.unlink()
                self.destination.symlink_to(self.root / "missing")
            else:
                self.destination.write_text("fixture")
            result = subprocess.run(["bash", str(ROOT / "Tools/Release/verify-artifact.sh"),
                                     str(self.resources.parent.parent)], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Local pattern model cannot be released", result.stderr)


if __name__ == "__main__":
    unittest.main()
