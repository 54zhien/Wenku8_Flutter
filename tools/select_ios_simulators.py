#!/usr/bin/env python3
"""Select a fixed iOS 26.4 simulator matrix; never silently skip device coverage."""
import argparse
import json
from pathlib import Path
import re
import subprocess


def select_devices(inventory, role, create_small):
    supported = [(runtime, [device for device in devices if device.get('isAvailable')])
                 for runtime, devices in inventory['devices'].items()
                 if re.fullmatch(r'com\.apple\.CoreSimulator\.SimRuntime\.iOS-26-4(?:-\d+)?', runtime)]
    supported.sort(key=lambda entry: tuple(map(int, entry[0].split('.iOS-')[1].split('-'))), reverse=True)
    for runtime, devices in supported:
        phone = next((device for device in devices if device['name'] == 'iPhone 17 Pro'), None)
        if phone:
            break
    else:
        raise RuntimeError('No available iOS 26.4 iPhone 17 Pro; do not fall back to an older toolchain runtime')
    selected = {'runtime': runtime, 'udid': phone['udid']}
    if role == 'interface':
        pad = next((device for device in devices if device['name'].startswith('iPad Pro 11-inch')), None)
        if pad is None:
            raise RuntimeError('No available iOS 26.4 iPad Pro 11-inch; interface coverage is required')
        small = next((device for device in devices if device['name'] == 'iPhone SE (3rd generation)'), None)
        selected['small_udid'] = small['udid'] if small else create_small(runtime)
        selected['pad_udid'] = pad['udid']
    return selected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--role', required=True, choices=['motion', 'interface'])
    parser.add_argument('--inventory', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--evidence', required=True, type=Path)
    args = parser.parse_args()

    def create_small(runtime):
        return subprocess.check_output([
            'xcrun', 'simctl', 'create', 'Wenku8 small iPhone',
            'com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation', runtime
        ], text=True, timeout=60).strip()

    selected = select_devices(json.loads(args.inventory.read_text()), args.role, create_small)
    for key, value in selected.items():
        if key != 'runtime' and not re.fullmatch(r'[0-9A-Fa-f-]{36}', value):
            raise RuntimeError('Invalid selected simulator identifier')
    args.evidence.parent.mkdir(parents=True, exist_ok=True)
    args.evidence.write_text(json.dumps(selected, indent=2))
    with args.output.open('a') as output:
        for key, value in selected.items():
            output.write(f'{key}={value}\n')
    print(json.dumps(selected, indent=2))


if __name__ == '__main__':
    main()
