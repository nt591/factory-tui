#!/usr/bin/env python3
"""Validate fresh-switch lock comparisons without installs, processes, or network."""

import importlib.util
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "fresh_switch", Path(__file__).with_name("smoke-fresh-switch.py")
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class LockTests(unittest.TestCase):
    lock = 'depends: [\n  "ocaml" {= "5.3.0"}\n  "dune" {= "3.25.0"}\n]\n'

    def test_exact_versions(self):
        self.assertEqual(
            MODULE.verify_versions(self.lock, "ocaml 5.3.0\ndune 3.25.0\n"), 2
        )

    def test_missing_package(self):
        with self.assertRaisesRegex(ValueError, "Installed versions differ"):
            MODULE.verify_versions(self.lock, "ocaml 5.3.0")

    def test_changed_version(self):
        with self.assertRaisesRegex(ValueError, "Installed versions differ"):
            MODULE.verify_versions(self.lock, "ocaml 5.3.0\ndune 3.24.0")

    def test_additional_tools_do_not_satisfy_missing_dependency(self):
        with self.assertRaisesRegex(ValueError, "Installed versions differ"):
            MODULE.verify_versions(self.lock, "ocaml 5.3.0\nocamlformat 0.29.0")

    def test_additional_tools_are_allowed(self):
        self.assertEqual(
            MODULE.verify_versions(
                self.lock, "ocaml 5.3.0\ndune 3.25.0\nocamlformat 0.29.0"
            ),
            2,
        )

    def test_unpinned_constraint_is_not_verified(self):
        with self.assertRaisesRegex(ValueError, "exact locked"):
            MODULE.verify_versions('depends: [\n"dune" {>= "3.17"}\n]', "dune 3.25.0")

    def test_duplicate_lock_package(self):
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            MODULE.verify_versions(
                'depends: [\n"dune" {= "3.25.0"}\n"dune" {= "3.25.0"}\n]', "dune 3.25.0"
            )

    def test_missing_dependency_block(self):
        with self.assertRaisesRegex(ValueError, "dependency block"):
            MODULE.verify_versions('opam-version: "2.0"', "")

    def test_workaround_is_not_implicit(self):
        self.assertEqual(MODULE.compiler_overrides(False, "Darwin"), {})

    def test_workaround_is_platform_scoped(self):
        with self.assertRaisesRegex(ValueError, "only on macOS"):
            MODULE.compiler_overrides(True, "Linux")

    def test_explicit_workaround_records_configure_choices(self):
        values = MODULE.compiler_overrides(True, "Darwin")
        self.assertEqual(values["ac_cv_func_pipe2"], "no")
        self.assertEqual(values["MACOSX_DEPLOYMENT_TARGET"], "14.0")
        self.assertNotIn("OPAMDISABLESANDBOXING", values)

    def test_empty_lock_cannot_pass(self):
        with self.assertRaisesRegex(ValueError, "must contain"):
            MODULE.verify_versions("depends: []", "")


if __name__ == "__main__":
    unittest.main()
