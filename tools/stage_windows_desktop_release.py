#!/usr/bin/env python3
"""Curated Windows release output; never sweeps source or private data folders into an upload."""
from pathlib import Path
import argparse,hashlib,json,os,shutil,subprocess,zipfile
p=argparse.ArgumentParser();p.add_argument('--qa',required=True);p.add_argument('--output',required=True);a=p.parse_args()
root=Path(__file__).resolve().parents[1];qa=Path(a.qa);out=Path(a.output);out.mkdir(exist_ok=False)
if not (qa/'PASS.txt').is_file():raise SystemExit('Native runtime/upgrade smoke has not passed; no release staging.')
java_release=(Path(os.environ['JAVA_HOME'])/'release').read_text()
if '21.0.12.1+1' not in java_release:raise SystemExit('JVM differs from pinned corresponding-source release; do not publish mismatched source.')
msis=list((root/'clients/desktop/build/compose/binaries/main/msi').glob('*.msi'))
if len(msis)!=1:raise SystemExit('Expected one MSI.')
shutil.copy2(msis[0],out/'Shot-Reporter-Windows-0.2.0-alpha.7.msi')
source_name='OpenJDK21U-jdk-sources_21.0.12.1_1.tar.gz'
subprocess.run(['gh','release','download','v0.1.1-alpha.3','--repo',os.environ['GITHUB_REPOSITORY'],'--pattern',source_name,'--dir',str(out)],check=True)
def sha(path):
 digest=hashlib.sha256()
 with path.open('rb') as source:
  for chunk in iter(lambda:source.read(1024*1024),b''):digest.update(chunk)
 return digest.hexdigest()
if sha(out/source_name)!='573057d03584ae793fb7ec9a14c76d826d9187a53efeefd99da47403a5308234':raise SystemExit('Pinned full OpenJDK corresponding-source hash mismatch.')
# Logs/XML/PASS markers only. No report databases or auth/config files.
with zipfile.ZipFile(out/'Windows-Validation-Evidence.zip','x',compression=zipfile.ZIP_DEFLATED) as z:
 for file in qa.rglob('*'):
  if file.is_file() and (file.name=='PASS.txt' or file.suffix=='.log'):z.write(file,'qa/'+file.relative_to(qa).as_posix())
 for file in (root/'clients').glob('*/build/test-results/test/TEST-*.xml'):z.write(file,file.relative_to(root).as_posix())
 for file in (root/'windows-preflight-test-results').glob('*.xml'):z.write(file,'sdk-free-tests/'+file.name)
metadata={'version':'0.2.0-alpha.7','msiVersion':'0.2.3','build':10,'sourceCommit':os.environ['GITHUB_SHA'],'platform':'windows-x64','distribution':'unsigned manual MSI; automatic installation disabled pending dedicated trusted publisher certificate/feed','validation':'Report and script tests, native unsigned/tampered update rejection, packaged reporting smoke and previous-to-new installed upgrade with report/history/preferences preservation passed','javaRelease':java_release,'files':{file.name:sha(file) for file in sorted(out.iterdir()) if file.is_file()}}
(out/'WINDOWS-RELEASE.json').write_text(json.dumps(metadata,indent=2)+'\n')
(out/'SHA256SUMS-Windows.txt').write_text(''.join(f'{sha(file)}  {file.name}\n' for file in sorted(out.iterdir()) if file.is_file()))
print(json.dumps(metadata,indent=2))
