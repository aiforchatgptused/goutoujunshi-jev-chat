import plistlib
import shutil
import subprocess
from pathlib import Path

app = Path('build/Build/Products/Release-iphoneos/Suiyan.app')
ext = app / 'PlugIns/SuiyanKeyboard.appex'
assert app.is_dir() and ext.is_dir()
assert len(list((app / 'PlugIns').glob('*.appex'))) == 1
for bundle in [ext, app]:
    info = plistlib.loads((bundle / 'Info.plist').read_bytes())
    assert info['CFBundleSupportedPlatforms'] == ['iPhoneOS']
    assert info['CFBundleShortVersionString'] == '0.1.1'
    assert info['CFBundleVersion'] == '2'
    assert 'GoutouAppGroup' not in info and 'GoutouKeychainGroup' not in info
    executable = bundle / info['CFBundleExecutable']
    subprocess.run(['lipo', str(executable), '-verify_arch', 'arm64'], check=True)
    assert not list(bundle.glob('*.debug.dylib')), 'No debug runtime in release IPA'
    if bundle == ext:
        assert info['CFBundleIdentifier'] == 'app.suiyan.independent.keyboard'
        assert info['NSExtension']['NSExtensionAttributes']['RequestsOpenAccess'] is True
    else:
        assert info['CFBundleIdentifier'] == 'app.suiyan.independent'
    assert not (bundle / 'embedded.mobileprovision').exists()
# The entire new project deliberately has no entitlements file or shared-container requirement.
assert not list(Path('.').glob('**/*.entitlements'))
target = Path('build/package/Payload/Suiyan.app')
target.parent.mkdir(parents=True, exist_ok=True)
subprocess.run(['ditto', str(app), str(target)], check=True)
print('PASS: one arm64 app, one arm64 keyboard, release build, no shared-group entitlements')
