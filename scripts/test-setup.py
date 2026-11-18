#!/usr/bin/env python3
"""Check setup file safety and prompts without models, credentials or repositories."""

import importlib.util
import stat
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

spec = importlib.util.spec_from_file_location(
    "setup", Path(__file__).with_name("setup.py")
)
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)


class Tests(unittest.TestCase):
    def test_variable_and_model_validation(self):
        self.assertTrue(setup.variable("LITELLM_API_KEY"))
        for value in ("1KEY", "KEY=value", "bad name", "", "sk-abc-secret"):
            self.assertFalse(setup.variable(value))
        self.assertTrue(setup.model("provider/model"))
        for value in ("your-model-id", "coding-large", "-flag", "", "model\nvalue"):
            self.assertFalse(setup.model(value))

    def test_toml_quotes_and_unicode(self):
        text = setup.toml(
            {"workspace": {"source": '/fixture/a"b\\c', "model": "é-model"}}
        )
        self.assertIn('source = "/fixture/a\\"b\\\\c"', text)
        self.assertIn("é-model", text)

    def test_no_secret_in_validation_environment_and_private_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            config, gateway = root / "config.toml", root / "gateway.toml"
            with mock.patch.object(
                setup.subprocess, "run", return_value=mock.Mock(returncode=0)
            ) as run:
                setup.install(
                    {config: "[storage]\n", gateway: 'key_environment="KEY"\n'},
                    Path("/fixture/binary"),
                    root,
                )
            self.assertEqual(set(run.call_args.kwargs["env"]), {"HOME", "PATH"})
            self.assertIn("--check-config", run.call_args.args[0])
            for file in (config, gateway):
                self.assertEqual(stat.S_IMODE(file.stat().st_mode), 0o600)
            self.assertEqual(set(root.iterdir()), {config, gateway})

    def test_conflict_rolls_back_only_our_new_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            config, gateway = root / "config.toml", root / "gateway.toml"
            gateway.write_text("existing")
            with (
                mock.patch.object(
                    setup.subprocess, "run", return_value=mock.Mock(returncode=0)
                ),
                self.assertRaises(FileExistsError),
            ):
                setup.install(
                    {config: "[storage]\n", gateway: "new"},
                    Path("/fixture/binary"),
                    root,
                )
            self.assertFalse(config.exists())
            self.assertEqual(gateway.read_text(), "existing")

    def test_validator_failure_publishes_nothing(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with (
                mock.patch.object(
                    setup.subprocess, "run", return_value=mock.Mock(returncode=2)
                ),
                self.assertRaises(ValueError),
            ):
                setup.install(
                    {root / "config.toml": "invalid"}, Path("/fixture/binary"), root
                )
            self.assertEqual(list(root.iterdir()), [])

    def test_folder_wizard_cancel_and_save(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            binary = root / "binary"
            binary.write_text("fixture")
            binary.chmod(0o700)
            output = root / "config"
            answers = [
                str(binary),
                "",
                "",
                "fixture-model",
                "",
                "",
                str(root),
                "",
                "yes",
            ]
            with (
                mock.patch.object(
                    sys,
                    "argv",
                    ["setup", "--binary", str(binary), "--config-dir", str(output)],
                ),
                mock.patch("builtins.input", side_effect=answers),
                mock.patch("builtins.print"),
                mock.patch.object(
                    setup.subprocess, "run", return_value=mock.Mock(returncode=0)
                ) as run,
            ):
                setup.main()
            self.assertEqual(run.call_count, 1)
            config = (output / "config.toml").read_text()
            self.assertIn('mode = "folder"', config)
            self.assertNotIn("jj =", config)
            self.assertNotIn("parent =", config)
            self.assertIn(
                'key_environment = "LITELLM_API_KEY"',
                (output / "gateway.toml").read_text(),
            )
            self.assertFalse((output / "board.sqlite").exists())

    def test_cancelling_wizard_saves_nothing(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            binary = root / "binary"
            binary.write_text("fixture")
            binary.chmod(0o700)
            output = root / "config"
            answers = [
                str(binary),
                "",
                "",
                "fixture-model",
                "",
                "",
                str(root),
                "",
                "no",
            ]
            with (
                mock.patch.object(
                    sys,
                    "argv",
                    ["setup", "--binary", str(binary), "--config-dir", str(output)],
                ),
                mock.patch("builtins.input", side_effect=answers),
                mock.patch("builtins.print"),
                mock.patch.object(setup.subprocess, "run") as run,
            ):
                setup.main()
            run.assert_not_called()
            self.assertFalse(output.exists())

    def test_greenfield_wizard_needs_parent_not_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            binary = root / "binary"
            binary.write_text("fixture")
            binary.chmod(0o700)
            output = root / "config"
            answers = [
                str(binary),
                "",
                "",
                "fixture-model",
                "default",
                "greenfield",
                str(binary),
                str(root),
                "",
                "yes",
            ]
            with (
                mock.patch.object(
                    sys,
                    "argv",
                    ["setup", "--binary", str(binary), "--config-dir", str(output)],
                ),
                mock.patch("builtins.input", side_effect=answers),
                mock.patch("builtins.print"),
                mock.patch.object(
                    setup.subprocess, "run", return_value=mock.Mock(returncode=0)
                ),
            ):
                setup.main()
            config = (output / "config.toml").read_text()
            self.assertIn('mode = "greenfield"', config)
            self.assertNotIn("source =", config)
            self.assertNotIn("reasoning_effort =", config)
            self.assertFalse((output / "board.sqlite").exists())

    def test_existing_files_refused_before_prompt_or_process(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "config.toml").write_text("existing")
            with (
                mock.patch.object(sys, "argv", ["setup", "--config-dir", str(root)]),
                mock.patch("builtins.input") as prompt,
                mock.patch.object(setup.subprocess, "run") as run,
                self.assertRaises(SystemExit),
            ):
                setup.main()
            prompt.assert_not_called()
            run.assert_not_called()
            self.assertEqual((root / "config.toml").read_text(), "existing")


if __name__ == "__main__":
    unittest.main()
