"""Wait for XCTest teardown, then boot exactly one integration-test target.

The five-minute workflow budget includes teardown, one boot, and bootstatus.
No reset, second boot attempt, or substitute device is permitted.
"""
import json
from pathlib import Path, PurePosixPath
import subprocess
import sys
import time


def boot_target(udid, output, *, run=subprocess.run, now=time.monotonic,
                sleep=time.sleep, budget=270):
    deadline = now() + budget
    history = []
    output.mkdir(parents=True, exist_ok=True)

    def command(arguments, *, label=None, limit=None):
        remaining = deadline - now()
        if remaining <= 0:
            raise TimeoutError('Integration target exhausted its original boot budget')
        try:
            result = run(arguments, check=True, capture_output=True, text=True,
                         timeout=min(remaining, limit) if limit else remaining)
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
            if label:
                parts = [part.decode(errors='replace') if isinstance(part, bytes) else (part or '')
                         for part in (error.stdout, error.stderr)]
                detail = ''.join(parts)
                (output / f'{label}.txt').write_text(detail + '\n' + str(error))
            raise
        if label:
            (output / f'{label}.txt').write_text(result.stdout)
        return result.stdout

    while True:
        inventory = json.loads(command(['xcrun', 'simctl', 'list', 'devices', '--json']))
        selected = [d for group in inventory['devices'].values() for d in group
                    if d['udid'] == udid]
        if len(selected) != 1:
            raise RuntimeError('Selected integration target disappeared')
        state = selected[0]['state']
        history.append({'state': state, 'remaining_seconds': deadline - now()})
        (output / 'integration-target-states.json').write_text(json.dumps(history, indent=2))
        if state != 'Shutting Down':
            break
        if deadline - now() <= 1:
            raise TimeoutError('XCTest teardown did not finish within the boot budget')
        sleep(1)
    if state == 'Shutdown':
        command(['xcrun', 'simctl', 'boot', udid])
    elif state not in ('Booting', 'Booted'):
        raise RuntimeError(f'Unexpected simulator state: {state}')
    developer = command(['xcode-select', '-p'], label='developer', limit=10).strip()
    command(['open', '-a', str(PurePosixPath(developer) / 'Applications/Simulator.app'),
             '--args', '-CurrentDeviceUDID', udid], label='display-session', limit=15)
    log = command(['xcrun', 'simctl', 'bootstatus', udid], label='bootstatus')
    (output / 'integration-boot.log').write_text(log)
    command(['xcrun', 'simctl', 'io', udid, 'screenshot',
             str(output / 'integration-ready.png')], label='ready-image', limit=15)


if __name__ == '__main__':
    boot_target(sys.argv[1], Path(sys.argv[2]))
