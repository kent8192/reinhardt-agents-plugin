# Changelog

All notable changes to the **reinhardt-agents-plugin** Claude Code and Codex plugin are documented in this file.

The format is loosely based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Align README, commands, skills, agents, and packaged plugin docs with the
  stable `reinhardt-web` `0.2.0` release instead of the older `0.2.0-rc.2`
  development target.
- Update the 0.1.x to 0.2.0 upgrade workflow to use
  `reinhardt-web` milestone
  [`v0.2.0-rc`](https://github.com/kent8192/reinhardt-web/milestone/1)
  as the issue-level source map for 0.2.0 migration surfaces.
- Make generated Cargo.toml examples stable-first with `reinhardt = "0.2.0"`
  and keep `0.1.x` guidance only for migration analysis.
- Set Claude Code and Codex plugin manifest versions to `0.2.0`.

## [1.2.0] - 2026-05-27

Updates all skills, commands, and agents to support both **reinhardt-web v0.1.2** (stable) and
**v0.2.0-rc.2** (development). Version strings bumped from `0.1.0-rc.29` to `0.1.2`; `0.2.x`
differences documented with inline version markers throughout.

### Added

- **Dual-version documentation** — every SKILL.md now carries `versions: ["0.1.2", "0.2.x"]`
  in frontmatter; version-conditional sections use `**(0.1.x)**` / `**(0.2.x)**` inline markers
  or `#### 0.1.x (stable)` / `#### 0.2.x` block headings.
- **`skills/modeling`** — `{Model}Info` companion struct auto-generation (0.2.x), `#[model(info = false)]`,
  `#[field(skip_info = true)]`, `type Objects` associated type unification replacing `HasCustomManager`.
- **`skills/authentication`** — unified `AuthBackend` trait returning `Box<dyn AuthIdentity>` (0.2.x),
  removal of `DefaultUser`/`DefaultUserManager`, user-ID-based permission lookups.
- **`skills/api-development`** — `#[url_patterns]` removal (0.2.x), `#[routes]` simplification,
  `ClientRouter` mandatory `name` first arg, type-safe URL reversal removal.
- **`skills/pages`** — explicit dependency arrays for `use_effect`/`use_memo`/`use_callback` (0.2.x),
  auto-wrapping of reactive expressions, `reinhardt::pages::navigate` SPA pattern.
- **`skills/macros`** — 0.2.x macro changes: `#[url_patterns]` removed, `#[routes]` simplified,
  `#[model(info)]`/`#[field(skip_info)]` additions.
- **`skills/migration`** — "Major Version Upgrade: 0.1.x → 0.2.x" section with full migration path.
- **`skills/dependency-injection`** — `InjectionContext` per-context registry isolation (0.2.x),
  `Injectable` impls for extractors, `#[serial(di_registry)]` no longer needed.
- **`skills/configuration`** — `SecurityConfig` removal in 0.2.x, `SecurityMiddleware` builder methods.
- **`skills/testing`** — DI override tests no longer require `#[serial(di_registry)]` in 0.2.x.
- **`skills/authorization`** — user-ID-based permission lookups (0.2.x), `AuthIdentity` type changes.
- **`agents/migration-analyzer.md`** — version family detection (0.1.x vs 0.2.x), major-version
  upgrade awareness.
- **`agents/code-reviewer.md`** — 0.2.x anti-pattern detection (`HasCustomManager`, `#[url_patterns]`,
  `named_route*`, `SecurityConfig`).
- **`commands/reinhardt-upgrade.md`** — 0.1.x → 0.2.x major upgrade path handling.

### Changed

- All `0.1.0-rc.29` version strings → `0.1.2` with `# For 0.2.x: "0.2.0-rc.2"` comments.
- **`README.md`** — requirements section shows dual version support.
- **`.claude-plugin/plugin.json`** — version bumped from `1.1.0` to `1.2.0`.

### Compatibility

- Target reinhardt-web versions: **`0.1.2`** (stable) / **`0.2.0-rc.2`** (development).
- No breaking changes to plugin consumers; all updates are additive.

## [1.1.0] - 2026-05-16

Synchronizes documentation, skills, agents, and commands with **reinhardt-web v0.1.0-rc.23 → v0.1.0-rc.29**
(2026-04-29 → 2026-05-13, 153 PRs upstream). Tracking issue: [#9](https://github.com/kent8192/reinhardt-agents-plugin/issues/9).

### Added

- **`skills/testing/references/di-overrides.md`** — full reference for the rc.29 DI testing kit:
  `with_di_overrides!` proc-macro, `register_override` + `OverrideGuard`, `DiOverrideBuilder`,
  `injection_context_with_di_overrides`, the new `reinhardt-testkit-macros` crate, and the mandatory
  `#[serial(di_registry)]` requirement (reinhardt-web #4297).
- **`CHANGELOG.md`** (this file) — initial release notes for the plugin.
- **README** — now documents the `pages`, `authentication`, `authorization`, `macros`, `signals`,
  `architecture`, and `lint` skills that were already shipped but previously undocumented.

### Changed

- **`skills/api-development/references/serializer-patterns.md`** — added "ModelSerializer Meta Options
  (rc.23+ regression-fix)" covering the now-honored `exclude` / `read_only` / `write_only` builders,
  `ModelLevelValidator<M>` trait, and `WritableNestedSerializer::serialize` (#3993).
- **`skills/api-development/references/view-patterns.md`** — added "ModelViewSet / ReadOnlyModelViewSet
  (rc.23+)" with tightened trait bounds, `ViewSetBuilder` / `.with_pool` / `.with_db_backend`, and
  the `GenericViewSet` error-string change (#3991).
- **`skills/api-development/references/routing-guide.md`** — documented the new `reinhardt-router`
  crate, the `VersionedRouter` trait, `RouteVersionInfo`, and the cross-target `ServerRouterStub::server_fn`
  stub (#4332, #4263).
- **`skills/authentication/references/social-auth.md`** — added `GenericOidcProvider` (Keycloak /
  Authentik / self-hosted GitLab worked examples, `with_userinfo_mapper`, `extra_token_params`,
  `discovery_ttl` / `jwks_ttl`, mandatory JWS verification, `client_secret` Debug redaction), the
  GitHub `/user` → `StandardClaims` fix, and OIDC JWK EC key support (P-256/P-384/P-521)
  (#3999, #4004, #4005).
- **`skills/configuration/references/fragments.md`** — added the `VersioningSettings` fragment
  (`[rest_versioning]`, retired `REINHARDT_VERSIONING_*` env vars) and the `from_settings(&Settings)`
  injection pattern (#4285, #4284).
- **`skills/configuration/references/settings-system.md`** — added "TOML Interpolation (rc.26+)"
  with all four `${VAR}` forms, `$$` escape, and source ordering, plus "MergeStrategy::Deep (rc.28+)"
  with `Shallow` vs `Deep` defaults across `build()` / `build_composed()` (#4092, #4264).
- **`skills/macros/references/attribute-macros.md`** — added the `manager` attribute to the `#[model]`
  options table, and a "Cross-target WASM marker module (rc.27+)" subsection under `#[server_fn]`
  (#3981, #4293).
- **`skills/migration/references/changelog-format.md`** — bumped worked CHANGELOG examples to
  rc.28/rc.29 and updated the canonical tag example.
- **`skills/migration/references/upgrade-workflow.md`** — refreshed target-version examples to rc.29.
- **`skills/modeling/references/migration-guide.md`** — added "Migration Auto-Detection Improvements
  (rc.23-29)" covering `AddConstraint` / `DropConstraint` emission and the non-integer PK
  `auto_increment` regression fix (#3998, #4380).
- **`skills/modeling/references/model-patterns.md`** — added "Custom Manager Attribute (rc.23+)"
  with row-level access control and tenant-filter worked examples (#3981).
- **`skills/modeling/references/queryset-api.md`** — added "CustomManager / HasCustomManager (rc.23+)"
  documenting the trait surface, the three veto hooks, and `Model::objects()` backward compatibility
  (#3981).
- **`skills/pages/references/reactive-hooks.md`** — added the `Signal<T>: Send + Sync` on native
  note (rc.25+) explaining why `ClientRouter` / `UnifiedRouter` are now resolvable through DI
  (#4068).
- **`skills/pages/references/routing-ssr.md`** — added "ClientLauncher Lifecycle Hooks (rc.23+)"
  (`intercept_links`, `before_launch`, `after_launch`, `on_path`, `on_path_pattern`), the rc.29
  SPA link interception DOM-walk fix, "SPA Navigation Improvements (rc.26+)", and the
  `--with-pages` URL submodule layout fix (#3997, #4344, #4078, #4114, #4357).
- **`skills/testing/references/api-testing.md`** — added "MSW (Mock Service Worker) for wasm32
  (rc.29+)" covering the `msw` facade feature and `wasm-pack test` workflow (#4288).
- **`agents/code-reviewer.md`** — extended the ORM, API Design, and Testing checklists with rc.23+
  items: custom-manager veto-hook discipline, `GenericOidcProvider` over hand-rolled OAuth providers,
  `[rest_versioning]` settings vs retired env vars, and the mandatory `#[serial(di_registry)]` on
  DI override tests.
- **Example version strings** in `commands/`, `README.md`, `skills/scaffolding/`,
  `skills/api-development/references/auth-config.md`, and `skills/testing/references/testcontainers.md`
  bumped from `0.1.0-alpha` / `0.1.0-rc.22` to `0.1.0-rc.29`.
- **`.claude-plugin/plugin.json`** — version bumped from `1.0.0` to `1.1.0`.

### Compatibility

- Target reinhardt-web version: **`0.1.0-rc.29`**.
- No breaking changes to plugin consumers; all updates are additive (new sections, version-string
  bumps, documentation of previously unlisted skills).

## [1.0.0] - prior

- Initial public release of the reinhardt-agents-plugin plugin (skills for scaffolding, modeling,
  api-development, testing, dependency-injection, configuration, admin, migration, plus the
  `pages`, `authentication`, `authorization`, `macros`, `signals`, `architecture`, and `lint`
  skills that were added incrementally before this CHANGELOG was introduced).
