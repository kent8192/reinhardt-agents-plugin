# Reinhardt Project Templates Reference

## Template Types

The `reinhardt-admin startproject` and `startapp` commands require exactly one of `--with-rest`, `--with-pages`, or `--template <rest|pages>`. Specifying more than one — or none — is a CLI error.

### `rest` / `--with-rest`

REST API backend project.

- Generates a project structured for JSON API development
- Includes `config/settings.rs` with TOML-based environment configuration
- Pre-configures JSON renderer and parser
- No frontend asset pipeline

### `pages` / `--with-pages`

Full-stack application with WASM + SSR support (reinhardt-pages).

- Generates a project with both server and client-side code
- Includes Pages component infrastructure for WASM rendering
- Configures server-side rendering (SSR) with hydration
- Includes server function support for RPC-style client-server communication
- Adds `build.rs` and `index.html` for WASM compilation
- Includes `client/` module for WASM routing and state management
- Includes `shared/` module for types shared between server and client
- Generated `bootstrap.rs` uses `reinhardt::pages::ClientLauncher` to wire panic hook, reactive scheduler, DOM mounting, and history listener with a single `.launch()` call (added in rc.18)

> **Removed flag (rc.18):** The legacy `-t restful|mtv` / `--template-type` flag has been removed. Use `--with-rest` / `--with-pages` (or `--template rest|pages`) instead. There is no longer a default — exactly one project-type flag is required.

## CLI Usage

```bash
# Create a RESTful API project
reinhardt-admin startproject my_project --with-rest

# Create a Pages (WASM + SSR) project
reinhardt-admin startproject my_project --with-pages

# Equivalent canonical form
reinhardt-admin startproject my_project --template rest
reinhardt-admin startproject my_project --template pages

# Create a RESTful app
reinhardt-admin startapp my_app --with-rest

# Create a Pages app
reinhardt-admin startapp my_app --with-pages
```

## Template Variables

The scaffolding engine substitutes these variables in generated files:

| Variable | Description | Example |
|----------|-------------|---------|
| `project_name` | The project name as provided by the user | `my_blog` |
| `crate_name` | Sanitized crate name (same as `project_name`, validated) | `my_blog` |
| `camel_case_project_name` | PascalCase version for struct/type names | `MyBlog` |
| `app_name` | App name (for `startapp`) | `user` |
| `camel_case_app_name` | PascalCase app name | `User` |

## Generated Project Structure

### RESTful Template

```text
my_project/
├── .gitignore
├── bacon.toml
├── Cargo.toml
├── Makefile.toml
├── README.md
├── settings/
│   ├── .gitignore
│   ├── base.example.toml
│   ├── local.example.toml
│   ├── production.example.toml
│   └── staging.example.toml
└── src/
    ├── lib.rs               # pub mod config; pub mod apps;
    ├── bin/
    │   └── manage.rs        # Management CLI entry point
    ├── apps.rs              # App module declarations (initially empty)
    ├── config.rs            # pub mod urls; pub mod settings;
    └── config/
        ├── settings.rs      # TOML-based settings with environment profiles
        └── urls.rs          # #[routes] fn routes() -> UnifiedRouter
```

### Pages Template (`--with-pages`)

```text
my_project/
├── .gitignore
├── bacon.toml
├── build.rs                 # WASM build configuration
├── Cargo.toml               # [[bin]] name = "manage", default-run = "manage"
├── index.html               # HTML shell for WASM app
├── Makefile.toml
├── README.md
├── settings/
│   └── (same as RESTful)
└── src/
    ├── lib.rs
    ├── bin/
    │   └── manage.rs
    ├── apps.rs
    ├── config.rs
    ├── config/
    │   ├── settings.rs
    │   ├── urls.rs
    │   └── wasm.rs          # WASM-specific config (added in rc.22)
    ├── client.rs            # WASM client module
    ├── client/
    │   ├── bootstrap.rs     # ClientLauncher entry point (rc.18)
    │   ├── router.rs        # Uses reinhardt::pages::router::Router (rc.18)
    │   └── state.rs         # Client state management
    ├── server_fn.rs         # Server-fn module entry (path aligned with basis tutorial in rc.22)
    ├── server_fn/           # Per-app server_fn modules
    ├── server_only.rs       # Re-export shim for server-only items (rc.22)
    ├── shared.rs            # Shared types module
    └── shared/
        ├── errors.rs        # Shared error types
        └── types.rs         # Shared data types
```

