# head!, form!, and #[server_fn] Reference

## head! Macro

Creates an HTML head section for SSR. Returns a `Head` struct.

### Syntax

```rust
use reinhardt::pages::prelude::*;

let my_head = head!(|| {
    title { "My Application" }
    meta { name: "description", content: "A great application" }
    meta { name: "viewport", content: "width=device-width, initial-scale=1.0" }
    link { rel: "icon", href: "/favicon.png", type: "image/png" }
    link { rel: "stylesheet", href: resolve_static("css/style.css") }
    script { src: resolve_static("js/app.js"), defer }
});

// Render to HTML string
let html = my_head.to_html();
```

### Supported Elements

| Element | Attributes | Example |
|---------|-----------|---------|
| `title` | Text content | `title { "Page Title" }` |
| `meta` | `name`, `content`, `property`, `charset`, `http_equiv` | `meta { name: "description", content: "..." }` |
| `link` | `rel`, `href`, `type`, `as_`, `integrity`, `crossorigin`, `media`, `sizes` | `link { rel: "stylesheet", href: "..." }` |
| `script` | `src`, `type`, `defer`, `async_`, `integrity`, `crossorigin`, `nonce`, text content | `script { src: "...", defer }` |
| `style` | Text content | `style { "body { margin: 0; }" }` |

### Static File Integration

Use `resolve_static()` for hashed static file URLs (collectstatic support):

```rust
link { rel: "stylesheet", href: resolve_static("css/main.css") }
// Resolves to: /static/css/main.abc123.css
```

## form! Macro

Creates type-safe forms with reactive bindings and validation.

### Basic Syntax

```rust
use reinhardt::pages::form;
use reinhardt::pages::component::Page;

let login_form = form! {
    name: LoginForm,
    server_fn: login,  // Links to a #[server_fn] function
    class: "space-y-4",
    redirect_on_success: "/",

    fields: {
        username: CharField { required, label: "Username", max_length: 150 },
        password: PasswordField { required, min_length: 8, label: "Password" },
        submit: SubmitButton { label: "Sign in", class: "btn-primary w-full" },
    },
};

// Convert to Page (NOT .into_view())
let form_view: Page = login_form.into_page();
```

### Form-Level Attributes

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| `name` | Ident | Yes | Form struct name |
| `action` | String | One of action/server_fn | URL endpoint |
| `server_fn` | Path | One of action/server_fn | Server function for type-safe RPC |
| `method` | Method | No | HTTP method (default: `Post`) |
| `class` | String | No | CSS class (default: `"reinhardt-form"`) |
| `initial_loader` | Path | No | Server function for initial values |
| `redirect_on_success` | String | No | URL redirect after success |
| `on_success` | Closure | No | Callback on successful submission |

### HTTP Methods

| Method | Syntax | Notes |
|--------|--------|-------|
| GET | `method: Get` | Standard HTML |
| POST | `method: Post` | Default |
| PUT | `method: Put` | Hidden `_method` field |
| PATCH | `method: Patch` | Hidden `_method` field |
| DELETE | `method: Delete` | Hidden `_method` field |

### Field Types

#### String Fields

| Field Type | Rust Type | Default Widget |
|------------|-----------|----------------|
| `CharField` | `String` | `TextInput` |
| `TextField` | `String` | `Textarea` |
| `EmailField` | `String` | `EmailInput` |
| `PasswordField` | `String` | `PasswordInput` |
| `UrlField` | `String` | `UrlInput` |
| `SlugField` | `String` | `TextInput` |
| `HiddenField` | `String` | `HiddenInput` |
| `JsonField` | `String` | `Textarea` |

#### Numeric Fields

| Field Type | Rust Type | Default Widget |
|------------|-----------|----------------|
| `IntegerField` | `i64` | `NumberInput` |
| `FloatField` | `f64` | `NumberInput` |
| `DecimalField` | `f64` | `NumberInput` |

#### Other Fields

| Field Type | Rust Type | Default Widget |
|------------|-----------|----------------|
| `BooleanField` | `bool` | `CheckboxInput` |
| `DateField` | `Option<NaiveDate>` | `DateInput` |
| `TimeField` | `Option<NaiveTime>` | `TimeInput` |
| `DateTimeField` | `Option<NaiveDateTime>` | `DateTimeInput` |
| `ChoiceField` | `String` | `Select` |
| `MultipleChoiceField` | `Vec<String>` | `SelectMultiple` |
| `FileField` | `Option<web_sys::File>` | `FileInput` |
| `ImageField` | `Option<web_sys::File>` | `FileInput` |

### Widget Types

| Category | Widgets |
|----------|---------|
| Text | `TextInput`, `EmailInput`, `PasswordInput`, `UrlInput`, `TelInput`, `SearchInput`, `Textarea` |
| Numeric | `NumberInput`, `RangeInput` |
| Date/Time | `DateInput`, `TimeInput`, `DateTimeInput` |
| Selection | `CheckboxInput`, `RadioInput`, `RadioSelect`, `Select`, `SelectMultiple` |
| Other | `FileInput`, `HiddenInput`, `ColorInput` |

### Field Properties

