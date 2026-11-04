# Print G2010 — Project Handoff

## 1. Project Overview

**Repository:** https://github.com/Peerapat-J/Print-G2010

**Project Name:** Print G2010

**Initial Target Device:** Canon PIXMA G2010

**Target Platform:** macOS (Apple Silicon / MacBook Pro M1 Pro)

**Application Framework:** SwiftUI + AppKit

**Project Type:** Open-source macOS Printer Driver and Scanning Utility

### Background

Canon PIXMA G2010 ไม่มี Printer Driver สำหรับ macOS อย่างเป็นทางการ ทำให้ไม่สามารถใช้งานเครื่องพิมพ์ได้ตามปกติ

เป้าหมายของโปรเจกต์คือทำให้ Canon G2010 สามารถพิมพ์และสแกนบน macOS ได้ โดยเลือกใช้หรือปรับปรุง Open-source Driver/Library ที่มีอยู่แล้วก่อน และพัฒนาเองเฉพาะส่วนที่ยังขาด

**Development Philosophy: Reuse First, Build Only When Necessary.**

ไม่จำเป็นต้องเขียน Driver ใหม่ทั้งหมดหากมี Implementation ที่นำมาใช้ได้จริง แต่ต้องตรวจสอบ Compatibility, Licensing และทดสอบกับ Hardware จริง

---

## 2. Functional Requirements

### A. System Printing — Primary Requirement

ต้องสามารถพิมพ์ผ่านระบบปกติของ macOS ได้

Expected Workflow:

1. เชื่อมต่อ Canon G2010 ผ่าน USB
2. เครื่องพิมพ์ปรากฏใน System Settings → Printers & Scanners หลังติดตั้งระบบที่พัฒนาขึ้น
3. เปิดเอกสารผ่าน Microsoft Word, Preview, Browser หรือ Application อื่น
4. กด `Command + P`
5. เลือก Canon PIXMA G2010
6. ตั้งค่าการพิมพ์และกด Print

**Critical Requirement:** ต้องพิมพ์ได้โดยไม่จำเป็นต้องเปิดแอป SwiftUI ของโปรเจกต์

ต้องใช้ระบบ Print Queue ของ macOS โดยรองรับตัวเลือกที่ Hardware สามารถทำได้ เช่น Paper Size, Color/Grayscale, Print Quality และ Copies

### B. Scanner Application

พัฒนา Native macOS Application ด้วย SwiftUI เพื่อควบคุมการสแกนและจัดการเอกสาร

Required Features:

- Scan ผ่าน USB
- เลือก Resolution และ Color Mode
- Scan Preview
- Multi-page Scan Session
- เพิ่มหน้าสแกนโดยไม่ต้อง Save ทีละหน้า
- หมุนหน้าเอกสาร
- ลบหน้า
- ย้ายและเรียงลำดับหน้าด้วย Drag & Drop
- สแกนใหม่เพื่อแทนที่หน้าที่เลือก
- Undo/Redo
- Export เป็น PDF หลายหน้า
- Export เป็น PNG/JPEG
- Session Recovery เมื่อแอปปิดโดยไม่ตั้งใจ

Canon G2010 เป็น Flatbed Scanner ไม่มี ADF จึงต้องเปลี่ยนกระดาษด้วยตัวเองทีละหน้า แต่แอปต้องรองรับการรวมทุกหน้าเป็นเอกสารชุดเดียว

### C. Print Workspace

ภายในแอปควรมีหน้าสำหรับ:

- Drag & Drop PDF/Images
- Document Preview
- เลือก Printer และ Print Settings
- ส่งงานเข้าระบบ Print Queue ของ macOS

ไม่สร้างระบบ Print Queue ที่แยกจาก macOS

### D. Deferred Features

ยังไม่ต้อง Implement:

- Wi-Fi / Network Printing
- Remote Printing
- Cloud Printing
- Ink Level Monitoring
- OCR
- Advanced Printer Maintenance

