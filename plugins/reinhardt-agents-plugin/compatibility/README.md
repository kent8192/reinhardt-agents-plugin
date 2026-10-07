# Framework Compatibility

Current 0.4.x guidance is verified against Reinhardt Web
`0.4.0-alpha.20`, published from commit
[`81dba7c`](https://github.com/kent8192/reinhardt-web/tree/81dba7c84d1dcdb26b6b2e6a56a0212b0c9e650f).
It requires Rust 1.96.0. A later alpha or branch tip is a different baseline.

Examples explicitly marked 0.1.x, 0.2.x, or 0.3.x retain their historical API.
Removed 0.2 routing macros and unprefixed 0.3 keyed DI wrappers are not
instructions for a 0.4 application. Read the project's manifest first.

## Feature Detection

`reinhardt-web-alpha20.json` contains the release's facade feature definitions.
The context hook expands local feature edges for 0.4 declarations from this
graph and reports `:feature-baseline "0.4.0-alpha.20"`.
Forwarded dependency features infer authentication capabilities and are not
mislabeled as facade flags. Availability does not prove that the application
configured a particular authentication method. Unversioned path/git dependencies
and older version families use legacy presets; inspect their actual manifests.

Scaffolding recipes use TOML dependency tables, accepted by Cargo and Python
3.11+ `tomllib`. Cargo 1.96's TOML 1.1 multiline inline tables are not readable
by Python 3.12 `tomllib`; the hook fails open on unsupported manifests.

## Checks

From the plugin source repository:

```bash
python3 hooks/tests/test-detect-antipatterns.py
python3 hooks/tests/test-alpha20-features.py
bash hooks/tests/test-inject-context.sh
scripts/sync-packaged-plugin.sh --check
```

These checks cover edit-hook dispatch, context injection, feature expansion,
and scaffolding manifest parsing. They do not compile the Rust documentation
examples or execute application behavior.

To compare a verified release checkout/archive:

```bash
python3 scripts/check-alpha20-snapshot.py /absolute/path/to/reinhardt-web-source
```

Verify its commit matches the SHA above before comparing the manifest. Updating
the baseline requires changing the source pin, feature graph, and guidance
together, then rerunning the hook and manifest checks.
Edit root sources and regenerate the package with
`scripts/sync-packaged-plugin.sh`.
