# Reinhardt User Models Reference

## User Trait Hierarchy

Reinhardt provides a layered trait system for user models:

```text
AuthIdentity          (minimal: id, is_authenticated, is_admin)
    |
BaseUser              (core: username, password, is_active, last_login)
    |
FullUser              (extended: first_name, last_name, email, date_joined)
    |
PermissionsMixin      (groups, permissions)
```

**Module:** `reinhardt_auth::core` (re-exported via `reinhardt::auth`)

### Version Differences (0.2.x)

- **`DefaultUser` removed**: The `DefaultUser` struct is removed in 0.2.x. Use `SimpleUser` or define a custom user model instead.
- **`DefaultUserManager` removed**: The `DefaultUserManager` is removed in 0.2.x. Implement the `UserManager` trait directly for your user type.
- **`SimpleUser.email` is now optional**: `SimpleUser.email` changed from `String` to `Option<String>` in 0.2.x.
- **Permission lookups use user ID**: Permission lookups changed from username-based to user-ID-based resolution in 0.2.x.

---

## AuthIdentity Trait

The minimal authentication interface (replaces deprecated `User` trait):

```rust
pub trait AuthIdentity: Send + Sync {
    fn id(&self) -> String;
    fn is_authenticated(&self) -> bool;
    fn is_admin(&self) -> bool;
}
```

---

## BaseUser Trait

The core authentication trait, equivalent to Django's `AbstractBaseUser`:

```rust
pub trait BaseUser: Send + Sync + Serialize + for<'de> Deserialize<'de> {
    type PrimaryKey: Clone + Send + Sync + Display;
    type Hasher: PasswordHasher + Default;

    // Required methods
    fn get_username_field() -> &'static str;
    fn get_username(&self) -> &str;
    fn password_hash(&self) -> Option<&str>;
    fn set_password_hash(&mut self, hash: String);
    fn last_login(&self) -> Option<DateTime<Utc>>;
    fn set_last_login(&mut self, time: DateTime<Utc>);
    fn is_active(&self) -> bool;

    // Default methods
    fn normalize_username(username: &str) -> String;
    fn set_password(&mut self, password: &str) -> Result<(), Error>;
    fn check_password(&self, password: &str) -> Result<bool, Error>;
    fn check_password_with_update(&mut self, password: &str)
        -> Result<PasswordCheck, Error>;
    fn check_password_with_policy_update(
        &mut self,
        password: &str,
        policy: &PasswordHashPolicy,
    ) -> Result<PasswordCheck, Error>;
    fn set_unusable_password(&mut self);
    fn has_usable_password(&self) -> bool;
    fn get_session_auth_hash(&self, secret: &str) -> String;
}
```

### Associated Types

| Type | Description |
|------|-------------|
| `PrimaryKey` | Primary key type (e.g., `Uuid`, `i64`, `String`) |
| `Hasher` | Default password hasher for single-hasher helpers (e.g., `Argon2Hasher`) |

---

## Built-in User Types

### SimpleUser

Basic user struct with essential fields:

```rust
pub struct SimpleUser {
    pub id: Option<Uuid>,
    pub username: String,
    pub email: String,
    pub password_hash: Option<String>,
    pub is_active: bool,
    pub is_admin: bool,
    pub is_staff: bool,
    pub is_superuser: bool,
    pub last_login: Option<DateTime<Utc>>,
}
```

### DefaultUser **(0.1.x only — removed in 0.2.x)**

Full-featured user with Argon2 password hashing. Requires `argon2-hasher` feature.

```rust
// Feature: argon2-hasher
pub struct DefaultUser {
    pub id: Option<Uuid>,
    pub username: String,
    pub email: String,
    pub password_hash: Option<String>,
    pub first_name: String,
    pub last_name: String,
    pub is_active: bool,
    pub is_staff: bool,
    pub is_superuser: bool,
    pub last_login: Option<DateTime<Utc>>,
    pub date_joined: DateTime<Utc>,
}
```

