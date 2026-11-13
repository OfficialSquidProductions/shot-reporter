#!/usr/bin/env python3
"""Prepare an unsigned Mac arm64 candidate and explicit signing/source manifest.

Offline only: no account, Keychain, signing, notarization, upload or feed write.
Stages the native report application and its Sparkle updater for macOS 14.
"""
from pathlib import Path
from report_bundle_policy import validate_report_bundle
import argparse
import base64
import json
import os
import plistlib
import re
import shutil
import subprocess

FEED = 'https://raw.githubusercontent.com/OfficialSquidProductions/shot-reporter/main/updates/macos/appcast.xml'
DOWNLOADER_BUNDLE = 'Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc'
DOWNLOADER_EXECUTABLE = DOWNLOADER_BUNDLE + '/Contents/MacOS/Downloader'

def macho_entitlement_profile(relative):
    if relative == DOWNLOADER_EXECUTABLE: return 'downloader.plist'
    return None

def run(args, *, cwd=None, env=None, log=None):
    if log:
        with Path(log).open('w') as stream:
            subprocess.run(list(map(str, args)), cwd=cwd, env=env, check=True, stdout=stream, stderr=subprocess.STDOUT)
    else:
        subprocess.run(list(map(str, args)), cwd=cwd, env=env, check=True)


def capture(args, cwd=None):
    return subprocess.check_output(list(map(str, args)), cwd=cwd, text=True, stderr=subprocess.STDOUT).strip()


