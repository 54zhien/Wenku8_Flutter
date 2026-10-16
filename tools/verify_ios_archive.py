#!/usr/bin/env python3
"""Verify a device archive statically. This never establishes UI/device acceptance."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import struct

GBK_SHA256 = 'e73761b4a3fa5df00f5bccc727d0fea272f3b44670967d7d20cafd9db4584d74'


def inspect_binary(data):
    if len(data) < 32:
        raise ValueError('Truncated Mach-O header')
    if data[:4] == b'\xca\xfe\xba\xbe':
        count = struct.unpack_from('>I', data, 4)[0]
        if count > 16 or len(data) < 8 + count * 20:
            raise ValueError('Invalid fat Mach-O header')
        slices = [struct.unpack_from('>iiIII', data, 8 + index * 20) for index in range(count)]
        selected = next((entry for entry in slices if entry[0] == 0x0100000C), None)
        if selected is None:
            raise ValueError('No arm64 device slice in Mach-O')
        _, _, offset, length, _ = selected
        if offset < 8 + count * 20 or offset + length > len(data):
            raise ValueError('Invalid fat Mach-O slice bounds')
        return inspect_binary(data[offset:offset + length])
    magic, cpu, _, _, commands, command_bytes, _, _ = struct.unpack_from('<IiiIIIII', data)
    if magic != 0xFEEDFACF or cpu != 0x0100000C or 32 + command_bytes > len(data):
        raise ValueError('Expected complete arm64 device Mach-O')
    offset = 32
    for _ in range(commands):
        if offset + 8 > 32 + command_bytes:
            raise ValueError('Truncated Mach-O load command')
        command, length = struct.unpack_from('<II', data, offset)
        if length < 8 or offset + length > 32 + command_bytes:
            raise ValueError('Invalid Mach-O load command bounds')
        if command == 0x32 and length >= 24:
            platform, minimum, sdk, _ = struct.unpack_from('<IIII', data, offset + 8)
            if platform != 2:
                raise ValueError(f'Expected iOS device platform 2, found {platform}')
            return {'architecture': 'arm64', 'platform': platform,
                    'minimum_os': f'{minimum >> 16}.{(minimum >> 8) & 255}.{minimum & 255}',
                    'sdk': f'{sdk >> 16}.{(sdk >> 8) & 255}.{sdk & 255}'}
        offset += length
    raise ValueError('Missing Mach-O device platform command')


def contained_file(root, path):
    resolved = path.resolve()
    if not resolved.is_relative_to(root):
        raise ValueError('Unsafe archive child path outside its root')
    return resolved


def inspect_archive(archive):
    archive = Path(archive).resolve()
    metadata = plistlib.loads(contained_file(archive, archive / 'Info.plist').read_bytes())
    products = archive / 'Products'
    app = (products / metadata['ApplicationProperties']['ApplicationPath']).resolve()
    if not app.is_relative_to(products / 'Applications') or app.suffix != '.app':
        raise ValueError('Unsafe archive application path')
    info = plistlib.loads(contained_file(app, app / 'Info.plist').read_bytes())
    if info['CFBundleIdentifier'] != 'org.mewx.wenku8Flutter':
        raise ValueError('Unexpected app bundle identifier')
    if info.get('MinimumOSVersion') not in ('26.0', '26.0.0'):
        raise ValueError('Minimum deployment must preserve iOS 26.0 support')
    if info.get('CFBundleSupportedPlatforms') != ['iPhoneOS']:
        raise ValueError('Archive does not contain an iOS device application')
    executable = contained_file(app, app / info['CFBundleExecutable'])
    binaries = {'Runner': executable,
                'App.framework': app / 'Frameworks/App.framework/App',
                'Flutter.framework': app / 'Frameworks/Flutter.framework/Flutter'}
    macho = {}
    for name, binary in binaries.items():
        binary = contained_file(app, binary)
        if not binary.is_file():
            raise ValueError(f'Missing {name} executable')
        macho[name] = inspect_binary(binary.read_bytes())
    if macho['Runner']['minimum_os'] != '26.0.0':
        raise ValueError('Runner Mach-O must preserve iOS 26.0 deployment')
    mapping = contained_file(app, app / 'gbk-map.bin')
    if not mapping.is_file() or hashlib.sha256(mapping.read_bytes()).hexdigest() != GBK_SHA256:
        raise ValueError('Missing or changed verified GBK mapping')
    return {'kind': 'UNACCEPTED_DIAGNOSTIC_DEVICE_ARCHIVE',
            'bundle_identifier': info['CFBundleIdentifier'],
            'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
            'minimum_os': info['MinimumOSVersion'], 'macho': macho,
            'gbk_sha256': GBK_SHA256,
            'provisioning_profile_present': contained_file(app, app / 'embedded.mobileprovision').exists(),
            'formal_ipa_delivery': False, 'ui_acceptance': 'not established',
            'physical_device_acceptance': 'not run', 'performance_acceptance': 'not established'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('--sha', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'[0-9a-f]{40}', args.sha):
        parser.error('Expected the exact 40-character source commit')
    archive = args.archive
    if archive.suffix != '.xcarchive':
        matches = list(archive.glob('*.xcarchive'))
        if len(matches) != 1:
            raise ValueError('Expected exactly one xcarchive from this build')
        archive = matches[0]
    report = {'source_sha': args.sha, **inspect_archive(archive)}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
