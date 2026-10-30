#!/usr/bin/env python3
import tempfile
import unittest
from pathlib import Path
from update_cask import update_cask


class CaskUpdateTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / 'utilipilled.rb'
        self.original = 'cask "utilipilled" do\n  version "1.2.0"\n  sha256 "' + 'a' * 64 + '"\n\n  app "Utilipilled.app"\nend\n'
        self.path.write_text(self.original)

    def test_updates_only_release_fields(self):
        self.assertTrue(update_cask(self.path, '1.2.1', 'b' * 64))
        self.assertEqual(self.path.read_text(), self.original.replace('1.2.0', '1.2.1').replace('a' * 64, 'b' * 64))

    def test_retry_of_same_release_is_a_noop(self):
        self.assertFalse(update_cask(self.path, '1.2.0', 'a' * 64))
        self.assertEqual(self.path.read_text(), self.original)

    def test_preserves_matching_text_in_comments(self):
        comment = '# Previous  version "1.2.0"\n# Previous  sha256 "' + 'a' * 64 + '"\n'
        self.path.write_text(comment + self.original)
        update_cask(self.path, '1.2.1', 'b' * 64)
        self.assertEqual(self.path.read_text(), comment + self.original.replace('1.2.0', '1.2.1').replace('a' * 64, 'b' * 64))

    def test_rejects_downgrades_and_changed_existing_release(self):
        for version in ('1.1.9', '1.2.0'):
            with self.subTest(version=version), self.assertRaises(ValueError):
                update_cask(self.path, version, 'b' * 64)
        self.assertEqual(self.path.read_text(), self.original)

    def test_compares_versions_numerically(self):
        self.path.write_text(self.original.replace('1.2.0', '1.9.0'))
        self.assertTrue(update_cask(self.path, '1.10.0', 'b' * 64))

    def test_rejects_invalid_release_values_without_writing(self):
        for version, checksum in [('1.2.1-rc1', 'b' * 64), ('1.2.1"\nend', 'b' * 64), ('1.2.1', 'invalid')]:
            with self.subTest(version=version, checksum=checksum), self.assertRaises(ValueError):
                update_cask(self.path, version, checksum)
        self.assertEqual(self.path.read_text(), self.original)

    def test_rejects_missing_or_duplicate_fields_without_writing(self):
        for text in (self.original.replace('  version', '# version'), self.original + '  sha256 "' + 'a' * 64 + '"\n'):
            self.path.write_text(text)
            with self.subTest(text=text), self.assertRaises(ValueError):
                update_cask(self.path, '1.2.1', 'b' * 64)
            self.assertEqual(self.path.read_text(), text)


if __name__ == '__main__':
    unittest.main()
