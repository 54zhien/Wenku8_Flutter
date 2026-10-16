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
    def exercise(self, *, initialize=False, timeout=False, image_failure=False):
        commands = []
        with tempfile.TemporaryDirectory() as temporary:
            destination = Path(temporary) / 'evidence'
            arguments = ['boot', '--initialize', str(destination)] if initialize else [
                'boot', '00000000-0000-0000-0000-000000000000', str(destination)]

            def execute(command, *, stdout, **options):
                commands.append(command)
                if command[:4] == ['xcrun', 'simctl', 'list', 'devices']:
                    stdout.write(b'{"devices": {}}')
                if command[:3] == ['xcrun', 'simctl', 'bootstatus'] and timeout:
                    raise subprocess.TimeoutExpired(command, options['timeout'])
                code = 1 if image_failure and 'screenshot' in command else 0
                return subprocess.CompletedProcess(command, code)

            with patch.object(boot.sys, 'platform', 'darwin'), \
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
