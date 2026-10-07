//! External consumer checks for the plugin's pinned framework examples.
pub mod pages;

#[cfg(not(target_arch = "wasm32"))]
pub mod native;

#[cfg(all(test, not(target_arch = "wasm32")))]
mod examples;

#[cfg(all(test, not(target_arch = "wasm32")))]
mod tests;

#[cfg(all(test, not(target_arch = "wasm32")))]
mod receiver;
