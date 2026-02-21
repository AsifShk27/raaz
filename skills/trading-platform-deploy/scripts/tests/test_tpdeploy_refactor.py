#!/usr/bin/env python3
"""Regression tests for tpdeploy modular refactor."""

import os
import sys
import unittest

SCRIPT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

from tpdeploy_lib.git_policy import is_mutating_git_command
from tpdeploy_lib.naming import canonical_lock_service_name, is_flink_job, normalize_flink_job_name, service_name_variants


class TpdeployRefactorTests(unittest.TestCase):
    def test_service_name_variants_include_aliases(self):
        variants = service_name_variants("trading-platform-auth_core")
        self.assertIn("trading-platform-auth_core", variants)
        self.assertIn("auth_core", variants)
        self.assertIn("auth-core", variants)

    def test_canonical_lock_service_name_returns_stable_key(self):
        key = canonical_lock_service_name("trading-platform-auth-core")
        self.assertNotIn("/", key)
        self.assertTrue(len(key) > 0)

    def test_flink_detection_and_normalization(self):
        self.assertTrue(is_flink_job("technical-indicators-java"))
        self.assertEqual(normalize_flink_job_name("technical-indicators-java"), "technical-indicators")

    def test_git_mutating_detection(self):
        self.assertFalse(is_mutating_git_command(["git", "status"]))
        self.assertTrue(is_mutating_git_command(["git", "commit", "-m", "x"]))


if __name__ == "__main__":
    unittest.main()
