#!/usr/bin/env python3
"""Test the fixture UI runner's plan and evidence states without running UI processes."""

import hashlib
import importlib.util
import io
import json
import subprocess
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock

spec = importlib.util.spec_from_file_location(
    "check_ui", Path(__file__).with_name("check-ui.py")
)
check_ui = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check_ui)


class CheckUiTests(unittest.TestCase):
    def test_all_cases_have_local_fixture_scripts(self):
        self.assertEqual(len(set(check_ui.CASES)), len(check_ui.CASES))
        for case in check_ui.CASES:
            path = check_ui.ROOT / f"scripts/smoke-{case}.py"
            self.assertTrue(path.is_file(), case)
            self.assertNotIn("codex", case)
            self.assertIn('"--binary"', path.read_text())

    def test_one_build_precedes_all_terminal_cases(self):
        steps = check_ui.plan(Path("/binary"), Path("/evidence"), check_ui.CASES, True)
        self.assertEqual([name for name, _ in steps[:2]], ["format", "unit"])
        self.assertEqual([name for name, _ in steps[2:]], list(check_ui.CASES))
        for _, command in steps[2:]:
            self.assertEqual(command[command.index("--binary") + 1], "/binary")
            self.assertIn("--preview", command)
            self.assertNotIn("build.sh", " ".join(command))

    def test_existing_binary_plan_skips_build_and_unit(self):
        steps = check_ui.plan(Path("/package/bin"), Path("/evidence"), ["panes"], False)
        self.assertEqual([name for name, _ in steps], ["panes"])
        self.assertEqual(steps[0][1][steps[0][1].index("--binary") + 1], "/package/bin")

    def test_interrupted_child_group_is_stopped_and_reaped(self):
        process = mock.Mock(pid=73)
        with mock.patch.object(check_ui.os, "killpg") as kill:
            check_ui.stop_process(process)
        kill.assert_called_once_with(73, check_ui.signal.SIGTERM)
        process.wait.assert_called_once_with(timeout=5)

    def test_stuck_child_group_is_killed_and_reaped(self):
        process = mock.Mock(pid=73)
        process.wait.side_effect = [subprocess.TimeoutExpired("fixture", 5), 0]
        with mock.patch.object(check_ui.os, "killpg") as kill:
            check_ui.stop_process(process)
        self.assertEqual(
            kill.call_args_list,
            [
                mock.call(73, check_ui.signal.SIGTERM),
                mock.call(73, check_ui.signal.SIGKILL),
            ],
        )
        self.assertEqual(
            process.wait.call_args_list, [mock.call(timeout=5), mock.call()]
        )

    def test_fail_fast_retains_failed_log_and_unrun_cases(self):
        with tempfile.TemporaryDirectory() as directory, redirect_stdout(io.StringIO()):
            output = Path(directory)
            calls = []
            report = {"scope": "test"}

            def run(command, log):
                calls.append(command)
                log.write(b"fixture output\n")
                return 3 if len(calls) == 2 else 0

            result = check_ui.execute(
                [("first", ["a"]), ("failed", ["b"]), ("later", ["c"])],
                output,
                report,
                run=run,
            )
            saved = json.loads((output / "report.json").read_text())
            self.assertEqual(result, 1)
            self.assertEqual(saved["status"], "failed")
            self.assertEqual(
                [step["status"] for step in saved["steps"]],
                ["passed", "failed", "not_run"],
            )
            self.assertEqual(saved["steps"][1]["returncode"], 3)
            self.assertEqual((output / "failed.log").read_bytes(), b"fixture output\n")
            self.assertFalse((output / "later.log").exists())
            self.assertEqual(calls, [["a"], ["b"]])

    def test_success_reports_all_steps(self):
        with tempfile.TemporaryDirectory() as directory, redirect_stdout(io.StringIO()):
            output = Path(directory)
            report = {}
            self.assertEqual(
                check_ui.execute([("one", ["a"])], output, report, run=lambda *_: 0), 0
            )
            saved = json.loads((output / "report.json").read_text())
            self.assertEqual(saved["status"], "passed")
            self.assertEqual(saved["steps"][0]["status"], "passed")
            self.assertFalse((output / "report.tmp").exists())

    def test_final_report_lists_actual_previews_and_executable_digest(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            binary = output / "fixture-binary"
            binary.write_bytes(b"executable fixture bytes")
            (output / "b.png").write_bytes(b"image fixture")
            (output / "a.png").write_bytes(b"image fixture")
            (output / "one.log").write_text("log")
            check_ui.finalize_report(output, {"status": "failed"}, binary)
            saved = json.loads((output / "report.json").read_text())
            self.assertEqual(saved["status"], "failed")
            self.assertEqual(saved["previews"], ["a.png", "b.png"])
            self.assertEqual(
                saved["binary_sha256"], hashlib.sha256(binary.read_bytes()).hexdigest()
            )
            check_ui.finalize_report(
                output, {"status": "interrupted"}, output / "missing"
            )
            saved = json.loads((output / "report.json").read_text())
            self.assertEqual(saved["status"], "interrupted")
            self.assertEqual(saved["previews"], ["a.png", "b.png"])
            self.assertNotIn("binary_sha256", saved)

    def test_launch_failure_is_failed_not_interrupted(self):
        with tempfile.TemporaryDirectory() as directory, redirect_stdout(io.StringIO()):
            output = Path(directory)
            report = {}

            def unavailable(*_):
                raise FileNotFoundError("fixture")

            self.assertEqual(
                check_ui.execute(
                    [("one", ["a"]), ("later", ["b"])], output, report, run=unavailable
                ),
                1,
            )
            saved = json.loads((output / "report.json").read_text())
            self.assertEqual(saved["status"], "failed")
            self.assertEqual(saved["steps"][0]["error_type"], "FileNotFoundError")
            self.assertEqual(saved["steps"][1]["status"], "not_run")

    def test_interrupt_is_not_reported_as_pass(self):
        with tempfile.TemporaryDirectory() as directory, redirect_stdout(io.StringIO()):
            output = Path(directory)
            report = {}

            def interrupted(*_):
                raise KeyboardInterrupt

            with self.assertRaises(KeyboardInterrupt):
                check_ui.execute(
                    [("one", ["a"]), ("later", ["b"])], output, report, run=interrupted
                )
            saved = json.loads((output / "report.json").read_text())
            self.assertEqual(saved["status"], "interrupted")
            self.assertEqual(
                [step["status"] for step in saved["steps"]], ["interrupted", "not_run"]
            )


if __name__ == "__main__":
    unittest.main()