| Property | Type | Example |
|----------|------|---------|
| `required` | flag | `required` |
| `min_length` | i64 | `min_length: 3` |
| `max_length` | i64 | `max_length: 150` |
| `min_value` | i64 | `min_value: 0` |
| `max_value` | i64 | `max_value: 100` |
| `pattern` | String | `pattern: "[0-9]+"` |
| `label` | String | `label: "Username"` |
| `placeholder` | String | `placeholder: "Enter..."` |
| `help_text` | String | `help_text: "Max 150 chars"` |
| `disabled` | flag | `disabled` |
| `readonly` | flag | `readonly` |
| `autofocus` | flag | `autofocus` |
| `class` | String | `class: "input"` |
| `widget` | Widget | `widget: PasswordInput` |
| `initial_from` | String | `initial_from: "field_name"` |

### Field Groups

```rust
form! {
    name: AddressForm,
    action: "/api/address",

    fields: {
        name: CharField { required, label: "Full Name" },

        address_group: FieldGroup {
            label: "Address",
            class: "address-section",
            fields: {
                street: CharField { required, label: "Street" },
                city: CharField { required, label: "City" },
                zip: CharField { required, label: "ZIP Code", max_length: 10 },
            },
        },
    },
}
```

Groups render as `<fieldset>` with optional `<legend>`. Fields are flattened for accessor methods (`form.street()`).

### SubmitButton

Add a submit button as a field:

```rust
fields: {
    // ... other fields ...
    submit: SubmitButton { label: "Submit", class: "btn-primary w-full py-2.5" },
}
```

### on_success Callback

Handle successful form submission (e.g., update auth state):

```rust
form! {
    name: LoginForm,
    server_fn: login,
    redirect_on_success: "/",
    on_success: |result: AuthResponse| {
        use reinhardt::pages::auth::{AuthData, auth_state};

        if let Some(ref user) = result.user {
            auth_state().update(AuthData {
                is_authenticated: true,
                username: Some(user.username.clone()),
                email: Some(user.email.clone()),
                ..Default::default()
            });
        }
    },
    fields: { /* ... */ },
}
```

### Validation

#### Server-Side

```rust
validators: {
    username: [
        |v| !v.trim().is_empty() => "Cannot be empty",
        |v| v.len() >= 3 => "Must be at least 3 characters",
        |v| v.chars().all(|c| c.is_alphanumeric() || c == '_')
            => "Only letters, numbers, and underscores",
    ],
}
```

#### Client-Side

```rust
client_validators: {
    username: [
        "value.length > 0" => "Cannot be empty",
        "value.length >= 3" => "Must be at least 3 characters",
    ],
}
```

## #[server_fn] Attribute Macro

Generates RPC stubs for client-server communication. On WASM: HTTP client stub. On native: route handler.

### Basic Usage

```rust
use reinhardt::pages::server_fn::{ServerFnError, server_fn};

#[server_fn]
pub async fn get_user(id: u32) -> Result<User, ServerFnError> {
    // Server-side code (removed on WASM build)
    let user = User::objects().get(id as i64).await?;
    Ok(user)
}

// On WASM: calls HTTP endpoint
// On native: runs as route handler
let user = get_user(42).await?;
```

### Dependency Injection in Server Functions

Use `#[inject]` on parameters to receive DI dependencies (replaces deprecated `use_inject` option):

```rust
#[server_fn]
pub async fn login(
    username: String,
    password: String,
    #[inject] http_request: reinhardt::pages::server_fn::ServerFnRequest,
) -> Result<AuthResponse, ServerFnError> {
    let user = services::verify_credentials(&username, &password)
        .await
        .map_err(|err| ServerFnError::application("Invalid credentials"))?;

    // Set session cookie via ServerFnRequest
    http_request.add_response_cookie(
        format!("sessionid={session_id}; HttpOnly; SameSite=Lax; Path=/; Max-Age=86400")
    );

    Ok(AuthResponse { success: true, user: Some(user.into()) })
}

// AuthUser extractor via DI
#[server_fn]
pub async fn me(
    #[inject] reinhardt::AuthUser(user): reinhardt::AuthUser<User>,
) -> Result<UserInfo, ServerFnError> {
    Ok(UserInfo::from(&user))
}
```

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `endpoint` | String | Auto-generated | Custom endpoint path |
| `codec` | String | `"json"` | Serialization: `"json"`, `"url"`, `"msgpack"` |
| `use_inject` | bool | — | **Deprecated** — use inline `#[inject]` on parameters instead |

### Error Handling

Use `ServerFnError::application(msg)` for application-level errors. Log internal details with `tracing`, return generic messages to prevent information leakage:

```rust
use tracing::error;

#[server_fn]
pub async fn create_user(name: String) -> Result<User, ServerFnError> {
    if name.is_empty() {
        return Err(ServerFnError::application("Name cannot be empty"));
    }
    let user = User::objects().create_from(&CreateUserData { name }).await
        .map_err(|e| {
            error!("Failed to create user: {e}");
            ServerFnError::application("Internal server error")
        })?;
    Ok(user)
}
```

### With form! Integration

```rust
let form = form! {
    name: CreateUserForm,
    server_fn: create_user,  // Links directly to server function
    fields: {
        name: CharField { required, label: "Name" },
        email: EmailField { required, label: "Email" },
        submit: SubmitButton { label: "Create" },
    },
};
```
