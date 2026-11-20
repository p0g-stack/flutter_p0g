# Upstream packet: WebUSB rejection evidence (follow-up to PR #232)

Status: branch pushed to the org fork, PR text ready for the increment that #232 does not contain. **No PR
opened** (opening upstream PRs is not authorized, and PR #232 already covers the first commit).

| | |
| --- | --- |
| Upstream repository | https://github.com/kevinmehall/nusb |
| Base commit | `c46ccd0183844b6299b5354a4a13d6837d5fcf63` (`descriptors: fix parsing 2-byte (no payload) nonstandard descriptors (#252)`; upstream `main` tip at preparation time) |
| Fork | https://github.com/p0g-stack/nusb (existing) |
| Head branch | `webusb-error-fidelity` @ `eb2fe2397e392bf56634cd98da8f7c6d32af153a` |
| Compare URL | https://github.com/kevinmehall/nusb/compare/c46ccd0183844b6299b5354a4a13d6837d5fcf63...p0g-stack:nusb:webusb-error-fidelity |
| Diff | 9 files, +214 −22 over the base |
| Existing PRs | #221 (open, `jkcoxson`: best-effort close on drop) and #232 (open, `1vivy`: preserve WebUSB rejection details) — do not duplicate either |

## What the branch contains

Two commits, both based on the current `main`:

1. `4e84097` *Preserve WebUSB rejection details in owned errors* — **identical change to open PR #232**
   (`git patch-id --stable` is `89f9b1b0c198e419cd71872d3db0629c072b8108` for both this commit and #232's head
   `71ddf6dd`, which was based on an older `main`). This commit exists here only so the branch is current;
   the reviewable PR for it is #232.
2. `eb2fe23` *Expose owned WebUSB rejection evidence for operations and endpoints* — 5 files, +141 −16:
   `src/device.rs`, `src/error.rs`, `src/lib.rs`, `src/platform/webusb/device.rs`, `src/platform/webusb/mod.rs`.
   It surfaces the owned rejection evidence #232 collects through device operations and endpoints, so a caller
   can report why the browser refused instead of a flattened message.

Branch series in the fork: `webusb-error-fidelity` ⊂ `webusb-request-device-errors` ⊂ `p0g-webusb`.

## Behavioral checks actually executed

rustc/cargo 1.99.0.

1. `cargo test --lib` → 12 passed, 0 failed (the same 12 as the base commit).
2. `cargo check --target wasm32-unknown-unknown` → `Finished`; 25 warnings, the same count as the base commit.
3. `wasm-pack test --node --lib` (the repository's wasm-bindgen tests, nothing browser- or device-specific in
   them) → 4 passed:
   `platform::webusb::error_tests::preserves_error_dom_exception_and_string_rejections`,
   `platform::webusb::error_tests::unusual_rejections_do_not_panic_or_erase_available_fields`,
   `platform::webusb::device::error_tests::synchronous_submission_rejection_preserves_details`,
   `platform::webusb::device::error_tests::completion_retains_rejection_and_clears_it_on_next_completion`.

The base commit's wasm test build does not compile (`error: Only features sync,macros,io-util,rt,time are
supported on wasm` from the non-wasm `tokio` dev-dependency), so these tests only exist from this branch on.
No physical device was used; the chooser/claim paths themselves still need a browser and a device.

## PR body (for `eb2fe23`, stacked on #232)

```text
webusb: expose owned rejection evidence for operations and endpoints

Follow-up to #232. That change keeps the browser's rejection reason on the
errors nusb returns; this one carries the same evidence through the
operations and endpoints that report their own error text, so a failing
call explains what the browser refused (a revoked permission, a busy
interface, a disconnected device) instead of a generic message.

The public error type gains the owned detail alongside the existing
message, and the WebUSB device/endpoint paths attach it where they
translate a rejected promise. Existing message text and error variants are
unchanged, so current callers keep compiling.

No behaviour changes for builds that do not target wasm32: the code is
behind `cfg(target_arch = "wasm32")`.

Checks: `cargo test --lib` (12 passed) and `cargo check --target
wasm32-unknown-unknown` (clean, same warnings as before).
```

## Notes

- Rebase before opening if `main` moved; the branch is cut from `main` as of preparation.
- If #232 lands first, the branch can be reduced to `eb2fe23` alone (`git rebase --onto`).
