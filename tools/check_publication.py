"""Validate publishable source/evidence without installing or changing drivers."""
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SKIP = {'.git', '.cache', 'build', 'local-recovery', '__pycache__'}
FORBIDDEN = {'.pfx', '.password', '.sys', '.dll', '.cat', '.exe', '.bin', '.nupkg', '.zip', '.pyc'}


def check():
    git = subprocess.run(['git', 'ls-files', '--cached', '--others', '--exclude-standard'], cwd=ROOT, capture_output=True, text=True, check=True)
    paths = [ROOT / name for name in git.stdout.splitlines()]
    inspected = 0
    for path in paths:
        if set(path.relative_to(ROOT).parts) & SKIP:
            continue
        if path.suffix.lower() in FORBIDDEN or path.name == 'signing.password':
            raise ValueError(f'Binary/private material in publication: {path.relative_to(ROOT)}')
        text = path.read_text(encoding='utf-8-sig')
        if re.search(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----\r?\n[A-Za-z0-9+/]{16,}', text):
            raise ValueError(f'Private key found: {path.relative_to(ROOT)}')
        if re.search(r'(?i)C:[\\/]Users[\\/][A-Za-z0-9_~-]+[\\/]', text):
            raise ValueError(f'Local user-profile path found: {path.relative_to(ROOT)}')
        if path.suffix.lower() == '.json':
            json.loads(text)
        if path.suffix.lower() == '.yml':
            for action in re.findall(r'uses:\s*(\S+)', text):
                if not re.fullmatch(r'[\w.-]+/[\w./-]+@[0-9a-f]{40}', action):
                    raise ValueError(f'Action must use an immutable commit: {action}')
        inspected += 1
    manifest = json.loads((ROOT / 'drivers/apu/manifests/asus-32.0.21043.21001-config.json').read_text())
    if manifest['variant'] != 'configuration-only' or 'patch' in manifest:
        raise ValueError('Default APU manifest must not patch an executable.')
    if manifest['kernel_sha256'] != 'ae975bbb56282be1471b9a91407f0155c087b619f99d2731d4e7989720522152':
        raise ValueError('Unexpected original ASUS kernel.')
    print(f'Publication checks passed for {inspected} source/evidence files.')


if __name__ == '__main__':
    check()
