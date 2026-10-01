# Sample: fetch a partition, on the device or from a computer

Canoe Boot Manager copies a partition's image in one of two ways:

- **On the device**, in the app's root process: `dd` from
  `/dev/block/by-name/<partition>`.
- **From a computer**, with the device in fastbootd: `fastboot fetch`.

These are not two platform code paths. They are two strategies of one
`fetch_partition` objective, and the facts of the place the service runs in
pick one. This sample builds that with the bricks, from an empty folder.
[`partition-fetch.patch`](partition-fetch.patch) is every hand edit below
as a diff. `tool/ci.sh` applies it to a freshly generated `cbm` and runs its
tests and `cbm partitions --how`, so the sample stays true to the bricks.

## 1. Generate

```sh
mason make p0g_app        # name: cbm, rust: false
cd cbm
mason make service --name partitions
mason make strategy --name fetch_partition --strategies '["dd", "fastboot fetch"]' --write false
```

The strategy brick writes `core/lib/src/strategy/fetch_partition.dart` with an
objective and two stub strategies, `FetchPartitionDd` and
`FetchPartitionFastbootFetch`, in that preference order. The service brick
writes `PartitionsService`, a `cbm partitions` command, a `serve` entry
and an app panel.

## 2. A fact for the host tool

`fastboot fetch` needs the `fastboot` tool. Whether a place has it is a fact,
checked where the place runs, so add the key and its checks:

- `core/lib/src/facts/facts.dart`: `static const fastboot = 'tool.fastboot';`,
  added to `Fact.all`.
- `core/lib/src/facts/check_io.dart`: `Fact.fastboot: await _canRun('fastboot', ['--version'])`.
- `core/lib/src/facts/check_web.dart`: `Fact.fastboot: false`.

## 3. Fill in the strategies

The stubs take and return `String`. A fetch needs a partition and a folder,
so the objective becomes `Objective<FetchRequest, String>`, returning the
image's path.

```dart
final fetchPartition = Objective<FetchRequest, String>('fetch_partition', const [
  FetchPartitionDd(),
  FetchPartitionFastbootFetch(),
]);
```

`dd` needs root, readable block devices and a shell:

```dart
@override
Set<String> get requires => const {Fact.root, Fact.blockDevices, Fact.processSpawn};
```

`fastboot fetch` needs the tool and USB, and overrides `available` for the
one case facts alone do not rule out. A place with root and block devices is
the device itself, and fastboot there would talk to some other device:

```dart
@override
Set<String> get requires => const {Fact.fastboot, Fact.usbNative, Fact.processSpawn};

@override
Availability available(Facts facts) {
  final base = super.available(facts);
  if (!base.ok) return base;
  return facts.has(Fact.root) && facts.has(Fact.blockDevices)
      ? Availability(name, note: 'this place is the device')
      : base;
}
```

Neither strategy reads `kIsWeb` or `Platform`; p0g_lints'
`strategy_reads_platform` would fail `dart analyze` if one did. Both `run`
bodies are a `Process.run` and a check of the exit code. A fetch changes
nothing on the device, so these are `ReadStrategy`s. Flashing the image back
would be a `WriteStrategy` (`--write true`): plan, confirm, receipt.

## 4. Expose it

`PartitionsService` gets two methods. Each runs in whatever place the
service was bound to, with that place's facts:

```dart
@squadronMethod
Future<String> howToFetch() async =>
    fetchPartition.selectRead(await PlaceInfo.current()).why;

@squadronMethod
Future<Map<String, String>> fetch(String partition, String outDir) async { ... }
```

`cbm partitions [--how] [-o dir] <partition>` calls them. In the app, bind the
service to the process place (the CLI's `serve`, as root on WebUI) and the
same call runs `dd` on the device. On a desktop with fastboot it runs
`fastboot fetch`. In a browser tab, nothing fits, and the objective throws
`NoStrategyAvailable` with the reasons.

## 5. Test

`core/test/fetch_partition_test.dart` checks the choice with fabricated
facts (device, host, both, browser tab), and runs the `dd` strategy against
a plain file standing in for `/dev/block/by-name/boot_a`. Every run is
logged on `objective.fetch_partition`, for example:

```
$ cbm partitions --how
nothing fits: dd skipped (missing block_devices); fastboot_fetch skipped (missing tool.fastboot, usb.native)
```
