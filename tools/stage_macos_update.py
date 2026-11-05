#!/usr/bin/env python3
"""Stage and authenticate a Mac appcast locally using the existing Shot Reporter key.
No key creation/export, network request, notarization, installation or publication.
An accepted native installed upgrade is still required before feed activation.
"""
import argparse
from datetime import datetime, timezone
from email.utils import format_datetime
import hashlib
import html
import json
from pathlib import Path
import plistlib
import posixpath
import stat
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile
from report_bundle_policy import reject_retired_resource

APP_ID='org.squidproductions.camerastats'
TEAM='FZ298DXLS3'
PUBLIC_KEY='qCE0vmWIGNh4ng7VgqyFKqnBY8jc90Wm9QouY7g01cs='
FEED='https://raw.githubusercontent.com/OfficialSquidProductions/shot-reporter/main/updates/macos/appcast.xml'
PREFIX='https://github.com/OfficialSquidProductions/shot-reporter/releases/download/'
SPARKLE='http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle',SPARKLE)

def digest(path):
    state=hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda:stream.read(1024*1024),b''):state.update(chunk)
    return state.hexdigest()

def inspect_archive(path):
    with zipfile.ZipFile(path) as archive:
        names=archive.namelist()
        if len(names)!=len(set(names)):raise ValueError('Duplicate archive member')
        for entry in archive.infolist():
            reject_retired_resource(entry.filename)
            parts=Path(entry.filename).parts
            if not parts or parts[0] not in ('Shot Reporter.app','__MACOSX') or '..' in parts or Path(entry.filename).is_absolute():raise ValueError('Unexpected archive member')
            if stat.S_ISLNK(entry.external_attr>>16):
                target=archive.read(entry).decode('utf-8')
                resolved=posixpath.normpath(posixpath.join(posixpath.dirname(entry.filename),target))
                if '\x00' in target or target.startswith('/') or not resolved.startswith('Shot Reporter.app/'):raise ValueError('Archive symlink escapes application')
            if entry.filename.lower().endswith(('.braw','.r3d','.sidecar','.p12','.p8','.keystore')) or 'BlackmagicRawAPI.framework' in parts or parts[-1] in ('BlackmagicRawAPI.h','BlackmagicRawAPIDispatch.cpp'):raise ValueError('Restricted file in release archive')
        info=plistlib.loads(archive.read('Shot Reporter.app/Contents/Info.plist'))
        manifest=json.loads(archive.read('Shot Reporter.app/Contents/Resources/DISTRIBUTION.json'))
    if info.get('CFBundleIdentifier')!=APP_ID or info.get('ShotReporterDistribution')!='direct':raise ValueError('Unexpected application/distribution')
    expected={'SUFeedURL':FEED,'SUPublicEDKey':PUBLIC_KEY,'SURequireSignedFeed':True,'SUVerifyUpdateBeforeExtraction':True,'SUAllowsAutomaticUpdates':False,'SUEnableDownloaderService':True,'SUSignedFeedFailureExpirationInterval':0}
    for key,value in expected.items():
        actual=info.get(key)
        if actual!=value or type(actual)!=type(value):raise ValueError('Missing secure update setting: '+key)
    build=info.get('CFBundleVersion','');version=info.get('ShotReporterReleaseVersion','')
    if not str(build).isdigit() or int(build)<5 or not re.fullmatch(r'\d+\.\d+\.\d+-alpha\.\d+',version):raise ValueError('Expected updater-enabled monotonic alpha build >=5')
    if manifest.get('version')!=version or manifest.get('build')!=int(build) or manifest.get('updaterConfigured') is not True or manifest.get('feedURL')!=FEED or info.get('CFBundleShortVersionString')!=version.split('-',1)[0]:raise ValueError('Bundle and distribution metadata differ')
    if manifest.get('sourceDirty') is not False or not re.fullmatch('[0-9a-f]{40}',manifest.get('sourceCommit','')):raise ValueError('Expected exact clean source provenance')
    return info,manifest

