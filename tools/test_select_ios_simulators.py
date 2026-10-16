import unittest
from select_ios_simulators import select_devices

RUNTIME = 'com.apple.CoreSimulator.SimRuntime.iOS-26-4'


def device(name, udid, available=True):
    return {'name': name, 'udid': udid, 'isAvailable': available}


class SimulatorSelectionTests(unittest.TestCase):
    def inventory(self, small=True):
        entries = [device('iPhone 17 Pro', 'pro'), device('iPad Pro 11-inch (M5)', 'pad')]
        if small:
            entries.append(device('iPhone SE (3rd generation)', 'small'))
        return {'devices': {RUNTIME: entries,
            'com.apple.CoreSimulator.SimRuntime.iOS-26-2': [device('iPhone 17 Pro', 'old')]}}

    def test_motion_uses_required_runtime_and_fixed_phone(self):
        selected = select_devices(self.inventory(), 'motion', lambda _: self.fail('Unexpected device creation'))
        self.assertEqual(selected, {'runtime': RUNTIME, 'udid': 'pro'})

    def test_interface_preserves_small_phone_and_ipad_coverage(self):
        selected = select_devices(self.inventory(), 'interface', lambda _: self.fail('Unexpected device creation'))
        self.assertEqual(selected, {'runtime': RUNTIME, 'udid': 'pro', 'small_udid': 'small', 'pad_udid': 'pad'})

    def test_absent_small_phone_is_created_on_the_same_runtime(self):
        calls = []
        def create(runtime):
            calls.append(runtime)
            return 'created-small'
        selected = select_devices(self.inventory(small=False), 'interface', create)
        self.assertEqual(calls, [RUNTIME])
        self.assertEqual(selected['small_udid'], 'created-small')

    def test_failed_small_device_creation_remains_a_failure(self):
        def fail_creation(_):
            raise RuntimeError('simctl create failed')
        with self.assertRaisesRegex(RuntimeError, 'simctl create failed'):
            select_devices(self.inventory(small=False), 'interface', fail_creation)

    def test_cannot_silently_fall_back_to_old_or_unavailable_runtime(self):
        inventory = self.inventory()
        inventory['devices'][RUNTIME][0]['isAvailable'] = False
        with self.assertRaisesRegex(RuntimeError, '26.4'):
            select_devices(inventory, 'motion', lambda _: self.fail('Unexpected device creation'))

    def test_missing_ipad_is_a_failure_instead_of_skipping_coverage(self):
        inventory = self.inventory()
        inventory['devices'][RUNTIME] = [device('iPhone 17 Pro', 'pro')]
        with self.assertRaisesRegex(RuntimeError, 'iPad'):
            select_devices(inventory, 'interface', lambda _: self.fail('Unexpected device creation'))


if __name__ == '__main__':
    unittest.main()