**Pages app sub-tree** (per app under `src/apps/<name>/`):

```text
src/apps/<name>/
├── lib.rs                   # #[app_config] + module declarations (no top-level pub mod ws_urls — fixed in rc.21)
├── client.rs                # #[cfg(wasm)]
├── server.rs                # Available on both native and WASM
├── shared.rs                # Available on both
├── models.rs                # #[cfg(native)]
├── views.rs                 # #[cfg(native)]
├── serializers.rs           # #[cfg(native)]
├── admin.rs                 # #[cfg(native)]
├── urls.rs                  # Mounts the unified urls/ submodule tree
└── urls/                    # rc.19: server/client/ws routing modes are symmetric here
    ├── server_urls.rs       # ServerRouter + #[get]/#[post]/etc. handlers
    ├── client_urls.rs       # Client-side route table
    └── ws_urls.rs           # WebSocketRouter (returns WebSocketRouter — rc.19 fix)
```

> **Breaking change (rc.19):** `ws_url_resolvers` moved from `crate::apps::<app>::ws_urls::*` to `crate::apps::<app>::urls::ws_urls::*`. Existing apps with a top-level `src/apps/<app>/ws_urls.rs` must move it under `src/apps/<app>/urls/`. See the migration skill for the per-app `git mv` recipe.

## Generated App Structure

### RESTful App

```text
<app_name>/
├── lib.rs           # #[app_config] + module declarations
├── admin.rs         # Admin configuration
├── admin/           # (gitkeep for future admin files)
├── models.rs        # Model definitions
├── models/          # (gitkeep for future model files)
├── serializers.rs   # Serializer definitions
├── serializers/     # (gitkeep for future serializer files)
├── urls.rs          # URL routing (ServerRouter)
├── views.rs         # View functions
├── views/           # (gitkeep for future view files)
├── tests.rs         # App tests
└── tests/           # (gitkeep for future test files)
```

## Post-Scaffolding Checklist

After running `reinhardt-admin startproject <name>`, complete these steps:

1. **Review `Cargo.toml`** — Verify feature flags match your requirements. Add or remove features based on your database backend, auth method, and component needs. See `feature-flags.md` for details.

2. **Set up settings files** — Copy example TOML files and configure:

   ```bash
   cp settings/base.example.toml settings/base.toml
   cp settings/local.example.toml settings/local.toml
   ```

   Configure database connection, secret key, and other environment-specific settings.

3. **Verify compilation**:

   ```bash
   cargo check --all-features
   ```

4. **Format generated code**:

   ```bash
   cargo fmt --all
   ```

5. **Remove placeholder surface area** — delete unused demo views/components,
   rename generated placeholder modules to domain names, and replace hardcoded
   links with route reverse helpers before building feature code on top.

6. **Initialize Git** (if not already):

   ```bash
   git init
   git add .
   git commit -m "chore: initialize reinhardt project"
   ```

---

## Version Differences (0.2.x)

### Workspace Template Consolidation

In 0.2.x, separate workspace app templates (`app_pages_workspace_template/`, `app_restful_workspace_template/`) are removed. A single non-workspace template per app type is used, with an `is_workspace` Tera conditional for import-path divergence. `startapp --workspace` now generates the full module structure (client/, server_fn.rs, cfg gates) within a single template.

### .example.toml Removed

In 0.2.x, the dual output of `.example.toml` files during scaffolding is removed. Use environment variables for configuration instead.
