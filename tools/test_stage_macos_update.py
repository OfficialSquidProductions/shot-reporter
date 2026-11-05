#!/usr/bin/env python3
"""Offline release-contract checks; uses no signing identity or private media."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
import zipfile
import stat
import xml.etree.ElementTree as ET

spec=importlib.util.spec_from_file_location('stage',Path(__file__).with_name('stage_macos_update.py'));stage=importlib.util.module_from_spec(spec);spec.loader.exec_module(stage)

class MacFeedTests(unittest.TestCase):
    def test_correct_release_is_arm64_alpha_and_notes_are_in_signed_xml(self):
        version='0.2.0-alpha.3';url=stage.PREFIX+'v'+version+'/Shot-Reporter-Mac-arm64-'+version+'.zip'
        raw=stage.feed_xml(version,5,url,1234,'A'*86+'==','Fixes reports.\n<script>untrusted text</script>')
        item=ET.fromstring(raw).find('channel/item');namespace={'s':stage.SPARKLE}
        self.assertEqual(item.find('s:hardwareRequirements',namespace).text,'arm64')
        self.assertEqual(item.find('s:minimumSystemVersion',namespace).text,'14.0')
        self.assertEqual(item.find('s:channel',namespace).text,'alpha')
        self.assertEqual(item.find('s:version',namespace).text,'5')
        self.assertEqual(item.find('enclosure').get('url'),url)
        self.assertIn('&lt;script&gt;',item.find('description').text)
        self.assertNotIn('<script>',item.find('description').text)
        self.assertIsNone(item.find('s:releaseNotesLink',namespace))
    def test_other_repo_or_unconfigured_old_build_cannot_be_offered(self):
        version='0.2.0-alpha.3';valid=stage.PREFIX+'v'+version+'/Shot-Reporter-Mac-arm64-'+version+'.zip'
        for url,build in [('https://example.org/app.zip',5),(valid,4),(valid.replace('/shot-reporter/','/scenic-planner/'),5)]:
            with self.subTest(url=url,build=build),self.assertRaises(ValueError):stage.feed_xml(version,build,url,1234,'A'*86+'==','Fixture')
    def test_missing_signature_and_oversized_notes_refused(self):
        version='0.2.0-alpha.3';url=stage.PREFIX+'v'+version+'/Shot-Reporter-Mac-arm64-'+version+'.zip'
        for signature,notes in [('', 'Fixture'),('A'*86+'==','x'*100001)]:
            with self.subTest(signature=bool(signature)),self.assertRaises(ValueError):stage.feed_xml(version,5,url,1234,signature,notes)

    def test_archive_traversal_and_external_symlinks_are_refused_before_extraction(self):
        with tempfile.TemporaryDirectory() as temp:
            for index,(name,target) in enumerate([('../outside',None),('Shot Reporter.app/Contents/escape','../../../outside')]):
                archive=Path(temp)/('bad'+str(index)+'.zip')
                with zipfile.ZipFile(archive,'w') as z:
                    info=zipfile.ZipInfo(name)
                    if target is not None:info.external_attr=(stat.S_IFLNK|0o777)<<16
                    z.writestr(info,target or 'fixture')
                with self.assertRaisesRegex(ValueError,'Unexpected archive member|symlink escapes'):
                    stage.inspect_archive(archive)

if __name__=='__main__':unittest.main()
