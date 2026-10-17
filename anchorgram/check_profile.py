import fnmatch
from pathlib import Path
import plistlib


def check_profile(path: Path, team: str, bundle: str, app_group: str) -> None:
    content = path.read_bytes()
    start = content.find(b'<?xml')
    end = content.find(b'</plist>', start)
    if start < 0 or end < 0:
        raise ValueError('Provisioning profile XML was not found')
    profile = plistlib.loads(content[start:end + 8])
    entitlements = profile.get('Entitlements', {})
    if team not in profile.get('TeamIdentifier', []):
        raise ValueError('Team does not match the provisioning profile')
    identifier = team + '.' + bundle
    if not fnmatch.fnmatchcase(identifier, entitlements.get('application-identifier', '')):
        raise ValueError('Bundle identifier is not permitted by this profile')
    if app_group not in entitlements.get('com.apple.security.application-groups', []):
        raise ValueError('App Group is not permitted by this profile')
    if not any(fnmatch.fnmatchcase(identifier, group) for group in entitlements.get('keychain-access-groups', [])):
        raise ValueError('Private Keychain group is not permitted by this profile')
    print('Profile permissions match the configured bundle, App Group and Keychain group.')
