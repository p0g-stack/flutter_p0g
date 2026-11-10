# Patterns: apps that talk to a device

For apps that reach a phone or a board over a cable (fastboot, adb, a serial
port), from the device itself, the CLI or the page. Nothing here is a brick:
these are rules for the code you write in the strategies the `strategy`
brick stamps. A link library (profiles, transports, the connect pop-up)
starts inside the first app that needs one and becomes a brick only once a
second app copies it. A protocol and its vendor extensions stay in the app
that speaks them.

## Fit the strategy model

**"Not now, connect a phone" is a waiting availability.** Facts say what a
place can do and never change while it runs. Whether a phone is plugged in
changes when a person acts, so it isn't a fact. The strategy holds its link
and checks it in `available`:

```dart
final class FlashOverWebUsb extends WriteStrategy<FlashRequest, void> {
  FlashOverWebUsb(this.link);
  final FastbootLink link;

  @override
  Set<String> get requires => const {Fact.usbWeb};

  @override
  Availability available(Facts facts) {
    final base = super.available(facts);
    if (!base.ok || link.ready('fastbootd')) return base;
    return Availability(name, note: 'connect a phone in fastbootd', waiting: true);
  }
  ...
}
```

`Selection.chosen` stays the first strategy that is ready now. `Selection.waiting`
lists the ones that would run once the user acts, so the UI can offer "or
connect a phone to use fastboot". `Selection.why` logs
`flash_over_webusb waits: connect a phone in fastbootd; dd chosen`.

**A write names its device.** A write to a device outside this place puts the
device in its input (`FlashRequest(serial, mode, image)`), shows it in
`plan`'s steps, and its `write` refuses when the device connected now is
another one. Otherwise a cable swapped between confirm and write flashes the
other phone. `WriteStrategy`'s doc comment carries this rule. A write to this
device (`dd` in the root process) has nothing to pin.

**Uncertain results are the app's.** When a write may or may not have
landed, return it in your result type (`FlashResult.uncertain(evidence)`) or
throw your own exception. The objective logs either one as the run's outcome.

**One log.** Log the link on `Logger('link.<name>')`. `logTo` already
collects every logger, so a downloadable report is the strategy log plus the
link events.

**Link state across places.** When the transport lives in the process place
(usbfs in the root process, the desktop CLI), a service method streams the
state (`Stream<LinkState> link()`). Choosing a device always happens on the
page, because WebUSB needs a click there.

## Describe what is known

Keep the original error: type and name, message, stack, cause chain, the
native code when the host exposes one, and errors from cleanup. Classify it
alongside, never instead.

Separate four things, because each one hides the others:

- **Source:** which API produced the evidence.
- **Responsibility:** host, user, device or unknown, plus the evidence that
  justifies it.
- **Outcome:** not submitted, confirmed complete, explicitly refused, or may
  have applied.
- **Session lifetime:** usable, retiring or retired.

**The API that reports an error is the source, not the responsible party.** A
permission-denied open supports host-access help, a parsed refusal supports
device help, an explicit no-selection supports "choose again", a wrong serial
supports user help. Silence and generic transfer errors support nothing yet:
they stay unknown until evidence narrows them, whether the cause is the
cable, the controller, the browser, the app or the firmware.

Say "No reply arrived within 5 s. The cause is not known.", not "host error"
or "the device is broken". For a write that may have applied, add "The result
is not confirmed. Nothing will be sent again automatically." A disconnect
means the connection disappeared, not that the person unplugged it. A
successful reconnect does not clear an uncertain write, and stopping is not
rollback.

**Every persistent failure leaves diagnostics.** Export the report for host
and user failures too, not only device and unknown ones: repeated permission
or claim errors are the evidence that a browser or a driver is at fault.
Guidance stays primary for an ordinary setup problem; the evidence stays
exportable.

## Show connection progress

Keep one connection state in the app and one presentation of it, separate
from the job's phase and from an uncertain write. Enter each state only on
the evidence named here:

- **unavailable:** the API, the secure context or the host capability is
  missing. Name the restriction; don't show an endless device spinner.
- **waiting for selection:** nothing granted matches. "Choose device" and
  "Check already granted" are two controls. "Not in the list?" opens a short
  checklist: mode, power/data cable, direct port, OS access, driver,
  packaging.
- **opening, claiming, probing:** say which stage, bound it, allow cancel.
- **ready:** only once the required identity and mode were observed. A grant,
  a USB descriptor, an open handle or a completed OUT transfer is none of
  them.
- **active:** one protocol operation at a time. Show the phase, measured
  bytes, elapsed wait, the last reply and what an interruption means.
- **waiting for a mode change:** the expected identity and mode are recorded.
  A reboot command or a disconnect event is not a successful transition.
- **needs access:** name what is established (site grant, OS access, claim)
  and give help for that one.
