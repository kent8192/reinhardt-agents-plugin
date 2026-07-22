# DTO-Derived Client Form Bindings

## Availability

`ClientForm` and `ClientFormChoices` are available in
**0.4.0-alpha.1+**. They are opt-in additions: `form!` continues to own
hand-defined static forms, while `use_form` remains the shared runtime for both
styles.

Use a generated companion only when a non-generic, named request DTO is the
canonical browser payload. Keep `form!` when the UI has an intentionally
different schema or needs collections, maps, file fields, or custom field types
outside the generated contract.

| Source of truth | Use when |
|-----------------|----------|
| `form!` | The page owns a distinct static schema, widgets, or fields that should not mirror one DTO. |
| `ClientForm` | A named DTO should own field names, typed request assembly, optional-string normalization, validation, and server-function input. |

## Canonical DTO Shape

`#[reinhardt::dto]` is the cross-target validation attribute for named request
DTOs. In this release line it supplies or normalizes `Validate`; explicitly
derive `Clone`, `Serialize`, and `Deserialize` when the DTO needs those traits.
Then derive `ClientForm` explicitly.

```rust,ignore
use reinhardt::pages::{ClientForm, ClientFormChoices, use_form};

#[derive(
    Clone,
    Default,
    PartialEq,
    serde::Serialize,
    serde::Deserialize,
    ClientFormChoices,
)]
#[serde(rename_all = "snake_case")]
enum ProviderMode {
    #[default]
    Fake,
    LiveApi,
}

#[reinhardt::dto]
#[derive(Clone, serde::Serialize, serde::Deserialize, ClientForm)]
#[client_form(server_fn = crate::server::submit_project, validate)]
pub struct ProjectRequest {
    pub name: String,
    pub title: Option<String>,
    pub provider_mode: ProviderMode,
}

let form = ProjectRequestClientForm::new();
let runtime = use_form(&form).build();
runtime.set_value(ProjectRequestClientFormField::Title, "  ".to_string());

let request = ProjectRequestClientForm::to_request(&runtime);
assert_eq!(request.title, None);

// WASM client code only: the generated helper owns async form state.
let outcome = form.submit(&runtime).await?;
```

By default, `ProjectRequest` generates `ProjectRequestClientForm`,
`ProjectRequestClientFormValues`, and `ProjectRequestClientFormField`. Use
`#[client_form(name = CustomProjectForm)]` only when a deliberate public naming
boundary requires a different stem.

## Supported Fields and Choices

Editable fields may be `String`, `Option<String>`, primitive numeric types,
`bool`, their supported `Option` forms, or a `ClientFormChoices` enum (including
`Option<Enum>`). The editable runtime type for `Option<String>` is `String`;
conversion trims it and maps an empty value to `None`.

Collections, maps, generic DTOs, generic field types, tuple/unit structs, and
unsupported nested field shapes fail at compile time. Do not work around those
errors by silently dropping client fields; choose `form!` or model the explicit
conversion boundary instead.

`ClientFormChoices` is for externally tagged, fieldless enums whose browser
values are bare strings. Its choices mirror serde's serialize and deserialize
names. It accepts matching variant rename values and matching `rename_all`
rules limited to `snake_case`, `kebab-case`, or `camelCase`. It rejects data
variants, tagged/untagged representations, directional renames that produce
different wire names, and aliases or duplicate values that collide with an
emitted choice. Select a non-skipped default variant when an enum skips choices.

## Hidden Fields, Validation, and Submission

Use `#[client_form(skip)]` or a serde skip attribute for a field that is not
editable. The generated form preserves its hidden/default value during refresh
and request reconstruction; an explicit `client_form(skip)` field must be an
`Option<T>` or implement `Default`. Exported DTOs must make every editable field
public.

`#[client_form(validate)]` maps the DTO's `Validate` errors into generated field
or form errors. Test the mapping directly rather than recreating validation in a
click handler.

`#[client_form(server_fn = path)]` generates a typed async submit helper for
WASM. The DTO must implement `Serialize`, the marker request must be that DTO,
the response must be `DeserializeOwned`, and the error must implement `Display`
and `From<ServerFnError>`. Do not place `serde(skip)`,
`serde(skip_serializing)`, `serde(skip_serializing_if)`, or
`serde(skip_deserializing)` on a request field used by that helper: browser and
native deserialization must agree. Keep a manual submission boundary if that
wire contract cannot be met.

The generated helper delegates to the `use_form` async lifecycle:

- validation failure does not invoke the server function;
- a second submit while pending reports an already-pending outcome;
- success, operation error, and cancellation must leave pending/success/error
  state accurate for the UI.

In native tests, exercise the same behavior with `runtime.submit_async(...)`.
Use `form.submit(&runtime)` only in WASM client code.

## Review and Test Matrix

Before merging a DTO-derived form, verify:

- DTO defaults and hidden values survive `with_defaults()` and `to_request()`.
- Optional strings, enum wire values, and `ClientFormChoices` defaults match
  their DTO and serde contracts.
- DTO validation errors surface at the expected field and prevent dispatch.
- Pending, success, error, and cancellation UI comes from the form runtime.
- Pass/fail derive coverage protects unsupported fields and invalid enum serde
  shapes, while browser coverage exercises the generated submit path.
