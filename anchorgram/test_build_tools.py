import contextlib
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import re
import struct
import sys
import tempfile
import unittest
import zipfile


def load(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


prepare = load('prepare_build').prepare
check = load('check_ipa').check


class BuildToolsTests(unittest.TestCase):
    def test_main_application_display_name(self):
        root = Path(__file__).resolve().parents[1]
        build = (root / 'Telegram/BUILD').read_text(encoding='utf-8')
        match = re.search(r'plist_fragment\(\s*name\s*=\s*"TelegramInfoPlist",.*?template\s*=\s*"""(.*?)"""', build, re.S)
        self.assertIsNotNone(match, 'Main app plist template was not found')
        info = plistlib.loads(('<plist><dict>' + match.group(1) + '</dict></plist>').encode('utf-8'))
        self.assertEqual(info['CFBundleDisplayName'], 'AnchorGram', 'Rename the main app, not only extension plist fragments')

    def test_configuration_validated_and_not_logged(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'build-system').mkdir()
            template = Path(__file__).resolve().parents[1] / 'build-system/template_minimal_development_configuration.json'
            (root / 'build-system/template_minimal_development_configuration.json').write_bytes(template.read_bytes())
            (root / '.bazelrc').write_text('build --existing\n', encoding='utf-8')
            env = {'TELEGRAM_API_ID': '123456', 'TELEGRAM_API_HASH': 'a' * 32, 'APPLE_TEAM_ID': 'ABCD123456'}
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                prepare(root, env)
                prepare(root, env)
            config = json.loads((root / 'build-input/anchorgram-configuration.json').read_text(encoding='utf-8'))
            self.assertEqual(config['api_id'], '123456')
            self.assertEqual(config['bundle_id'], 'org.libbro09.anchorgram')
            self.assertNotIn(env['TELEGRAM_API_HASH'], output.getvalue())
            self.assertEqual((root / '.bazelrc').read_text(encoding='utf-8').count('build --jobs=3'), 1)
            for key, value in [('TELEGRAM_API_ID', '2147483648'), ('TELEGRAM_API_HASH', 'bad'), ('APPLE_TEAM_ID', 'bad')]:
                with self.assertRaises(ValueError):
                    prepare(root, dict(env, **{key: value}))
            custom = dict(env, ANCHORGRAM_BUNDLE_ID='app.example.anchorgram', APPLE_APP_GROUP='group.example.1')
            with contextlib.redirect_stdout(output):
                prepare(root, custom)
            config = json.loads((root / 'build-input/anchorgram-configuration.json').read_text(encoding='utf-8'))
            self.assertEqual(config['bundle_id'], 'app.example.anchorgram')
            self.assertEqual(config['app_group_id'], 'group.example.1')
            sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'build-system/Make'))
            try:
                from BuildConfiguration import build_configuration_from_json
                resolved = build_configuration_from_json(str(root / 'build-input/anchorgram-configuration.json'))
                variables = root / 'variables.bzl'
                resolved.write_to_variables_file('/test/bazel', True, '', str(variables))
                self.assertIn('telegram_app_group_id = "group.example.1"', variables.read_text(encoding='utf-8'))
                self.assertIn('telegram_bundle_id = "app.example.anchorgram"', variables.read_text(encoding='utf-8'))
            finally:
                sys.path.pop(0)
            for key, value in [('ANCHORGRAM_BUNDLE_ID', 'app.*'), ('APPLE_APP_GROUP', 'not-a-group')]:
                with self.assertRaises(ValueError):
                    prepare(root, dict(env, **{key: value}))

    def test_device_artifact_and_simulator_rejection(self):
        for platform in [2, 7]:
            with self.subTest(platform=platform), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / 'test.ipa'
                executable = struct.pack('<IIIIIIII', 0xFEEDFACF, 0x0100000C, 0, 2, 1, 24, 0, 0)
                executable += struct.pack('<IIIIII', 0x32, 24, platform, 0, 0, 0)
                info = {'CFBundleDisplayName': 'AnchorGram', 'CFBundleIdentifier': 'org.libbro09.anchorgram', 'CFBundleExecutable': 'Telegram'}
                with zipfile.ZipFile(path, 'w') as archive:
                    archive.writestr('Payload/Telegram.app/Info.plist', plistlib.dumps(info))
                    archive.writestr('Payload/Telegram.app/Telegram', executable)
                if platform == 7:
                    with self.assertRaises(ValueError):
                        check(path)
                else:
                    with contextlib.redirect_stdout(io.StringIO()):
                        check(path)

    def test_custom_profile_bundle_and_app_group(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'test.ipa'
            executable = struct.pack('<IIIIIIII', 0xFEEDFACF, 0x0100000C, 0, 2, 1, 24, 0, 0)
            executable += struct.pack('<IIIIII', 0x32, 24, 2, 0, 0, 0)
            info = {'CFBundleDisplayName': 'AnchorGram', 'CFBundleIdentifier': 'app.example.anchorgram', 'CFBundleExecutable': 'Telegram', 'AnchorGramAppGroup': 'group.example.1'}
            with zipfile.ZipFile(path, 'w') as archive:
                archive.writestr('Payload/Telegram.app/Info.plist', plistlib.dumps(info))
                archive.writestr('Payload/Telegram.app/Telegram', executable)
            with contextlib.redirect_stdout(io.StringIO()):
                check(path, 'app.example.anchorgram', 'group.example.1')
            with self.assertRaises(ValueError):
                check(path, 'app.example.anchorgram', 'group.other.1')

    def test_profile_rejects_incompatible_identity(self):
        check_profile = load('check_profile').check_profile
        profile = {'TeamIdentifier': ['ABCD123456'], 'Entitlements': {
            'application-identifier': 'ABCD123456.app.example.anchorgram',
            'com.apple.security.application-groups': ['group.example.1'],
            'keychain-access-groups': ['ABCD123456.*'],
        }}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'profile.mobileprovision'
            path.write_bytes(b'CMS' + plistlib.dumps(profile) + b'END')
            with contextlib.redirect_stdout(io.StringIO()):
                check_profile(path, 'ABCD123456', 'app.example.anchorgram', 'group.example.1')
            for team, bundle, group in [('ABCD123456', 'org.libbro09.anchorgram', 'group.example.1'), ('ABCD123456', 'app.example.anchorgram', 'group.not-permitted.1'), ('OTHER12345', 'app.example.anchorgram', 'group.example.1')]:
                with self.assertRaises(ValueError):
                    check_profile(path, team, bundle, group)


if __name__ == '__main__':
    unittest.main()
