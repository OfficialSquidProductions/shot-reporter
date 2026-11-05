#!/usr/bin/env python3
"""Focused release regression; synthetic code only, no account or private media."""
import importlib.util
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from verify_macos_entitlements import verify_entitlement_policy, read_entitlements, DOWNLOADER, INSTALLER

spec = importlib.util.spec_from_file_location('prepare', Path(__file__).with_name('prepare_macos_desktop_release.py'))
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)


class MacSigningPolicyTests(unittest.TestCase):
    def fixture(self):
        app = Path('/isolated/fixture.app')
        rights = {app: {'com.apple.security.app-sandbox': True}, app / INSTALLER: {}}
        for path in [app / DOWNLOADER, app / DOWNLOADER / 'Contents/MacOS/Downloader']:
            rights[path] = {'com.apple.security.app-sandbox': True, 'com.apple.security.network.client': True}
        return app, rights

    def test_only_exact_downloader_receives_explicit_profile(self):
        self.assertEqual(prepare.macho_entitlement_profile(prepare.DOWNLOADER_EXECUTABLE), 'downloader.plist')
        for path in [INSTALLER + '/Contents/MacOS/Installer', 'Contents/MacOS/Shot Reporter', 'other/Downloader', prepare.DOWNLOADER_EXECUTABLE + '.extra']:
            self.assertIsNone(prepare.macho_entitlement_profile(path))

    def test_final_policy_rejects_stripped_downloader_and_expanded_other_privileges(self):
        app, rights = self.fixture()
        verify_entitlement_policy(app, reader=rights.__getitem__)
        for path, replacement in [(app / DOWNLOADER, {}), (app / DOWNLOADER / 'Contents/MacOS/Downloader', {}), (app / INSTALLER, {'com.apple.security.app-sandbox': True}), (app, {'com.apple.security.app-sandbox': True, 'com.apple.security.network.client': True})]:
            changed = dict(rights); changed[path] = replacement
            with self.subTest(path=str(path)), self.assertRaises(ValueError):
                verify_entitlement_policy(app, reader=changed.__getitem__)

    def test_real_adhoc_bundle_resigning_retains_downloader_profile(self):
        # Exercises the executable→bundle signing order that previously relied
        # on a stock payload with no entitlements. Never launches this fixture.
        with tempfile.TemporaryDirectory(prefix='shot-synthetic-signing-') as directory:
            root = Path(directory); bundle = root / 'Downloader.xpc'; executable = bundle / 'Contents/MacOS/Downloader'
            executable.parent.mkdir(parents=True)
            source = root / 'main.c'; source.write_text('int main(void) { return 0; }\n')
            (bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'org.squidproductions.signing-fixture', 'CFBundleExecutable': 'Downloader', 'CFBundlePackageType': 'XPC!'}))
            subprocess.run(['xcrun', 'clang', str(source), '-o', str(executable)], check=True, capture_output=True)
            profile = root / 'downloader.plist'; expected = {'com.apple.security.app-sandbox': True, 'com.apple.security.network.client': True}; profile.write_bytes(plistlib.dumps(expected))
            self.assertEqual(read_entitlements(executable), {})
            for path in [executable, bundle]:
                subprocess.run(['codesign', '--force', '--sign', '-', '--entitlements', str(profile), str(path)], check=True, capture_output=True)
            subprocess.run(['codesign', '--verify', '--deep', '--strict', str(bundle)], check=True, capture_output=True)
            self.assertEqual(read_entitlements(executable), expected)
            self.assertEqual(read_entitlements(bundle), expected)


if __name__ == '__main__':
    unittest.main()
