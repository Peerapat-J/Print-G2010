<p align="center">
  <img src="docs/images/app-icon.png" width="128" alt="Print G2010 app icon">
</p>

<h1 align="center">Print G2010</h1>

<p align="center"><b>Printing for the Canon PIXMA G2010 on Apple silicon Macs</b></p>

<p align="center"><i>Add your files. Pick the pages. Print, in reading order.</i></p>

<p align="center">
  <img src="https://img.shields.io/badge/App-v1.0.0-8250df" alt="App: v1.0.0">
  <img src="https://img.shields.io/badge/macOS-14%2B-555555?logo=apple&logoColor=white" alt="macOS: 14+">
  <img src="https://img.shields.io/badge/Hardware-Apple%20silicon-6e56cf?logo=apple&logoColor=white" alt="Hardware: Apple silicon">
  <img src="https://img.shields.io/badge/Printer-Canon%20G2010-c1121f" alt="Printer: Canon G2010">
  <img src="https://img.shields.io/badge/Price-Free%20to%20use-2da66b" alt="Price: Free to use">
  <img src="https://img.shields.io/badge/Printing-Gutenprint-2f6fed" alt="Printing: Gutenprint">
</p>

<p align="center"><a href="#app">Features</a> · <a href="#how">How it works</a> · <a href="#build">Build</a> · <a href="#share">Sharing</a> · <a href="#limits">Limits</a> · <a href="#license">Licenses</a></p>

<p align="center"><b>English</b> &nbsp;|&nbsp; <a href="README.th.md">ภาษาไทย</a></p>

---

Print on a **Canon PIXMA G2010** from a Mac. Canon provides no driver for this printer on recent
versions of macOS, and its G2000 driver hangs on a Mac with Apple silicon. This project prints
through [Gutenprint](https://gutenprint.sourceforge.io/), built natively for Apple silicon, and
wraps it in a small app, **Print G2010**.

Status (3 Nov 2026): **printing works** on an M1 Pro MacBook Pro running macOS 27.2 with the G2010
connected over USB. Scanning worked in earlier experiments (SANE, 300 DPI) but is not part of the
app yet.

<a id="app"></a>

## The app

Print G2010 is a single window:

- Add PDFs, pictures or text files with **Add Files…** or drop them on the window.
- Tick the files to print and press **Print Selected**, or press the printer button on a file to
  choose its copies and pages (all, odd, even, or a list such as `1, 3, 5-9`).
- Drag rows to change the print order. Files print in a queue, with a badge on each file
  (Queued, Printed 2/5 pages, Printed, Failed) and a status line with the printer's progress.
- A badge shows whether the printer is ready, busy, switched off or has no print queue.
- **Print last page first** (on by default): the G2010 delivers pages face up, so this leaves the
  stack in reading order.
- Word, Pages and other Office documents must be exported to PDF first.

The app is self-contained: it carries the print script, the page-splitting tool, Gutenprint and
its printer description, so it does not need this repository to run, and it finds the G2010's
print queue by itself.

<a id="how"></a>

## How it works

```
PDF / image / text
  → one PDF per page                       (tools/pdf-tool, PDFKit)
  → CUPS raster                            (cupsfilter, Apple's own filters)
  → printer commands                       (Gutenprint, "Canon G2000 series" profile)
  → one raw CUPS job per page              (lp -o raw → USB backend → printer)
```

Sending raw jobs bypasses the queue's own filters, which is where Canon's driver hangs. Sending
each page as its own job is what lets the app count the pages the printer has taken. The G2010
(USB ID `04a9:183a`) is not in Canon's G2000 package, but its device ID reports the same command set (`BJRaster3`) and Gutenprint's G2000 profile prints on it; Gutenprint
marks the Canon G-series as experimental.

## Requirements

To use the app: a Mac with **Apple silicon**, **macOS 14 or later**, the G2010 connected by USB and
added once in System Settings → Printers & Scanners (any driver; the app does its own conversion).

To build it: Xcode, Homebrew, and `pkgconf` and `xcodegen` from Homebrew. Only tested on macOS 27.2
with Xcode 27.2.

<a id="build"></a>

## Build and run

```sh
brew install pkgconf xcodegen
scripts/build-gutenprint.sh     # once: downloads and builds Gutenprint 5.3.5 into build/
scripts/build-app.sh            # builds build/Print G2010.app
open "build/Print G2010.app"
```

Without the app, from a terminal:

```sh
scripts/g2010-print file.pdf
scripts/g2010-print -n 2 --pages 1,3,5-9 file.pdf     # copies, pages (or odd / even)
scripts/g2010-print --dry-run file.pdf                # convert only, send nothing
```

`G2010_DRY_RUN=1 "build/Print G2010.app/Contents/MacOS/Print G2010" --selftest file.pdf` runs the
app's printing code without a printer or paper.

<a id="share"></a>

## Sharing the app

`scripts/make-dmg.sh` builds `dist/PrintG2010-<version>.dmg` with the app, an Applications shortcut
and a Read Me. To open on other Macs without a warning the app must be signed with a Developer ID
and notarized (`NOTARY_PROFILE=<notarytool profile> scripts/make-dmg.sh`; the one-time setup is in
the script header). Without that, other Macs show "Apple could not verify…" and the user has to
choose Open Anyway once; the Read Me in the DMG explains how.

## Repository layout

| Path | What it is |
| --- | --- |
| `app/` | The SwiftUI app, its Info.plist and asset catalog |
| `tools/pdf-tool/` | Command line tool that splits a PDF into pages |
| `scripts/g2010-print` | The print pipeline |
| `scripts/build-gutenprint.sh` | Downloads, verifies and builds Gutenprint for Apple silicon |
| `scripts/build-app.sh`, `make-dmg.sh` | Build the app; package it for sharing |
| `scripts/xcode-bundle-helpers.sh` | Xcode build phase that bundles the helpers into the app |
| `project.yml`, `PrintG2010.xcodeproj` | Xcode project (generated from `project.yml` by XcodeGen) |
| `docs/` | Notes and research, **in Thai** |

<a id="limits"></a>

## Known limits

- Apple silicon only; macOS 14 or later.
- Printing from the normal Print dialog (⌘P) is not supported yet; use the app or the script.
- Print quality, margins and colour have not been checked in detail; there is no black-and-white
  or quality option yet.
- The G2010's scanner is not part of the app.
- Not yet tried on a second Mac.

## Documentation (Thai)

- [Printing on the G2010: what was tried, what works, how to use it](docs/printing-g2010.md)
- Research notes from the first experiments: [handoff](docs/project-handoff.md),
  [R-01 / R-02](docs/research/2026-10-30-r01-r02.md),
  [R-03 / R-04](docs/research/2026-10-30-r03-r04-hardware.md),
  [print queue URI fix](docs/research/2026-10-30-print-queue-uri.md),
  [next hardware task](docs/research/next-hardware-task.md),
  [reviewed roadmap](docs/research/reviewed-roadmap.md)

Printer serial numbers appear in some system commands' output; remove them before publishing logs.

<a id="license"></a>

## Licenses

The app bundles [Gutenprint](https://gutenprint.sourceforge.io/) 5.3.5, which is free software under
the GNU General Public License (version 2 or later). `scripts/build-gutenprint.sh` downloads the
unmodified source from SourceForge and checks its SHA-256, so the exact source of the bundled
binaries is available there. Print G2010 is not affiliated with Canon or the Gutenprint project;
"Canon" and "PIXMA" are trademarks of their owners.

© 2026 Peerapat Jardrit
