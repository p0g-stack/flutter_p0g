# Upstream packet: WebUSB lifecycle (integration branch, not a PR)

Status: **integration branch only — do not open a PR from it.** It contains open PR #221's commits, so a PR
from this branch would duplicate #221 (and #232). PR text is provided for the one increment upstream does not
have yet.

| | |
| --- | --- |
| Upstream repository | https://github.com/kevinmehall/nusb |
| Base commit | `c46ccd0183844b6299b5354a4a13d6837d5fcf63` (upstream `main` tip at preparation time) |
| Fork | https://github.com/p0g-stack/nusb (existing) |
| Head branches | `p0g-webusb` and `webusb-device-lifecycle-followup`, **both** at `84890ce3774d1749905aef0b98a84fef0b70114b` (one commit, two refs) |
| Compare URL (whole stack) | https://github.com/kevinmehall/nusb/compare/c46ccd0183844b6299b5354a4a13d6837d5fcf63...p0g-stack:nusb:p0g-webusb |
| Shape | merge of `4e664c7` (PR #221 side) into `a63a98e` (error/cancellation side) |

## What the branches contain

`84890ce` is a merge commit with two parents:

- `4e664c7` — `jkcoxson`'s side, i.e. open PR #221: `47b1afa` *webusb: best effort close on WebusbDevice
  drop* and `4e664c7` *webusb: refcounted close after all device handles dropped*. Those commits sit on
  `816284b` (an older `main`), which is why a plain diff from them to the merge looks large: it also carries
  `main` forward to `c46ccd0`.
- `a63a98e` — this fork's error/cancellation series (rebase of #232, error evidence, chooser cancellation),
  based on `c46ccd0`.

The new content of the merge, relative to `a63a98e`, is 4 files, +206 −19:

- `src/platform/webusb/lifecycle.rs` (new, 157 lines): a lease on a JS `USBDevice` shared by independent nusb
  `Device` instances (and wasm modules). State-changing promises (`open`, claims) are queued behind each other
  on the JS object, so a cancellation cannot close the device while an open/claim is pending and a failed
  claim does not poison a later open. Reference counted: the device closes only when the last lease is
  released, and a pending close settles before a reopen.
- `src/platform/webusb/device.rs`: the device implementation goes through the lease.
- `src/device.rs`: `Device::force_close()` for wasm32, documented for callers that own exclusive access to the
  whole device; it invalidates independently opened handles, unlike dropping one.
- `src/platform/webusb/mod.rs`: registers the module.

## Behavioral checks actually executed

rustc/cargo 1.99.0, node 24.22.1 (wasm-bindgen tests run under node; nothing in them needs a browser).

1. `cargo test --lib` → 12 passed, 0 failed (same as the base commit).
2. `cargo check --target wasm32-unknown-unknown` → `Finished`; 25 warnings, the same count as the base commit.
3. `wasm-pack test --node --lib` → 9 passed, including the three new lifecycle tests:
   `platform::webusb::lifecycle::tests::independent_handles_close_only_after_last_lease`,
   `platform::webusb::lifecycle::tests::failed_state_change_does_not_prevent_force_close_or_reopen`,
   `platform::webusb::lifecycle::tests::cancellation_before_open_settles_still_closes`,
   plus the six error/cancellation tests from the earlier commits.

The base commit's wasm test build does not compile (`error: Only features sync,macros,io-util,rt,time are
supported on wasm` from the non-wasm `tokio` dev-dependency), so those tests only exist from this series on. No
physical device was used.

## Suggested upstream sequence

1. #221 (open, `jkcoxson`) — review/merge as is.
2. #232 (open, `1vivy`) — review/merge; the fork's `4e84097` is the same patch rebased on `main`.
3. A PR from `webusb-error-fidelity`, reduced to `eb2fe23`.
4. A PR from `webusb-request-device-errors`, reduced to `a63a98e`.
5. A PR on top of #221 for the lease/`force_close` increment below.

## PR body (for the lease increment, after #221 lands)

```text
webusb: share a JS device between handles and close only the last lease

Independent nusb Device instances, and independent wasm modules, can be
handed the same JS USBDevice. PR #221 made dropping a handle close the
device best-effort; with two handles that closes the device under the
other one, and a cancellation can close it while an open or a claim is
still pending.

Queue state-changing promises per JS device and reference count the opens:
the device closes only when the last lease is released, a failed claim does
not poison a later open, and a pending close settles before a reopen.

Add Device::force_close() (wasm32) for callers that own exclusive access to
the entire device and want to cancel its transfers; dropping a handle
deliberately does not do that.

Checks: `cargo test --lib` (12 passed), `cargo check --target
wasm32-unknown-unknown`, and the wasm-bindgen tests under node
(`wasm-pack test --node --lib`, 9 passed including three lease tests:
close only after the last lease, failed state change does not block
force_close or reopen, cancellation before the open settles still closes).
```

## Notes

- `p0g-webusb` and `webusb-device-lifecycle-followup` are the same commit; one of the two refs is redundant and
  can be retired once nothing depends on it. Neither was reset.
- The merge carries `main` from `816284b` to `c46ccd0` for the #221 side; that is why the compare URL shows a
  large diff against the merge's first parent.
