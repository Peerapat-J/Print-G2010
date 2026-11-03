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

<p align="center"><a href="#features">Features</a> · <a href="#download">Download</a> · <a href="#licenses">Licenses</a></p>

<p align="center"><b>English</b> &nbsp;|&nbsp; <a href="README.th.md">ภาษาไทย</a></p>

---

Canon doesn't make a driver for the **PIXMA G2010** on recent Macs, so I made a small one.
Print G2010 is a free app that prints to the G2010 over USB (with a USB to USB-C adapter) from a Mac
with Apple silicon.

<a id="features"></a>

## Features

- Drop in PDFs or pictures, tick the ones you want, press Print.
- Choose copies and pages for any file: all, odd, even, or something like `1, 3, 5-9`.
- Prints the last page first, so the stack comes out with page 1 on top.
- Shows what the printer is doing, and queues up several files.
- Drag files up and down to change the order.

**Note:** Word and Pages documents need to be exported to PDF first.

<a id="download"></a>

## Download

<p align="center">
  <a href="../../releases/latest"><img src="https://img.shields.io/badge/Download-Print%20G2010%20for%20macOS-2da66b?style=for-the-badge&logo=apple&logoColor=white" alt="Download Print G2010 for macOS"></a>
</p>

Download the latest `.dmg` from [Releases](../../releases), open it and drag **Print G2010** to
Applications. If macOS says it can't verify the app, the Read Me inside the disk image shows how to
open it.

You'll need a Mac with Apple silicon on macOS 14 or later, and the G2010 connected by USB and added
once in System Settings → Printers & Scanners.

<details>
<summary>Build it yourself</summary>

```sh
brew install pkgconf xcodegen
scripts/build-gutenprint.sh     # once
scripts/build-app.sh
open "build/Print G2010.app"
```

</details>

<a id="licenses"></a>

## Licenses

Printing is done by [Gutenprint](https://gutenprint.sourceforge.io/), free software under the GNU
GPL, which the app includes. This project isn't affiliated with Canon.

© 2026 Peerapat Jardrit
