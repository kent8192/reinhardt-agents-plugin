use reinhardt::auth::sessions::{
    CsrfSessionManager, InMemorySessionBackend, RotationPolicy, Session, SessionBackend,
    SessionCleanupTask, SessionRotator,
};
use reinhardt::pages::{SsrOptions, SsrRenderer, reactive::ReactiveScope};
use rstest::rstest;

use crate::{
    examples::{AppError, MyAppSettings},
    pages,
};

#[rstest]
fn scoped_context_and_form_callbacks_use_current_apis() {
    // Arrange
    let scope = ReactiveScope::new();

    // Act
    let value = scope.enter(|| {
        pages::form_runtime();
        pages::context_value()
    });

    // Assert
    assert_eq!(value, 42);
}

#[rstest]
#[case(true, "<p>42</p>")]
#[case(false, "<p>Hidden</p>")]
#[tokio::test]
async fn page_control_flow_renders_native_html(#[case] shown: bool, #[case] expected: &str) {
    // Arrange
    let scope = ReactiveScope::new();
    let page = scope.enter(|| pages::reactive_page(shown));
    let mut renderer = SsrRenderer::new();

    // Act
    let html = renderer.render_page_into_page_to_string(page).await;

    // Assert
    assert_eq!(
        html.split_once("<div id=\"app\">")
            .unwrap()
            .1
            .split_once("</div>")
            .unwrap()
            .0,
        expected,
    );
}

#[rstest]
#[tokio::test]
async fn catalogs_render_translated_copy() {
    // Arrange
    let scope = ReactiveScope::new();
    let page = scope.enter(pages::localized_page);
    let mut renderer =
        SsrRenderer::with_options(SsrOptions::new().i18n_context(pages::japanese_context()));

    // Act
    let html = renderer.render_page_into_page_to_string(page).await;

    // Assert
    assert_eq!(
        html.split_once("<div id=\"app\">")
            .unwrap()
            .1
            .split_once("</div>")
            .unwrap()
            .0,
        "<h1>ワークスペース</h1>",
    );
    assert_eq!(
        html.split_once("<html lang=\"")
            .unwrap()
            .1
            .split_once("\"")
            .unwrap()
            .0,
        "ja"
    );
    assert_eq!(
        renderer.state().get_metadata("pages.i18n").unwrap()["current_locale"],
        "ja"
    );
}

#[rstest]
fn settings_validate_the_environment_profile() {
    use reinhardt::conf::settings::{fragment::SettingsValidation, profile::Profile};
    // Arrange
    let settings = MyAppSettings {
        api_key: "dev-secret".into(),
        max_retries: 3,
        timeout_secs: 30,
    };

    // Act
    let development = settings.validate(&Profile::Development);
    let production = settings.validate(&Profile::Production);

    // Assert
    development.unwrap();
    assert_eq!(
        production.unwrap_err().to_string(),
        "Security error: production myapp.api_key must not use a development key"
    );
}

#[rstest]
fn framework_errors_are_sanitized_at_the_http_boundary() {
    // Arrange
    let error = AppError::Framework(reinhardt::Error::Internal("private diagnostic".into()));

    // Act
    let response = error.error_response().unwrap();

    // Assert
    assert_eq!(response.status, hyper::StatusCode::INTERNAL_SERVER_ERROR);
    assert_eq!(
        serde_json::from_slice::<serde_json::Value>(&response.body).unwrap(),
        serde_json::json!({"detail": "Internal server error"})
    );
}

#[rstest]
#[tokio::test]
async fn session_backend_cleanup_rotation_and_csrf_are_compatible() {
    // Arrange
    let backend = InMemorySessionBackend::new();
    let data = serde_json::json!({"user_id": 42});
    let mut session = Session::new(backend.clone());
    let csrf = CsrfSessionManager::new();

    // Act
    backend
        .save("session-key", &data, Some(3600))
        .await
        .unwrap();
    let loaded: Option<serde_json::Value> = backend.load("session-key").await.unwrap();
    let token = csrf.generate_token(&mut session).unwrap();
    let valid = csrf.validate_token(&mut session, &token).unwrap();
    let invalid = csrf.validate_token(&mut session, "wrong-token").unwrap();
    SessionRotator::new(RotationPolicy::default())
        .rotate(&mut session)
        .await
        .unwrap();
    let cleaned = SessionCleanupTask::new(backend, std::time::Duration::from_secs(3600))
        .run_cleanup()
        .await
        .unwrap();

    // Assert
    assert_eq!(loaded, Some(data));
    assert_eq!((valid, invalid), (true, false));
    assert_eq!(cleaned, 0);
}

#[rstest]
#[case(AppError::NotFound("missing".into()), 404, "missing")]
#[case(AppError::Validation("invalid".into()), 400, "invalid")]
#[case(AppError::PermissionDenied("forbidden".into()), 403, "forbidden")]
#[case(AppError::Conflict("conflict".into()), 409, "conflict")]
#[case(AppError::Unauthorized("unauthorized".into()), 401, "unauthorized")]
fn application_errors_map_safe_messages(
    #[case] error: AppError,
    #[case] status: u16,
    #[case] detail: &str,
) {
    // Arrange
    let result: Result<serde_json::Value, AppError> = Err(error);

    // Act
    let response = crate::examples::error::http_result(result, hyper::StatusCode::OK).unwrap();

    // Assert
    assert_eq!(response.status.as_u16(), status);
    assert_eq!(
        serde_json::from_slice::<serde_json::Value>(&response.body).unwrap(),
        serde_json::json!({"detail": detail})
    );
}
