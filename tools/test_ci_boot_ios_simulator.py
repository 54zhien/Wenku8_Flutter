import contextlib
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import ci_boot_ios_simulator as boot


class SimulatorGateTests(unittest.TestCase):
    def exercise(self, *, initialize=False, timeout=False, image_failure=False, inventory_timeout=False, display_failure=False, shutdown_others=False, inventory=None, shutdown_failure=False, start_failure=False, elapsed_start=0, elapsed_display=0):
        commands = []
        clock = [0.0]
        with tempfile.TemporaryDirectory() as temporary:
            destination = Path(temporary) / 'evidence'
            arguments = ['boot', '--initialize', str(destination)] if initialize else [
                'boot', '00000000-0000-0000-0000-000000000000', str(destination)]

            if shutdown_others:
                arguments += ['--shutdown-others']

            def execute(command, *, stdout, **options):
                commands.append(command)
                if command[:3] == ['xcrun', 'simctl', 'boot']:
                    clock[0] += elapsed_start
                if command[0] == 'open':
                    clock[0] += elapsed_display
                if command[:4] == ['xcrun', 'simctl', 'list', 'devices']:
                    if inventory_timeout:
                        raise subprocess.TimeoutExpired(command, options['timeout'])
                    stdout.write(json.dumps(inventory or {'devices': {'runtime': [{'udid': '00000000-0000-0000-0000-000000000000', 'state': 'Shutdown'}]}}).encode())
                if command[:3] == ['xcrun', 'simctl', 'bootstatus'] and timeout:
                    raise subprocess.TimeoutExpired(command, options['timeout'])
                code = 1 if ((image_failure and 'screenshot' in command) or (display_failure and command[0] == 'open') or (shutdown_failure and command[:3] == ['xcrun', 'simctl', 'shutdown']) or (start_failure and command[:3] == ['xcrun', 'simctl', 'boot'])) else 0
                return subprocess.CompletedProcess(command, code)

            with patch.object(boot.time, 'monotonic', side_effect=lambda: clock[0]), \
                    patch.object(boot.sys, 'platform', 'darwin'), \
                    patch.object(boot.sys, 'argv', arguments), \
                    patch.object(boot.subprocess, 'check_output', return_value='/Applications/Xcode.app/Contents/Developer'), \
                    patch.object(boot.subprocess, 'run', side_effect=execute), \
                    contextlib.redirect_stdout(io.StringIO()), \
                    contextlib.redirect_stderr(io.StringIO()):
                status = boot.main()
            evidence = json.loads((destination / 'stages.json').read_text())
            self.assertTrue((destination / 'devices-after.txt').exists())
            self.assertTrue((destination / 'simulator-service.txt').exists())
            return status, evidence, commands

    def test_initialization_cannot_be_mistaken_for_device_readiness(self):
        status, evidence, commands = self.exercise(initialize=True)
        self.assertEqual(status, 0)
        self.assertFalse(any('bootstatus' in command for command in commands))
        self.assertFalse(any('screenshot' in command for command in commands))
        self.assertEqual(next(stage for stage in evidence if stage['stage'] == 'display-session')['exit_code'], 0)

    def test_cold_inventory_is_not_the_display_launch_gate(self):
        status, evidence, _ = self.exercise(initialize=True, inventory_timeout=True)
        self.assertEqual(status, 0)
        self.assertFalse(any(stage['stage'] == 'devices-before' for stage in evidence))
        self.assertTrue(next(stage for stage in evidence if stage['stage'] == 'devices-after')['timed_out'])

    def test_display_launch_failure_still_fails_initialization(self):
        status, _, _ = self.exercise(initialize=True, display_failure=True)
        self.assertEqual(status, 1)

    def test_only_other_running_devices_stop_before_display_and_boot(self):
        target = '00000000-0000-0000-0000-000000000000'
        other = '11111111-1111-1111-1111-111111111111'
        stopped = '22222222-2222-2222-2222-222222222222'
        inventory = {'devices': {'runtime': [
            {'udid': target, 'state': 'Booted'},
            {'udid': other, 'state': 'Booted'},
            {'udid': stopped, 'state': 'Shutdown'}]}}
        status, _, commands = self.exercise(shutdown_others=True, inventory=inventory)
        self.assertEqual(status, 0)
        shutdowns = [command for command in commands if command[:3] == ['xcrun', 'simctl', 'shutdown']]
        self.assertEqual(shutdowns, [['xcrun', 'simctl', 'shutdown', other]])
        shutdown_index = commands.index(shutdowns[0])
        self.assertLess(shutdown_index, next(i for i, cmd in enumerate(commands) if cmd[0] == 'open'))
        self.assertLess(shutdown_index, next(i for i, cmd in enumerate(commands) if 'bootstatus' in cmd))

    def test_failed_other_device_shutdown_stops_before_gui_or_boot(self):
        inventory = {'devices': {'runtime': [
            {'udid': '00000000-0000-0000-0000-000000000000', 'state': 'Shutdown'},
            {'udid': '11111111-1111-1111-1111-111111111111', 'state': 'Booted'}]}}
        status, _, commands = self.exercise(shutdown_others=True, inventory=inventory, shutdown_failure=True)
        self.assertEqual(status, 1)
        self.assertFalse(any(command[0] == 'open' or 'bootstatus' in command for command in commands))

    def test_one_boot_owner_starts_before_gui_and_readiness_only_monitors(self):
        status, _, commands = self.exercise()
        self.assertEqual(status, 0)
        starts = [command for command in commands if command[:3] == ['xcrun', 'simctl', 'boot']]
        self.assertEqual(len(starts), 1)
        started = commands.index(starts[0])
        displayed = next(i for i, command in enumerate(commands) if command[0] == 'open')
        ready = next(i for i, command in enumerate(commands) if 'bootstatus' in command)
        self.assertLess(started, displayed)
        self.assertLess(displayed, ready)
        self.assertNotIn('-b', commands[ready])

    def test_already_booted_target_is_only_monitored(self):
        inventory = {'devices': {'runtime': [
            {'udid': '00000000-0000-0000-0000-000000000000', 'state': 'Booted'}]}}
        status, _, commands = self.exercise(inventory=inventory)
        self.assertEqual(status, 0)
        self.assertFalse(any(command[:3] == ['xcrun', 'simctl', 'boot'] for command in commands))
        self.assertNotIn('-b', next(command for command in commands if 'bootstatus' in command))

    def test_boot_start_failure_is_not_retried_by_gui_or_readiness(self):
        status, _, commands = self.exercise(start_failure=True)
        self.assertEqual(status, 1)
        self.assertFalse(any(command[0] == 'open' or 'bootstatus' in command for command in commands))

    def test_start_and_display_consume_original_readiness_budget(self):
        status, evidence, _ = self.exercise(elapsed_start=10, elapsed_display=5)
        self.assertEqual(status, 0)
        readiness = next(stage for stage in evidence if stage['stage'] == 'boot-readiness')
        self.assertEqual(readiness['timeout_seconds'], 345)

    def test_exhausted_original_budget_cannot_start_a_fresh_wait(self):
        status, _, commands = self.exercise(elapsed_start=350, elapsed_display=15)
        self.assertEqual(status, 1)
        self.assertFalse(any('bootstatus' in command for command in commands))

    def test_timeout_fails_once_and_keeps_diagnostics(self):
        status, evidence, commands = self.exercise(timeout=True)
        self.assertEqual(status, 1)
        self.assertEqual(sum('bootstatus' in command for command in commands), 1)
        failure = next(stage for stage in evidence if stage['stage'] == 'boot-readiness')
        self.assertTrue(failure['timed_out'])
        self.assertEqual(failure['exit_code'], 124)

    def test_failed_display_capture_cannot_pass_gate(self):
        status, _, _ = self.exercise(image_failure=True)
        self.assertEqual(status, 1)

    def test_success_requires_readiness_and_display_capture(self):
        status, evidence, _ = self.exercise()
        self.assertEqual(status, 0)
        stages = {stage['stage']: stage for stage in evidence}
        self.assertEqual(stages['boot-readiness']['exit_code'], 0)
        self.assertEqual(stages['ready-image']['exit_code'], 0)


if __name__ == '__main__':
    unittest.main()
