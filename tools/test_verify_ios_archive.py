import plistlib
from pathlib import Path
import struct
import tempfile
import unittest

from verify_ios_archive import inspect_archive, inspect_binary


def macho(platform=2, cpu=0x0100000C, minimum=(26 << 16)):
    header = struct.pack('<IiiIIIII', 0xFEEDFACF, cpu, 0, 2, 1, 24, 0, 0)
    return header + struct.pack('<IIIIII', 0x32, 24, platform, minimum, 0x1A0400, 0)


class ArchiveTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'Runner.xcarchive'
        self.app = self.root / 'Products/Applications/Runner.app'
        self.app.mkdir(parents=True)
        (self.root / 'Info.plist').write_bytes(plistlib.dumps({'ApplicationProperties': {
            'ApplicationPath': 'Applications/Runner.app',
            'CFBundleIdentifier': 'org.mewx.wenku8Flutter'}}))
        (self.app / 'Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': 'org.mewx.wenku8Flutter', 'CFBundleExecutable': 'Runner',
            'CFBundleShortVersionString': '0.2.4', 'CFBundleVersion': '1',
            'MinimumOSVersion': '26.0', 'CFBundleSupportedPlatforms': ['iPhoneOS']}))
        for relative in ['Runner', 'Frameworks/App.framework/App', 'Frameworks/Flutter.framework/Flutter']:
            path = self.app / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(macho())
        mapping = Path(__file__).resolve().parent.parent / 'ios/Runner/Resources/gbk-map.bin'
        (self.app / 'gbk-map.bin').write_bytes(mapping.read_bytes())

    def test_complete_device_archive_is_explicitly_unaccepted(self):
        report = inspect_archive(self.root)
        self.assertEqual(report['kind'], 'UNACCEPTED_DIAGNOSTIC_DEVICE_ARCHIVE')
        self.assertEqual(report['minimum_os'], '26.0')
        self.assertEqual(report['macho']['Runner']['platform'], 2)
        self.assertFalse(report['formal_ipa_delivery'])
        self.assertEqual(report['ui_acceptance'], 'not established')
        self.assertEqual(report['physical_device_acceptance'], 'not run')

    def test_arm64_simulator_binary_cannot_masquerade_as_device_binary(self):
        (self.app / 'Runner').write_bytes(macho(platform=7))
        with self.assertRaisesRegex(ValueError, 'device'):
            inspect_archive(self.root)

    def test_missing_framework_cannot_pass_integrity(self):
        (self.app / 'Frameworks/App.framework/App').unlink()
        with self.assertRaisesRegex(ValueError, 'App.framework'):
            inspect_archive(self.root)

    def test_changed_gbk_resource_cannot_pass_integrity(self):
        (self.app / 'gbk-map.bin').write_bytes(b'not the verified mapping')
        with self.assertRaisesRegex(ValueError, 'GBK'):
            inspect_archive(self.root)

    def test_archive_cannot_redirect_inspection_outside_its_products(self):
        (self.root / 'Info.plist').write_bytes(plistlib.dumps({'ApplicationProperties': {
            'ApplicationPath': '../../../outside.app'}}))
        with self.assertRaisesRegex(ValueError, 'path'):
            inspect_archive(self.root)

    def test_framework_symlink_cannot_escape_app_root(self):
        outside = Path(self.temp.name) / 'outside-macho'
        outside.write_bytes(macho())
        binary = self.app / 'Frameworks/App.framework/App'
        binary.unlink(); binary.symlink_to(outside)
        with self.assertRaisesRegex(ValueError, 'path'):
            inspect_archive(self.root)

    def test_mapping_symlink_cannot_escape_app_root(self):
        mapping = self.app / 'gbk-map.bin'
        outside = Path(self.temp.name) / 'outside-mapping'
        outside.write_bytes(mapping.read_bytes())
        mapping.unlink(); mapping.symlink_to(outside)
        with self.assertRaisesRegex(ValueError, 'path'):
            inspect_archive(self.root)

    def test_minimum_deployment_cannot_silently_exclude_ios_26(self):
        path = self.app / 'Info.plist'
        info = plistlib.loads(path.read_bytes()); info['MinimumOSVersion'] = '27.0'
        path.write_bytes(plistlib.dumps(info))
        with self.assertRaisesRegex(ValueError, '26.0'):
            inspect_archive(self.root)

    def test_truncated_macho_cannot_pass(self):
        with self.assertRaisesRegex(ValueError, 'Mach-O'):
            inspect_binary(b'bad')


if __name__ == '__main__':
    unittest.main()
