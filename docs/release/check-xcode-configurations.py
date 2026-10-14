#!/usr/bin/env python3
"""Check that both distribution configurations are complete Xcode targets."""
import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[2]
project_file = root / 'App/macos/Runner.xcodeproj/project.pbxproj'
objects = json.loads(subprocess.check_output([
    'plutil', '-convert', 'json', '-o', '-', str(project_file)
]))['objects']

for target in objects.values():
    if target.get('isa') not in ('PBXProject', 'PBXNativeTarget', 'PBXAggregateTarget'):
        continue
    configurations = objects[target['buildConfigurationList']]['buildConfigurations']
    names = [objects[key]['name'] for key in configurations]
    assert names.count('DeveloperID') == names.count('MAS') == 1, (target.get('name'), names)
    for key in configurations:
        configuration = objects[key]
        name = configuration['name']
        if name not in ('DeveloperID', 'MAS'):
            continue
        settings = configuration['buildSettings']
        assert settings['FLUTTER_BUILD_MODE'] == 'release', (name, target.get('name'))
        if target.get('name') == 'Runner':
            config_file = objects[configuration['baseConfigurationReference']]['path']
            assert config_file == f'{name}.xcconfig', (name, config_file)
            assert settings['CODE_SIGN_ENTITLEMENTS'] == f'Runner/Release/{name}.entitlements'
            assert settings['CODE_SIGN_STYLE'] == 'Manual'
        elif target.get('isa') == 'PBXProject':
            assert settings['CODE_SIGN_IDENTITY'] == {
                'DeveloperID': 'Developer ID Application', 'MAS': 'Apple Distribution'
            }[name]

for name in ('DeveloperID', 'MAS'):
    config = (root / f'App/macos/Runner/Release/{name}.xcconfig').read_text()
    assert '#include "../Configs/AppInfo.xcconfig"' in config
    assert '#include "../Configs/Release.xcconfig"' in config
    assert 'NECARAMBA_DEVELOPMENT_RULES = NO' in config
    assert 'ARCHS = arm64 x86_64' in config
    assert 'ONLY_ACTIVE_ARCH = NO' in config
    assert 'MACOSX_DEPLOYMENT_TARGET = 12.0' in config
    assert 'ENABLE_HARDENED_RUNTIME = YES' in config

print('DeveloperID/MAS configuration invariants PASS')
