#!/usr/bin/env python3
import unittest
from release_plan import release_plan


class ReleasePlanTests(unittest.TestCase):
    def test_main_version_bump_publishes_without_a_manual_tag(self):
        self.assertEqual(release_plan('1.2.1', 'v1.2.0', 'refs/heads/main'),
                         {'version': '1.2.1', 'tag': 'v1.2.1', 'publish': 'true'})

    def test_ordinary_merge_does_not_republish_existing_version(self):
        self.assertEqual(release_plan('1.2.1', 'v1.2.1', 'refs/heads/main')['publish'], 'false')

    def test_matching_manual_tag_still_publishes(self):
        self.assertEqual(release_plan('1.2.1', 'v1.2.0', 'refs/tags/v1.2.1')['publish'], 'true')

    def test_duplicate_manual_tag_is_rejected(self):
        with self.assertRaises(ValueError):
            release_plan('1.2.1', 'v1.2.1', 'refs/tags/v1.2.1')

    def test_other_branches_and_mismatched_tags_are_rejected(self):
        for ref in ('refs/heads/feature', 'refs/tags/v1.2.2', 'refs/tags/v1.2.1-rc1'):
            with self.subTest(ref=ref), self.assertRaises(ValueError):
                release_plan('1.2.1', 'v1.2.0', ref)

    def test_downgrades_are_rejected(self):
        for ref in ('refs/heads/main', 'refs/tags/v1.2.1'):
            with self.subTest(ref=ref), self.assertRaises(ValueError):
                release_plan('1.2.1', 'v1.3.0', ref)

    def test_versions_are_compared_numerically(self):
        self.assertEqual(release_plan('1.10.0', 'v1.9.0', 'refs/heads/main')['publish'], 'true')

    def test_invalid_app_versions_are_rejected(self):
        for version in ('1.2.1-rc1', '01.2.1', '1.2', '1.2.1\nextra=unsafe', None):
            with self.subTest(version=version), self.assertRaises(ValueError):
                release_plan(version, 'v1.2.0', 'refs/heads/main')

    def test_invalid_published_version_is_rejected(self):
        with self.assertRaises(ValueError):
            release_plan('1.2.1', 'invalid', 'refs/heads/main')

    def test_first_release_does_not_require_an_existing_release(self):
        self.assertEqual(release_plan('1.0.0', '', 'refs/heads/main')['publish'], 'true')


if __name__ == '__main__':
    unittest.main()
