#!/usr/bin/env python3
"""Exercise the production package gate with temporary, ephemeral signatures."""
import json
import os
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
CORE = ROOT / 'Sources/NecarambaCore'
FORMAT = [CORE / 'Types/InputTypes.swift', CORE / 'Types/RuleTypes.swift', CORE / 'Delivery/RuleManifest.swift']
VERIFIER = CORE / 'Delivery/RulePackageVerifier.swift'
TOOL = ROOT / 'Tools/Release/ValidateProductionRulePackage.swift'
FIXTURE = r'''
import Foundation
import CryptoKit
@main struct Fixture {
    static func main() throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let keyID = CommandLine.arguments[2]
        let key = Curve25519.Signing.PrivateKey()
        let rules = RuleSnapshot(modelVersion: 3,
            lexicon: [.init(word: "hello", language: .english, frequencyBand: 1),
                      .init(word: "привет", language: .russian, frequencyBand: 1)],
            mappings: [.init(source: .init(rawValue: "US"), target: .init(rawValue: "RU"), pairs: ["f": "а"]),
                       .init(source: .init(rawValue: "RU"), target: .init(rawValue: "US"), pairs: ["а": "f"])])
        let payload = try JSONEncoder().encode(rules)
        let digest = Data(SHA256.hash(data: payload))
        let manifest = try canonicalManifest(.init(schemaVersion: 1, modelVersion: 3,
            minimumAppVersion: "1.0.0", payloadSize: UInt64(payload.count),
            payloadSHA256: digest.map { String(format: "%02x", $0) }.joined(), keyID: keyID))
        let signature = try key.signature(for: Data("NecarambaRules-v1\0".utf8) + manifest + Data([0]) + digest)
        try payload.write(to: folder.appendingPathComponent("payload.json"))
        try manifest.write(to: folder.appendingPathComponent("manifest.json"))
        try signature.write(to: folder.appendingPathComponent("signature.ed25519"))
        let keys = try JSONSerialization.data(withJSONObject: [keyID: key.publicKey.rawRepresentation.base64EncodedString()], options: [.sortedKeys, .withoutEscapingSlashes])
        try keys.write(to: folder.appendingPathComponent("TrustedRuleKeys.json"))
        let licenses = folder.appendingPathComponent("Licenses", isDirectory: true)
        try FileManager.default.createDirectory(at: licenses, withIntermediateDirectories: true)
        try Data("Synthetic test attribution\n".utf8).write(to: licenses.appendingPathComponent("attribution.txt"))
    }
}
'''


def run(argv, success, env=None):
    p = subprocess.run(argv, cwd=ROOT, capture_output=True, text=True, env=env)
    assert (p.returncode == 0) == success, (argv, p.returncode, p.stdout, p.stderr)


with tempfile.TemporaryDirectory(prefix='necaramba-release-test-') as tmp:
    temp = pathlib.Path(tmp)
    fixture_source = temp / 'Fixture.swift'
    fixture_source.write_text(FIXTURE)
    fixture = temp / 'fixture'
    validator = temp / 'validator'
    run(['swiftc', *map(str, FORMAT), str(fixture_source), '-o', str(fixture)], True)
    run(['swiftc', *map(str, FORMAT), str(VERIFIER), str(TOOL), '-o', str(validator)], True)
    package = temp / 'package'
    package.mkdir()
    run([str(validator), str(package), '1.0.0', str(ROOT / 'App/macos/Runner/Release/BundledRules/Development/DevelopmentTrustedRuleKeys.json')], False)
    run([str(fixture), str(package), 'owner-key'], True)
    run([str(validator), str(package), '1.0.0', str(ROOT / 'App/macos/Runner/Release/BundledRules/Development/DevelopmentTrustedRuleKeys.json')], True)
    resources = temp / 'Resources'
    (resources / 'Rules/Development').mkdir(parents=True)
    (resources / 'Rules/Development/DevelopmentOnly.json').write_text('{}')
    stage = ROOT / 'Tools/Packaging/stage-rule-resources.sh'
    production_env = dict(os.environ, NECARAMBA_PRODUCTION_RULES_DIR=str(package),
        NECARAMBA_TEAM_ID='OWNTEAM', NECARAMBA_BUNDLE_ID='own.necaramba.app',
        PRODUCT_BUNDLE_IDENTIFIER='own.necaramba.app')
    run(['bash', str(stage), str(ROOT), str(resources), 'NO', '1.0.0', str(validator)], True, production_env)
    assert not (resources / 'Rules/Development').exists()
    assert (resources / 'Rules/Production/payload.json').read_bytes() == (package / 'payload.json').read_bytes()
    run(['bash', str(stage), str(ROOT), str(resources), 'YES', '1.0.0', str(validator)], True, production_env)
    assert not (resources / 'Rules/Production').exists()
    assert (resources / 'Rules/Development/DevelopmentOnly.json').exists()
    payload = package / 'payload.json'
    good = payload.read_bytes()
    payload.write_bytes(good + b' ')
    run([str(validator), str(package), '1.0.0', str(ROOT / 'App/macos/Runner/Release/BundledRules/Development/DevelopmentTrustedRuleKeys.json')], False)
    payload.write_bytes(good)
    (package / 'DevelopmentOnly.json').write_text('{}')
    run([str(validator), str(package), '1.0.0', str(ROOT / 'App/macos/Runner/Release/BundledRules/Development/DevelopmentTrustedRuleKeys.json')], False)
    (package / 'DevelopmentOnly.json').unlink()
    (package / 'Licenses/attribution.txt').unlink()
    run([str(validator), str(package), '1.0.0', str(ROOT / 'App/macos/Runner/Release/BundledRules/Development/DevelopmentTrustedRuleKeys.json')], False)
    (package / 'Licenses/attribution.txt').write_text('Synthetic test attribution\n')
    run([str(fixture), str(package), 'development-only'], True)
    run([str(validator), str(package), '1.0.0', str(ROOT / 'App/macos/Runner/Release/BundledRules/Development/DevelopmentTrustedRuleKeys.json')], False)
    run([str(fixture), str(package), 'owner-key'], True)
    development_keys = json.loads((ROOT / 'App/macos/Runner/Release/BundledRules/Development/DevelopmentTrustedRuleKeys.json').read_text())
    (package / 'TrustedRuleKeys.json').write_text(json.dumps({'owner-key': next(iter(development_keys.values()))}, separators=(',', ':')))
    run([str(validator), str(package), '1.0.0', str(ROOT / 'App/macos/Runner/Release/BundledRules/Development/DevelopmentTrustedRuleKeys.json')], False)
    run(['bash', str(stage), str(ROOT), str(resources), 'NO', '1.0.0', str(validator)], False,
        dict(production_env, NECARAMBA_TEAM_ID=''))

print('production package gate PASS')
