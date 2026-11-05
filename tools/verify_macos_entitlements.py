#!/usr/bin/env python3
"""Read-only verification of final Mac signing entitlements; never launches code."""
import argparse
import json
from pathlib import Path
import plistlib
import subprocess

DOWNLOADER = 'Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc'
INSTALLER = 'Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc'


def read_entitlements(path):
    result = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(path)], check=True, capture_output=True)
    # A restricted execution environment can make codesign print an invalid-blob
    # warning without usable data. Never silently interpret that as no privileges.
    if b'invalid entitlements' in result.stderr:
        raise ValueError('Code-signing service could not read entitlements: ' + str(path))
    return plistlib.loads(result.stdout) if result.stdout else {}


def verify_entitlement_policy(app, *, host_sandboxed=True, reader=read_entitlements):
    app = Path(app)
    host = reader(app)
    downloader = reader(app / DOWNLOADER)
    downloader_executable = reader(app / DOWNLOADER / 'Contents/MacOS/Downloader')
    installer = reader(app / INSTALLER)
    expected_downloader = {'com.apple.security.app-sandbox': True, 'com.apple.security.network.client': True}
    if downloader != expected_downloader or downloader_executable != expected_downloader:
        raise ValueError('Downloader executable and bundle must retain the explicit sandbox/network-client profile')
    if installer.get('com.apple.security.app-sandbox') is True:
        raise ValueError('Installer must remain unsandboxed to replace and relaunch the app')
    if host.get('com.apple.security.app-sandbox', False) is not host_sandboxed:
        raise ValueError('Host sandbox policy changed')
    if host.get('com.apple.security.network.client', False) is not False:
        raise ValueError('Host must not gain network-client rights')
    return {'host': host, 'downloader': downloader, 'installer': installer}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--unsandboxed-host', action='store_true')
    args = parser.parse_args()
    print(json.dumps(verify_entitlement_policy(args.app, host_sandboxed=not args.unsandboxed_host), indent=2))
