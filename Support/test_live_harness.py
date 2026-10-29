#!/usr/bin/env python3
"""Safe harness tests: no real app or volume-control command is launched."""
import pathlib
import subprocess
import sys
import tempfile
import unittest

import check_live


class LiveHarnessTests(unittest.TestCase):
    def test_zero_baseline_cannot_report_a_mute_pass(self):
        with self.assertRaisesRegex(RuntimeError, "above zero"):
            check_live.require_audible_baseline({"alert volume": "0"})
        self.assertEqual(check_live.require_audible_baseline({"alert volume": "63"}), 63)

    def test_production_lock_rejects_another_instance(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = pathlib.Path(tmp) / "state"
            with check_live.production_lock(directory):
                with self.assertRaisesRegex(RuntimeError, "Quit Utilipilled"):
                    with check_live.production_lock(directory):
                        self.fail("A second test acquired the active production lock")

    def test_pending_production_recovery_is_not_discarded(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = pathlib.Path(tmp) / "state"
            directory.mkdir(mode=0o700)
            record = directory / "recovery.json"
            record.write_text('{"originalVolume": 74}')
            with self.assertRaisesRegex(RuntimeError, "existing recovery"):
                with check_live.production_lock(directory):
                    self.fail("Live test ignored production recovery")
            self.assertTrue(record.exists())

    def test_symlink_lock_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = pathlib.Path(tmp) / "state"
            directory.mkdir(mode=0o700)
            (directory / "instance.lock").symlink_to(pathlib.Path(tmp) / "outside")
            with self.assertRaises(OSError):
                with check_live.production_lock(directory):
                    self.fail("Live test followed a lock symlink")

    def test_partial_startup_line_is_bounded(self):
        process = subprocess.Popen(
            [sys.executable, "-c", "import sys,time;sys.stdout.write('partial');sys.stdout.flush();time.sleep(5)"],
            stdout=subprocess.PIPE,
        )
        try:
            with self.assertRaisesRegex(RuntimeError, "startup timed out"):
                check_live.startup_line(process, timeout=0.1)
        finally:
            process.kill()
            process.wait(timeout=2)
            process.stdout.close()

    def test_complete_startup_line_is_read(self):
        process = subprocess.Popen([sys.executable, "-c", "print('Exercise active')"], stdout=subprocess.PIPE)
        try:
            self.assertEqual(check_live.startup_line(process), "Exercise active")
        finally:
            process.wait(timeout=2)
            process.stdout.close()


if __name__ == "__main__":
    unittest.main()
