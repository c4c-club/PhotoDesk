import zipfile, plistlib, hashlib, glob, os, shutil
root = r'C:/Users/RuiZh/Desktop/photo_manager/artifacts/release/1.8.0'
ipas = glob.glob(os.path.join(root, 'rl-tmp', '**', '*.ipa'), recursive=True)
print('found:', ipas)
ipa = ipas[0]
h = hashlib.sha256()
with open(ipa, 'rb') as f:
    for chunk in iter(lambda: f.read(1 << 20), b''):
        h.update(chunk)
digest = h.hexdigest()
final = os.path.join(root, 'PhotoDesk-1.8.0-build9-unsigned.ipa')
shutil.move(ipa, final)
with open(final + '.sha256', 'w', newline='\n') as f:
    f.write(digest + '  PhotoDesk-1.8.0-build9-unsigned.ipa\n')
print('SHA256:', digest)
print('bytes:', os.path.getsize(final))
with zipfile.ZipFile(final) as z:
    names = z.namelist()
    app_bin = [n for n in names if n == 'Payload/PhotoDesk.app/PhotoDesk']
    print('Payload/PhotoDesk.app/PhotoDesk exists:', bool(app_bin))
    plists = [n for n in names if n.endswith('.app/Info.plist')]
    info = plistlib.loads(z.read(plists[0]))
    print('MinimumOSVersion:', info.get('MinimumOSVersion'))
    print('CFBundleShortVersionString:', info.get('CFBundleShortVersionString'))
    print('CFBundleVersion:', info.get('CFBundleVersion'))
    print('CFBundleIdentifier:', info.get('CFBundleIdentifier'))
sidecar = glob.glob(os.path.join(root, 'rl-tmp', '**', '*.sha256'), recursive=True)
if sidecar:
    print('sidecar:', open(sidecar[0]).read().strip())