def macho_info(path):
    description = capture(['file', '-b', path])
    if 'Mach-O' not in description:
        return None
    architecture = capture(['lipo', '-archs', path])
    if 'arm64' not in architecture.split():
        raise RuntimeError('Packaged Mach-O lacks arm64: ' + path.name)
    build = capture(['vtool', '-show-build', path])
    minima = re.findall(r'\bminos\s+([0-9.]+)', build)
    if not minima:
        load = capture(['otool', '-l', path])
        minima = re.findall(r'cmd LC_VERSION_MIN_MACOSX\s+cmdsize \d+\s+version ([0-9.]+)', load)
    if not minima or any(tuple(map(int, value.split('.'))) > (14, 0, 0) for value in minima):
        raise RuntimeError('Missing or incompatible macOS minimum for ' + path.name + ': ' + str(minima))
    dependencies = capture(['otool', '-L', path])
    for dependency in dependencies.splitlines()[1:]:
        if not dependency.startswith('\t'): continue
        name = dependency.strip().split(' (', 1)[0]
        if name.startswith('/') and not name.startswith(('/System/Library/', '/usr/lib/')):
            raise RuntimeError('Unbundled absolute native dependency: ' + name)
    return {'architectures': architecture.split(), 'minimumOS': minima}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--app-input', type=Path, help='Existing unsigned Release app; omitted builds current Xcode project')
    parser.add_argument('--version', default='0.2.0-alpha.13')
    parser.add_argument('--build', type=int, default=16)
    parser.add_argument('--public-update-key', help='Public Ed25519 key only; never pass a private key')
    parser.add_argument('--unsandboxed-host', action='store_true', help='Explicit direct-distribution model; requires data-root compatibility acceptance')
    parser.add_argument('--allow-dirty', action='store_true', help='Review candidate only; manifest forbids public release until rebuilt clean')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = args.output.absolute()
    if output.exists() or output.is_symlink() or output.resolve().is_relative_to(root):
        parser.error('Output must be a fresh directory outside the source checkout')
    if not re.fullmatch(r'\d+\.\d+\.\d+-alpha\.\d+', args.version) or args.build < 3:
        parser.error('This alpha profile requires a 3-part alpha version and monotonic numeric build >=3')
    dirty = bool(capture(['git', 'status', '--porcelain'], cwd=root))
    if dirty and not args.allow_dirty:
        parser.error('Source is dirty; commit reviewed source or request a review-only --allow-dirty candidate')
    if args.public_update_key:
        try:
            key = base64.b64decode(args.public_update_key, validate=True)
        except ValueError:
            parser.error('Public update key must be canonical base64')
        if len(key) != 32 or not any(key):
            parser.error('Public update key must contain 32 nonzero Ed25519 public-key bytes')
    if args.app_input:
        validate_report_bundle(args.app_input.resolve(strict=True))
    output.mkdir(parents=True)
    logs = output / 'logs'; logs.mkdir()
    env = dict(os.environ, MACOSX_DEPLOYMENT_TARGET='14.0')
    if args.app_input:
        app_input = args.app_input.resolve(strict=True)
    else:
        derived = output / 'xcode-derived'
        run(['xcodebuild', '-project', root/'apple/CameraStats.xcodeproj', '-scheme', 'CameraStats', '-configuration', 'Release', '-destination', 'platform=macOS', '-derivedDataPath', derived, '-clonedSourcePackagesDirPath', root/'app/.build', '-disableAutomaticPackageResolution', '-onlyUsePackageVersionsFromResolvedFile', 'ARCHS=arm64', 'ONLY_ACTIVE_ARCH=YES', 'CODE_SIGNING_ALLOWED=NO', 'build'], env=env, log=logs/'app-build.log')
        app_input = derived/'Build/Products/Release/Shot Reporter.app'
    validate_report_bundle(app_input)
    app = output/'Shot Reporter.app'
    shutil.copytree(app_input, app, symlinks=True)
    info_path = app/'Contents/Info.plist'; info = plistlib.loads(info_path.read_bytes())
    if info.get('CFBundleIdentifier') != 'org.squidproductions.camerastats':
        raise RuntimeError('Unexpected app identity')
    if str(info.get('CFBundleVersion')) != str(args.build) or info.get('CFBundleShortVersionString') not in {args.version, args.version.split('-',1)[0]}:
        raise RuntimeError('Build source must already have reviewed release version/build')
    info.update({'ShotReporterDistribution':'direct', 'ShotReporterReleaseVersion':args.version, 'ShotReporterUpdateChannel':'alpha', 'SUEnableDownloaderService':True, 'SURequireSignedFeed':True, 'SUSignedFeedFailureExpirationInterval':0, 'SUVerifyUpdateBeforeExtraction':True, 'SUAllowsAutomaticUpdates':False, 'SUEnableAutomaticChecks':True, 'SUAutomaticallyUpdate':False, 'SUEnableSystemProfiling':False, 'SUShowReleaseNotes':True, 'SUScheduledCheckInterval':86400})
    if args.public_update_key:
        info.update({'SUFeedURL':FEED, 'SUPublicEDKey':args.public_update_key})
    else:
        info.pop('SUFeedURL', None); info.pop('SUPublicEDKey', None)
    info_path.write_bytes(plistlib.dumps(info))
    legal = app/'Contents/Resources/legal'
    legal.mkdir(parents=True, exist_ok=True)
    for source, name in [(root/'LICENSE','Shot-Reporter-MIT.txt'), (root/'THIRD_PARTY_NOTICES.md','THIRD_PARTY_NOTICES.md'), (root/'app/.build/checkouts/Sparkle/LICENSE','Sparkle-LICENSE.txt')]:
        shutil.copyfile(source, legal/name)
    signing = output/'signing'; signing.mkdir()
    host_entitlements = {'com.apple.security.app-sandbox':True,'com.apple.security.files.user-selected.read-write':True,'com.apple.security.temporary-exception.mach-lookup.global-name':['org.squidproductions.camerastats-spks','org.squidproductions.camerastats-spki']} if not args.unsandboxed_host else {}
    (signing/'host.plist').write_bytes(plistlib.dumps(host_entitlements))
    # Sparkle supports this optional least-privilege Downloader configuration.
    # Installer remains unsandboxed so it can replace and relaunch the app.
    (signing/'downloader.plist').write_bytes(plistlib.dumps({'com.apple.security.app-sandbox':True,'com.apple.security.network.client':True}))
    objects = []
    for file in sorted(app.rglob('*')):
        if file.is_symlink():
            if not file.resolve().is_relative_to(app.resolve()):
                raise RuntimeError('Bundle symlink escapes distribution')
            continue
        if not file.is_file(): continue
        detail = macho_info(file)
        if detail:
            objects.append({'path':str(file.relative_to(app)), 'entitlements':macho_entitlement_profile(str(file.relative_to(app))), **detail})
    bundles = sorted([p for p in app.rglob('*') if p.is_dir() and not p.is_symlink() and p.suffix in ['.framework','.xpc','.app']],key=lambda p:len(p.parts),reverse=True)
    plan = {'identityTeam':'FZ298DXLS3','identifier':'org.squidproductions.camerastats','architecture':'arm64','hostSandboxed':not args.unsandboxed_host,'hardenedRuntime':True,'timestampRequired':True,'signingPerformed':False,'macho':sorted(objects,key=lambda x:len(Path(x['path']).parts),reverse=True),'nestedBundles':[str(p.relative_to(app)) for p in bundles],'nestedBundleEntitlements':{DOWNLOADER_BUNDLE:'downloader.plist'},'outerBundle':'Shot Reporter.app','outerEntitlements':'host.plist','instructions':'Coordinator must sign nested Mach-O and bundles from inside out, then outer host; no --deep signing. Retain original Sparkle helper entitlements where applicable. Verify each signature and final bundle; notarize, staple, then rearchive. Do not install candidate over owner app for QA.'}
    (output/'MAC_SIGNING_PLAN.json').write_text(json.dumps(plan,indent=2)+'\n')
    manifest = {'version':args.version,'build':args.build,'platform':'macOS 14+ Apple Silicon arm64','sourceCommit':capture(['git','rev-parse','HEAD'],cwd=root),'sourceDirty':dirty,'updaterConfigured':bool(args.public_update_key),'feedURL':FEED if args.public_update_key else None,'scope':'shot and script reporting','unsigned':True,'notarized':False,'downloaderSandboxed':True,'releaseReady':False,'releaseGates':['Reviewed clean source rebuild' if dirty else 'Final exact-source regression evidence','Coordinator signature/notarization/stapling','Actual signed report application acceptance','Existing report roots and preferences preservation','Real signed Sparkle older-to-newer upgrade/relaunch'+('' if args.public_update_key else ' and dedicated public-key/feed configuration')]}
    (app/'Contents/Resources/DISTRIBUTION.json').write_text(json.dumps(manifest,indent=2)+'\n')
    (output/'MAC_RELEASE_CANDIDATE.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps({'app':str(app),'signingPlan':str(output/'MAC_SIGNING_PLAN.json'),'releaseReady':False}))

if __name__ == '__main__':
    main()
