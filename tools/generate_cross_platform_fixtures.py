#!/usr/bin/env python3
"""Compile the Apple report core unchanged and generate contract fixtures.

Pass --output to validate generation in a fresh directory without changing goldens.
Without it, intentionally regenerate the repository's conformance fixtures.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
mode = parser.add_mutually_exclusive_group()
mode.add_argument('--output', type=Path, help='Fresh output directory; existing paths are never overwritten')
mode.add_argument('--verify', type=Path, nargs='+', help='Verify supplied packages without generating or changing fixtures')
args = parser.parse_args()
output = args.output.absolute() if args.output else root/'fixtures/camreport'
if args.output and (output.exists() or output.is_symlink()):
    parser.error('Choose a fresh output directory; existing files are preserved.')
sources = [root/'app/Sources/CameraStatsCore'/name for name in
           ['Model.swift','Production.swift', 'NamingSettings.swift', 'Exchange.swift', 'Reports.swift']]
sources.append(root/'app/Tests/CameraStatsCoreTests/LegacyReportFixtures.swift')
with tempfile.TemporaryDirectory(prefix='camerastats-fixture-tool-') as directory:
    temporary = Path(directory)
    executable = temporary/'fixture-tool'
    subprocess.run(['xcrun', 'swiftc', '-D', 'SHOT_REPORTER_FIXTURE_TOOL', '-module-cache-path', str(temporary/'module-cache'),
                    *map(str, sources), str(root/'tools/fixtures/CameraStatsFixtureTool.swift'),
                    '-o', str(executable)], check=True)
    if not args.verify:
        subprocess.run([str(executable), 'generate', str(output)], check=True)
    for package in (args.verify or sorted(output.glob('*.camreport'))):
        subprocess.run([str(executable), 'verify', str(package)], check=True)
print('Verified cross-platform packages:', len(args.verify)) if args.verify else print('Verified cross-platform fixtures:', output)
