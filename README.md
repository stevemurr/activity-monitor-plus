# Activity Monitor Plus

A better macOS system monitor. A native SwiftUI app that leads with a high-level
dashboard — a donut of the top CPU consumers, memory pressure, storage, and
network throughput — with a live network connection log and a fast, stable
process table behind it.

![Platform](https://img.shields.io/badge/platform-macOS%2015%2B-111111)
![Swift](https://img.shields.io/badge/Swift-6.0-F05138)
![UI](https://img.shields.io/badge/UI-SwiftUI%20%2B%20Swift%20Charts-2A6EF0)

![Overview](docs/screenshots/overview.png)

## Features

- **Overview dashboard (primary view).** A donut chart of the top five CPU
  processes plus "Other" and "Idle", with an Activity-Monitor-style
  User / System / Idle split; a memory card broken into App / Wired /
  Compressed; per-volume storage bars; and network in/out rates with a
  60-second throughput sparkline.
- **Process table.** Sortable by name, PID, %CPU, or memory, with search.
  Values are exponentially smoothed and row order is frozen between periodic
  re-ranks, so the table reads calmly instead of oscillating every second.
  Select any process to **Inspect** it (path, user, parent PID, start time, and
  its recent network activity) or **Quit / Force Quit** it.
- **Network log.** A live feed of connection events — opened, closed, and
  per-interval traffic with bytes in/out — attributed to process and remote
  address, built by diffing socket snapshots once a second. Pause and clear
  from the toolbar.
- **Menu bar extra.** A gauge in the menu bar; click it for live CPU, memory,
  and network figures without opening the window.
- **Appearance.** Follows the system Light/Dark setting, with a manual override
  in Settings (⌘,).

## Screenshots

| Processes | Network log |
|---|---|
| ![Processes](docs/screenshots/processes.png) | ![Network](docs/screenshots/network.png) |

## Architecture

The app is built around a small, testable core and a clean sampling seam.

- **Sampling seam.** Every source of data is a protocol — `CPUSampling`,
  `MemorySampling`, `StorageSampling`, `ThroughputSampling`,
  `ConnectionSnapshotProviding`, `ProcessControlling`. Live implementations read
  the system via `libproc`, Mach host statistics, `getifaddrs`, and `netstat`;
  fixture implementations return deterministic data for tests. A
  `--uitest-fixtures` launch argument swaps the whole set.
- **Sampling loop.** An `actor SamplingCoordinator` runs a 1 Hz loop and
  publishes each `SystemSnapshot` (plus connection events) through an
  `AsyncStream`. A `@MainActor @Observable AppModel` consumes the stream and
  drives the SwiftUI views.
- **Pure core.** The parsing and transformation logic — `NetstatParser`,
  `ConnectionDiffEngine`, `CPUDonutSlices`, `ProcessSmoother`, `StableRanker`,
  `RingBuffer`, `Formatters` — is free of I/O and unit-tested on the host.

```
ActivityMonitorPlus/
├── App/            @main app, AppModel, appearance
├── Models/         snapshots, connection events, ring buffer, donut/table logic
├── Sampling/       protocols, coordinator, parser, diff engine, live + fixtures
├── Views/          Overview cards, process table, network log, menu bar
└── Support/        formatters
```

## Getting started

**Requirements:** macOS 15+, Xcode with the Swift 6 toolchain, and
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
The `.xcodeproj` is generated, not committed.

```bash
git clone https://github.com/stevemurr/activity-monitor-plus.git
cd activity-monitor-plus
xcodegen generate
open ActivityMonitorPlus.xcodeproj      # or build from the command line:
xcodebuild -scheme ActivityMonitorPlus -configuration Release build
```

The app is **non-sandboxed** (it reads other processes' statistics and spawns
`netstat`) and **ad-hoc signed** for personal use.

## Testing

```bash
# Unit tests — safe to run on the host
xcodebuild -scheme ActivityMonitorPlus test
```

The **UI tests are XCUITest** and take over the real mouse and keyboard while
they run, so they must run inside a VM, never on your host. They assert against
fixture data via the `--uitest-fixtures` launch argument. Compile-checking the
UI-test target on the host is fine:

```bash
xcodebuild -scheme ActivityMonitorPlusUITests build-for-testing
```

## Notes

- **CPU attribution.** Per-process CPU comes from `proc_pid_rusage`, which is
  denied for processes owned by other users (root daemons). Those rows show
  "—" and their usage is still reflected in the donut's "Other" slice, since
  the total comes from Mach host statistics.
- **Process table cap.** SwiftUI's `Table` uses automatic row heights, which
  forces AppKit to realize a view for every row on a reorder. To keep sorting
  and filtering instant, the table renders the top 150 rows by the active sort;
  search still scans every process.
