from pathlib import Path
import subprocess


def apply_patch(root: Path) -> None:
    rules = root / 'build-system/bazel-rules/rules_apple'
    patch = root / 'anchorgram/unsigned-device.patch'
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=rules, text=True).strip()
    if revision != '485016eb5b0948cc17307064e7977a6d68e94046':
        raise RuntimeError('rules_apple revision changed: review unsigned-device.patch before building')
    command = ['git', 'apply', '--check', str(patch.resolve())]
    result = subprocess.run(command, cwd=rules, capture_output=True)
    if result.returncode:
        reverse = subprocess.run(['git', 'apply', '--reverse', '--check', str(patch.resolve())], cwd=rules, capture_output=True)
        if reverse.returncode:
            raise RuntimeError('Unsigned device patch does not match the pinned rules_apple sources')
        print('Unsigned archive rules already prepared.')
        return
    subprocess.run(['git', 'apply', str(patch.resolve())], cwd=rules, check=True)
    print('Unsigned archive rules prepared; normal signed builds retain profile validation.')


if __name__ == '__main__':
    apply_patch(Path(__file__).resolve().parents[1])
