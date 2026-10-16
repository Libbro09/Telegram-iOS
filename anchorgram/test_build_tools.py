import contextlib
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import struct
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
    def test_configuration_validated_and_not_logged(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'build-system').mkdir()
            (root / 'build-system/template_minimal_development_configuration.json').write_text('{}', encoding='utf-8')
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


if __name__ == '__main__':
    unittest.main()
