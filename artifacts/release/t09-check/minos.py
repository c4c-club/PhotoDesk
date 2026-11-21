import zipfile, plistlib, hashlib, glob, os
root = r'C:/Users/RuiZh/Desktop/photo_manager/artifacts/release/t09-check'
ipas = glob.glob(os.path.join(root, '**', '*.ipa'), recursive=True)
for ipa in ipas:
    h = hashlib.sha256()
    with open(ipa, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    print('ipa:', os.path.basename(ipa))
    print('SHA256:', h.hexdigest())
    print('bytes:', os.path.getsize(ipa))
    with zipfile.ZipFile(ipa) as z:
        plists = [n for n in z.namelist() if n.endswith('.app/Info.plist')]
        if plists:
            info = plistlib.loads(z.read(plists[0]))
            print('MinimumOSVersion:', info.get('MinimumOSVersion'))
            print('CFBundleShortVersionString:', info.get('CFBundleShortVersionString'))
            print('CFBundleVersion:', info.get('CFBundleVersion'))
            print('CFBundleIdentifier:', info.get('CFBundleIdentifier'))