ให้รองรับ USB อย่างสมบูรณ์ก่อน

---

## 3. Technical Architecture

แยกระบบออกเป็นส่วนหลักดังนี้

### Printer Subsystem

- macOS Printing System
- CUPS / Local IPP Printer Application ตามแนวทางที่เหมาะสม
- Print Backend Abstraction
- Print Data Rendering / Raster Encoding
- Printer Protocol
- USB Transport
- Print Job Lifecycle

### Scanner Subsystem

- SANE / sane-pixma
- Scanner Backend Adapter
- Scan Service
- Image Processing
- Multi-page Session Management

### Desktop Application

- SwiftUI
- AppKit
- PDFKit
- Document Management
- Print Workspace
- Scan Workspace

ควรออกแบบ Backend ให้แยกจาก UI เพื่อสามารถเปลี่ยน Implementation และเพิ่มการรองรับ Printer รุ่นอื่นได้ในอนาคต

ไม่จำเป็นต้องเขียนทุก Component ด้วย Swift หาก C/C++ หรือ Library อื่นเหมาะกับงาน Low-Level มากกว่า

---

## 4. Existing Solutions to Investigate

### Printing

**Canon G2000 CUPS Driver**

Canon มี Driver สำหรับ G2000 บน macOS แต่ไม่ได้ระบุรองรับ G2010 โดยตรง ต้องทดสอบ Compatibility จริง ห้ามสรุปว่าใช้งานได้โดยไม่ทดลอง

**Gutenprint**

Open-source Printer Driver ที่มี Implementation สำหรับ Canon PIXMA หลายรุ่น

ศึกษาว่ามี Raster Encoder หรือส่วนของ Printer Protocol ที่นำมาใช้ต่อได้หรือไม่

**Other Open-source Projects**

ศึกษาโครงการอย่าง pixma-rs และ Printer Backend สำหรับ PIXMA รุ่นใกล้เคียง โดยตรวจว่ารองรับ USB และ G2010 จริงหรือไม่

### Scanning

**SANE / sane-pixma**

ฐานข้อมูล SANE ระบุ Canon PIXMA G2010 Series โดยมี USB ID ที่รายงานเป็น:

- Vendor ID: `0x04A9`
- Product ID: `0x183A`

ให้ใช้เป็น Candidate หลักสำหรับ Scanner Backend แต่ยังต้องทดสอบการทำงานบน macOS จริง

### Selection Strategy

1. Reuse — ใช้ Implementation ที่มีอยู่
2. Integrate — เชื่อมเข้ากับระบบของเรา
3. Adapt — ปรับเฉพาะส่วนที่ไม่เข้ากัน
4. Implement — พัฒนาส่วนที่ยังขาด
5. Reverse Engineer — ศึกษา Protocol เมื่อไม่มีทางเลือกที่ใช้ได้

---

## 5. Development Roadmap

แบ่งงานเป็น 6 Epics รวม 29 Planned Tasks และ 3 Conditional R&D Tasks

รหัสต่อไปนี้เป็นรหัสสำหรับวางแผน ยังไม่ใช่หมายเลข GitHub Issues จริง

### Epic 00 — Research & Hardware Validation

- R-01: Define macOS Support & Architecture Baseline
- R-02: Investigate USB Device Enumeration
- R-03: Validate G2010 Scanning with SANE
- R-04: Evaluate Existing Printer Drivers
- R-05: Research Printing Protocol & Licensing
- R-06: Document Technical Findings & Implementation Decision

### Epic 01 — System Printing

- P-01: Implement Print Backend Abstraction
- P-02: Integrate Printer with macOS Print System
- P-03: Implement Printing Options
- P-04: Implement Print Job Lifecycle & Error Handling
- P-05: Validate End-to-End System Printing

### Epic 02 — Scanner Engine

- S-01: Integrate SANE Scanner Backend
- S-02: Implement Scanner Configuration
- S-03: Implement Asynchronous Scan Operations
- S-04: Implement Multi-Page Scan Sessions
- S-05: Handle Scanner Disconnection & Recovery

