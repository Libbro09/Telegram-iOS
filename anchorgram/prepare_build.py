import json
import os
from pathlib import Path
import re


def prepare(root: Path, env) -> None:
    api_id = env.get('TELEGRAM_API_ID', '').strip()
    api_hash = env.get('TELEGRAM_API_HASH', '').strip()
    team_id = env.get('APPLE_TEAM_ID', '').strip()
    bundle_id = (env.get('ANCHORGRAM_BUNDLE_ID') or 'org.libbro09.anchorgram').strip()
    app_group_id = (env.get('APPLE_APP_GROUP') or 'group.' + bundle_id).strip()
    if not re.fullmatch(r'[1-9][0-9]{0,9}', api_id) or int(api_id) > 2147483647:
        raise ValueError('Add TELEGRAM_API_ID in repository Actions secrets.')
    if not re.fullmatch(r'[0-9a-fA-F]{32}', api_hash):
        raise ValueError('Add TELEGRAM_API_HASH in repository Actions secrets.')
    if not re.fullmatch(r'[A-Z0-9]{10}', team_id):
        raise ValueError('Add APPLE_TEAM_ID in repository Actions variables (10 letters/digits from your certificate).')
    if not re.fullmatch(r'[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)+', bundle_id):
        raise ValueError('Invalid ANCHORGRAM_BUNDLE_ID')
    if not re.fullmatch(r'group\.[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)+', app_group_id):
        raise ValueError('Invalid APPLE_APP_GROUP')

    config = json.loads((root / 'build-system/template_minimal_development_configuration.json').read_text(encoding='utf-8'))
    config.update({
        'bundle_id': bundle_id,
        'app_group_id': app_group_id,
        'api_id': api_id,
        'api_hash': api_hash,
        'team_id': team_id,
        'app_specific_url_scheme': 'anchorgram',
        'is_internal_build': 'false',
        'is_appstore_build': 'false',
    })
    target = root / 'build-input/anchorgram-configuration.json'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(config, indent=2) + '\n', encoding='utf-8')
    target.chmod(0o600)

    rc = root / '.bazelrc'
    text = rc.read_text(encoding='utf-8')
    marker = '# AnchorGram unsigned device build'
    if marker not in text:
        rc.write_text(text + '\n' + marker + '\n'
                      'build --//Telegram:disableProvisioningProfiles\n'
                      'build --//Telegram:disableExtensions\n'
                      'build --features=disable_legacy_signing\n'
                      'build --jobs=3\n', encoding='utf-8')
    print('Unsigned release configuration prepared. API credentials are not printed.')


if __name__ == '__main__':
    prepare(Path(__file__).resolve().parents[1], os.environ)
