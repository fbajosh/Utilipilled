import unittest
from analyze_switcher_measurements import analyze, percentiles
from measure_switcher_idle import cpu_seconds
from compare_switcher_resources import compare


class Measurements(unittest.TestCase):
    def test_percentiles_and_empty(self):
        self.assertIsNone(percentiles([])['p95_ms'])
        self.assertEqual(percentiles(range(1, 101)), {'n': 100, 'p50_ms': 50, 'p95_ms': 95, 'p99_ms': 99})

    def test_overlapping_sessions_are_not_mixed(self):
        events = [
            (1, 'invocation', 0), (1, 'presentation', 120), (1, 'commit', 140),
            (2, 'invocation', 150), (2, 'selection', 160), (1, 'activationConfirmed', 170),
            (2, 'render', 180), (2, 'commit', 190), (2, 'activationConfirmed', 230),
        ]
        result = analyze({'schema': 1, 'events': [{'session': s, 'kind': k, 'time': t * 1000000} for s, k, t in events]})
        self.assertEqual(result['latencies']['commit_to_observed_frontmost']['p50_ms'], 30)
        self.assertEqual(result['latencies']['selection_to_AppKit_draw']['p95_ms'], 20)
        self.assertEqual(result['latencies']['invocation_to_AppKit_presentation']['n'], 1)

    def test_malformed_records_are_rejected(self):
        with self.assertRaises(ValueError):
            analyze({'schema': 1, 'events': [{'kind': 'invocation', 'time': 1}]})

    def test_resource_pair_and_preconditions(self):
        base = dict(schema=1, pid=1, os='26.6.2', duration_seconds=300, average_cpu_percent=0.01, rss_mean_bytes=80000000)
        disabled = dict(base, label='disabled')
        enabled = dict(base, label='enabled', average_cpu_percent=0.02, rss_mean_bytes=81000000)
        result = compare(disabled, enabled)
        self.assertAlmostEqual(result['incremental_cpu_percentage_points'], 0.01)
        self.assertEqual(result['incremental_mean_rss_bytes'], 1000000)
        self.assertTrue(result['observed_increment_below_initial_targets'])
        with self.assertRaises(ValueError):
            compare(disabled, dict(enabled, pid=2))
        with self.assertRaises(ValueError):
            compare(disabled, dict(enabled, duration_seconds=10))
        with self.assertRaises(ValueError):
            compare(enabled, disabled)

    def test_cpu_duration_parsing(self):
        self.assertAlmostEqual(cpu_seconds('00:01.25'), 1.25)
        self.assertEqual(cpu_seconds('02:03:04'), 7384)
        self.assertEqual(cpu_seconds('1-02:03:04'), 93784)


if __name__ == '__main__':
    unittest.main()