### AnonymousUser

Represents an unauthenticated user:

```rust
pub struct AnonymousUser;
// is_authenticated() -> false
// is_admin() -> false
```

---

## Custom User Model

Define with `#[model]` and `#[user]` attributes:

```rust
use reinhardt::prelude::*;
use reinhardt::auth::prelude::*;

#[model(app_label = "accounts")]
#[user(hasher = Argon2Hasher, username_field = "email")]
pub struct User {
    #[field(primary_key)]
    pub id: Option<Uuid>,

    #[field(unique)]
    pub email: String,

    pub password_hash: Option<String>,
    pub display_name: String,
    pub is_active: bool,
    pub is_staff: bool,
    pub is_superuser: bool,
    pub last_login: Option<DateTime<Utc>>,
    pub date_joined: DateTime<Utc>,
}
```

### `#[user]` Attribute Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `hasher` | Type | (required) | Password hasher type (e.g., `Argon2Hasher`) |
| `username_field` | `&str` | `"username"` | Field used as the unique identifier |

The `#[user]` macro auto-generates:

- `BaseUser` trait implementation
- `AuthIdentity` trait implementation
- Password hash/verify methods using the specified hasher

---

## Password Hashing

### PasswordHasher Trait

```rust
pub trait PasswordHasher: Send + Sync {
    fn hash(&self, password: &str) -> Result<String, Error>;
    fn verify(&self, password: &str, hash: &str) -> Result<bool, Error>;
    fn algorithm(&self) -> Option<&'static str> { None }
    fn identify(&self, hash: &str) -> bool { false }
    fn must_update(&self, hash: &str) -> Result<bool, Error> { Ok(false) }
}
```

Custom hashers need `Send + Sync`; hashers registered with
`PasswordHashPolicy::new` or `with_legacy` must also be `'static`.
`BaseUser::Hasher` additionally requires `Default` because the ordinary
`set_password` and `check_password` helpers construct the configured default
hasher.

### Built-in Hashers

| Hasher | Feature Flag | Algorithm | Security Level | Speed |
|--------|-------------|-----------|----------------|-------|
| `Argon2Hasher` | `argon2-hasher` | Argon2id | Highest (recommended) | Slow (by design) |
| `BcryptHasher` | `bcrypt-hasher` | Bcrypt | High | Explicit policy choice; 72-byte input limit |

### Usage

```rust
use reinhardt::auth::{Argon2Hasher, PasswordHasher};

let hasher = Argon2Hasher::default();
let hashed = hasher.hash("user_password")?;

let is_valid = hasher.verify("user_password", &hashed)?;
```

Or via the user model:

```rust
let mut user = User::default();
user.set_password("secure_password_123")?;
assert!(user.check_password("secure_password_123")?);
assert!(!user.check_password("wrong_password")?);
```

### Password Hash Policy Upgrades **(0.4.x)**

`PasswordHashPolicy` has one preferred hasher for new hashes and any number of
legacy hashers. Verification checks the preferred hasher first and then legacy
hashers in registration order. A valid legacy hash, or a preferred hash whose
parameters are stale, can return `PasswordVerification::ValidNeedsRehash`.

For example, migrate stored bcrypt hashes to Argon2id at successful login:

```rust
// Cargo.toml: features = ["argon2-hasher", "bcrypt-hasher"]
use reinhardt::auth::{
    Argon2Hasher, BaseUser, BcryptHasher, PasswordCheck, PasswordHashPolicy,
};

let policy = PasswordHashPolicy::new(Argon2Hasher::default())
    .with_legacy(BcryptHasher::default());

let previous_hash = user.password_hash().map(str::to_owned);
match user.check_password_with_policy_update(password, &policy)? {
    PasswordCheck::Invalid => {
        // Reject the credentials.
    }
    PasswordCheck::Valid => {
        // Authenticate without a storage change.
    }
    PasswordCheck::ValidUpdated => {
        // `user.password_hash()` changed only in memory. Persist it with an
        // atomic/optimistic update constrained by `previous_hash` or a record
        // version; reload and recheck instead of overwriting a concurrent
        // password change.
    }
}
```

