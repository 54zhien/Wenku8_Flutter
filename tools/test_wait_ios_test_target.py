import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from wait_ios_test_target import boot_target


class IntegrationTargetTests(unittest.TestCase):
    def exercise(self, states, *, budget=270, fail_boot=False):
        clock = [0]
        calls = []
        remaining_states = iter(states)
        last = states[-1]

        def execute(args, **options):
            calls.append((args, options['timeout']))
            if args[2] == 'list':
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
        boots = [c for c in self.calls if c[0][2] == 'boot']
        self.assertEqual(len(boots), 1)
        self.assertEqual(boots[0][1], 268)
        self.assertEqual([h['state'] for h in self.history], ['Shutting Down'] * 2 + ['Shutdown'])

    def test_booting_or_booted_only_monitors_without_second_boot(self):
        for state in ('Booting', 'Booted'):
            self.exercise([state])
            self.assertEqual([c[0][2] for c in self.calls], ['list', 'bootstatus'])

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
