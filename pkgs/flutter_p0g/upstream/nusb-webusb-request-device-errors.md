# Upstream packet: WebUSB chooser cancellation vs refusal

Status: branch pushed to the org fork, PR text ready for the top commit only. **No PR opened** (opening
upstream PRs is not authorized; the branch stacks on the open PRs #221/#232).

| | |
| --- | --- |
| Upstream repository | https://github.com/kevinmehall/nusb |
| Base commit | `c46ccd0183844b6299b5354a4a13d6837d5fcf63` (`descriptors: fix parsing 2-byte (no payload) nonstandard descriptors (#252)`; upstream `main` tip at preparation time) |
| Fork | https://github.com/p0g-stack/nusb (existing) |
| Head branch | `webusb-request-device-errors` @ `a63a98efc841dcbb86d1d339c2b5d5aa5a3a6a34` |
| Compare URL | https://github.com/kevinmehall/nusb/compare/c46ccd0183844b6299b5354a4a13d6837d5fcf63...p0g-stack:nusb:webusb-request-device-errors |
| Diff | 10 files, +263 −27 over the base |
| Existing PRs | #221 (open, `jkcoxson`) and #232 (open, `1vivy`) — do not duplicate |

## What the branch contains

Three commits, all based on the current `main`:

1. `4e84097` — identical change to open PR #232 (same patch-id, see the error-fidelity packet).
2. `eb2fe23` *Expose owned WebUSB rejection evidence for operations and endpoints* — see the
   `nusb-webusb-error-fidelity` packet.
3. `a63a98e` *Distinguish WebUSB chooser cancellation from refusal* — **the new, reviewable increment**:
   1 file, `src/platform/webusb/enumeration.rs`, +49 −5. `requestDevice()` currently reports the user closing
   the chooser the same way as the browser refusing to show it (no transient activation, permission policy,
   no matching device); the change keeps them apart so a caller can tell "the user picked nothing" from
   "the picker was not allowed to open".

## Behavioral checks actually executed

rustc/cargo 1.99.0.

1. `cargo test --lib` → 12 passed, 0 failed (the same 12 as the base commit).
2. `cargo check --target wasm32-unknown-unknown` → `Finished`; 25 warnings, the same count as the base commit.
3. `wasm-pack test --node --lib` → 6 passed, including the two new tests in this commit:
   `platform::webusb::enumeration::tests::only_not_found_is_cancellation` (only `NotFoundError` maps to
   cancellation; `SecurityError`, `NotAllowedError` and `InvalidStateError` keep their name and message in the
   returned error) and `platform::webusb::enumeration::tests::unstructured_rejection_is_not_cancellation`
   (a plain string rejection and `undefined` stay errors). The other four are the error-evidence tests from the
   previous commit.

The base commit's wasm test build does not compile (`error: Only features sync,macros,io-util,rt,time are
supported on wasm` from the non-wasm `tokio` dev-dependency), so these tests only exist from this series on.
No physical device was used; showing the chooser still needs a browser and a user gesture.

## PR body (for `a63a98e`, stacked on #232 and the error-evidence change)

```text
webusb: distinguish chooser cancellation from refusal

`requestDevice()` reports two different outcomes the same way: the user
closing the browser's chooser, and the browser refusing to show it at all
(no transient activation, a permission policy, no matching device). A caller
cannot tell "the user picked nothing" from "the picker was not allowed to
open", which are different things to tell a user and different things to
retry.

Map the chooser's own cancellation to a distinct outcome and keep the
refusal on the existing error path, so the message still carries the
browser's reason.

Checks: `cargo test --lib` (12 passed) and `cargo check --target
wasm32-unknown-unknown` (clean, same warnings as before).
```

## Notes

- The branch is cumulative for convenience; if #232 and the error-evidence PR land, `git rebase --onto` leaves
  this single commit.
