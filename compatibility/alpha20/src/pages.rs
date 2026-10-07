use reinhardt::pages::i18n::{I18nContext, MessageCatalog, TranslationContext};
use reinhardt::pages::{
    Context, Page, Signal, deps, form, get_context, page, provide_context, style_def, use_form,
    use_form_action, use_resource,
};

#[style_def]
pub static STYLES: CompatibilityStyles = style! {
    .card { color: red; }
};

pub fn context_value() -> i32 {
    let context: Context<Signal<i32>> = Context::new();
    provide_context(&context, Signal::new(42));
    get_context(&context).expect("provided context").get()
}

pub fn reactive_page(shown: bool) -> Page {
    let visible = Signal::new(shown);
    let value = Signal::new(42);
    let _resource = use_resource(|| async { Ok::<_, String>(42) }, deps![]);
    page!(|visible: Signal<bool>, value: Signal<i32>| {
        if visible.get() {
            p { { value.get().to_string() } }
        } else {
            p { "Hidden" }
        }
    })(visible, value)
}

pub fn form_runtime() {
    let login_form = form! {
        name: CompatibilityLogin,
        action: "/login",
        fields: {
            username: CharField { label: "Username", required: true },
            password: CharField { label: "Password", required: true },
        }
    };
    let runtime = use_form(&login_form)
        .on_submit_success(|runtime| runtime.reset())
        .build();
    let submit = use_form_action(&runtime, |values| async move {
        Ok::<_, String>(values.username)
    })
    .on_success(|runtime, _result| runtime.reset());
    // The application connects this handler at its single form submission boundary.
    let _handler = submit.submit_handler();
}

pub fn japanese_context() -> I18nContext {
    let mut catalog = MessageCatalog::new("ja");
    catalog.add_translation("Workspace", "ワークスペース");
    let mut translations = TranslationContext::new("ja", "en-US");
    translations
        .add_catalog("ja", catalog)
        .expect("valid locale");
    I18nContext::new(translations)
}

pub fn localized_page() -> Page {
    page!(|| {
        h1 { { reinhardt::pages::t!("Workspace") } }
    })()
}

#[reinhardt::url_patterns]
pub fn app_routes() -> reinhardt::prelude::UnifiedRouter {
    reinhardt::prelude::UnifiedRouter::new().client(|router| router)
}

#[cfg(not(target_arch = "wasm32"))]
#[reinhardt::di::injectable_key]
pub struct CompatibilityValueKey;

#[reinhardt::pages::server_fn::server_fn]
pub async fn read_injected_value(
    suffix: String,
    #[inject] value: reinhardt::di::KeyedDepends<CompatibilityValueKey, String>,
) -> Result<String, reinhardt::pages::ServerFnError> {
    Ok(format!("{}{suffix}", &*value))
}
