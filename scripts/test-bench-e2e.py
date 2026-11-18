#!/usr/bin/env python3
"""Test perf report summaries and fixture construction without launching a TUI."""

import importlib.util
import json
import math
import stat
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest import mock

spec = importlib.util.spec_from_file_location(
    "bench", Path(__file__).with_name("bench-e2e.py")
)
bench = importlib.util.module_from_spec(spec)
with mock.patch.dict(
    sys.modules, {"fixtures.terminal": types.SimpleNamespace(Terminal=object)}
):
    spec.loader.exec_module(bench)


class Tests(unittest.TestCase):
    def test_distribution(self):
        self.assertEqual(bench.distribution([4, 1, 3, 2])["median_ms"], 2.5)
        self.assertEqual(bench.distribution(list(range(20)))["p95_ms"], 18)
        self.assertEqual(bench.distribution([3])["max_ms"], 3)
        for values in ([], [-1], [math.nan], [math.inf]):
            with self.assertRaises(ValueError):
                bench.distribution(values)

    def test_existing_state_is_not_latency(self):
        probe = bench.Probe.__new__(bench.Probe)
        action = mock.Mock()
        with self.assertRaises(ValueError):
            probe.latency(action, lambda: True, 1)
        action.assert_not_called()

    def test_failure_and_interrupt_keep_partial_report(self):
        for error, status in (
            (RuntimeError("fixture failure"), "failed"),
            (KeyboardInterrupt(), "interrupted"),
        ):
            with tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "report.json"

                def fail(args, report, error=error):
                    report["latency"] = {"card_navigation": bench.distribution([2])}
                    report["current_action"] = "stream_replacement"
                    raise error

                with (
                    mock.patch.object(sys, "argv", ["bench", "--report", str(path)]),
                    mock.patch.object(bench, "run", side_effect=fail),
                    self.assertRaises(type(error)),
                ):
                    bench.main()
                report = json.loads(path.read_text())
                self.assertEqual(report["status"], status)
                self.assertEqual(report["current_action"], "stream_replacement")
                self.assertEqual(
                    report["latency"]["card_navigation"]["samples_ms"], [2]
                )

    def test_snapshot(self):
        source = {
            "tasks": [
                {"id": "seed", "state": "queued", "messages": [], "model": "fixture"}
            ],
            "serial": 0,
            "drafts": [],
        }
        fixture = bench.seed_snapshot(source, 3, 4)
        self.assertEqual(source["tasks"][0]["id"], "seed")
        self.assertEqual(
            [task["id"] for task in fixture["tasks"]], ["P-0000", "P-0001", "P-0002"]
        )
        self.assertEqual(
            [len(task["messages"]) for task in fixture["tasks"]], [5, 1, 1]
        )
        self.assertEqual(fixture["selected"], "P-0000")
        self.assertTrue(fixture["tasks"][0]["messages"][0]["queued"])
        self.assertFalse(fixture["tasks"][0]["messages"][1]["queued"])

    def test_private_atomic_report(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "report.json"
            bench.write_report(path, {"status": "failed", "latency": {}})
            self.assertEqual(json.loads(path.read_text())["status"], "failed")
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            self.assertEqual(list(Path(directory).iterdir()), [path])


if __name__ == "__main__":
    unittest.main()
