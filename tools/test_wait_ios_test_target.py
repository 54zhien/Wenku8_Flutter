import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from wait_ios_test_target import boot_target


class IntegrationTargetTests(unittest.TestCase):
    def exercise(self, states, *, budget=270, fail_boot=False, fail_display=False):
        clock = [0]
        calls = []
        remaining_states = iter(states)
        last = states[-1]

        def execute(args, **options):
            calls.append((args, options['timeout']))
            if args[0] == 'xcode-select':
                text = '/Applications/Xcode.app/Contents/Developer\n'
            elif args[0] == 'open' and fail_display:
                raise subprocess.CalledProcessError(1, args)
            elif args[2] == 'list':
                state = next(remaining_states, last)
                text = json.dumps({'devices': {'ios': [{'udid': 'target', 'state': state}]}})
            elif args[2] == 'boot' and fail_boot:
                raise subprocess.CalledProcessError(1, args)
            else:
                text = 'ready'
            return subprocess.CompletedProcess(args, 0, stdout=text)

        def sleep(seconds):
            clock[0] += seconds

        with tempfile.TemporaryDirectory() as root:
            try:
                boot_target('target', Path(root), run=execute, now=lambda: clock[0],
                            sleep=sleep, budget=budget)
            finally:
                self.calls = calls
                self.history = json.loads((Path(root) / 'integration-target-states.json').read_text())

    def test_xctest_shutdown_transition_finishes_before_one_boot(self):
        self.exercise(['Shutting Down', 'Shutting Down', 'Shutdown'])
        boots = [c for c in self.calls if c[0][:3] == ['xcrun', 'simctl', 'boot']]
        self.assertEqual(len(boots), 1)
        self.assertEqual(boots[0][1], 268)
        self.assertEqual([h['state'] for h in self.history], ['Shutting Down'] * 2 + ['Shutdown'])

    def test_booting_or_booted_only_monitors_without_second_boot(self):
        for state in ('Booting', 'Booted'):
            self.exercise([state])
            self.assertFalse(any(c[0][:3] == ['xcrun', 'simctl', 'boot'] for c in self.calls))

    def test_display_and_render_readiness_follow_one_explicit_boot(self):
        self.exercise(['Shutdown'])
        commands = [c[0] for c in self.calls]
        opened_commands = [c for c in commands if c[0] == 'open']
        self.assertEqual(len(opened_commands), 1)
        opened = opened_commands[0]
        self.assertEqual(opened, ['open', '-a', '/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app', '--args', '-CurrentDeviceUDID', 'target'])
        ready = next(c for c in commands if 'bootstatus' in c)
        screenshot = next(c for c in commands if 'screenshot' in c)
        self.assertLess(commands.index(opened), commands.index(ready))
        self.assertLess(commands.index(ready), commands.index(screenshot))

    def test_display_failure_does_not_pass_booted_state_as_render_readiness(self):
        with self.assertRaises(subprocess.CalledProcessError):
            self.exercise(['Booted'], fail_display=True)
        self.assertFalse(any('bootstatus' in c[0] or 'screenshot' in c[0] for c in self.calls))

    def test_teardown_deadline_fails_without_reset_or_boot(self):
        with self.assertRaises(TimeoutError):
            self.exercise(['Shutting Down'], budget=3)
        self.assertTrue(all(c[0][2] == 'list' for c in self.calls))

    def test_boot_failure_is_not_retried(self):
        with self.assertRaises(subprocess.CalledProcessError):
            self.exercise(['Shutdown'], fail_boot=True)
        self.assertEqual([c[0][2] for c in self.calls], ['list', 'boot'])

    def test_unknown_state_fails(self):
        with self.assertRaises(RuntimeError):
            self.exercise(['Creating'])


if __name__ == '__main__':
    unittest.main()
