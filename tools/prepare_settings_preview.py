#!/usr/bin/env python3
"""Prepare a new local preview. Never installs, updates, publishes or overwrites an app."""
import argparse
import hashlib
import json
import plistlib
import shutil
import subprocess
from pathlib import Path
from report_bundle_policy import validate_report_bundle

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--built-app', required=True, type=Path)
parser.add_argument('--output', required=True, type=Path)
parser.add_argument('--profile', required=True, type=Path)
args = parser.parse_args()
output, profile = args.output.absolute(), args.profile.resolve()
if output.exists() or profile.exists():
    raise SystemExit('Choose fresh output and profile paths; existing files are preserved.')
if not profile.name.startswith('ShotReporterTest-') or not args.profile.is_absolute():
    raise SystemExit('The dedicated profile must be absolute and named ShotReporterTest-*.')
if output.suffix != '.app' or output.parent.resolve() in [Path('/Applications'), Path.home() / 'Applications']:
    raise SystemExit('Choose a local development app path outside Applications.')
validate_report_bundle(args.built_app)
output.parent.mkdir(parents=True, exist_ok=True)
profile.mkdir(parents=True)
for folder in ['Diagnostics', 'Logs', 'Backups']:
    (profile / folder).mkdir()
shutil.copytree(args.built_app, output, symlinks=True)
info_path = output / 'Contents/Info.plist'
info = plistlib.loads(info_path.read_bytes())
info.update(CFBundleIdentifier='org.squidproductions.shotreporter.settings-preview',
            CFBundleDisplayName='Shot Reporter Reporting Preview', CFBundleName='Shot Reporter Reporting Preview',
            ShotReporterPreviewProfileRoot=str(profile), ShotReporterDistribution='development',
            SUEnableAutomaticChecks=False, SUAutomaticallyUpdate=False, SUAllowsAutomaticUpdates=False)
# A preview must not register itself as the owner of production report files.
for key in ['SUFeedURL', 'CFBundleDocumentTypes', 'UTExportedTypeDeclarations', 'CFBundleURLTypes']:
    info.pop(key, None)
info_path.write_bytes(plistlib.dumps(info))
receipt = {'profile': str(profile), 'directLaunchProfilePinnedInInfoPlist': True,
           'ownerLibraryCopied': False, 'profileInitiallyEmpty': True,
           'backup': 'Backups/initial-empty-profile.json', 'logs': ['Diagnostics', 'Logs'],
           'updateFeed': None, 'installedAppReplaced': False}
(profile / 'Backups/initial-empty-profile.json').write_text(json.dumps(receipt, indent=2) + '\n')
(profile / 'Logs/prelaunch.json').write_text(json.dumps(receipt, indent=2) + '\n')
subprocess.run(['codesign', '--force', '--deep', '--sign', '-', str(output)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(output)], check=True)
assert plistlib.loads(info_path.read_bytes())['ShotReporterPreviewProfileRoot'] == str(profile)
assert profile.resolve() == profile and not profile.is_symlink()
receipt['executableSHA256'] = hashlib.sha256((output / 'Contents/MacOS/Shot Reporter').read_bytes()).hexdigest()
(output.parent / 'PRELAUNCH-VERIFICATION.json').write_text(json.dumps(receipt, indent=2) + '\n')
print('Verified isolated development preview:', output)
print('Data, diagnostic logs and backups:', profile)
