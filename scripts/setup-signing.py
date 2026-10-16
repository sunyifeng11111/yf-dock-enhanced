#!/usr/bin/env python3
"""Create one persistent local signing identity; never rotate it implicitly."""
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess


def signing_directory():
    override = os.environ.get('DOCK_ENHANCED_SIGNING_DIR')
    return Path(override).expanduser().resolve() if override else Path.home() / 'Library/Application Support/Dock Enhanced/Signing'


def run(arguments, **kwargs):
    return subprocess.run(arguments, check=True, capture_output=True, text=True, **kwargs).stdout


def setup():
    directory = signing_directory()
    config = directory / 'identity.json'
    if config.exists():
        identity = json.loads(config.read_text())
        if not all((directory / name).exists() for name in ('private-key.pem', 'certificate.pem', 'identity.p12', 'keychain-password')) or not Path(identity['keychain']).exists():
            raise SystemExit('Signing identity is incomplete. Restore its backup; do not create a replacement identity for existing releases.')
        print('Using the existing signing identity. No new certificate was created.')
        return
    if directory.exists() and any(directory.iterdir()):
        raise SystemExit('Signing directory already contains files. Restore or inspect it before continuing; refusing to replace an identity.')
    directory.mkdir(parents=True, mode=0o700, exist_ok=True)
    os.chmod(directory, 0o700)
    os.umask(0o077)
    openssl = shutil.which('openssl')
    if not openssl:
        raise SystemExit('OpenSSL is required to create a local signing certificate.')
    password = secrets.token_urlsafe(32)
    (directory / 'keychain-password').write_text(password)
    configuration = directory / 'certificate.cnf'
    configuration.write_text('[req]\ndistinguished_name=dn\nx509_extensions=extensions\nprompt=no\n[dn]\nCN=Dock Enhanced Release Signing\n[extensions]\nbasicConstraints=critical,CA:false\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\nsubjectKeyIdentifier=hash\n')
    run([openssl, 'req', '-new', '-newkey', 'rsa:3072', '-x509', '-sha256', '-days', '3650', '-nodes', '-config', str(configuration), '-keyout', str(directory / 'private-key.pem'), '-out', str(directory / 'certificate.pem')])
    run([openssl, 'pkcs12', '-export', '-inkey', str(directory / 'private-key.pem'), '-in', str(directory / 'certificate.pem'), '-out', str(directory / 'identity.p12'), '-keypbe', 'PBE-SHA1-3DES', '-certpbe', 'PBE-SHA1-3DES', '-macalg', 'sha1', '-passout', 'stdin'], input=password + '\n')
    keychain = directory / 'release.keychain-db'
    run(['security', 'create-keychain', '-p', password, str(keychain)])
    run(['security', 'set-keychain-settings', '-lut', '7200', str(keychain)])
    run(['security', 'unlock-keychain', '-p', password, str(keychain)])
    run(['security', 'import', str(directory / 'identity.p12'), '-k', str(keychain), '-P', password, '-T', '/usr/bin/codesign'])
    run(['security', 'set-key-partition-list', '-S', 'apple-tool:,apple:', '-s', '-k', password, str(keychain)])
    fingerprint = run([openssl, 'x509', '-in', str(directory / 'certificate.pem'), '-noout', '-fingerprint', '-sha1']).strip().split('=')[-1].replace(':', '')
    config.write_text(json.dumps({'identity': fingerprint, 'keychain': str(keychain)}, indent=2) + '\n')
    print('Created a persistent self-signed identity outside the source repository. Back up the entire signing directory privately.')
    print('No system certificate trust settings were changed.')


if __name__ == '__main__':
    try:
        setup()
    except subprocess.CalledProcessError as error:
        # Arguments can contain keychain passwords; never echo the command.
        raise SystemExit('Signing setup failed. Private files were retained for inspection; no automatic retry or identity rotation was performed.') from None
