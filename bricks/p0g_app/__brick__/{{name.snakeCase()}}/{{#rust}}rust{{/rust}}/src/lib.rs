//! Rust used by the core through flutter_rust_bridge. FFI only: threads,
//! places and lifetimes belong to Squadron, so calls here can be
//! `#[frb(sync)]` and run inside whichever worker calls them.
pub mod api;
