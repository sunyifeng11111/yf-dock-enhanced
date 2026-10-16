#!/usr/bin/env python3
"""Sign with the persistent local identity, with no ad hoc fallback."""
import json
from pathlib import Path
import subprocess
import sys
from importlib.util import module_from_spec, spec_from_file_location

spec = spec_from_file_location('setup_signing', Path(__file__).with_name('setup-signing.py'))
setup_signing = module_from_spec(spec)
spec.loader.exec_module(setup_signing)
directory = setup_signing.signing_directory()
config = directory / 'identity.json'
if not config.exists():
    raise SystemExit('No fixed signing identity. Run python3 scripts/setup-signing.py once, then privately back up the signing directory.')
identity = json.loads(config.read_text())
password = (directory / 'keychain-password').read_text()
try:
    setup_signing.run(['security', 'unlock-keychain', '-p', password, identity['keychain']])
except subprocess.CalledProcessError:
    raise SystemExit('Cannot unlock the fixed signing keychain. Restore its credentials; refusing to fall back to ad hoc signing.') from None
app = Path(sys.argv[1]).resolve()
subprocess.run(['codesign', '--force', '--sign', identity['identity'], '--keychain', identity['keychain'], '--timestamp=none', '--identifier', 'dev.yifeng.DockEnhanced', str(app)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
