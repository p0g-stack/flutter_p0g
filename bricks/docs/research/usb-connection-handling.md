# Responsive USB connection handling

Research date: 2026-11-10. Status: proposal for owner review, not an implementation or hardware qualification.

## Scope and evidence

This report covers WebUSB, native nusb/usbfs/WinUSB/IOKit, and Android USB-host access. Fastboot supplies examples, not the generic connection contract. No connected device was accessed. No repository code, existing pattern page, or upstream project was changed.

Source statements cite the table below. **[INFERENCE]** marks recommendations, deductions, proposed messages, and behavior not established by the inspected source. A marker on a table row applies to the whole row. A marker introducing a numbered list applies to every item in that list. Source inspection establishes what that revision implements, not that every deployed browser, kernel, or device behaves identically.

The starting point is [the existing pattern](../patterns/devices.md), especially its host/user/device/unknown classification, target pinning, waiting availability, and uncertainty rules. The four archived web-target research/distillation files and both `link-prototype/lib/*.dart` files were read from `library-docs-2026-11-06.zip` with `unzip -p`. Their prototype uses fake transports. Its passing tests are historical claims in those notes, not checks performed for this report.

Owner-supplied case: a OnePlus 13R stopped answering browser and host-fastboot commands after a WebUSB open sent `SET_INTERFACE` for alternate 0. Change `03e22f9` removed that request, but its effect on the phone remains unverified. The observed timeout was displayed with `blame: host`. **[INFERENCE]** A data-toggle mismatch is a plausible mechanism, not a proven diagnosis of this incident. Neither a timeout nor simultaneous failure in two host programs proves which component caused the silence.

## Key recommendations

**[INFERENCE]** Keep the architecture in the existing pattern: app-owned link code, strategy availability, exact-target confirmation, and an app result for uncertain writes. Do not introduce USB types into the generic strategy core or Squadron.

**[INFERENCE]** Change the classification rule, not merely the timeout text. The API that reports an error is its **source**. It is not necessarily the component responsible. An unexplained timeout, link disappearance, or generic transfer failure is `unknown` until evidence narrows it.

**[INFERENCE]** Model connection state separately from operation outcome. A device can reconnect successfully while the previous write remains uncertain. Display the last confirmed phase, elapsed time, expected mode, and safe next action.

**[INFERENCE]** Open conservatively: discover descriptors, select a configuration only when necessary, claim the intended interface, and change an alternate only when actually required. Do not send redundant `SET_INTERFACE(0)`, clear every endpoint, reset the device, or disable host power management as routine connection preparation.

**[INFERENCE]** Copy established behavior selectively: ESP's no-selection checklist, Calyx's same-serial reconnect, Tango's disconnect-race handling, and protocol-specific timeouts. Do not copy fastboot.js's opportunistic reset or identity-unpinned reconnect.

**[INFERENCE]** Offer a local diagnostic report for every persistent failure, including host problems. Classification should change the prominence and guidance, not remove the evidence needed to correct a misclassification.

## 1. Sources read

Code links below are pinned to the revisions inspected. Official documentation/specification pages are live documents accessed on the research date. Where upstream `main` differs from a released dependency, this report names that distinction rather than asserting dependency parity.

