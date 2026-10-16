#!/usr/bin/env python3
"""Generate and authenticate a stable release's feed; never publishes it."""
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
from importlib.util import module_from_spec, spec_from_file_location

root = Path(__file__).resolve().parent.parent
spec = spec_from_file_location('setup_signing', root / 'scripts/setup-signing.py')
setup = module_from_spec(spec)
spec.loader.exec_module(setup)
parser = argparse.ArgumentParser()
parser.add_argument('archive', type=Path)
args = parser.parse_args()
archive = args.archive.resolve()
config = json.loads((root / 'updates/config.json').read_text())
info = plistlib.loads((root / 'dist/Dock Enhanced.app/Contents/Info.plist').read_bytes())
version = info['CFBundleShortVersionString']
if any(c not in '0123456789.' for c in version):
    raise SystemExit('Only stable numeric versions can enter the stable feed.')
if version not in archive.name or not archive.is_file():
    raise SystemExit('Archive does not match the bundled version.')
key = setup.signing_directory() / 'sparkle-update-private-key'
if not key.is_file():
    raise SystemExit('Restore the persistent Sparkle signing key before preparing a release. Never generate a fresh key for an existing update feed.')
tools = root / '.build/artifacts/sparkle/Sparkle/bin'
staging = root / 'dist/appcast'
if staging.exists():
    raise SystemExit('dist/appcast already exists; move the previous prepared feed aside before generating another one.')
staging.mkdir()
shutil.copy2(archive, staging / archive.name)
subprocess.run([str(tools / 'generate_appcast'), '--ed-key-file', str(key), '--download-url-prefix', f"https://github.com/{config['releaseRepository']}/releases/download/v{version}/", '--maximum-deltas', '0', '--link', f"https://github.com/{config['releaseRepository']}/releases", str(staging)], check=True)
feed = staging / 'appcast.xml'
subprocess.run([str(tools / 'sign_update'), '--ed-key-file', str(key), '--verify', str(feed)], check=True)
shutil.copy2(feed, root / 'updates/appcast.xml')
print('Prepared signed appcast. Upload the matching archive before publishing this feed.')
