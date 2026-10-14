#!/usr/bin/env python3
"""Resolve real Xcode signing settings in a temporary project; never build/sign.

Flutter's generated package is stubbed because only build settings are inspected.
No installed app, keychain, local signing file or TCC database is modified.
"""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class LocalSigningTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="necaramba-signing-")
        cls.root = Path(cls.temp.name)
        cls.macos = cls.root / "App/macos"
        shutil.copytree(ROOT / "App/macos", cls.macos,
                        ignore=shutil.ignore_patterns("ephemeral", "LocalSigning.xcconfig", "xcuserdata"))
        for name in ("Package.swift", "Sources", "Tools", "Tests"):
            (cls.root / name).symlink_to(ROOT / name)
        generated = cls.macos / "Flutter/ephemeral"
        package = generated / "Packages/FlutterGeneratedPluginSwiftPackage"
        source = package / "Sources/FlutterGeneratedPluginSwiftPackage"
        source.mkdir(parents=True)
        (source / "Placeholder.swift").write_text("// Build-settings fixture only.\n")
        (package / "Package.swift").write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "FlutterGeneratedPluginSwiftPackage",
    products: [.library(name: "FlutterGeneratedPluginSwiftPackage", targets: ["FlutterGeneratedPluginSwiftPackage"])],
    targets: [.target(name: "FlutterGeneratedPluginSwiftPackage")])
''')
        (generated / "Flutter-Generated.xcconfig").write_text("// Build-settings fixture only.\n")
        cls.local = cls.macos / "Runner/Configs/LocalSigning.xcconfig"

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def tearDown(self):
        self.local.unlink(missing_ok=True)

    def settings(self, config, target="Runner", *overrides):
        result = subprocess.run([
            "xcodebuild", "-project", str(self.macos / "Runner.xcodeproj"),
            "-target", target, "-configuration", config, "-showBuildSettings", "-json", *overrides,
        ], text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return next(item["buildSettings"] for item in json.loads(result.stdout)
                    if item["target"] == target)

    def test_debug_profile_have_separate_permission_identity(self):
        for config, suffix in (("Debug", "debug"), ("Profile", "profile")):
            with self.subTest(config=config):
                settings = self.settings(config)
                self.assertEqual(settings["PRODUCT_BUNDLE_IDENTIFIER"], f"local.necaramba.app.{suffix}")
                self.assertEqual(settings.get("NECARAMBA_DISPLAY_NAME"), f"Necaramba {config}")
                self.assertEqual(settings["PRODUCT_NAME"], "Necaramba")
                self.assertEqual(settings["PRODUCT_MODULE_NAME"], "Necaramba")
        host = self.settings("Debug", "RunnerTests")
        self.assertTrue(host["TEST_HOST"].endswith("/Necaramba.app/Contents/MacOS/Necaramba"))

    def test_release_without_local_file_remains_portable(self):
        settings = self.settings("Release")
        self.assertEqual(settings["PRODUCT_BUNDLE_IDENTIFIER"], "local.necaramba.app")
        self.assertEqual(settings.get("NECARAMBA_DISPLAY_NAME"), "Necaramba")
        self.assertEqual(settings["CODE_SIGN_IDENTITY"], "-")

    def test_local_identity_applies_only_to_release_and_cli_can_override(self):
        self.local.write_text("CODE_SIGN_IDENTITY = LOCAL_TEST_CERTIFICATE\n"
                              "DEVELOPMENT_TEAM = LOCAL_TEST_TEAM\n"
                              "CODE_SIGN_STYLE = Manual\n")
        release = self.settings("Release")
        self.assertEqual(release["CODE_SIGN_IDENTITY"], "LOCAL_TEST_CERTIFICATE")
        self.assertEqual(release["DEVELOPMENT_TEAM"], "LOCAL_TEST_TEAM")
        self.assertEqual(release["CODE_SIGN_STYLE"], "Manual")
        for config, identity in (("Debug", "-"), ("Profile", "-"),
                                 ("DeveloperID", "Developer ID Application"), ("MAS", "Apple Distribution")):
            with self.subTest(config=config):
                settings = self.settings(config, "Runner", "NECARAMBA_TEAM_ID=DISTRIBUTION_TEAM",
                                         "NECARAMBA_BUNDLE_ID=example.release")
                self.assertEqual(settings["CODE_SIGN_IDENTITY"], identity)
                self.assertNotEqual(settings.get("DEVELOPMENT_TEAM"), "LOCAL_TEST_TEAM")
                if config in ("DeveloperID", "MAS"):
                    self.assertEqual(settings["DEVELOPMENT_TEAM"], "DISTRIBUTION_TEAM")
                    self.assertEqual(settings["PRODUCT_BUNDLE_IDENTIFIER"], "example.release")
        override = self.settings("Release", "Runner", "CODE_SIGN_IDENTITY=EXPLICIT_CERTIFICATE")
        self.assertEqual(override["CODE_SIGN_IDENTITY"], "EXPLICIT_CERTIFICATE")


if __name__ == "__main__":
    unittest.main(verbosity=2)