| ID | Project | What was read | Primary source |
| --- | --- | --- | --- |
| S1 | AOSP fastboot | Linux descriptor discovery, sysfs serial, interface claim, URB submission, read retries, timeout, reset, disconnect wait | [`usb_linux.cpp`, `a3b721a`](https://github.com/aosp-mirror/platform_system_core/blob/a3b721a32242006b59cb12bd62c9133632af3a2d/fastboot/usb_linux.cpp) |
| S2 | AOSP fastboot | IOKit interface open, clear-stall-on-open, blocking/timed reads and writes, disabled ZLP code, reset limitation | [`usb_osx.cpp`, same revision](https://github.com/aosp-mirror/platform_system_core/blob/a3b721a32242006b59cb12bd62c9133632af3a2d/fastboot/usb_osx.cpp) |
| S3 | AOSP fastboot | AdbWinApi open, 5-second writes, unbounded reads, invalid-handle cleanup, unsupported reset | [`usb_windows.cpp`, same revision](https://github.com/aosp-mirror/platform_system_core/blob/a3b721a32242006b59cb12bd62c9133632af3a2d/fastboot/usb_windows.cpp) |
| S4 | AOSP adb | Linux/macOS/Windows legacy host backends: ZLP, claims, timeout and kick behavior. Current libusb connection error handling | [`client/`, `1cf2f01`](https://android.googlesource.com/platform/packages/modules/adb/+/1cf2f017d312f73b3dc53bda85ef2610e35a80e9/client/): [`usb_linux.cpp`](https://android.googlesource.com/platform/packages/modules/adb/+/1cf2f017d312f73b3dc53bda85ef2610e35a80e9/client/usb_linux.cpp), [`usb_osx.cpp`](https://android.googlesource.com/platform/packages/modules/adb/+/1cf2f017d312f73b3dc53bda85ef2610e35a80e9/client/usb_osx.cpp), [`usb_windows.cpp`](https://android.googlesource.com/platform/packages/modules/adb/+/1cf2f017d312f73b3dc53bda85ef2610e35a80e9/client/usb_windows.cpp), [`usb_libusb.cpp`](https://android.googlesource.com/platform/packages/modules/adb/+/1cf2f017d312f73b3dc53bda85ef2610e35a80e9/client/usb_libusb.cpp) |
| S5 | Google Android Flash Tool / Pixel | Official workflow, adb interference, first fastboot permission, unbootable-device entry, transfer troubleshooting. Public tool landing page | [Official guide](https://source.android.com/docs/setup/test/flash), [tool](https://flash.android.com/) |
| S6 | GrapheneOS | Installer requirements, cables, hubs, Linux udev/fwupd, Windows Pixel driver qualifications, Android reconnect. Installer JS connection/reconnect UI and wake lock | [Guide](https://grapheneos.org/install/web), [`web-install.js`, `11e4e9e`](https://github.com/GrapheneOS/grapheneos.org/blob/11e4e9e0f1d061c6701b73de8fe5b408291e6e01/static/js/web-install.js) |
| S7 | CalyxOS installer | Connect/install components, client creation, reconnect callback, error/Start Over UI, dependency version | [`calyxos-webinstall`, `d106e13`](https://github.com/CalyxOS/calyxos-webinstall/tree/d106e13fbff476a26a045fdc42f551ffff074650/src), [`InstallStep.vue`](https://github.com/CalyxOS/calyxos-webinstall/blob/d106e13fbff476a26a045fdc42f551ffff074650/src/components/InstallStep.vue), [`package.json`](https://github.com/CalyxOS/calyxos-webinstall/blob/d106e13fbff476a26a045fdc42f551ffff074650/package.json) |
| S8 | CalyxOS fastboot.ts | Same-serial reconnect, escalating delays, event wait, chooser callback, claim/configuration sequence | [`device.ts`, `fd284c5`](https://github.com/CalyxOS/fastboot.ts/blob/fd284c55af95253acab5ef9a16fd82ecb846f974/src/device.ts), [`client.ts`](https://github.com/CalyxOS/fastboot.ts/blob/fd284c55af95253acab5ef9a16fd82ecb846f974/src/client.ts) |
| S9 | ya-webadb / Tango | `DeviceBusyError`, claim/configuration/alternate checks, ZLP, disconnect subscription, 100-ms Windows race workaround | [`device.ts`, `d22e9dc`](https://github.com/yume-chan/ya-webadb/blob/d22e9dc3c9d53178f4cf88cd757253f7ce780b10/libraries/adb-daemon-webusb/src/device.ts), [`error.ts`](https://github.com/yume-chan/ya-webadb/blob/d22e9dc3c9d53178f4cf88cd757253f7ce780b10/libraries/adb-daemon-webusb/src/error.ts) |
| S10 | fastboot.js | Open/reset/configure/claim, getvar timeout, event-driven reconnect, Android callback | [`fastboot.ts`, `5b61333`](https://github.com/kdrag0n/fastboot.js/blob/5b613332aa9d66cca5bebb49f147cd084a76c464/src/fastboot.ts) |
| S11 | esptool-js | Default and size-specific deadlines, decimal-MB calculation, bounded sync attempts, write-block retry loops | [`esploader.ts`, `d5b779b`](https://github.com/espressif/esptool-js/blob/d5b779b0314bdec367125f4c7e3c6d2206b14311/src/esploader.ts) |
| S12 | ESP Web Tools | No-port-selected checklist, chooser cancellation, open errors, dialog lifetime | [`no-port-picked-dialog.ts`, `b027c3c`](https://github.com/esphome/esp-web-tools/blob/b027c3c939dd660e1f7abb7efd6404839453e759/src/no-port-picked/no-port-picked-dialog.ts), [`connect.ts`](https://github.com/esphome/esp-web-tools/blob/b027c3c939dd660e1f7abb7efd6404839453e759/src/connect.ts) |
| S13 | WebUSB specification | Grant scope, transient activation, exclusive claims, error names, transfer statuses, alternate selection, clear halt, reset | [Specification](https://usb.spec.whatwg.org/), especially [USBDevice methods](https://usb.spec.whatwg.org/#usbdevice) |
| S14 | Chromium | Fatal transfer status mapping, generic claim failure, access-denied open, pending request rejection on disconnect, zero timeout passed to transfer IPC | [`usb_device.cc`, `72364fe`](https://github.com/chromium/chromium/blob/72364fea0d191a90cca966f8531e35781ccb0571/third_party/blink/renderer/modules/webusb/usb_device.cc) |
| S15 | WebUSB / Chromium issues | Windows transfer error before disconnect event, platform ordering explanation, later implementation observation. Windows claim failure caused by registry GUID handling | [WebUSB issue 219](https://github.com/WICG/webusb/issues/219), [Chromium issue 40933654](https://issues.chromium.org/issues/40933654) |
| S16 | Chrome | Secure context, chooser gesture, grants, udev, chunking, device log and USB internals | [Access USB Devices on the Web](https://developer.chrome.com/docs/capabilities/usb) |
| S17 | nusb API | Platform access requirements, `from_fd`, exclusive claims, endpoint cancellation, clear halt, reset invalidation | [nusb 0.2.9](https://docs.rs/nusb/0.2.9/nusb/), [Device](https://docs.rs/nusb/0.2.9/nusb/struct.Device.html), [Endpoint](https://docs.rs/nusb/0.2.9/nusb/struct.Endpoint.html), [TransferError](https://docs.rs/nusb/0.2.9/nusb/transfer/enum.TransferError.html) |
| S18 | nusb source | Native raw error translation, error kinds, endpoint clear-halt contract and reset platform limitations | [`c46ccd0`](https://github.com/kevinmehall/nusb/tree/c46ccd0183844b6299b5354a4a13d6837d5fcf63/src): [`linux_usbfs/mod.rs`](https://github.com/kevinmehall/nusb/blob/c46ccd0183844b6299b5354a4a13d6837d5fcf63/src/platform/linux_usbfs/mod.rs), [`windows_winusb/transfer.rs`](https://github.com/kevinmehall/nusb/blob/c46ccd0183844b6299b5354a4a13d6837d5fcf63/src/platform/windows_winusb/transfer.rs), [`macos_iokit/mod.rs`](https://github.com/kevinmehall/nusb/blob/c46ccd0183844b6299b5354a4a13d6837d5fcf63/src/platform/macos_iokit/mod.rs), [`error.rs`](https://github.com/kevinmehall/nusb/blob/c46ccd0183844b6299b5354a4a13d6837d5fcf63/src/error.rs), [`device.rs`](https://github.com/kevinmehall/nusb/blob/c46ccd0183844b6299b5354a4a13d6837d5fcf63/src/device.rs) |
| S19 | libusb | Claim is logical/no bus request, reconfiguration resets, clear-halt preconditions, reset and rediscovery | [Device handling documentation](https://libusb.sourceforge.io/api-1.0/group__libusb__dev.html) |
| S20 | Linux USB core | URB submission/completion errno meanings, partial transfer on failure, ambiguous controller errors | [USB error codes](https://docs.kernel.org/driver-api/usb/error-codes.html) |
| S21 | Linux USB core | usbfs claim/clear-halt/reset-endpoint, alternate-setting caveats, xHCI behavior | [Host-side API](https://docs.kernel.org/driver-api/usb/usb.html), [usbfs nodes](https://docs.kernel.org/driver-api/usb/usb.html#the-usb-character-device-nodes) |
| S22 | Linux power / quirks | Open usbfs prevents idle autosuspend, autoresume, per-device controls, reset-resume/no-set-interface/no-reset/no-LPM quirks | [Power management](https://docs.kernel.org/driver-api/usb/power-management.html), [kernel parameters, `usbcore.quirks`](https://docs.kernel.org/admin-guide/kernel-parameters.html) |
| S23 | Microsoft / Android drivers | WinUSB interface binding and GUIDs, timeout/ZLP/stall/resume policies, pipe reset semantics, OEM driver installation | [WinUSB installation](https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/winusb-installation), [pipe policies](https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/winusb-functions-for-pipe-policy-modification), [ResetPipe](https://learn.microsoft.com/en-us/windows/win32/api/winusb/nf-winusb-winusb_resetpipe), [OEM drivers](https://developer.android.com/studio/run/oem-usb) |
| S24 | Android USB host | Host role/power, enumeration, per-device permission result, detach cleanup | [Official USB host guide](https://developer.android.com/develop/connectivity/usb/host) |
| S25 | WebDFU, non-Android | Conditional configuration, alternate behavior, protocol status/poll timeout, detach/manifestation/reset, disconnect/error UI | [`dfu.js`, `56d5d1d`](https://github.com/devanlai/webdfu/blob/56d5d1d961587aca381a1ce97acbc8ff5d807acd/dfu-util/dfu.js), [`dfu-util.js`](https://github.com/devanlai/webdfu/blob/56d5d1d961587aca381a1ce97acbc8ff5d807acd/dfu-util/dfu-util.js) |
| S26 | Espressif, non-Android | Bootloader silence, serial permissions, ModemManager/terminal conflicts, power and cable diagnosis | [Official troubleshooting](https://docs.espressif.com/projects/esptool/en/latest/esp32c6/troubleshooting.html) |
| S27 | micro:bit, non-Android | Browser compatibility, complete power-cycle guidance, Snap raw-usb confinement, udev, Windows driver conflicts | [Official WebUSB troubleshooting](https://support.microbit.org/support/solutions/articles/19000105428-webusb-troubleshooting) |

### Local sources

These are working-tree observations, not upstream or hardware verification. Files were being edited by other work, so symbol names are more durable than line numbers.

- L1: [`webusb.rs`](../../../flasher-web/rust/crates/fastboot-link/src/webusb.rs), notably `open`, `devices`, `bounded`, `BulkTransport`, and the claim-only comment. Repository-relative path from the bricks checkout is `../flasher-web/rust/crates/fastboot-link/src/webusb.rs`.
- L2: `flasher-web/rust/crates/fastboot-link/src/native.rs`: `open`, `SessionGuard`, `BulkTransport`.
- L3: `flasher-web/rust/crates/fastboot-link/src/session.rs`: `Session::command`, `command_inner`, `write_download`, `end_download`, `send`, `read_response`, `retire`.
- L4: `flasher-web/rust/crates/fastboot-link/src/error.rs`: `LinkError::from_transport`, `device`, `protocol`, `session_retired`.
- L5: `flasher-web/packages/device_link/lib/device_link.dart`: `LinkFailure`, `FastbootTransport`, `FastbootSession`.
- L6: `flasher-web/app/lib/flash/device_sheet.dart`: `_loadGranted`, `_choose`, `_guidance`, sheet rendering.
- L7: `flasher-web/app/lib/flash/flash_controller.dart`: `FlashPhase`, `_onEvent`, retry guidance, `_onError`, `_onDone`, `downloadReceipt`, `saveLog`.
- L8: `flasher-web/app/lib/flash/flash_page.dart`: failure and receipt cards. `flash_target.dart`: `describeLinkFailure`.
- L9: `bricks/docs/patterns/devices.md`, plus the archived `web-target/{webusb-wasm-research,link-distill-web,link-distill-bricks,link-profile-critique}.md` and `link-prototype/lib/{link,fastboot}.dart`.

## 2. What established tools actually do

| Tool | Silence / timeout | Disconnect / mode change | Busy / permission | Transferable lesson |
| --- | --- | --- | --- | --- |
| AOSP fastboot Linux [S1] | Read timeout comes from `usb_open(timeout_ms)`, default constructor value 0. A failed read has at most two retries with 100-ms sleeps. Async write reaping is not a responsive UI deadline. `ENOMEM` at URB submission reduces chunk size, down to 16 KiB. | `WaitForDisconnect` checks for device-node removal for up to three seconds. `Reset` explicitly issues `USBDEVFS_RESET`. | Open tries read-only access for a useful permission diagnostic. Successful discovery claims the matching interface. | **[INFERENCE]** Preserve submission-vs-completion evidence. An allocation failure before submission differs from an uncertain completed/partial write. Do not copy read retries as command replay. |
| AOSP fastboot macOS [S2] | Zero timeout selects blocking `ReadPipe`/`WritePipe`. Nonzero uses timed variants. Writes are split at 1 MiB. | `Reset` reports unsupported. | Opens the IOKit interface. Clears both bulk endpoint stalls on open, with a comment about bad initial Mac endpoint state. | **[INFERENCE]** There is an established platform-specific clear-stall precedent, not a universal requirement. |
| AOSP fastboot Windows [S3] | 5-second endpoint writes, read timeout 0, chunks up to 1 MiB. The `usb_open` timeout argument is unused. | `ERROR_INVALID_HANDLE` triggers handle cleanup. Reset is unsupported in this backend. | Uses AdbWinApi interface and endpoint open calls, preserving `GetLastError` in errno. | **[INFERENCE]** AOSP's transport is not a host-neutral timeout policy to copy verbatim. |
| AOSP adb [S4] | Legacy Linux writes wait up to five seconds. Its read loop continues on timeout while the handle exists. Windows uses 5-second writes and timeout-0 reads. These serve a long-lived protocol connection. | Legacy backends kick dead connections. Current `LibUsbConnection::OnError` also removes hotplug bookkeeping so Windows sleep/resume can rediscover an apparently unchanged address. | Linux claims its interface. macOS maps exclusive access, stalled pipe, and timeout distinctly. | ADB sends ZLP when the write length is a maximum-packet multiple. **[INFERENCE]** Do not transplant this into fastboot's length-counted data phase. |
| Google Android Flash Tool / Pixel [S5] | Official help identifies high-throughput trouble with ports/hubs and recommends direct ports, no extensions/adapters, and trying another port/type. No transport source/deadline was verified. | First use may need a second device selection after entering fastboot. Unbootable devices can enter fastboot with hardware keys. | Explicitly says stop an existing adb server with `adb kill-server`. Separates browser ADB access from the phone's USB-debugging authorization. | **[INFERENCE]** Say which authorization or mode is needed. Do not present one undifferentiated USB permission error. |
| GrapheneOS / Pixel [S6] | Guide prioritizes cable/hub/VM problems. Installer shows connection and action progress. | JS exposes a reconnect button and hides the progress bar while waiting. Guide says Android needs permission after each reboot and warns about desktop-mode detection. | Linux udev packages and fwupd interference get separate sections. Driver advice is qualified by Windows and Pixel generation. | **[INFERENCE]** Keep mode-specific setup help and an explicit reconnect affordance, without promising every Windows phone needs a new driver. |
| CalyxOS [S7, S8] | `retryReconnect` uses immediate, 3-second, then 30-second waits. Installer displays status/logs and exposes error plus Start Over. | Stack searches grants by exact serial. Ordinary reconnect can then await a connect event. Fastboot-mode reconnect can call a user-action callback for a chooser. | Open/claim errors propagate. The installer callback presents a Reconnect button rather than calling a chooser from background work. | **[INFERENCE]** Copy bounded reconnect and same-serial matching. Do not copy an unbounded final event wait or Start Over as the sole recovery action. The inspected stack revision is not proof that package `0.0.18-rc.5` is identical. |
| Tango / ya-webadb [S9] | Read stream awaits protocol packets. On `NetworkError`, waits 100 ms and checks whether disconnect cleanup ran. | Subscribes to device disconnect. `NotFoundError` ends the stream. | Claim `NetworkError` becomes `DeviceBusyError` with the original cause. Configuration and alternate are changed only if different. | **[INFERENCE]** Copy the race workaround and cause preservation, but weaken “another program definitely owns it” to a possibility for generic claim errors. |
| fastboot.js [S10] | `getVariable` has a 10-second timeout. This is not a blanket deadline on all transfers/commands. | Uses connect/disconnect events. Android reconnect invokes a callback. Its `waitForConnect` explicitly accepts the next device regardless of previous identity. | Open opportunistically calls `reset`, ignores reset failure, selects configuration 1, and claims interface 0. It does not explicitly select an alternate. | **[INFERENCE]** Adopt neither opportunistic reset nor unpinned identity. The archived statement that fastboot.js has no timeouts is too broad for this revision. |
| esptool-js [S11] | Default 3 seconds. Erase-region 30,000 ms/MB, erase/write 40,000 ms/MB, MD5 8,000 ms/MB, chip erase 120 seconds. Connect uses bounded reset/sync attempts. | Connection logic can reopen after chip detection fails. Reset strategies are chip/transport-specific. | Higher-level serial access failures are not a generic USB permissions diagnosis. | Its function named `timeoutPerMb` divides bytes by **1,000,000**, not 1,048,576, and floors at 3 seconds. It also retries write blocks three times. **[INFERENCE]** Copy size/phase-aware deadlines, not ESP constants or write retry semantics. |
| ESP Web Tools [S12] | Installation uses esptool. The connection wrapper itself reports port-open errors. | Port closes when the install dialog closes. | `requestPort` `NotFoundError` opens a “No port selected” checklist: power, data cable, Linux serial group, chip drivers, Try Again. Other chooser/open errors are shown directly. | **[INFERENCE]** Reuse checklist structure, not its `dialout` instructions for raw usbfs. |
| WebDFU [S25] | Polls DFU `GETSTATUS` and waits the device's `pollTimeout`. The loop has no independent overall deadline in the inspected implementation. | Waits for detach/manifestation disconnect, distinguishes manifestation states, and resets after manifestation. UI disables transfers and says “Device disconnected” on unexpected removal. | Chooser/open errors reach status text. Clears **DFU protocol status** in `dfuERROR`, which is not endpoint `clearHalt`. | **[INFERENCE]** Respect protocol busy/status timing and expected-disconnect phases, with an app-owned overall bound. DFU alternate settings select functionality/targets, so “never select an alternate” is not generic USB guidance. |
| micro:bit and Espressif support [S26, S27] | Advise power/cable/boot-mode checks. micro:bit describes removing all power when ordinary reconnect fails. | Espressif notes firmware can disable USB and disappear. | Explain serial terminal/ModemManager conflicts, Snap confinement, udev and driver conflicts. | **[INFERENCE]** Offer a device-specific physical recovery procedure only after explaining interruption risk. Do not treat ModemManager as a proven owner of arbitrary fastboot interfaces. |

### Corrections to the archived research

- fastboot.js currently has a getvar deadline and an opportunistic reset [S10]. “No timeouts” and “claim only” need those qualifications.
- Tango's `DeviceBusyError` is a useful UX convention, but claim `NetworkError` also has other causes [S9, S13–S15].
- Calyx reconnect in the inspected stack uses the serial, not a VID/PID fallback [S8].
- The WebUSB issue records the Windows ordering problem, but current Chromium has explicit `DISCONNECT` and connection-error `NotFoundError` paths [S14, S15]. **[INFERENCE]** Support both forms. Do not assert that every current Windows disconnect first raises `NetworkError`.
- Linux documents that an open usbfs file prevents idle autosuspend [S22]. **[INFERENCE]** “Disable autosuspend” is not a justified first response to a silent active connection.
- The prototype treats all command `NetworkError`s as disconnects and all timeouts as host blame [L9]. **[INFERENCE]** These mappings need replacement before reuse.

## 3. Responsibility layers and observable signals

### 3.1 Layer boundaries

| Layer | Evidence it can supply | What that evidence does not establish | Guidance consequence |
| --- | --- | --- | --- |
| Cable, port, hub, host role/power | Enumeration/removal, speed and topology when exposed. Google/GrapheneOS/Espressif document cable, hub and power problems [S5, S6, S26]. | A removal does not distinguish unplugging, power loss, firmware reboot, or controller failure [S15, S20]. | **[INFERENCE]** Say “The connection was lost,” not “You unplugged it.” Offer direct-port/data-cable checks only when safe to interrupt. |
| Host controller / kernel | Native transfer status, errno, kernel diagnostics, suspend state. Linux documents `EPROTO`, `EILSEQ`, `ETIME` ambiguity, and `EHOSTUNREACH` for suspended URB rejection [S20–S22]. | CRC/no-response/controller errors need not identify the defective component. A Linux errno name is not a causal verdict [S20]. | **[INFERENCE]** Put detailed kernel/driver checks behind diagnostics. Do not silently toggle power, unbind xHCI, reset a hub, or change global quirks. |
| OS access and driver binding | Permission-denied open, native busy claim, Windows interface driver/GUID, IOKit exclusive access [S17–S19, S23, S4]. | A browser grant does not grant OS node access or bind WinUSB [S16, S17]. Generic browser claim failure does not identify the owner [S15]. | **[INFERENCE]** Separate “site permission,” “OS denied access,” and “could not claim interface.” Name likely programs as conditional help, not evidence. |
| Browser / context / tabs | API availability, secure context, transient activation, policy restriction, granted-device list, DOMException, transfer status, connect/disconnect [S13, S14, S16]. | Empty grants are not proof that no hardware is connected. A grant is not a successful claim or responsive protocol [S13, S19]. | **[INFERENCE]** Have separate Check granted and Choose controls. Distinguish “not granted here” from “not enumerated by the OS.” |
| App transport and ownership | Own lock owner/busy result, exact submission phase, submitted/completed byte counts, cancellation and cleanup result [L1–L5, S17]. | Completion of USB OUT does not prove the device committed a higher-level operation. Failure can follow partial completion [S20]. | **[INFERENCE]** Serialize protocol access. Carry certainty independently from state and source. Record application lock evidence separately from generic OS busy. |
| Device protocol and firmware | Parsed reply, protocol status/error, requested polling delay, authenticated/queried identity, observed mode [S4, S10, S25, L3]. | No reply is not a reply saying “device broken.” A FAIL identifies a response, not necessarily a firmware bug or a no-side-effects guarantee. | **[INFERENCE]** Use protocol evidence for mode and refusal. Treat silence as unknown. Protocol adapters decide whether a refusal proves a write was not applied. |

### 3.2 Per-host signals and information loss

Native nusb source mappings below are from S18. The separately inspected released API docs are 0.2.9 [S17]. **[INFERENCE]** An implementation must check its actual pinned version/fork before relying on raw-code retention or newer variants.

| Host / API | Discovery and access | Transfer evidence | What is distinguishable | What remains ambiguous |
| --- | --- | --- | --- | --- |
| WebUSB, any OS | `navigator.usb`/secure context/policy, `getDevices`, chooser outcome, open and claim failures [S13, S16]. Chromium open access denied produces `SecurityError`. Protected claim is `SecurityError`; generic claim failure is `NetworkError` [S14]. | Result `ok`, `stall`, `babble`, and data/bytesWritten. Chromium maps transfer error to `NetworkError`, permission denial to `SecurityError`, timeout to `TimeoutError`, cancellation to `AbortError`, disconnect to `NotFoundError` [S13, S14]. | Chooser `NotFoundError` means no selection returned. Transfer `NotFoundError` can mean disconnection. The **stage** distinguishes them. Own Web Lock refusal can prove another cooperating context holds the app lock [L1]. | No standard raw errno, xHCI status, runtime power state, kernel owner PID, or Windows driver identity is supplied by this API [S13]. **[INFERENCE]** Do not label a generic `SecurityError` “user denied” or every `NetworkError` “busy/disconnected.” |
| Linux usbfs / native nusb | nusb requires write access to `/dev/bus/usb/BBB/DDD`. Open errors have native causes. `ErrorKind` separates permission, busy, disconnected, not-found, unsupported [S17, S18]. usbfs interface claims are exclusive [S19, S21]. | Mapping: `ENODEV`/`ESHUTDOWN` → Disconnected, `EPIPE` → Stall, `ENOENT`/`ECONNRESET`/`ETIMEDOUT` → Cancelled, `EPROTO`/`EILSEQ`/`EOVERFLOW`/`ECOMM`/`ETIME` → Fault, `EINVAL` → InvalidArgument [S18]. Kernel actual length can be positive on error [S20]. | A permission-denied **open** differs from busy **claim**. Explicit `EPIPE` completion establishes a halted endpoint. A local deadline establishes elapsed wait, not device response [S18–S21]. | `Cancelled` merges cancellation and timeout. `Fault` merges several kernel statuses. A raw submission `EPIPE` can instead mean wrong pipe type [S20]. **[INFERENCE]** Preserve raw code and stage before normalization when available. Kernel logs/topology are optional native diagnostics, not browser facts. |
| Windows / WinUSB / nusb | Correct interface must bind WinUSB. Composite interfaces can have separate drivers. nusb exposes permission/busy-style errors and OS codes [S17, S18, S23]. | nusb: `ERROR_GEN_FAILURE` → Stall. `ERROR_REQUEST_ABORTED`/`ERROR_TIMEOUT`/`ERROR_SEM_TIMEOUT`/`ERROR_OPERATION_ABORTED` → Cancelled. `ERROR_FILE_NOT_FOUND`/`ERROR_DEVICE_NOT_CONNECTED`/`ERROR_NO_SUCH_DEVICE` → Disconnected. Other values → Unknown(raw) [S18]. | Native error code and endpoint stage are available. WinUSB pipe timeout is configurable. Default bulk timeout is 0, and ordinary queued time is excluded from its timer [S23]. | The normalized category loses timeout-vs-cancel detail. Browser claim errors can also arise from GUID/driver enumeration defects [S15]. **[INFERENCE]** “WinUSB installed” is not proof the particular browser can claim that interface. |
| macOS / IOKit / nusb | nusb uses IOKit. Kernel-driver-owned devices are unavailable. Vendor-class devices can need configuration selection [S17]. ADB names `kIOReturnExclusiveAccess` as another exclusive opener [S4]. | nusb: Success/Underrun → success. NoDevice → Disconnected. Aborted/USBTransactionTimeout → Cancelled. USBPipeStalled → Stall. BadArgument → InvalidArgument. Others → Unknown(raw) [S18]. | Native IOReturn and stage can separate exclusive access, pipe stall, transaction timeout, and missing device [S4, S18]. | Not every error has the same code across macOS/backend versions. AOSP's older backend does clear both pipes on open [S2]. **[INFERENCE]** Do not infer that nusb needs the same workaround, or that macOS has Linux-style udev setup. |
| Android app USB-host API → nusb fd | `UsbManager` enumerates devices and returns explicit `EXTRA_PERMISSION_GRANTED`; permission lasts until disconnect. Detach intent triggers cleanup. nusb accepts an owned fd derived from `UsbDeviceConnection.getFileDescriptor` [S24, S17, S18]. | Once using usbfs, kernel/nusb completion categories are those of the Linux backend [S18]. | Framework permission refusal is distinguishable from a later usbfs transfer failure. The official API identifies host-role support and connected interfaces [S24]. | Permission for a previous attachment does not authorize a new attachment [S24]. **[INFERENCE]** Do not conflate Android's USB permission dialog with adb's RSA authorization, or browser origin grants. |
| Android root process / direct usbfs | nusb's fd route and Linux backend exist [S18]. **[INFERENCE]** Direct node access additionally depends on the actual root service's device-node and security-policy access. Do not assume “root” proves all required access. | Same usbfs errno/completion limitations [S18, S20]. **[INFERENCE]** Root may permit extra diagnostics, but must not make reset/detach policy less conservative. | **[INFERENCE]** Log root-service acquisition separately from USB node open and interface claim. Stream state through the service, not browser chooser calls. | **[INFERENCE]** No qualification of this app's Android root transport occurred here. udev instructions do not apply to Android. Host role, power and attachment lifetime need Android-specific guidance. |

**[INFERENCE]** The cross-platform abstraction should preserve meaning, not rename every native error to a browser DOMException. A small semantic failure code can sit beside native kind/code, browser name, stage, and raw cause. Do not make applications parse rendered English or errno strings to recover that structure.

## 4. Failure taxonomy: source, responsibility, certainty

The existing pattern defines host/user/device/unknown [L9]. **[INFERENCE]** Keep these labels for compatibility with the pattern's vocabulary, but document them as evidence-based responsibility categories, not a judgment about the person.

**[INFERENCE]** Keep four separate axes in the app's error/result:

1. `source`: browser, OS/usbfs/WinUSB/IOKit, app transport, protocol, or caller.
2. `responsibility`: host, user, device, or unknown, plus the evidence/rule that justifies it.
3. `outcome`: not submitted, completed according to protocol, explicitly refused, or may have applied.
4. `session`: usable, retiring, or retired. Neither blame nor outcome decides lifetime implicitly.

| Failure / evidence | Proposed category and wording | Safe action |
| --- | --- | --- |
| API absent, insecure origin, known Permissions Policy restriction [S13, S16] | **[INFERENCE]** `host`: “This page cannot use USB in this browser/context.” Name the detected restriction. | **[INFERENCE]** Open supported context/help. Do not display an endless device spinner. |
| No device selected from chooser [S13] | **[INFERENCE]** `user` as an actionable no-selection result, not an error accusation: “No device was selected.” | **[INFERENCE]** Offer Choose again and an optional “Not in the list?” checklist. Cannot distinguish intentional cancellation from an empty list through `NotFoundError` alone. |
| Explicit OS access-denied open [S14, S17] | **[INFERENCE]** `host`: “The operating system refused USB access.” | **[INFERENCE]** OS-specific udev/driver/confinement help. Do not say the phone rejected a command. |
| Own cooperating lock denied [L1] / native busy claim [S18, S19] | **[INFERENCE]** `host`: “This interface is already in use.” Identify the app's own other session when known. | **[INFERENCE]** Close another tab/program, then Check connection. Never kill it automatically. |
| Generic browser claim `NetworkError` [S14, S15] | **[INFERENCE]** `unknown`, or a host-access symptom with cause explicitly unresolved: “Could not claim the USB interface. Another tab, program, or driver may be using it.” | **[INFERENCE]** Conditional adb/fwupd help for Android fastboot/adb. Driver/setup help remains available. Report retains the original error. |
| Wrong serial, ambiguous identity, known incompatible mode [L5, L9] | **[INFERENCE]** `user` only when the chosen target/mode is positively established: “This is not the device/mode confirmed for this operation.” | **[INFERENCE]** Stop before writing. Choose the intended target, or prepare and confirm a new plan. No VID/PID fallback. |
| Device returned a parsed protocol refusal [L3, S10, S25] | **[INFERENCE]** `device` describes the origin of the refusal, not necessarily a defect. “The device refused: …” A known locked-state refusal can instead receive app-specific user guidance. | **[INFERENCE]** Keep the original reply. Protocol-specific policy decides session reuse and side-effect certainty. A generic FAIL is not a universal rollback guarantee. |
| Unexpected or malformed response | **[INFERENCE]** `unknown` until protocol evidence excludes transport framing, stale data, or app parser bugs. “The reply did not match the expected protocol.” | **[INFERENCE]** Retire a desynchronized session. Preserve bounded response bytes and parser/version details. |
| Deadline expired, no response [S13, S20] | **[INFERENCE]** `unknown`: “No reply arrived within 5 seconds. The cause is not known.” During writes: “The device may still be working. The result is not confirmed.” | **[INFERENCE]** Stop new commands, retire/cancel safely, retain uncertainty. Do not immediately advise unplugging during an unconfirmed write. |
| Device disappeared / `Disconnected` / verified disconnect event [S14, S18, S20] | **[INFERENCE]** Event known, cause usually `unknown`: “The USB connection was lost.” If expected during a transition, show waiting rather than failure. | **[INFERENCE]** Wait for the same identity within the transition budget. Reprobe mode before resuming any permitted operation. |
| Proven application precondition/serialization/parser defect | **[INFERENCE]** `unknown` in this four-way vocabulary, with `source: caller/app`. “The app could not complete this operation. Download the report.” | **[INFERENCE]** No hardware-reset advice to conceal an app defect. |

### Honest silence messages

**[INFERENCE]** Use these as templates, not claims of a universal five-second timeout:

- Initial probe: “USB access opened, but no protocol reply arrived within 5 seconds. The cause is not known.” Actions: Check connection, Connection help, Download report, Cancel.
- A live long command: “The device is processing ‘write image’. No reply for 25 seconds. Waiting up to 180 seconds.” Do not invent a percentage from silence.
- Deadline during a write: “The device did not confirm completion. It may still be writing. No command will be sent again automatically.” Actions: Save report, Stop further commands, app-specific recovery instructions.
- Unexpected removal: “Connection lost while sending image data. This step may be incomplete.” A subsequent successful reconnect does not clear this outcome.

**[INFERENCE]** The report button must remain available for host and user-classified failures. Repeated permission or claim problems can expose browser/driver defects. This directly disagrees with existing rule 1: “Only unknown and device problems get the report button.” Keep guidance primary for ordinary setup failures, but do not suppress evidence export.

## 5. Connection state model and UI contract

**[INFERENCE]** Use one app-owned connection controller and one presentation of its state. This is a model for existing app code, not a proposed new shared framework. Keep connection state distinct from the flashing job's `idle/preparing/running/uncertain` phases.

| Proposed state | Evidence required to enter | Message / user action |
| --- | --- | --- |
| **[INFERENCE]** Unavailable | Detected missing API/context/host capability, not merely no device | Name the detected restriction. Offer host help or a different supported strategy. |
| **[INFERENCE]** Awaiting selection / attachment | No selected identity or no matching granted attachment | “Connect the device in [mode].” Choose device and Check granted are distinct. “Not in the list?” opens a short checklist. |
| **[INFERENCE]** Choosing | An explicit click invoked the chooser | “Select the device in the browser dialog.” Cancel returns to waiting without losing the user's plan inputs. |
| **[INFERENCE]** Opening | Selected identity exists. Open/configuration/claim is in progress | Show current stage: “Opening USB access” or “Claiming interface.” Give a bounded deadline and cancel action. No protocol-ready claim yet. |
| **[INFERENCE]** Probing | Claim succeeded. A bounded, known-safe protocol query is pending | “USB opened. Checking device mode…” Show elapsed time. Do not run vendor probes or multiple simultaneous commands. |
| **[INFERENCE]** Ready | Identity and required mode/capabilities were positively observed | Show identity, observed mode, and readiness for the named action. Any target/plan mismatch disables writes. |
| **[INFERENCE]** Active | A protocol operation is in progress on the single session | Show phase, bytes/progress when real, last reply, elapsed wait, and interruption semantics. Disable second open/competing probes. |
| **[INFERENCE]** Transitioning / awaiting return | The app intentionally requested a mode change, records expected identity/mode, and closed or lost the old session | “Waiting for [same device] in [mode].” Explain that a second chooser may be needed. Offer Choose only through a click. Never equate disconnect with successful transition. |
| **[INFERENCE]** Needs access / busy | A specific access/ownership failure occurred | Name what is established. Offer targeted OS/tab/program guidance and Check connection. A generic claim failure uses tentative wording. |
| **[INFERENCE]** Not responding / lost | Deadline or unexpected disconnect, with failed phase and certainty retained | Show honest silence/loss text. Offer diagnostic export and safe recovery. An uncertain write remains a separate visible result. |
| **[INFERENCE]** Closing / stopped | Stop/cancel requested, session retirement in progress or acknowledged | “Stopping further commands.” Do not say “cancelled safely” before cancellation/cleanup is acknowledged. Then show stopped/no rollback and any uncertainty. |

**[INFERENCE]** State transitions and concurrency rules:

1. Register relevant arrival/removal observation before starting a transition, then rescan grants/enumeration. This avoids relying on one event arriving at the perfect moment.
2. Every asynchronous result belongs to a connection generation. A stale open/probe result cannot overwrite a later selection or resurrect a closed session.
3. `connect`, focus/visibility return, and explicit Check can trigger a debounced rescan of grants. They must not issue extra protocol commands during active work.
4. A pending read-only preparation can resume once after Ready. A pending write requires its still-valid exact-target plan/confirmation. Waiting does not grant permission to replay a previous uncertain command.
5. Multiple candidates, duplicate/absent serials, or a changed identity stop automatic recovery. Native topology can aid diagnosis but is not a substitute for confirmed write identity.
6. Every wait has a cancellation path and finite automatic budget. After the budget, stop active polling and show a waiting/actionable state. The user may explicitly begin another bounded check.
7. User-visible states announce changes through accessibility live status. Spinners mean work is happening, not that the user must guess a required action.

The basis is exclusive WebUSB claims and gesture restrictions [S13], same-serial Calyx reconnect [S8], Tango's event lifecycle [S9], GrapheneOS's reconnect affordance [S6], and existing target/uncertainty rules [L9]. The generation and presentation rules above are design deductions, not copied APIs.

## 6. Timeout, cancellation and recovery policy

### 6.1 Separate budgets by phase

AOSP provides differing defaults across backends [S1–S4]. fastboot.js uses a 10-second getvar bound [S10]. esptool-js scales selected operations by data size [S11]. WebDFU respects device-supplied poll timing [S25]. WebUSB's transfer methods expose no caller timeout/AbortSignal argument in the inspected IDL [S13]. Chromium passes timeout 0 to generic transfer IPC [S14].

| Phase | Proposed policy, explicitly [INFERENCE] | Evidence and limits |
| --- | --- | --- |
| Initial open/claim | Bound acquisition separately from the protocol probe. Log substage and elapsed time. | Open success is not responsiveness [S13, S19]. A stalled open cannot be described as “phone did not answer getvar.” |
| First harmless probe | Start with a short profile-specific deadline. A candidate for this app is 3–5 seconds, with an explicitly requested longer 10–15-second check for slow environments. These numbers are provisional, not measured requirements. | ESP default is 3 seconds and fastboot.js getvar is 10 seconds [S10, S11]. Do not change destructive-command bounds to make the chooser feel fast. |
| Bulk data | Bound each submitted chunk using `max(floor, base + bytes/minimum_expected_rate)`, within profile limits. Show completed bytes, not just submitted bytes. Also bound no-progress time. | esptool's real function uses decimal MB [S11]. Chrome recommends bounded chunks/queues [S16]. Protocol/transport profiles must state units and constants. |
| Long processing/write/erase | Separate transfer completion from device processing. Use the protocol's known time bounds or an app-qualified allowance. Show silence and elapsed wait while processing. | AOSP can wait indefinitely. ESP gives chip erase 120 seconds and size-aware write/erase deadlines [S1–S4, S11]. These are examples, not Android constants. |
| INFO/status activity | Keep a no-progress deadline and an absolute operation deadline. Meaningful protocol progress may renew the former, never the latter without explicit policy. | WebDFU polls with `pollTimeout` [S25]. Local fastboot loops allow 4096 replies and currently restart each read's timeout [L3]. |
| Re-enumeration | A bounded elapsed-time and attempt budget, shared across reconnect/open/probe cycles. Immediate + delayed checks can use Calyx's 3/30-second shape, but keep the UI responsive. | Calyx waits 3 then 30 seconds [S8]. The archived prototype found reconnects could loop unless charged to the same budget [L9]. |
| Cleanup | Bound close/release/cancel. Attach failure to the original error. Do not silently turn an uncertain operation into success if cleanup times out. | Existing session retirement already bounds cleanup [L3]. nusb endpoint drop cancels pending transfers [S17]. |

**[INFERENCE]** A timeout only terminates the app's wait unless cancellation is also completed. Racing a Promise or dropping a wait future does not prove that the USB request stopped, or that firmware stopped processing it. Retire the old session, cancel/drop its pending endpoints through the backend's lifecycle, and fence late completions before opening a new command stream. WebUSB cleanup errors remain evidence. If cleanup cannot be acknowledged, say so and do not start a second session against the same operation.

### 6.2 Reopen: claim only by default, not blind rehabilitation

The inspected AOSP fastboot and legacy adb platform files do not explicitly issue `SET_INTERFACE`/alternate-setting selection in their open path [S1–S4]. This statement concerns those files, not every possible OS-internal side effect or alternative backend. fastboot.js also does not select an alternate, but it **does** attempt reset [S10]. Tango changes the alternate only if it differs [S9].

WebUSB `selectAlternateInterface` explicitly aborts interface transfers and issues `SET_INTERFACE`, even without a specified same-alternate shortcut [S13]. Linux has `USB_QUIRK_NO_SET_INTF` for devices that cannot handle it [S22]. AOSP macOS clears both pipes on open [S2]. Thus there is no source-supported universal rule that every library must perform exactly the same recovery sequence.

| Operation | Proposed default, [INFERENCE] | When an exception is justified |
| --- | --- | --- |
| Re-enumerate / reopen same identity | Acquire app ownership, open, inspect actual active configuration/descriptors, claim intended interface, then harmless probe. | An intended mode change requires a new observed mode and possibly a new grant. Never reuse stale endpoint/USBDevice objects as proof of readiness [S8, S13]. |
| Set configuration | Skip if the required configuration is already active. Set only when absent/different and required by the protocol. | macOS vendor-class devices may need explicit configuration [S17]. libusb warns that setting the already-active configuration resets alternate settings, halts and toggles [S19]. Chromium currently shortcuts unchanged configuration [S14], but do not rely on all backends doing so. |
| `SET_INTERFACE` | No redundant alternate-0 request. Select only a required alternate that is not active. | Protocols such as DFU can need alternates [S25]. A required change is a deliberate state change with no pending transfers, not an open ritual. Record the selected alternate. |
| `clear_halt` / `clearHalt` | Not routine on every open, and not inferred from silence alone. | Explicit Stall/EPIPE completion, followed by quiesced/cancelled endpoint work and a protocol-safe recovery plan. nusb documents resetting **both** host and device toggles, no pending transfers [S18]. A platform workaround such as AOSP Mac's must be separately justified, scoped and recorded [S2]. |
| Reset endpoint host-side toggle alone | Do not use as a generic repair. | Linux warns `USBDEVFS_RESETEP` can lose toggle synchronization and recommends a complete handshake instead [S21]. WinUSB ResetPipe is a defined pipe operation that clears stall/resets toggle, not a whole-device reboot [S23]. |
| Whole-device USB reset | No opportunistic reset on open, no automatic reset after a write timeout. | Explicit app/device recovery procedure, interruption warning, and required user authorization. Drop stale handles and rediscover. nusb says reset invalidates the Device and is unsupported on Windows [S18]. libusb can require rediscovery [S19]. This is not proof that firmware's protocol state or a stuck storage write reset safely. |
| Kernel-driver detach / kill another program | Do not force as routine connect. | A deliberate native-only procedure can target the precise claimed interface and restore ownership afterward. Generic help should suggest closing competing software. Never detach storage, networking, or unrelated composite functions merely to gain access [S17, S19]. |
| Autosuspend / LPM / quirks | Do not change automatically, globally, or on a timeout guess. | A diagnosed, per-device, reversible workaround with host evidence. Record previous values, target and change. Open usbfs suppresses idle autosuspend, but system suspend still exists [S22]. |

**[INFERENCE]** There is no generic post-timeout `clear_halt` recipe justified by these sources. If the host and device are desynchronized without a reported stall, repeated control requests can make diagnosis harder. Retire once, offer the documented physical recovery sequence, and retain the original failure. A qualified app may implement a narrower protocol-specific recovery later.

### 6.3 Same-device recovery and uncertain writes

**[INFERENCE]** Recovery order:

1. Stop issuing new protocol operations. Record failed phase, timing, submitted/completed bytes and last reply.
2. Mark any possibly applied write uncertain. Distinguish the operation's outcome from whether USB access can be restored.
3. Retire the session and preserve cleanup errors. Do not keep sending probes to a possibly active write on the old stream.
4. For an expected reboot, wait for the same serial through already-granted devices. If a new grant is required, present a click-controlled chooser. Never open it automatically.
5. Recheck identity, observed mode, and relevant capabilities. A different PID may be expected, but PID is not identity.
6. For harmless reads, retry only within the shared finite budget and only after a synchronized fresh session exists. “Read-only” does not itself prove a stale protocol stream is safe.
7. For a potentially applied write, reconcile using a real protocol capability or retain uncertainty. Device responsiveness, reboot success, or user clicking Retry does not prove that the earlier write did not apply.
8. Permit a new explicit write only under the app's documented operation-specific policy and confirmation. Do not genericize “reflash is harmless.” Earlier writes stay applied. Do not replay the entire plan.

The no-blind-resend rule already exists [L9]. Linux explicitly allows partial transfer length on errors [S20]. ADB/ESP write retry behavior [S4, S11] is protocol-specific precedent, not permission to retry arbitrary writes.

**[INFERENCE]** For silence during storage writes, do not immediately recommend cable removal, USB reset, or hardware reboot. First explain that completion is unknown and provide device-specific interruption guidance. A disconnected device may already require physical recovery, but the app cannot infer whether storage activity stopped merely because the host handle closed.

### 6.4 Host help should be conditional and precise

- Linux raw USB: write permission on usbfs node, narrowly scoped udev rules or distribution's supported Android rules. Reattach after permission setup as documented [S6, S16, S17].
- Windows: the intended **interface and mode** need the right driver. WinUSB is an interface binding. Composite-device parent, adb and bootloader interfaces can differ [S17, S23]. Pixel guidance includes current Windows configurations that require no manual driver [S6].
- macOS: no udev setup. nusb notes kernel-driver ownership and possible configuration needs [S17].
- Browser: secure page, supported API, correct frame policy, site grant, and another tab's ownership are separate [S13, S16].
- Snap: GrapheneOS advises avoiding confined browser builds [S6]. micro:bit documents a `raw-usb` connection workaround [S27]. **[INFERENCE]** Present this as a packaging/confinement check, not “all Chromium on Linux is broken,” and do not grant a Snap permission automatically.
- Android: browser/UsbManager authorization may need renewal after re-enumeration [S6, S24]. **[INFERENCE]** Explain the required attachment/mode and permission channel, not Linux udev commands.
- adb server: Google explicitly says it can interfere with Android Flash Tool [S5]. fwupd: GrapheneOS documents fastboot claims [S6]. ModemManager/serial terminals: Espressif documents serial interference [S26]. **[INFERENCE]** Offer each only for the relevant protocol/host, with user-controlled stop/close instructions. Do not claim a specific process is running without observing it.

## 7. Diagnostics and report content

The existing pattern requires original errors, source chains, cleanup errors, and unified `link.*` logs [L9]. nusb asks for debug logs [S17]. Chrome provides device-log and USB internals [S16]. Espressif recommends trace output for support [S26].

**[INFERENCE]** A useful local report contains:

1. Build/revision and transport/dependency versions. Browser version/OS when available, secure-context/API/policy observations, worker/place, and whether Web Locks were available. Mark unavailable fields explicitly.
2. A bounded chronological event trace with monotonic timestamps, operation IDs and connection generation. Include open/configure/claim/probe/transfer/reboot/cancel/cleanup durations and deadlines.
3. Requested identity, observed identity and mode, VID/PID, configuration/interface/alternate, endpoint addresses/types/max-packet sizes, connection speed/topology where exposed. Record grant source without treating it as OS access proof.
4. The failed command or safe command category, protocol phase, expected and completed byte counts, chunk size, deadline type, last progress time, and bounded INFO/TEXT/status/response evidence. Exclude image payloads and secrets.
5. Raw error type/name/message/stack, native code and cause chain if exposed, plus classification code/rule and its supporting evidence. Unknown stays unknown. Record local deadline expiry separately from native timeout.
6. Attempt/reconnect counts and reasons, selected recovery action, expected re-enumeration, and observed arrival/removal times. Do not rewrite the original error when a later disconnect explains it better. Append that observation.
7. Session retirement/cleanup outcome, pending cancellation acknowledgement, operation certainty and receipt status. If reconciliation was possible, include what was asked and what the response established.
8. Optional user-supplied cable/hub/power/screen observations, clearly identified as user observations. Optional native OS diagnostics require explicit collection scope. A web app must not pretend it read kernel logs.

**[INFERENCE]** Keep summaries by transfer phase and a bounded ring of chunk events. Preserve the initial failure and cleanup evidence even when the ring rolls over. Avoid one permanent event per MiB for multi-GiB images.

**[INFERENCE]** Separate an exact-target **local receipt** from a shareable diagnostic report. A serial may be needed in the receipt and on screen. Redact serials, device paths, usernames and sensitive URLs by default in an export meant for sharing. Use a per-report consistent pseudonym rather than a globally stable unsalted serial hash. Provide a preview and never upload automatically. A pre-write preparation failure must also allow export, even if no flash receipt exists.

## 8. Comparison with current flasher-web

These observations apply to the read snapshots L1–L8, not every transitive backend or executor. Recommendations are marked separately. No build, test, browser run or device check was performed.

### What already matches the pattern

- WebUSB opens exact serial matches, rejects duplicate matches, has a local guard and a cross-tab Web Lock with `ifAvailable` [L1]. Native has a per-process serial/interface guard and claims only the selected interface [L2].
- WebUSB changes configuration only when needed. It now skips alternate 0 and only calls `set_alt_setting` for a nonzero selected alternate. Neither local open path routinely calls reset or clear-halt [L1, L2].
- Rust keeps original transport messages, browser stack where available, causes, INFO/TEXT and cleanup errors. Public failure separates `source`, `uncertain`, and `sessionRetired` [L3–L5].
- `Session` retires on transport/desynchronization errors, bounds cleanup, and does not internally reopen or retry writes. Complete fastboot FAIL leaves the session usable for later probes [L3, L4].
- The sheet distinguishes Choose USB device from Check already granted, handles unsupported/insecure contexts and no-selection, and calls the chooser from the click task [L6].
- The controller binds read-only preparation to target/inputs/confirmation, represents uncertain/stopped results, and says retries are explicit. The UI offers receipt/log downloads and warns earlier steps stay applied [L7, L8].

### Concrete gaps and recommended changes

| Priority | Observed gap | Proposed change, [INFERENCE] |
| --- | --- | --- |
| High | `LinkError::from_transport` assigns `blame = host` to **every** transport failure, including local/native timeout, generic NetworkError, and disconnect [L4]. `describeLinkFailure` prints that blame prominently [L8]. | Preserve `source`, but default unattributed transport failures to unknown. Classify host only with access/ownership/context evidence. Provide cause-aware action text instead of a raw `(blame: host, …)` diagnosis. This directly addresses the live incident. |
| High | `LinkError::protocol` always assigns device blame. All complete FAILs are modeled non-uncertain, regardless of command-specific semantics [L4]. | Distinguish malformed reply from proven device refusal. Audit certainty for destructive commands separately from session usability. A synchronized refusal may keep a connection usable without proving no side effects. |
| High | Initial probes use the session I/O allowance, while writes use 180 seconds. There is no separately modeled short first responsiveness stage in the inspected session contract [L3, L5]. | Add profile/app-owned probe deadlines and responsive stage messages. Preserve long storage-processing bounds. Do not shorten writes merely to make connect feel faster. |
| High | `command_inner`, `begin_inner` and `end_inner` pass the full timeout to each response. A 4096-response cap bounds count but not a practical overall duration [L3]. | Add absolute operation and no-progress deadlines. Keep INFO/TEXT activity without allowing a chatty device to extend an operation for days. |
| Medium | `write_download` uses the same `self.timeout` for every chunk up to 1 MiB. Browser transport has a separate fixed 600-second backup [L1, L3]. | Use length/phase-aware transfer policy, explicit units and recorded deadlines. Keep an outer operation bound that governs the backup. Do not borrow ESP throughput constants without qualification. |
| High | The sheet/controller expose loading/choosing/error and flash phases, not one explicit connection phase stream with opening/claiming/probing/ready/not-responding states [L6, L7]. | Introduce app-owned connection state evidence and UI messages. Keep this separate from flash job phase and write certainty. Stream it from the transport-owning place. |
| Medium | Sheet grant refresh is manual or on initialization. The inspected sheet does not subscribe to attach/removal/focus; grant-list selections can precede the later real open/probe [L6]. | Rescan on relevant lifecycle events without concurrent active probes. Say “granted” until open and protocol checks actually succeed. Avoid opening every unrelated grant as a readiness test. |
| Medium | `webusb::devices` opens each granted device and returns early on any open error, even before selecting its fastboot interface [L1]. | Isolate per-device discovery failures, retain them as evidence, and avoid one irrelevant/inaccessible grant hiding the intended target. Discovery must not force-close a live session. This is a recommendation, not a demonstrated runtime failure. |
| High | Transfer errors are immediately surfaced/retired without an app-visible correlation with a following browser disconnect event [L1, L4]. | Preserve the original transfer failure, observe a bounded disconnect-correlation interval (Tango uses 100 ms), then attach the later observation. Do not relabel every NetworkError or resend the transfer. |
| Medium | The sheet's permission/no-selection messages do not distinguish OS access, site grant, confinement, driver setup, own tab ownership, and generic claim failure. No-selection help is mostly bootloader/choose-again [L6]. | Add the small ESP-style “not in list” checklist and host-specific help. Qualify adb/fwupd/ModemManager suggestions by protocol. Add driver/configuration help without assuming causation. |
| High | Failure guidance begins with “Retry that step” even for an uncertain result. The card offers Retry and Reboot-to-fastboot-and-retry, with inspection warnings [L7, L8]. | Make uncertainty the primary state. A retry button must reflect operation-specific replay/reconciliation policy, not just user willingness. Warn before reboot/reset during possible storage processing. The executor's complete replay policy was not audited here. |
| Medium | UI exports a receipt and text log. `downloadReceipt`/`saveLog` include raw serial in filenames, `_log` is an unbounded string list, and export is tied to flash artifacts [L7, L8]. | Add a bounded, structured, redacted connection report available before preparation succeeds. Preserve exact serial only in deliberate local receipt output. Do not claim the text log is a complete transport trace. |
| Medium | Native `open` assumes a matching interface/active descriptor after claim, without the browser path's explicit conditional configuration selection [L2]. nusb documents a macOS vendor-class configuration case [S17]. | Check the actual supported device/configuration requirement before changing code. If needed, mirror conditional configuration selection. This is an integration risk, not a reproduced failure. |
| Medium | The browser skips alternate selection for 0 but calls it unconditionally for a selected nonzero alternate [L1]. | For a generic future adapter, compare actual active alternate too. The present fastboot-specific rule should not become “USB alternates are forbidden.” |

**[INFERENCE]** Do not erase existing strengths while fixing these gaps: exact serial, one session, inspection/confirmation, source preservation, explicit retirement, and no automatic write replay remain required. This research does not justify replacing the protocol implementation merely to obtain nicer connect messages.

## 9. Where the pattern belongs

| Location | Recommended responsibility, [INFERENCE] |
| --- | --- |
| `bricks/docs/patterns/devices.md` | Evidence-based responsibility, state-vs-outcome separation, waiting availability, identity pinning, one owner/one stream, chooser-vs-granted distinction, finite deadlines/reconnect budget, conservative reopen, uncertain writes, reports and host-specific-help principles. |
| First app's transport package | Native/browser adapters, typed raw evidence, pending-I/O lifecycle, ownership guards, cancellation, configuration/alternate handling, hotplug translation. Use nusb/platform behavior rather than reimplement USB access. |
| First app's protocol package | Safe probe, framing/ZLP, real mode recognition, processing deadlines, protocol status, replay/reconciliation semantics, allowed recovery procedures. |
| First app's UI/controller | Connection messages/actions, no-selection checklist, host help links, chooser gesture, readiness display, report preview, operation-specific interruption warnings. |
| App-specific configuration | Device/vendor quirks, expected mode transitions, firmware-specific limitations and validation. No CANOE-BDS, Super Fastboot, or vendor variables in generic prose/contracts. |
| Squadron/process service | Generic execution/stream delivery only. The service can carry app `LinkState` and evidence without owning USB policy. |
| Future brick | Only a slice that two independent consuming apps actually copied, after comparing their live requirements. Not a registry of speculative protocol profiles or a second strategy vocabulary. |

**[INFERENCE]** Nothing inspected here demonstrates the “second app copies it” extraction bar for this proposed connection handler. Web and native paths of flasher-web remain one consuming app. The archived fake prototype is not a second app. External apps demonstrate established patterns worth adopting, not that a p0g feature brick is already justified. Document the rules now. Extract actual duplicated app code only when that duplication exists.

### Disagreements with current devices.md

1. **[INFERENCE]** Replace the rule that only device/unknown failures get reports. Allow evidence export for persistent host/user failures too.
2. **[INFERENCE]** State that API source is not responsibility. Do not make silence, generic transport error, or unexpected mode after an automatic transition automatically host/user blame.
3. **[INFERENCE]** Clarify harmless retries: even a read requires a synchronized session. Reconnect alone does not make an uncertain write safe to replay.
4. **[INFERENCE]** Add conservative initialization and actual operation deadlines. Current rules omit redundant alternate selection, endpoint halt/reset consequences, and non-cancelling timeout hazards.
5. **[INFERENCE]** Keep the existing architecture unchanged: no USB facts for changing attachment state, no shared link core, no vendor-specific mode probes, no loss of exact-target confirmation.

## Appendix A. Proposed replacement text for devices.md

**[INFERENCE]** The following is a complete draft for owner review. It does not modify the current page. All normative wording is proposed project policy, derived from the evidence above, not a claim that the current code already meets it.

---

# Patterns: apps that talk to a device

For apps that communicate with a phone or board over USB, adb, fastboot, or a serial connection. The transport can live in a page, desktop CLI, or Android root process.

These are patterns, not a brick. Link code starts in the first app that needs it. Extract a brick only after a second app copies the same code. Keep device-specific protocols and vendor extensions in their consuming app.

## Fit the strategy model

**A connected device is changing availability, not a host fact.** Facts describe what a place can do. The strategy holds its app-owned link and checks its observed state in `available`.

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
    return Availability(
      name,
      note: 'connect a phone in fastbootd',
      waiting: true,
    );
  }
  // Existing plan/write implementation follows.
}
```

`Selection.chosen` remains the first ready strategy. `Selection.waiting` lets the UI offer an alternative that needs user action. Do not make attachment, permission grant, or mode into an immutable place fact.

**A write names its target.** Put the external device identity and required mode in the input. Show them in the plan and confirmation. Before writing, refuse a different, missing, or ambiguous target. Do not replace serial matching with VID/PID or “the only device.” A write to this device, inside its root process, has no external USB target to pin.

**Uncertain results belong to the app.** If a write may have applied, use the app's result or typed exception. A new connection does not clear that uncertainty. Stopping is not rollback.

**One log, one transport owner.** Log connection evidence on `Logger('link.<name>')` so `logTo` collects it with strategy events. When USB lives in a process place, stream the app's state through its service. The page owns browser chooser gestures. Neither Squadron nor generic strategy code owns USB policy.

## Describe what is known

Keep the original error: type/name, message, stack, cause chain, native code when exposed, and cleanup errors. Add classification beside it.

Separate:

- **Source:** which API produced the evidence.
- **Responsibility:** host, user, device, or unknown, supported by that evidence.
- **Outcome:** not submitted, confirmed complete, explicitly refused, or may have applied.
- **Session lifetime:** usable, retiring, or retired.

A permission-denied open supports host-access guidance. An explicit no-selection result supports a Choose action. A parsed device refusal supports device/protocol guidance. A timeout or generic transfer error does not identify the cause. Use unknown when evidence cannot distinguish cable, controller, browser, app, or firmware.

Say “No reply arrived within [deadline]. The cause is not known,” not “Host error” or “The device is broken.” For a possible write, add “The result is not confirmed. Nothing will be sent again automatically.” A disconnect means the connection disappeared, not necessarily that the person unplugged it.

Keep report export available for persistent failures in every category. Guidance can be primary for setup problems. Do not suppress the original evidence because a classifier calls it a host problem.

## Make connection progress actionable

The app's connection controller distinguishes unavailable, waiting for selection, choosing, opening/claiming, probing, ready, active, waiting for a mode change, access/busy, not responding/lost, and closing/stopped.

Enter ready only after the required identity and protocol mode are observed. A grant, USB descriptor, open handle, or successful OUT transfer is not readiness or write completion.

Show the current phase, elapsed wait, expected mode, and next action. Show bytes only when measured. Use a spinner while work is active and an action prompt when the person must act. Keep connection state separate from the job result, especially an uncertain write.

Serialize protocol work. A second probe must not race a download or consume its response. Fence late asynchronous results so an old connection cannot replace a newer selection.

## Choose and reconnect safely

1. Open a browser chooser only from the person's click. Keep Choose device separate from Check already granted.
2. No selection is a waiting result. Offer an optional checklist for a missing device: correct mode, power/data cable, direct port, OS access, driver and browser packaging.
3. Reconnect automatically only through already-granted or already-authorized attachments, matched to the confirmed identity. Never guess between devices.
4. Observe arrival/removal and rescan on a relevant event or return to the page. Do not run competing protocol probes during active work.
5. Bound automatic reconnect by both elapsed time and attempts. Open/probe failures spend the same budget. After exhaustion, show actions instead of polling forever.
6. After a mode change, query the device's actual mode. A reboot command or disconnect event does not establish that transition succeeded. A new browser grant may need another click.

Find mode through the protocol's supported evidence, not a vendor/product filter when modes share it. For fastboot, use `getvar is-userspace` where supported. Treat unavailable mode evidence explicitly. Vendor/project variables stay app-specific.

## Open conservatively

Inspect descriptors and current configuration. Select a configuration only when required and not already active. Claim only the intended interface. Do not send redundant `SET_INTERFACE` for an already-active alternate, especially alternate 0. Change alternates only when required by the protocol.

Do not clear every endpoint or reset the device on every open. Clear a known halted endpoint only after pending transfers are quiesced and the protocol's recovery rule permits it. A timeout alone is not a stall. Do not reset only the host's data toggle.

A device reset, driver detach, host power change, or physical reboot is a deliberate recovery procedure, not generic retry preparation. Scope it to the exact target. Explain interruption risks and reacquire identity/mode afterward. Do not silently kill competing programs or disable global autosuspend.

Use host-specific help. Browser origin permission, Linux usbfs permission, Windows interface driver binding, macOS ownership, Android attachment permission, and another tab's claim are different problems. Name adb, fwupd, ModemManager, or a serial terminal only when relevant, and as possibilities unless observed.

## Bound waits without replaying writes

Use separate deadlines for open/claim, first safe probe, bulk transfer, long device processing, transition, and cleanup. Scale data deadlines by length when appropriate. State units. Respect protocol polling delays, with an overall operation bound.

A no-progress deadline and an absolute deadline solve different problems. Informative replies may extend the former under explicit policy. They must not create an unbounded operation.

A timeout stops waiting. It does not prove that USB or firmware stopped. Retire/cancel the session through the backend's lifecycle and preserve cleanup evidence. Do not start a second command stream while old I/O may still be active.

Retry only operations known to be harmless in the current protocol state. A read-only query on a desynchronized stream is not automatically safe. For a write that may have applied, reconcile through a real device capability or retain uncertainty. Never resend blindly, automatically or behind a generic Retry button. App-specific explicit replay requires its own safety rule and confirmation.

## Keep useful diagnostics

Record build/transport versions, host capabilities, identity/mode evidence, selected configuration/interface/alternate/endpoints, operation phase, deadlines, byte counts, event times, attempts, raw errors, classification evidence, cancellation, cleanup and certainty.

Keep a bounded trace that preserves failures. Do not log image payloads or an unbounded event for every chunk. Offer a redacted shareable report before any write succeeds. Keep exact-target local receipts separate. Never upload diagnostics automatically.

Background, source comparisons, and recovery details: [USB connection handling research](../research/usb-connection-handling.md).

---

## Review boundaries

No physical-device diagnosis, USB trace, driver change, reset, power change, build, test, or UI execution was performed. The 03e22f9 hardware effect remains unverified. Google Android Flash Tool's private transport implementation was not established from its public landing page. The recommendations above do not assert qualification of Android root access or a specific browser/backend combination.