- **not responding or lost:** the honest silence or loss text, with the failed
  phase retained.
- **closing or stopped:** "stopping further commands", then stopped, no
  rollback, and any uncertainty.

Fence asynchronous results by connection generation, so a stale open or probe
cannot replace a newer selection. Announce state changes to assistive
technology. A spinner means work is happening; a prompt means a person must
act now.

## Choose and reconnect safely

1. Open the browser's device chooser only from a click. Reconnect silently
   only to attachments already granted or authorized, matched to the
   confirmed identity. Never guess between two devices.
2. No selection is a waiting result, not an accusation. It cannot tell an
   intentional cancel from an empty list, so offer both "choose again" and
   the checklist.
3. Observe arrival and removal, and rescan on a relevant event or a return to
   the page. Don't run a competing probe while an operation is active.
4. Bound automatic reconnect by elapsed time *and* attempts, and charge every
   open or probe failure to the same budget. Without that, a flapping cable
   loops forever.
5. After a mode change, ask the device which mode it is actually in. Find it
   with the protocol's own query (fastboot: `getvar is-userspace`), not from
   its USB filter: the bootloader and fastbootd share one. Unavailable mode
   evidence is a state, not a guess. Never probe project- or vendor-specific
   variables in shared code; an app that needs one gates it behind its own
   feature.

## Open conservatively

- Inspect the descriptors and the active configuration. Select a
  configuration only when the protocol needs one and it isn't active; claim
  only the intended interface.
- Never send a redundant `SET_INTERFACE` for the alternate that is already
  active, alternate 0 included. Change an alternate only when the protocol
  needs it, with no transfer pending, and record which one.
- No routine clear-halt and no reset on open. Clear a halted endpoint only
  after a reported stall (`stall` from WebUSB, `EPIPE` from a Linux
  completion), with pending work quiesced and the protocol's recovery rule
  allowing it. A timeout is not a stall, and resetting the host's toggle
  alone loses toggle synchronization.
- A device reset, a driver detach, a power-management change or a physical
  reboot is a deliberate recovery procedure: narrow it to the exact target,
  explain the interruption risk, and reestablish identity and mode afterwards.
- Host help belongs to the host that failed: site grant, usbfs permission,
  Windows interface driver binding, macOS ownership, Android attachment
  permission, another tab's claim. Name adb, fwupd or a serial terminal only
  for the protocol they can interfere with, and as a possibility unless you
  observed it.

## Bound the waits

- Use separate deadlines: a short first probe, a long allowance for device
  processing and writes, and an absolute bound on the whole operation. Say
  the units and the constants in the protocol profile.
- Real protocol progress may renew a no-progress deadline under an explicit
  rule. It never renews the absolute deadline.
- A timeout ends the app's wait, not the transfer. Retire or cancel through
  the backend's lifecycle, keep the cleanup result, and don't open a second
  command stream while old I/O may still be running.
- Send bulk data in whole protocol units and let only the final transfer be
  short. Header and metadata bytes travel inside that unit, never as short
  writes of their own: fastboot uses 1024 B (AOSP's `SparseWriteCallback`, so
  the sparse file header and chunk header are part of the 1024 B).

## Recover the same device

1. Stop issuing operations. Record the failed phase, the timing, the
   submitted and completed bytes and the last reply.
2. Mark a write that may have applied uncertain. Restoring USB access does
   not settle it.
3. Wait for the same serial through attachments already granted. A different
   PID can be expected after a mode change; a PID is not an identity.
4. Retry a read-only operation only on a fresh, synchronized session.
   "Read-only" does not make a stale protocol stream safe.
5. Before any write after a recovery, ask the same read-only queries twice
   and require identical answers. A query that answers `OKAY` and then `FAIL`,
   an unknown command, an empty variable: the device is not answering
   consistently, so power-cycle it (unplug, hold Power, then Volume-Down and
   Power) and start over. Never write to a device whose identical queries
   disagree.
6. For a write that may have applied, ask the device for the fact that
   settles it, or keep "uncertain". Never replay it because someone pressed
   Retry, and a later reboot that worked does not prove the earlier write
   failed.

## Keep useful diagnostics

Record the build and transport versions, host capabilities, identity and mode
evidence, the selected configuration, interface, alternate and endpoints, the
operation phase, deadlines, byte counts, event times, attempts, raw errors,
the classification with its evidence, cancellation, cleanup and certainty.

Keep a bounded trace that preserves failures: a ring of chunk events and
per-phase summaries, never one event per chunk or per MiB. Log no image
payloads. Offer a redacted shareable report before any write has succeeded,
keep the exact-target receipt separate, and never upload a report
automatically.

Background, source comparisons and recovery details:
[USB connection handling research](../research/usb-connection-handling.md).
The earlier web-target notes (`link-profile-critique.md`, `link-prototype/`)
described a prototype of these rules; its fake transports prove nothing about
a real device.
