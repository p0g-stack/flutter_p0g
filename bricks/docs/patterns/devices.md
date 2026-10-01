# Patterns: apps that talk to a device

For apps that reach a phone or a board over a cable (fastboot, adb, a serial
port), from the device itself, the CLI or the page. Nothing here is a brick:
these are rules for the code you write in the strategies the `strategy`
brick stamps. A link library (profiles, transports, the connect pop-up)
starts inside the first app that needs one and becomes a brick only once a
second app copies it.

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

## Rules for the link code

1. Sort errors by whose problem they are: host, user, device or unknown.
   Only unknown and device problems get the report button.
2. Keep the original error (name, message, stack, cause chain, and errors
   from cleanup). Classify it alongside, never instead.
3. Open the browser's device chooser only from a click. Reconnect silently
   only to devices already granted, matched by serial. Never guess between
   two.
4. Retry only operations that are harmless to repeat. A reconnect spends
   the same retry budget (without that, a flapping cable loops forever).
5. For a write that may have landed, ask the device, or report "uncertain".
   Never resend blindly.
6. Find a mode by asking the device, not from its USB filter: fastbootd and
   Super Fastboot share one with the bootloader.
7. After a reboot, check which mode the device actually came back in.

Background and a tested prototype of these rules: the web-target notes in the
project files (`link-profile-critique.md`, `link-prototype/`).
