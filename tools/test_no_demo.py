#!/usr/bin/env python3
"""Shipping apps must not include demo UI, scripts, or fixture resources."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class NoDemoPackagingTests(unittest.TestCase):
    def test_demo_ui_and_generators_are_not_shipping_sources(self):
        roots = [ROOT / 'app/Sources', ROOT / 'clients/shared-ui/src/main',
                 ROOT / 'clients/core/src/main', ROOT / 'clients/android/src/main',
                 ROOT / 'clients/desktop/src/main']
        removed = ['Open The Last Light demo', 'Read the demo script',
                   'Read the 16-shot plan', 'Shared demo shots',
                   'demo-report.json', 'separateDemo(', 'func demo()', 'fun demo()']
        for root in roots:
            for source in root.rglob('*'):
                if source.suffix not in {'.swift', '.kt', '.json'}:
                    continue
                text = source.read_text()
                for marker in removed:
                    with self.subTest(source=source.relative_to(ROOT), marker=marker):
                        self.assertNotIn(marker, text)

    def test_production_packaging_does_not_copy_demo_fixtures(self):
        for filename in ['clients/android/build.gradle.kts', 'clients/desktop/build.gradle.kts']:
            source = (ROOT / filename).read_text()
            with self.subTest(filename=filename):
                self.assertNotIn('owner-demo.json', source)
                self.assertNotIn('rename {"demo-report.json"}', source)
        self.assertFalse((ROOT / 'app/Sources/CameraStatsCore/Demo.swift').exists())
        self.assertNotIn('func fixture()', (ROOT / 'app/Sources/CameraStatsCore/Model.swift').read_text())

    def test_legacy_test_fixtures_remain_outside_shipping_sources(self):
        self.assertTrue((ROOT / 'app/Tests/CameraStatsCoreTests/LegacyReportFixtures.swift').exists())
        for name in ['swift-demo.camreport', 'owner-demo.json']:
            self.assertTrue((ROOT / 'fixtures/camreport' / name).exists())


if __name__ == '__main__':
    unittest.main()
