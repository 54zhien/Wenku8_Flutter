"""Wait for XCTest teardown, then boot exactly one integration-test target.

The five-minute workflow budget includes teardown, one boot, and bootstatus.
No reset, second boot attempt, or substitute device is permitted.
"""
import json
from pathlib import Path
import subprocess
import sys
import time


def boot_target(udid, output, *, run=subprocess.run, now=time.monotonic,
                sleep=time.sleep, budget=270):
    deadline = now() + budget
    history = []
    output.mkdir(parents=True, exist_ok=True)

    def command(arguments):
        remaining = deadline - now()
        if remaining <= 0:
            raise TimeoutError('Integration target exhausted its original boot budget')
        return run(arguments, check=True, capture_output=True, text=True,
                   timeout=remaining).stdout

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
    log = command(['xcrun', 'simctl', 'bootstatus', udid])
    (output / 'integration-boot.log').write_text(log)


if __name__ == '__main__':
    boot_target(sys.argv[1], Path(sys.argv[2]))
