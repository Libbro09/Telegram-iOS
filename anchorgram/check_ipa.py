import plistlib
from pathlib import Path
import struct
import sys
import zipfile


def check(path: Path) -> None:
    with zipfile.ZipFile(path) as archive:
        info = plistlib.loads(archive.read('Payload/Telegram.app/Info.plist'))
        if info.get('CFBundleDisplayName') != 'AnchorGram':
            raise ValueError(f"Unexpected app display name: {info.get('CFBundleDisplayName')!r}; expected 'AnchorGram'")
        if info.get('CFBundleIdentifier') != 'org.libbro09.anchorgram':
            raise ValueError('Unexpected bundle id')
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
    check(Path(sys.argv[1]))
