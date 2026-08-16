# Component-Scoped Style DSL Reference (0.4.x)

The Pages style DSL gives a component a typed class and variable API while
emitting one static stylesheet. Use the canonical envelope
`#[style_def] static ... = style! { ... };`.

## Definition and Use

```rust
use reinhardt::pages::{CssColor, page, style, style_def};

#[style_def]
static STYLES: CardStyles = style! {
    globals { border: Color; }
    vars { accent: Color = red; }

    .card {
        border-color: globals.border;
        color: vars.accent;
        .label { color: vars.accent; }
    }
};

let accent = CssColor::parse("blue")?;
let view = page!({
    article {
        class: STYLES.card() + "legacy-card",
        style: STYLES.vars().accent(accent),
        span { "Card" }
    }
});
```

Selectors and properties follow CSS-shaped names. `globals` declares values
that are supplied by the surrounding style context, while `vars` declares
typed variables and their defaults. Generated helpers validate references and
typed runtime overrides. Nested rules are required because Rust token streams
do not preserve selector whitespace.

## Asset and Build Contract

The generated stylesheet is a static asset at the logical path
`__reinhardt__/components.css`. Applications must link it once per document;
the macro does not inject a `<link>` element automatically. Keep the link in
the document head or the application shell rather than in every component.

CSS-only changes can flow through the extractor/formatter/collectstatic/HMR
pipeline without a native or WASM rebuild. Review the generated asset path and
the collectstatic/HMR configuration when introducing a new style definition.

Plain string `class:` and `style:` attributes remain supported, so migrate a
component incrementally when a typed style boundary is not useful.

## Review Checklist

- The definition uses `#[style_def]` on a static item whose type matches the
  generated style API.
- Every referenced global/variable is declared, and runtime overrides use the
  generated typed helpers.
- Nested selectors are expressed as nested rules, not whitespace-dependent
  token text.
- `__reinhardt__/components.css` is linked exactly once per document.
- CSS-only changes are validated through the asset pipeline without adding a
  native/WASM rebuild requirement.
