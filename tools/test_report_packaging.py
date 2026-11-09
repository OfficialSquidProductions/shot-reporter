#!/usr/bin/env python3
"""Isolated report-only packaging contracts; no installs or signing accounts."""
import contextlib
import io
import json
from pathlib import Path
import plistlib
import runpy
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile
import prepare_macos_desktop_release as prepare
import stage_macos_update as stage


class ReportPackagingTests(unittest.TestCase):
    def app(self, root):
        app = root / 'input.app'
        (app / 'Contents/MacOS').mkdir(parents=True)
        (app / 'Contents/MacOS/Shot Reporter').write_bytes(b'synthetic executable')
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': stage.APP_ID, 'CFBundleVersion': '5',
            'CFBundleShortVersionString': '0.2.0', 'SUFeedURL': 'old',
            'CFBundleDocumentTypes': [{'CFBundleTypeName': 'Report'}]}))
        return app

    def test_native_candidate_and_secure_feed_share_manifest_without_extra_runtime(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); app = self.app(root); out = root / 'candidate'
            def capture(args, cwd=None):
                return '' if args[:2] == ['git', 'status'] else 'a' * 40
            real_copy = shutil.copyfile
            def copy_license(source, dest, **kwargs):
                if Path(dest).parent.name == 'legal':
                    return Path(dest).write_text('synthetic license')
                return real_copy(source, dest, **kwargs)
            with patch.object(sys, 'argv', ['prepare', '--app-input', str(app), '--output', str(out), '--version', '0.2.0-alpha.3', '--build', '5', '--public-update-key', stage.PUBLIC_KEY]), patch.object(prepare, 'capture', side_effect=capture), patch.object(prepare, 'macho_info', return_value=None), patch.object(prepare.shutil, 'copyfile', side_effect=copy_license), contextlib.redirect_stdout(io.StringIO()):
                prepare.main()
            candidate = out / 'Shot Reporter.app'
            self.assertEqual(sorted(p.name for p in (out / 'signing').iterdir()), ['downloader.plist', 'host.plist'])
            self.assertEqual(sorted(p.name for p in (candidate / 'Contents/Resources').iterdir()), ['DISTRIBUTION.json', 'legal'])
            archive = root / 'candidate.zip'
            with zipfile.ZipFile(archive, 'w') as z:
                for path in candidate.rglob('*'):
                    if path.is_file(): z.write(path, path.relative_to(out))
            info, manifest = stage.inspect_archive(archive)
            self.assertEqual(manifest['scope'], 'shot and script reporting')
            self.assertFalse(manifest['releaseReady'])
            self.assertTrue(info['SURequireSignedFeed'])
            # The source bundle is never rewritten.
            self.assertEqual(plistlib.loads((app / 'Contents/Info.plist').read_bytes())['SUFeedURL'], 'old')

    def test_preview_needs_only_app_and_fresh_isolated_profile(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve(); app = self.app(root)
            output = root / 'preview.app'; profile = root / 'ShotReporterTest-reporting'
            args = ['preview', '--built-app', str(app), '--output', str(output), '--profile', str(profile)]
            with patch.object(sys, 'argv', args), patch('subprocess.run') as run, contextlib.redirect_stdout(io.StringIO()):
                runpy.run_path(str(Path(__file__).with_name('prepare_settings_preview.py')), run_name='__main__')
            self.assertEqual(run.call_count, 2)
            info = plistlib.loads((output / 'Contents/Info.plist').read_bytes())
            self.assertEqual(info['ShotReporterPreviewProfileRoot'], str(profile))
            self.assertEqual(info['CFBundleDisplayName'], 'Shot Reporter Reporting Preview')
            self.assertEqual(info['CFBundleName'], 'Shot Reporter Reporting Preview')
            self.assertNotIn('SUFeedURL', info)
            self.assertNotIn('CFBundleDocumentTypes', info)
            self.assertFalse(info['SUEnableAutomaticChecks'])
            self.assertTrue((profile / 'Backups/initial-empty-profile.json').is_file())
            with patch.object(sys, 'argv', args), self.assertRaises(SystemExit):
                runpy.run_path(str(Path(__file__).with_name('prepare_settings_preview.py')), run_name='__main__')

    def test_retired_payloads_are_rejected_without_modifying_inputs(self):
        payloads = ['Contents/Resources/DesktopMedia/runtime/bin/java',
                    'Contents/Resources/DesktopCodecs/bin/ffmpeg',
                    'Contents/Resources/lib/media-worker-1.0.jar',
                    'Contents/Resources/bin/ffprobe']
        for payload in payloads:
            with self.subTest(payload=payload), tempfile.TemporaryDirectory() as directory:
                root = Path(directory); app = self.app(root)
                retired = app / payload; retired.parent.mkdir(parents=True, exist_ok=True)
                retired.write_bytes(b'original supplied bytes')
                out = root / 'candidate'
                with patch.object(sys, 'argv', ['prepare', '--app-input', str(app), '--output', str(out)]), patch.object(prepare, 'capture', return_value=''), self.assertRaisesRegex(ValueError, 'Retired runtime resource'):
                    prepare.main()
                self.assertFalse(out.exists())
                preview = root / 'preview.app'; profile = root / 'ShotReporterTest-retired'
                with patch.object(sys, 'argv', ['preview', '--built-app', str(app), '--output', str(preview), '--profile', str(profile)]), patch('subprocess.run') as run, self.assertRaisesRegex(ValueError, 'Retired runtime resource'):
                    runpy.run_path(str(Path(__file__).with_name('prepare_settings_preview.py')), run_name='__main__')
                run.assert_not_called()
                self.assertFalse(preview.exists())
                self.assertFalse(profile.exists())
                archive = root / 'retired.zip'
                with zipfile.ZipFile(archive, 'w') as z:
                    z.writestr('Shot Reporter.app/' + payload, b'original supplied bytes')
                before = archive.read_bytes()
                with self.assertRaisesRegex(ValueError, 'Retired runtime resource'):
                    stage.inspect_archive(archive)
                self.assertEqual(archive.read_bytes(), before)
                self.assertEqual(retired.read_bytes(), b'original supplied bytes')

    def test_windows_stage_curates_reporting_evidence_without_extra_assets(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); tools = root / 'tools'; tools.mkdir()
            script = tools / 'stage_windows_desktop_release.py'
            shutil.copyfile(Path(__file__).with_name(script.name), script)
            msi = root / 'clients/desktop/build/compose/binaries/main/msi'
            msi.mkdir(parents=True); (msi / 'fixture.msi').write_bytes(b'synthetic installer')
            qa = root / 'qa'; qa.mkdir(); (qa / 'PASS.txt').write_text('synthetic pass')
            (qa / 'reports.sqlite3').write_bytes(b'private report data must be excluded')
            (qa / 'run.log').write_text('synthetic log')
            java = root / 'jdk'; java.mkdir(); (java / 'release').write_text('21.0.12.1+1')
            out = root / 'staged'
            def download(args, **kwargs):
                (out / 'OpenJDK21U-jdk-sources_21.0.12.1_1.tar.gz').write_bytes(b'synthetic source')
            with patch.object(sys, 'argv', ['stage', '--qa', str(qa), '--output', str(out)]), patch.dict('os.environ', {'JAVA_HOME': str(java), 'GITHUB_SHA': 'a' * 40, 'GITHUB_REPOSITORY': 'example/reports'}), patch('subprocess.run', side_effect=download), patch('hashlib.sha256') as digest, contextlib.redirect_stdout(io.StringIO()):
                digest.return_value.hexdigest.return_value = '573057d03584ae793fb7ec9a14c76d826d9187a53efeefd99da47403a5308234'
                runpy.run_path(str(script), run_name='__main__')
            self.assertEqual(len(list(out.glob('*.msi'))), 1)
            metadata = json.loads((out / 'WINDOWS-RELEASE.json').read_text())
            self.assertEqual(metadata['version'], '0.2.0-alpha.7')
            self.assertEqual(metadata['msiVersion'], '0.2.3')
            self.assertEqual(metadata['build'], 10)
            self.assertEqual(metadata['sourceCommit'], 'a' * 40)
            self.assertTrue((out / 'Shot-Reporter-Windows-0.2.0-alpha.7.msi').is_file())
            self.assertTrue((out / 'SHA256SUMS-Windows.txt').is_file())
            with zipfile.ZipFile(out / 'Windows-Validation-Evidence.zip') as archive:
                self.assertEqual(set(archive.namelist()), {'qa/PASS.txt', 'qa/run.log'})

if __name__ == '__main__': unittest.main()
