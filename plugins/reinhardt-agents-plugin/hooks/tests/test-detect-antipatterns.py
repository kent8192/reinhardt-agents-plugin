#!/usr/bin/env python3
"""Exercise edit-event parsing and scanner dispatch through the actual hook."""

import json
import os
from pathlib import Path
import subprocess
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
HOOK = ROOT / "hooks/scripts/detect-antipatterns.sh"


class EditHookTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="reinhardt-edit-hook-", dir="/tmp")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.log = self.root / "invocations.jsonl"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        stub = self.bin / "semgrep"
        stub.write_text(
            "#!/usr/bin/env python3\n"
            "import json,os,sys\n"
            "with open(os.environ['SCAN_LOG'],'a') as log:\n"
            " log.write(json.dumps(sys.argv[1:])+'\\n')\n"
        )
        stub.chmod(0o755)
        self.environment = dict(os.environ)
        self.environment.pop("TOOL_INPUT", None)
        self.environment.pop("CLAUDE_PLUGIN_ROOT", None)
        self.environment.update(
            PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
            PLUGIN_ROOT=str(ROOT),
            SCAN_LOG=str(self.log),
        )

    def file(self, name):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("pub use example::*;\n")
        return path

    def invoke(self, payload="", legacy=None):
        env = dict(self.environment)
        if legacy is not None:
            env["TOOL_INPUT"] = legacy
        result = subprocess.run(
            ["bash", str(HOOK)], input=payload, cwd=self.root, env=env,
            capture_output=True, text=True, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        invocations = (
            [json.loads(line) for line in self.log.read_text().splitlines()]
            if self.log.exists() else []
        )
        return result, invocations

    def assert_scanned(self, invocations, paths):
        self.assertEqual([item[-1] for item in invocations], [str(p) for p in paths])
        for item in invocations:
            self.assertEqual(item[:3], ["scan", "--config", str(ROOT / "hooks/semgrep/reinhardt-antipatterns.yml")])

    def test_stdin_edit_with_escaped_path(self):
        path = self.file('quoted "名前".rs')
        _, scans = self.invoke(json.dumps({"tool_name": "Edit", "tool_input": {"file_path": str(path)}}))
        self.assert_scanned(scans, [path])

    def test_legacy_environment(self):
        path = self.file("legacy.rs")
        _, scans = self.invoke(legacy=json.dumps({"file_path": str(path)}))
        self.assert_scanned(scans, [path])

    def test_stdin_takes_precedence(self):
        chosen, ignored = self.file("chosen.rs"), self.file("ignored.rs")
        _, scans = self.invoke(
            json.dumps({"tool_input": {"file_path": str(chosen)}}),
            legacy=json.dumps({"file_path": str(ignored)}),
        )
        self.assert_scanned(scans, [chosen])

    def test_cargo_manifest_is_scanned(self):
        path = self.file("Cargo.toml")
        _, scans = self.invoke(json.dumps({"tool_input": {"file_path": str(path)}}))
        self.assert_scanned(scans, [path])

    def test_apply_patch_multiple_files_and_deduplication(self):
        first, second = self.file("one.rs"), self.file("app/Cargo.toml")
        patch = f"*** Begin Patch\n*** Update File: {first}\n*** Add File: {second}\n*** Update File: {first}\n*** End Patch"
        _, scans = self.invoke(json.dumps({"tool_name": "apply_patch", "tool_input": {"patch": patch}}))
        self.assert_scanned(scans, [first, second])

    def test_relative_path_uses_event_cwd(self):
        path = self.file("app/sample.rs")
        _, scans = self.invoke(json.dumps({"cwd": str(path.parent), "tool_input": {"path": path.name}}))
        self.assert_scanned(scans, [path])

    def test_invalid_or_unrelated_events_do_not_scan(self):
        for payload in ["", "{", "[]", "null", '{"tool_input": 4}']:
            with self.subTest(payload=payload):
                _, scans = self.invoke(payload)
                self.assertEqual(scans, [])
        path = self.file("README.md")
        _, scans = self.invoke(json.dumps({"tool_input": {"file_path": str(path)}}))
        self.assertEqual(scans, [])

    def test_module_filename_warning(self):
        path = self.file("mod.rs")
        result, scans = self.invoke(json.dumps({"tool_input": {"file_path": str(path)}}))
        self.assertIn("ERROR [reinhardt-no-mod-rs]", result.stderr)
        self.assert_scanned(scans, [path])


    @unittest.skipUnless(shutil.which("semgrep"), "Requires the optional local semgrep scanner")
    def test_real_scanner_reports_rust_and_manifest_rules(self):
        rust = self.file("actual.rs")
        manifest = self.file("Cargo.toml")
        manifest.write_text('[dev-dependencies]\nreinhardt-test = { workspace = true }\n')
        env = dict(self.environment)
        env["PATH"] = os.environ["PATH"]
        for path, rule in [
            (rust, "reinhardt-no-glob-reexport"),
            (manifest, "reinhardt-no-workspace-test-dep"),
        ]:
            with self.subTest(path=path):
                result = subprocess.run(
                    ["bash", str(HOOK)],
                    input=json.dumps({"tool_input": {"file_path": str(path)}}),
                    cwd=self.root, env=env, capture_output=True, text=True, check=False,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, "")
                self.assertEqual(rule in "".join(result.stderr.split()), True, result.stderr)

    @unittest.skipUnless(shutil.which("semgrep"), "Requires the optional local semgrep scanner")
    def test_real_scanner_covers_cargo_dependency_tables(self):
        cases = {
            "inline": ('[dev-dependencies]\nreinhardt-test = { workspace = true }\n', True),
            "inline-target": (
                '[target.\'cfg(unix)\'.dev-dependencies]\n'
                '"reinhardt-test" = { features = ["test-utils"], workspace = true }\n', True),
            "inline-runtime": ('[dependencies]\nreinhardt-test = { workspace = true }\n', False),
            "inline-build": ('[build-dependencies]\nreinhardt-test = { workspace = true }\n', False),
            "inline-target-runtime": (
                '[target.\'cfg(unix)\'.dependencies]\n'
                'reinhardt-test = { workspace = true }\n', False),
            "inline-next-section": (
                '[dev-dependencies]\nother = { version = "1" }\n'
                '[dependencies]\nreinhardt-test = { workspace = true }\n', False),
            "subtable": ('[dev-dependencies.reinhardt-test]\nworkspace = true\n', True),
            "quoted-target": (
                '[target.\'cfg(unix)\'.dev-dependencies."reinhardt-test"]\n'
                '# Extra dependency properties are allowed before workspace.\n'
                'features = ["test-utils"]\nworkspace = true\n', True),
            "different-table": (
                '[dev-dependencies.reinhardt-test]\npath = "../test"\n'
                '[dependencies.other]\nworkspace = true\n', False),
            "disabled": ('[dev-dependencies.reinhardt-test]\nworkspace = false\n', False),
            "runtime": ('[dependencies.reinhardt-test]\nworkspace = true\n', False),
        }
        expected = set()
        for name, (text, finding) in cases.items():
            path = self.file(f"{name}/Cargo.toml")
            path.write_text(text)
            if finding:
                expected.add(path.resolve())
        result = subprocess.run(
            [shutil.which("semgrep"), "scan", "--config",
             str(ROOT / "hooks/semgrep/reinhardt-antipatterns.yml"),
             "--json", "--metrics", "off", "--quiet", "--no-git-ignore", str(self.root)],
            cwd=self.root, capture_output=True, text=True, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report["errors"], [])
        actual = {Path(finding["path"]).resolve() for finding in report["results"]
                  if finding["check_id"].endswith("reinhardt-no-workspace-test-dep")}
        self.assertEqual(actual, expected)


if __name__ == "__main__":
    unittest.main()