Do not reject a valid login just because the replacement hash cannot be
generated: policy verification deliberately reports it as valid without an
update. Enable `bcrypt-hasher` whenever the selected policy needs bcrypt as a
preferred or legacy hasher; its hasher rejects passwords longer than 72 bytes.

---

## User Management

### DefaultUserManager **(0.1.x only — removed in 0.2.x)**

In 0.1.x, `DefaultUserManager` provided a ready-made `UserManager` implementation for `DefaultUser`. In 0.2.x, both `DefaultUser` and `DefaultUserManager` are removed — implement the `UserManager` trait directly for your custom user type.

### UserManager Trait

```rust
pub trait UserManager: Send + Sync {
    async fn create_user(&self, data: CreateUserData) -> Result<Box<dyn User>, UserManagementError>;
    async fn get_user(&self, user_id: &str) -> Result<Option<Box<dyn User>>, UserManagementError>;
    async fn update_user(&self, user_id: &str, data: UpdateUserData) -> Result<Box<dyn User>, UserManagementError>;
    async fn delete_user(&self, user_id: &str) -> Result<(), UserManagementError>;
    async fn list_users(&self) -> Result<Vec<Box<dyn User>>, UserManagementError>;
}
```

### Group Management

```rust
pub trait GroupManager: Send + Sync {
    async fn create_group(&self, data: CreateGroupData) -> Result<Group, Error>;
    async fn get_group(&self, group_id: &str) -> Result<Option<Group>, Error>;
    // ...
}
```

### Superuser Creation

CLI command: `cargo run --bin createsuperuser`

```rust
pub trait SuperuserCreator: Send + Sync {
    async fn create_superuser(&self, username: &str, password: &str) -> Result<(), Error>;
}

// Auto-registration
auto_register_superuser_creator::<User>();
```

---

## PermissionsMixin Trait

Adds permission and group fields to user models:

```rust
pub trait PermissionsMixin {
    fn groups(&self) -> &[Group];
    fn user_permissions(&self) -> &[Permission];
    fn has_perm(&self, perm: &str) -> bool;
    fn has_perms(&self, perms: &[&str]) -> bool;
    fn has_module_perms(&self, app_label: &str) -> bool;
}
```

---

## Feature Flags

| Feature | Default | Purpose |
|---------|---------|---------|
| `params` | enabled | `CurrentUser<U>`, `AuthInfo`, `Guard<P>` extractors |
| `argon2-hasher` | disabled | Argon2id password hashing, `DefaultUser` |
| `bcrypt-hasher` | disabled | Bcrypt compatibility hashing for policy-based migrations |
| `database` | disabled | Database-backed user/group storage |

## Dynamic References

For the latest user model API:

1. Read `reinhardt/crates/reinhardt-auth/src/core/base_user.rs` for BaseUser trait
2. Read `reinhardt/crates/reinhardt-auth/src/core/auth_identity.rs` for AuthIdentity trait
3. Read `reinhardt/crates/reinhardt-auth/src/core/full_user.rs` for FullUser trait
4. Read `reinhardt/crates/reinhardt-auth/src/core/hasher.rs` for PasswordHasher
5. Read `reinhardt/crates/reinhardt-auth/src/core/permissions_mixin.rs` for PermissionsMixin
6. Read `reinhardt/crates/reinhardt-auth/src/core/superuser_creator.rs` for SuperuserCreator
7. Read `reinhardt/crates/reinhardt-auth/src/default_user.rs` for DefaultUser
8. Read `reinhardt/crates/reinhardt-auth/src/user_management.rs` for UserManager
