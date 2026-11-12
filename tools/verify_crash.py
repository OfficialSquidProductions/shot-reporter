#!/usr/bin/env python3
"""Prove committed SQLite data survives killing a separate native process. macOS test host only."""
from pathlib import Path
import json, os, signal, subprocess, tempfile
ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='camerastats-crash-') as tmp:
    tmp=Path(tmp)
    executable=tmp/'CrashCommitProbe'
    command=['swiftc','-D','SHOT_REPORTER_FIXTURE_TOOL','-module-cache-path',str(tmp/'module-cache'),'-I',str(ROOT/'app/Sources/CSQLite')]
    # This probe exercises report persistence, not application crash capture.
    # Keep its dependency closure explicit so unrelated C-backed services do not
    # require their runtime/module when compiling the standalone test process.
    sources = ['Model.swift', 'NamingSettings.swift', 'Exchange.swift', 'Reports.swift', 'ProjectZIP.swift', 'ProjectArchive.swift', 'Repository.swift']
    command += [str(ROOT/'app/Sources/CameraStatsCore'/name) for name in sources]
    command += [str(ROOT/'app/Tests/CameraStatsCoreTests/LegacyReportFixtures.swift'),str(ROOT/'tools/CrashCommitProbe.swift'),'-o',str(executable)]
    subprocess.run(command,check=True)
    killed=subprocess.run([str(executable),'commit-and-kill',str(tmp/'fixture')],capture_output=True)
    assert killed.returncode == -signal.SIGKILL, f'Unexpected crash fixture result: {killed.returncode}'
    result=json.loads(subprocess.check_output([str(executable),'read',str(tmp/'fixture')]))
    assert result == {'documents':1,'entries':3,'title':'Committed before SIGKILL'},result
    print(json.dumps({'result':'PASS','committed_report_survived_SIGKILL':True,'entries_recovered':3,'uses_app_control':False}))
