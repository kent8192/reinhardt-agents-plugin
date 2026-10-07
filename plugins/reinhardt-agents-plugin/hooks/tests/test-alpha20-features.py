#!/usr/bin/env python3
"""Check pinned feature expansion and all published scaffolding manifests."""
import importlib.util
import json
from pathlib import Path
import re
import sys
import tomllib
import unittest

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("inject_context", ROOT / "hooks/scripts/inject_context.py")
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)
SNAPSHOT = json.loads((ROOT / "compatibility/reinhardt-web-alpha20.json").read_text())

class Alpha20Features(unittest.TestCase):
    def test_all_feature_closures_match_the_pinned_graph(self):
        graph = SNAPSHOT["features"]
        for feature in graph:
            with self.subTest(feature=feature):
                expected = {feature}
                pending = [feature]
                while pending:
                    for target in graph[pending.pop()]:
                        if target in graph and target not in expected:
                            expected.add(target)
                            pending.append(target)
                self.assertEqual(hook.expand_features({feature}, "=0.4.0-alpha.20"), expected)

    def test_minimal_includes_routing(self):
        self.assertEqual(hook.expand_features({"minimal"}, "=0.4.0-alpha.20"),
                         {"minimal", "core", "routing", "di", "server"})

    def test_session_auth_includes_sessions(self):
        self.assertEqual(hook.expand_features({"auth-session"}, "=0.4.0-alpha.20"),
                         {"auth-session", "auth", "sessions"})

    def test_legacy_version_keeps_its_own_graph(self):
        self.assertEqual(hook.expand_features({"auth-session"}, "0.3.0"),
                         {"auth-session", "auth"})

    def test_context_selects_graph_from_the_allowed_version_family(self):
        requirements = {
            "0.4": True, "^0.4": True, "~0.4": True,
            "0.4.*": True, "=0.4.1": True,
            ">=0.3, <0.4.0": False, ">=0.3, <0.4": False,
            ">=0.4, <0.5": True, ">0.4.0, <0.4.2": True,
            ">0.4.0, <0.4.1": False, "<=0.4": True,
            "^0": True, "~0": True, "0.*": True,
            ">0.4": False, "^0.0": False, "=0.4": True,
            ">=0.5, <0.6": False, ">=0.5, <0.4.0": False,
            "0.3": False, "~0.3": False,
        }
        for requirement, current in requirements.items():
            with self.subTest(requirement=requirement):
                metadata = hook.dependency_metadata({"dependencies": {"reinhardt": {
                    "package": "reinhardt-web", "version": requirement,
                    "default-features": False, "features": ["minimal"],
                }}}, {})
                self.assertEqual(metadata["feature_baseline"],
                                 "0.4.0-alpha.20" if current else "legacy presets")
                self.assertEqual("routing" in metadata["features"], current)

    def test_published_manifests_are_readable_and_features_exist(self):
        document = (ROOT / "skills/scaffolding/references/feature-flags.md").read_text()
        manifests = re.findall(r"```toml\n(.*?)```", document, re.S)
        self.assertEqual(len(manifests), 6)
        for text in manifests:
            with self.subTest(manifest=text):
                parsed = tomllib.loads(text)
                for section in ("dependencies", "dev-dependencies"):
                    dependency = parsed.get(section, {}).get("reinhardt")
                    if dependency is not None:
                        self.assertEqual(dependency["package"], "reinhardt-web")
                        self.assertEqual(set(dependency["features"]) - SNAPSHOT["features"].keys(), set())
                self.assertIsNotNone(hook.dependency_metadata(parsed, {}))

    def test_default_context_uses_pinned_dependency_capabilities(self):
        metadata = hook.dependency_metadata({"dependencies": {"reinhardt": {
            "package": "reinhardt-web", "version": "=0.4.0-alpha.20"
        }}}, {})
        self.assertEqual(metadata["feature_baseline"], "0.4.0-alpha.20")
        self.assertEqual("reinhardt-auth" in metadata["dependency_tokens"], True)
        self.assertEqual("db-postgres" in metadata["features"], True)

if __name__ == "__main__":
    unittest.main()