def feed_xml(version,build,archive_url,size,signature,notes,now=None):
    if not re.fullmatch(r'\d+\.\d+\.\d+-alpha\.\d+',version) or int(build)<5:raise ValueError('Invalid release version/build')
    expected=PREFIX+'v'+version+'/Shot-Reporter-Mac-arm64-'+version+'.zip'
    if archive_url!=expected:raise ValueError('Archive must use the exact Shot Reporter GitHub release target')
    if not re.fullmatch('[A-Za-z0-9+/]{86}==',signature) or size<=0:raise ValueError('Missing archive signature/length')
    if len(notes.encode())>100000:raise ValueError('Release notes too large')
    rss=ET.Element('rss',version='2.0');channel=ET.SubElement(rss,'channel')
    for tag,text in [('title','Shot Reporter Mac alpha updates'),('link','https://shotreporter.squidproductions.org/'),('description','Authenticated Mac desktop releases'),('language','en')]:ET.SubElement(channel,tag).text=text
    item=ET.SubElement(channel,'item')
    for tag,text in [('title','Shot Reporter '+version),('link','https://github.com/OfficialSquidProductions/shot-reporter/releases/tag/v'+version),('description',''.join('<p>'+html.escape(line)+'</p>' for line in notes.splitlines() if line.strip())),('pubDate',format_datetime(now or datetime.now(timezone.utc))),('{'+SPARKLE+'}version',str(build)),('{'+SPARKLE+'}shortVersionString',version),('{'+SPARKLE+'}channel','alpha'),('{'+SPARKLE+'}minimumSystemVersion','14.0'),('{'+SPARKLE+'}hardwareRequirements','arm64')]:ET.SubElement(item,tag).text=text
    ET.SubElement(item,'enclosure',{'url':archive_url,'length':str(size),'type':'application/octet-stream','{'+SPARKLE+'}edSignature':signature})
    encoded=ET.tostring(rss,encoding='utf-8',xml_declaration=True)+b'\n'
    ET.fromstring(encoded)  # Refuse XML-illegal control characters before signing.
    return encoded

def run(args):
    return subprocess.check_output(list(map(str,args)),text=True,stderr=subprocess.STDOUT).strip()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive',type=Path,required=True)
    parser.add_argument('--notes',type=Path,required=True,help='Plain UTF-8 release notes; embedded safely inside the signed feed')
    parser.add_argument('--output',type=Path,required=True,help='New private directory outside Git')
    args=parser.parse_args();root=Path(__file__).resolve().parents[1];archive=args.archive.resolve(strict=True);output=args.output.absolute()
    if output.exists() or output.resolve().is_relative_to(root):parser.error('Output must be a new directory outside the repository')
    info,manifest=inspect_archive(archive);version=info['ShotReporterReleaseVersion'];build=info['CFBundleVersion']
    if archive.name!='Shot-Reporter-Mac-arm64-'+version+'.zip':parser.error('Archive filename must match release metadata')
    with tempfile.TemporaryDirectory(prefix='shot-reporter-update-inspect-') as temp:
        run(['ditto','-x','-k',archive,temp]);app=Path(temp)/'Shot Reporter.app'
        run(['codesign','--verify','--deep','--strict',app]);run(['codesign','--verify','--strict','-R=anchor apple generic and identifier "'+APP_ID+'" and certificate leaf[subject.OU] = "'+TEAM+'"',app])
        run(['xcrun','stapler','validate',app]);run(['spctl','--assess','--type','execute',app])
    signer=root/'app/.build/artifacts/Sparkle/Sparkle/bin/sign_update';verifier=Path(__file__).with_name('verify_macos_update.swift')
    signature=run([signer,'--account','shot-reporter','-p',archive])
    run(['xcrun','swift',verifier,'--public-key',PUBLIC_KEY,archive,signature])
    output.mkdir(parents=True);feed=output/'appcast.xml';notes=args.notes.read_text(encoding='utf-8');url=PREFIX+'v'+version+'/'+archive.name
    feed.write_bytes(feed_xml(version,build,url,archive.stat().st_size,signature,notes))
    run([signer,'--account','shot-reporter',feed]);run(['xcrun','swift',verifier,'--public-key',PUBLIC_KEY,feed])
    receipt={'version':version,'build':int(build),'sourceCommit':manifest['sourceCommit'],'feedURL':FEED,'archiveURL':url,'archiveBytes':archive.stat().st_size,'archiveSHA256':digest(archive),'archiveEdSignature':signature,'feedSHA256':digest(feed),'embeddedNotesSHA256':hashlib.sha256(notes.encode()).hexdigest(),'hardware':'arm64','minimumOS':'14.0','signingAccount':'shot-reporter','publicKey':PUBLIC_KEY,'published':False,'installedOlderToNewerAcceptance':'still required before activation'}
    (output/'STAGED-UPDATE.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(receipt,indent=2))

if __name__=='__main__':main()
