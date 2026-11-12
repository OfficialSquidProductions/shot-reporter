#!/usr/bin/env python3
"""Complete archive Mac -> native iOS Simulator -> Mac handoff on disposable QA data only.
Creates its own simulator; never installs on a phone or uses any real report root.
Requires an already-installed simulator runtime. No component setup or agreements.
"""
import argparse,json,plistlib,shutil,subprocess,time,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,required=True);args=p.parse_args()
output=args.output.absolute();output.mkdir(parents=True,exist_ok=False)
SIM='/Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/Resources/bin/simctl'
def run(cmd,**kw):return subprocess.run(list(map(str,cmd)),check=True,**kw)
def capture(cmd):return subprocess.check_output(list(map(str,cmd)),text=True,timeout=60).strip()
runtimes=json.loads(capture([SIM,'list','runtimes','-j']))['runtimes'];runtime=next(r for r in runtimes if r['isAvailable'] and r['name'].startswith('iOS'))
common=[ROOT/'app/Sources/CameraStatsCore'/n for n in ['Model.swift','NamingSettings.swift','Exchange.swift','ProjectZIP.swift','ProjectArchive.swift','Repository.swift','Reports.swift']]
fixture=[ROOT/'app/Tests/CameraStatsCoreTests/FullProjectFixture.swift',ROOT/'tools/fixtures/CompleteArchiveProbe.swift']
base=['xcrun','swiftc','-D','SHOT_REPORTER_FIXTURE_TOOL','-module-cache-path',output/'modules','-I',ROOT/'app/Sources/CSQLite']
run([*base,*common,*fixture,'-o',output/'handoff-mac'])
run([output/'handoff-mac','generate',output])
app=output/'ProjectHandoffQA.app';app.mkdir();shutil.copyfile(output/'complete-project.camreport',app/'complete-project.camreport')
(app/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'org.squidproductions.qa.handoff','CFBundleExecutable':'ProjectHandoffQA','CFBundleName':'Project Handoff QA','CFBundlePackageType':'APPL','CFBundleVersion':'1','CFBundleShortVersionString':'1.0','MinimumOSVersion':'17.0','UIDeviceFamily':[1,2],'LSRequiresIPhoneOS':True,'UILaunchScreen':{}}))
sdk=capture(['xcrun','--sdk','iphonesimulator','--show-sdk-path'])
run([*base,'-target','arm64-apple-ios17.0-simulator','-sdk',sdk,*common,*fixture,'-o',app/'ProjectHandoffQA']);run(['codesign','--force','--sign','-',app])
device=capture([SIM,'create','ShotReporterHandoffQA-'+str(uuid.uuid4()),'com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro',runtime['identifier']])
(output/'simulator-id.txt').write_text(device+'\n')
try:
 run([SIM,'boot',device]);run([SIM,'bootstatus',device,'-b']);run([SIM,'install',device,app]);run([SIM,'launch',device,'org.squidproductions.qa.handoff'])
 container=Path(capture([SIM,'get_app_container',device,'org.squidproductions.qa.handoff','data']))/'Documents'
 for _ in range(180):
  if (container/'FAIL.txt').exists():raise RuntimeError((container/'FAIL.txt').read_text())
  if (container/'PASS.txt').exists():break
  time.sleep(1)
 else:raise RuntimeError('Native iOS handoff probe did not finish')
 shutil.copyfile(container/'phone-return.camreport',output/'phone-return.camreport');shutil.copyfile(container/'PASS.txt',output/'iOS-PASS.txt')
 run([output/'handoff-mac','verify-return',output])
 receipt={'result':'PASS','runtime':runtime['name']+' '+runtime['version'],'nativeIOSReadPersistEditExport':True,'nativeMacReadPersistReExport':True,'everyReportModelFieldCompared':True,'allFileSHA256Compared':True,'mediaOver32MiB':True,'unicodeBinaryAttachment':True,'preferencesAndRecoveriesPreserved':True,'fixture':{'cameras':2,'totalTakes':6,'activeTakes':5,'hiddenMovieSeasonEpisode':True,'unicodeAndMultilineNotes':True,'customMapValues':True,'namingSettingsAndLegacyFields':True,'deletedTakeAndHistory':True},'limits':['Synthetic compiled-core probe, not physical iPhone UI or AirDrop/iCloud delivery','One complete open report; unrelated saved reports and OS backups are not silently bundled','Includes explicitly added files; filename text does not grant access to media','Stored ZIP64, 1 TiB total, 8 MiB metadata, 19,989 resources; available disk space required','All app-owned preferences retained as archive data; only reviewed appearance/detail preferences applied','Synthetic 35 MiB media; >4 GiB physical media and real AirDrop remain field checks'],'usedRealUserData':False}
 (output/'HANDOFF-ACCEPTANCE.json').write_text(json.dumps(receipt,indent=2)+'\n')
finally:
 subprocess.run([SIM,'shutdown',device],check=False);run([SIM,'delete',device])
print('PASS complete archive native iOS Simulator and Mac round trip; disposable simulator removed')