### Epic 03 — Document Management

- D-01: Design Document & Page Data Model
- D-02: Implement Page Thumbnails & Preview
- D-03: Implement Page Editing & Reordering
- D-04: Implement Rescan & Page Replacement
- D-05: Implement PDF & Image Export

### Epic 04 — macOS Application

- U-01: Implement Native macOS Application Shell
- U-02: Implement Drag-and-Drop Print Workspace
- U-03: Implement Settings, Feedback & Accessibility

### Epic 05 — Quality & Distribution

- Q-01: Configure CI & Automated Tests
- Q-02: Build Mock Devices & Test Fixtures
- Q-03: Implement Setup, Installation & Uninstallation
- Q-04: Prepare Signing, Notarization & License Compliance
- Q-05: Complete Hardware QA, Documentation & Release

### Conditional R&D

ทำเมื่อไม่พบ Driver/Backend ที่นำมาใช้ได้ หรือยังมีความสามารถที่ขาดอยู่:

- RD-01: Investigate G2010 USB Printing Protocol
- RD-02: Prototype Minimal Raster Printing
- RD-03: Implement & Validate Native Print Encoder

---

## 6. Current Hardware Testing Status

### Hardware

- MacBook Pro M1 Pro
- Canon PIXMA G2010
- USB Printer Cable
- USB-A to USB-C Adapter
- เครื่องพิมพ์เชื่อมต่อกับ Mac แล้ว

### Completed Test

ผู้ใช้รัน:

```bash
system_profiler SPUSBDataType
```

ผลลัพธ์:

```text
(No output)
```

**Important Finding:**

ยังสรุปไม่ได้ว่า Mac ตรวจไม่พบ Canon G2010

เนื่องจาก macOS Tahoe 26 เปลี่ยน USB Data Type เป็น `SPUSBHostDataType` และคำสั่งเดิมอาจไม่แสดงผล

ยังไม่มีข้อมูลยืนยัน macOS Version ปัจจุบันจากเครื่องจริง

### Tests Not Yet Completed

- Verify macOS version
- Detect USB device using correct Data Type
- Inspect Vendor ID / Product ID
- Check CUPS USB discovery
- Check installed printer queues
- Install/test SANE
- Perform actual scan
- Perform actual print

ยังไม่มีหลักฐานยืนยันว่าพิมพ์หรือสแกนได้สำเร็จ

---

## 7. Immediate Next Steps — Hardware Diagnostics

**Priority: P0**

เริ่มจาก USB Detection ก่อน อย่าเพิ่งเขียน Driver หรือพัฒนา UI

### Step 1 — Identify macOS Version

```bash
sw_vers
```

### Step 2 — Identify USB Data Type

```bash
system_profiler -listDataTypes | grep -i USB
```

หากมี `SPUSBHostDataType` ให้ใช้:

```bash
system_profiler SPUSBHostDataType
```

### Step 3 — Inspect USB Registry

```bash
ioreg -p IOUSB -l -w0
```

ค้นหา Canon, G2010, PIXMA และ USB Vendor/Product IDs

### Step 4 — Inspect CUPS

```bash
lpinfo -v
lpstat -p -d
```

### Step 5 — Scanner Backend

ตรวจ Homebrew และ SANE ก่อน:

```bash
brew --version
brew list sane-backends
```

หากยังไม่มี SANE สามารถติดตั้งด้วย:

```bash
brew install sane-backends
```

แล้วทดสอบ:

```bash
sane-find-scanner
scanimage -L
```

หากตรวจพบ Scanner และตั้งค่าได้ถูกต้อง ให้ทดลองสแกนจริง:

```bash
scanimage --format=png --resolution 300 --output-file="$HOME/Desktop/g2010-test.png"
```

การสแกนจริงต้องมีผู้ใช้อยู่หน้าเครื่องและวางเอกสารบนกระจกก่อน

