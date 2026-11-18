import plistlib
import sys
import os

plist = sys.argv[1]
with open(plist, "rb") as f:
    d = plistlib.load(f)
print("MinimumOSVersion =", d.get("MinimumOSVersion"))
print("CFBundleShortVersionString =", d.get("CFBundleShortVersionString"))
print("CFBundleVersion =", d.get("CFBundleVersion"))
print("CFBundleIdentifier =", d.get("CFBundleIdentifier"))
