import plistlib
import argparse
import json
from pathlib import Path
import struct
import sys
import zipfile


def check(path: Path, expected_bundle_id: str = 'org.libbro09.anchorgram', expected_app_group: str | None = None, expected_version: str | None = None) -> None:
    with zipfile.ZipFile(path) as archive:
        info = plistlib.loads(archive.read('Payload/Telegram.app/Info.plist'))
        if info.get('CFBundleDisplayName') != 'AnchorGram':
            raise ValueError(f"Unexpected app display name: {info.get('CFBundleDisplayName')!r}; expected 'AnchorGram'")
        if expected_version is not None and info.get('CFBundleShortVersionString') != expected_version:
            raise ValueError('Unexpected application version; possible stale IPA')
        if info.get('CFBundleIdentifier') != expected_bundle_id:
            raise ValueError('Unexpected bundle id')
        if expected_app_group is not None and info.get('AnchorGramAppGroup') != expected_app_group:
            raise ValueError('Unexpected configured App Group')
        executable = archive.read('Payload/Telegram.app/' + info['CFBundleExecutable'])
        magic, cpu = struct.unpack_from('<II', executable)
        if magic != 0xFEEDFACF or cpu != 0x0100000C:
            raise ValueError('Expected thin arm64 device executable')
        commands, = struct.unpack_from('<I', executable, 16)
        offset = 32
        platform = None
        for _ in range(commands):
            command, size = struct.unpack_from('<II', executable, offset)
            if size < 8 or offset + size > len(executable):
                raise ValueError('Invalid Mach-O load commands')
            if command == 0x32:
                platform, = struct.unpack_from('<I', executable, offset + 8)
            offset += size
        if platform != 2:
            raise ValueError('Expected iOS device platform, not simulator')
        if any(name.startswith('Payload/Telegram.app/PlugIns/') for name in archive.namelist()):
            raise ValueError('Unexpected extensions in standalone build')
    print('IPA verified: AnchorGram, expected bundle id, iOS device arm64, no extensions.')
    print('Unsigned artifact: installation still requires valid signing and compatible entitlements.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('ipa', type=Path)
    parser.add_argument('--configuration', type=Path)
    parser.add_argument('--expected-version')
    args = parser.parse_args()
    configuration = json.loads(args.configuration.read_text(encoding='utf-8')) if args.configuration else {}
    check(args.ipa, configuration.get('bundle_id', 'org.libbro09.anchorgram'), configuration.get('app_group_id'), args.expected_version)
