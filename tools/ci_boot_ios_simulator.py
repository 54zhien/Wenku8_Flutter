#!/usr/bin/env python3
"""Boot one CI simulator with its display session and preserve failure evidence.

One attempt only: a failed readiness gate remains failed. No erase or retries.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('udid', nargs='?')
    parser.add_argument('output', type=Path)
    parser.add_argument('--shutdown')
    parser.add_argument('--shutdown-others', action='store_true',
                        help='Stop other booted devices on this disposable CI host')
    parser.add_argument('--initialize', action='store_true',
                        help='Initialize the display service before device discovery')
    args = parser.parse_args()
    if sys.platform != 'darwin':
        parser.error('This helper only runs on the macOS CI host')
    if args.initialize == bool(args.udid):
        parser.error('Provide either a device identifier or --initialize')
    for value in (args.udid, args.shutdown):
        if value and not re.fullmatch(r'[0-9A-Fa-f-]{36}', value):
            parser.error('Invalid simulator identifier')
    args.output.mkdir(parents=True, exist_ok=True)
    events = []

    def run(label, command, timeout, required=True):
        print(f'{label}: starting', flush=True)
        event = {'stage': label, 'command': command, 'timeout_seconds': timeout}
        events.append(event)
        started = time.monotonic()
        try:
            with (args.output / f'{label}.txt').open('wb') as log:
                result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT,
                                        timeout=timeout, check=False)
            event['exit_code'] = result.returncode
        except subprocess.TimeoutExpired:
            event['timed_out'] = True
            event['exit_code'] = 124
        finally:
            event['elapsed_seconds'] = round(time.monotonic() - started, 3)
            (args.output / 'stages.json').write_text(json.dumps(events, indent=2))
        print(f'{label}: exit {event["exit_code"]}', flush=True)
        if required and event['exit_code'] != 0:
            raise RuntimeError(f'{label} failed; preserved its output and stage manifest')

    status = 1
    try:
        run('processes-before', ['ps', '-axo', 'pid,ppid,state,etime,pcpu,comm'], 5, False)
        if not args.initialize:
            # Inspect/stop other CI devices before opening the selected GUI.
            # Opening Simulator without a UDID can auto-boot its remembered
            # default, so workflow callers must discover/select the device first.
            run('devices-before', ['xcrun', 'simctl', 'list', 'devices', '--json'], 10)
            inventory = json.loads((args.output / 'devices-before.txt').read_text())
            target = next((device for devices in inventory['devices'].values()
                           for device in devices if device['udid'] == args.udid), None)
            if target is None:
                raise RuntimeError('Selected simulator is missing from inventory')
            for devices in inventory['devices'].values():
                for device in devices:
                    identifier = device['udid']
                    if identifier == args.udid or device['state'] == 'Shutdown':
                        continue
                    if args.shutdown_others or identifier == args.shutdown:
                        run(f'shutdown-{identifier}', ['xcrun', 'simctl', 'shutdown', identifier], 20)
            # One boot owner. Simulator GUI and bootstatus -b can race and
            # fail with SimError 405 (already Booted), as preserved in CI.
            # Admission plus GUI setup and readiness share the original 360s.
            boot_deadline = time.monotonic() + 360
            if target['state'] == 'Shutdown':
                run('boot-start', ['xcrun', 'simctl', 'boot', args.udid], 30)
            elif target['state'] not in ('Booting', 'Booted'):
                raise RuntimeError(f'Selected simulator cannot start from {target["state"]}')
        developer = subprocess.check_output(['xcode-select', '-p'], timeout=10,
                                            text=True).strip()
        simulator = Path(developer) / 'Applications/Simulator.app'
        command = ['open', '-a', str(simulator)]
        if args.udid:
            command += ['--args', '-CurrentDeviceUDID', args.udid]
        run('display-session', command, 15)
        if args.initialize:
            # GUI launch only; this mode is not used by the device workflows.
            status = 0
            return status
        remaining = min(360, boot_deadline - time.monotonic())
        if remaining <= 0:
            raise RuntimeError('Original 360-second boot budget was exhausted')
        run('boot-readiness', ['xcrun', 'simctl', 'bootstatus', args.udid], remaining)
        run('ready-image', ['xcrun', 'simctl', 'io', args.udid, 'screenshot',
                            str(args.output / 'ready.png')], 15)
        status = 0
    except (RuntimeError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr, flush=True)
    finally:
        # Bounded diagnostics run on both success and failure, including a stuck
        # simctl. Save process names only, never process arguments or auth URLs.
        run('devices-after', ['xcrun', 'simctl', 'list', 'devices', '--json'], 10, False)
        run('processes', ['ps', '-axo', 'pid,ppid,state,etime,pcpu,comm'], 5, False)
        run('simulator-service', ['log', 'show', '--last', '5m', '--style', 'compact',
             '--predicate', 'process == "CoreSimulatorService" OR process == "Simulator" OR process == "simdiskimaged" OR eventMessage CONTAINS "simdiskimaged"'],
             10, False)
    return status


if __name__ == '__main__':
    raise SystemExit(main())
