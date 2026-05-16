# Deprecation Patterns Reference

How to identify, interpret, and migrate deprecated APIs in reinhardt-web.

---

## Rust Deprecation Attribute

The standard Rust deprecation attribute structure:

```rust
#[deprecated(since = "0.1.0-rc.13", note = "use `NewType` instead")]
pub type OldType = NewType;
```

Fields:
- **`since`** — the version where deprecation was introduced. Use this to filter
  deprecations relevant to your upgrade range.
- **`note`** — human-readable migration guidance. Always contains the replacement
  API or approach.

### Reading the `note` field

The `note` typically follows one of these patterns:
- `"use X instead"` — direct 1:1 replacement
- `"use X with Y instead"` — replacement requires additional configuration
- `"removed in favor of X"` — different approach, may require restructuring
- `"no longer needed, remove usage"` — functionality absorbed elsewhere

---

## Reinhardt-Specific Deprecation Patterns

### Pattern 1: Type Alias Deprecation

A type is renamed. The old name is kept as a deprecated alias pointing to the
new type, allowing gradual migration.

```rust
// In reinhardt source (crate code):
/// The new type with improved API.
pub struct ProjectConfig {
    // ...
}

#[deprecated(since = "0.1.0-rc.13", note = "renamed to `ProjectConfig`")]
pub type AppConfig = ProjectConfig;
```

**Migration:**

```rust
// Before
use reinhardt::AppConfig;

fn setup() -> AppConfig {
    AppConfig::default()
}

// After
use reinhardt::ProjectConfig;

fn setup() -> ProjectConfig {
    ProjectConfig::default()
}
```

**How to find in app code:**
```bash
grep -rn 'AppConfig' src/ --include='*.rs'
```

### Pattern 2: Trait Migration

An old trait is deprecated and replaced by a new trait with a different interface.
This typically happens when the abstraction is redesigned.

```rust
// In reinhardt source:
#[deprecated(since = "0.1.0-rc.14", note = "implement `ModelMeta` trait instead")]
pub trait ModelInfo {
    fn table_name() -> &'static str;
}

/// New trait with richer metadata.
pub trait ModelMeta {
    fn table_name() -> &'static str;
    fn primary_key() -> &'static str;
    fn schema() -> Schema;
}
```

**Migration:**

```rust
// Before
use reinhardt::ModelInfo;

impl ModelInfo for User {
    fn table_name() -> &'static str {
        "users"
    }
}

// After
use reinhardt::ModelMeta;

impl ModelMeta for User {
    fn table_name() -> &'static str {
        "users"
    }

    fn primary_key() -> &'static str {
        "id"
    }

    fn schema() -> Schema {
        Schema::new("users")
            .field("id", FieldType::Integer)
            .field("name", FieldType::Text)
    }
}
```

**How to find in app code:**
```bash
grep -rn 'impl ModelInfo' src/ --include='*.rs'
grep -rn 'use reinhardt::ModelInfo' src/ --include='*.rs'
```

### Pattern 3: Settings System Migration

The settings system transitioned from a monolithic `Settings` trait to a
fragment-based `ProjectSettings` with composable `CoreSettings`.

```rust
// In reinhardt source:
#[deprecated(
    since = "0.1.0-rc.13",
    note = "use `ProjectSettings` with `CoreSettings` fragment instead"
)]
pub trait Settings {
    fn database_url(&self) -> &str;
    fn secret_key(&self) -> &str;
    fn debug(&self) -> bool;
}

/// Fragment-based settings with composable configuration.
pub trait ProjectSettings: Debug {
    type Core: CoreSettings;

    fn core(&self) -> &Self::Core;
}

pub trait CoreSettings {
    fn database_url(&self) -> &str;
    fn secret_key(&self) -> &str;
    fn debug(&self) -> bool;
}
```

**Migration:**

