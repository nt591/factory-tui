#!/usr/bin/env python3
"""Test E2E comparison validation without processes or benchmark dependencies."""

import copy
import importlib.util
import json
import sys
import unittest
from pathlib import Path
from unittest import mock

spec = importlib.util.spec_from_file_location(
    "compare", Path(__file__).with_name("compare-e2e.py")
)
compare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compare)
ROOT = Path(__file__).resolve().parent.parent


class Tests(unittest.TestCase):
    def setUp(self):
        self.report = json.loads(
            (ROOT / "docs/verification/e2e-perf-200-20261118.json").read_text()
        )

    def test_self_comparison(self):
        result = compare.compare(self.report, self.report)
        self.assertEqual(result["status"], "compared")
        for values in result["latency"].values():
            self.assertEqual(values["median_ms"]["difference"], 0)
            self.assertEqual(values["p95_ms"]["percent"], 0)

    def test_valid_change(self):
        candidate = copy.deepcopy(self.report)
        candidate["binary_sha256"] = "a" * 64
        entry = candidate["latency"]["card_navigation"]
        entry["samples_ms"] = [v * 2 for v in entry["samples_ms"]]
        entry.update(compare.summary(entry["samples_ms"]))
        result = compare.compare(self.report, candidate)
        self.assertEqual(
            result["latency"]["card_navigation"]["median_ms"]["percent"], 100
        )
        self.assertNotEqual(
            result["baseline_binary_sha256"], result["candidate_binary_sha256"]
        )

    def test_zero_baseline(self):
        self.assertIsNone(compare.delta(0, 1)["percent"])
        self.assertEqual(compare.delta(0, 1)["difference"], 1)

    def test_incompatible_metadata(self):
        for key in compare.COMPATIBILITY:
            if key == "schema_version":
                continue
            candidate = copy.deepcopy(self.report)
            candidate[key] = (
                {**candidate[key], "tasks": 201}
                if key == "parameters"
                else ("a" * 64 if key == "benchmark_sha256" else "different")
            )
            with (
                self.subTest(key=key),
                self.assertRaisesRegex(ValueError, "Incompatible"),
            ):
                compare.compare(self.report, candidate)

    def test_partial_status(self):
        for status in ("running", "failed", "interrupted"):
            candidate = {**self.report, "status": status}
            with self.assertRaises(ValueError):
                compare.compare(self.report, candidate)

    def test_missing_and_inconsistent_latency(self):
        mutations = [
            lambda r: r["latency"].pop("paste"),
            lambda r: r["latency"]["paste"]["samples_ms"].pop(),
            lambda r: r["latency"]["paste"].update(count=1),
            lambda r: r["latency"]["paste"].update(median_ms=0),
            lambda r: r["latency"]["paste"]["samples_ms"].__setitem__(0, float("nan")),
            lambda r: r["latency"]["paste"]["samples_ms"].__setitem__(0, -1),
            lambda r: r.update(binary_bytes=0),
            lambda r: r.update(binary_sha256="not-a-hash"),
            lambda r: r["parameters"].update(runs=True),
        ]
        for change in mutations:
            candidate = copy.deepcopy(self.report)
            change(candidate)
            with self.assertRaises((TypeError, ValueError)):
                compare.validate(candidate)

    def test_resource_completeness(self):
        for change in (
            lambda r: r["resources"].pop(),
            lambda r: r["resources"].__setitem__(1, r["resources"][0]),
            lambda r: r["resources"][0].update(rss_samples_bytes=[1]),
            lambda r: r["resources"][0].update(observer_cpu_seconds=float("inf")),
        ):
            candidate = copy.deepcopy(self.report)
            change(candidate)
            with self.assertRaises(ValueError):
                compare.validate(candidate)

    def test_different_checked_in_workloads_are_rejected(self):
        large = json.loads(
            (ROOT / "docs/verification/e2e-perf-1000-20261118.json").read_text()
        )
        with self.assertRaisesRegex(ValueError, "parameters"):
            compare.compare(self.report, large)

    def test_cli_failure_has_no_comparison_output(self):
        with (
            mock.patch.object(sys, "argv", ["compare", "baseline", "candidate"]),
            mock.patch.object(compare, "read", return_value={"status": "failed"}),
            mock.patch("builtins.print") as output,
            self.assertRaises(SystemExit) as failure,
        ):
            compare.main()
        self.assertEqual(failure.exception.code, 2)
        output.assert_not_called()


if __name__ == "__main__":
    unittest.main()
