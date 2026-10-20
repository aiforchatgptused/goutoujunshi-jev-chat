#!/usr/bin/env python3
"""Attach ad-hoc signature entitlement metadata for third-party re-signers.
This is NOT an installable distribution signature or a provisioning grant.
"""
import plistlib
import subprocess
import sys
import tempfile
from pathlib import Path

app = Path(sys.argv[1])
for bundle in [*sorted((app / 'PlugIns').glob('*.appex')), app]:
    info = plistlib.loads((bundle / 'Info.plist').read_bytes())
    group = info['GoutouAppGroup']
    if not group.startswith('group.') or '$(' in group:
        raise ValueError(f'Unresolved App Group in {bundle.name}')
    # Unsigned builds have no AppIdentifierPrefix. Do not seed an invalid keychain group.
    # The app can use the protected shared container if the signer supplies no shared keychain group.
    entitlements = {'com.apple.security.application-groups': [group]}
    with tempfile.NamedTemporaryFile(suffix='.plist') as handle:
        handle.write(plistlib.dumps(entitlements))
        handle.flush()
        subprocess.run(['codesign', '--force', '--sign', '-', '--entitlements', handle.name,
                        '--generate-entitlement-der', str(bundle)], check=True)
    actual = subprocess.check_output(['codesign', '-d', '--entitlements', ':-', str(bundle)], stderr=subprocess.DEVNULL)
    if plistlib.loads(actual).get('com.apple.security.application-groups') != [group]:
        raise ValueError(f'Entitlement metadata was not embedded in {bundle.name}')
    subprocess.run(['codesign', '--verify', '--strict', str(bundle)], check=True)
print('Prepared all three bundles for re-signing; an authorized distribution/development signature is still required.')