บันทึกผลลัพธ์ของแต่ละคำสั่งไว้สำหรับ Hardware Diagnostics โดยปกปิดข้อมูลส่วนตัวหรือ Serial Number ก่อนเผยแพร่สู่ Public Repository

---

## 8. Development Rules

1. อย่าสมมติว่า G2010 รองรับ Driver ของ G2000 โดยอัตโนมัติ
2. อย่าเขียน Driver ใหม่ตั้งแต่ต้นหากมี Implementation ที่นำมาใช้ได้
3. ใช้ Native macOS Printing System สำหรับ `Command + P`
4. อย่าผูก System Printing กับ SwiftUI Application
5. แยก Device Transport, Print Backend และ Application UI
6. ออกแบบให้สามารถเพิ่ม Network Backend ได้ในอนาคต แต่ยังไม่ Implement
7. ตรวจสอบ License ก่อนนำ Third-party Code มาใช้
8. ทดสอบ Hardware จริงก่อนอ้างว่าฟีเจอร์รองรับ
9. ใช้ Mock Device สำหรับ Automated Testing เมื่อไม่สามารถเชื่อม Hardware ได้
10. อย่าส่งคำสั่ง USB ที่ยังไม่เข้าใจหรือแก้ไข Firmware โดยไม่มีแผนทดสอบที่ปลอดภัย
11. ดำเนินงานเป็น Issues ขนาดเล็ก พร้อม Acceptance Criteria และ Tests
12. หลีกเลี่ยงการพัฒนา Feature ที่ไม่อยู่ใน MVP โดยไม่จำเป็น

---

## 9. First Deliverable for Codex

ให้ Codex เริ่มโดย:

1. Inspect Repository และยืนยันสถานะจริง
2. ตรวจสอบ Technical Architecture และ Roadmap
3. ดำเนินการ USB Hardware Diagnostics บน Mac ที่เชื่อมต่อ G2010 หากเข้าถึงเครื่องได้
4. วิเคราะห์ผลการตรวจ USB, CUPS และ SANE
5. จัดทำ Technical Findings
6. เสนอ Implementation Strategy สำหรับ Printer และ Scanner
7. ระบุว่าควร Reuse, Adapt หรือ Implement Component ใดบ้าง
8. เสนอ Issue แรกที่ควรเริ่ม Implement พร้อม Acceptance Criteria

**Current Priority:** USB Detection → Scanner Backend Validation → Existing Printer Driver Compatibility → System Printing Integration

อย่าเพิ่งสร้าง GitHub Issues จำนวนมากหรือ Implement Driver ทั้งระบบโดยไม่มีผล Hardware Diagnostics

เป้าหมายแรกคือพิสูจน์เส้นทางการเชื่อมต่อกับ Canon G2010 แล้วใช้ผลจริงตัดสินใจด้าน Architecture

---

## 10. Project Success Criteria

โปรเจกต์ v0.1 จะถือว่าสำเร็จเมื่อ:

- Canon G2010 เชื่อมต่อผ่าน USB บน macOS ได้
- เครื่องพิมพ์ถูกติดตั้งในระบบ macOS
- พิมพ์จากแอปอื่นผ่าน `Command + P` ได้จริง
- การพิมพ์ไม่ต้องเปิดแอป SwiftUI
- สามารถสแกนเอกสารผ่านแอปได้
- สแกนเอกสารหลายหน้าเป็น Session เดียวได้
- หมุน ลบ ย้าย เรียง และแทนที่หน้าสแกนได้
- Export PDF หลายหน้าได้ถูกต้อง
- มีวิธีติดตั้งและถอนการติดตั้งที่ใช้งานได้
- มีการทดสอบและ Documentation เพียงพอสำหรับพัฒนาต่อ

**Overall Goal:** Make Canon PIXMA G2010 function as a usable macOS printer and scanner, reusing existing software wherever practical and implementing only the missing components.