```rust
// Before
use reinhardt::Settings;

#[derive(Clone)]
struct MySettings {
    db_url: String,
    secret: String,
    debug: bool,
}

impl Settings for MySettings {
    fn database_url(&self) -> &str { &self.db_url }
    fn secret_key(&self) -> &str { &self.secret }
    fn debug(&self) -> bool { self.debug }
}

// After
use reinhardt::{ProjectSettings, CoreSettings};

#[derive(Clone, Debug)]
struct MySettings {
    core: MyCoreSettings,
}

#[derive(Clone, Debug)]
struct MyCoreSettings {
    db_url: String,
    secret: String,
    debug: bool,
}

impl ProjectSettings for MySettings {
    type Core = MyCoreSettings;

    fn core(&self) -> &Self::Core {
        &self.core
    }
}

impl CoreSettings for MyCoreSettings {
    fn database_url(&self) -> &str { &self.db_url }
    fn secret_key(&self) -> &str { &self.secret }
    fn debug(&self) -> bool { self.debug }
}
```

**How to find in app code:**
```bash
grep -rn 'impl Settings for' src/ --include='*.rs'
grep -rn 'use reinhardt::Settings' src/ --include='*.rs'
```

### Pattern 4: Method Deprecation

Individual methods are deprecated with notes pointing to replacement methods.

```rust
// In reinhardt source:
impl QueryBuilder {
    #[deprecated(since = "0.1.0-rc.14", note = "use `filter_by()` instead")]
    pub fn where_clause(&mut self, clause: &str) -> &mut Self {
        self.filter_by(clause)
    }

    /// Type-safe filtering with column validation.
    pub fn filter_by(&mut self, expr: impl Into<FilterExpr>) -> &mut Self {
        // ...
    }
}
```

**Migration:**

```rust
// Before
let query = QueryBuilder::new("users")
    .where_clause("age > 18")
    .build();

// After
let query = QueryBuilder::new("users")
    .filter_by(col("age").gt(18))
    .build();
```

**How to find in app code:**
```bash
grep -rn '\.where_clause(' src/ --include='*.rs'
```

---

## Finding Deprecated APIs in Reinhardt Source

### Scan all deprecated items

```bash
grep -rn '#\[deprecated' reinhardt/crates/ --include='*.rs'
```

### Filter by version range

To find deprecations introduced between rc.18 and rc.22:
```bash
grep -rn '#\[deprecated' reinhardt/crates/ --include='*.rs' | grep -E 'since\s*=\s*"0\.1\.0-rc\.(1[89]|2[0-2])"'
```

### Extract symbol names

For each `#[deprecated]` match, look at the following line to identify the
deprecated symbol:
- `pub type Name` — type alias
- `pub trait Name` — trait
- `pub fn name` — function
- `pub struct Name` — struct
- `pub enum Name` — enum
- `pub fn name` (in impl block) — method

---

## Finding Usage in Application Code

### General pattern

```bash
grep -rn 'SymbolName' src/ --include='*.rs'
```

### Targeted searches by pattern type

| Deprecated Item | Search Pattern |
|----------------|----------------|
| Type alias | `grep -rn 'OldTypeName' src/ --include='*.rs'` |
| Trait impl | `grep -rn 'impl OldTrait' src/ --include='*.rs'` |
| Trait import | `grep -rn 'use reinhardt::OldTrait' src/ --include='*.rs'` |
| Method call | `grep -rn '\.old_method(' src/ --include='*.rs'` |
| Function call | `grep -rn 'old_function(' src/ --include='*.rs'` |

---

## `#[allow(deprecated)]` Policy

- **Production code** — NEVER use `#[allow(deprecated)]`. Always migrate to the
  replacement API.
- **Tests** — MAY use `#[allow(deprecated)]` when specifically testing backward
  compatibility of deprecated APIs.
- **Examples** — MAY use `#[allow(deprecated)]` when demonstrating migration paths
  in documentation examples.

If `#[allow(deprecated)]` is found in production code during migration, it
should be flagged and the underlying deprecated usage should be migrated.
