<p align="center">
  <img src="docs/images/app-icon.png" width="128" alt="Print G2010 app icon">
</p>

<h1 align="center">Print G2010</h1>

<p align="center"><b>สั่งพิมพ์ Canon PIXMA G2010 บน Mac ชิป Apple</b></p>

<p align="center"><i>เพิ่มไฟล์ เลือกหน้า แล้วพิมพ์ กองกระดาษเรียงถูกต้อง</i></p>

<p align="center">
  <img src="https://img.shields.io/badge/App-v1.0.0-8250df" alt="App: v1.0.0">
  <img src="https://img.shields.io/badge/macOS-14%2B-555555?logo=apple&logoColor=white" alt="macOS: 14+">
  <img src="https://img.shields.io/badge/Hardware-Apple%20silicon-6e56cf?logo=apple&logoColor=white" alt="Hardware: Apple silicon">
  <img src="https://img.shields.io/badge/Printer-Canon%20G2010-c1121f" alt="Printer: Canon G2010">
  <img src="https://img.shields.io/badge/Price-Free%20to%20use-2da66b" alt="Price: Free to use">
  <img src="https://img.shields.io/badge/Printing-Gutenprint-2f6fed" alt="Printing: Gutenprint">
</p>

<p align="center"><a href="#app">แอป</a> · <a href="#how">ทำงานอย่างไร</a> · <a href="#build">สร้างและรัน</a> · <a href="#share">แจกแอป</a> · <a href="#limits">ข้อจำกัด</a> · <a href="#license">สัญญาอนุญาต</a></p>

<p align="center"><a href="README.md">English</a> &nbsp;|&nbsp; <b>ภาษาไทย</b></p>

---

สั่งพิมพ์ **Canon PIXMA G2010** จาก Mac Canon ไม่มีไดรเวอร์สำหรับเครื่องรุ่นนี้บน macOS รุ่นใหม่
และไดรเวอร์ G2000 ของ Canon ค้างบน Mac ชิป Apple โปรเจกต์นี้พิมพ์ผ่าน
[Gutenprint](https://gutenprint.sourceforge.io/) ที่คอมไพล์เองสำหรับชิป Apple และห่อด้วยแอปเล็กๆ ชื่อ
**Print G2010**

สถานะ (3 พ.ย. 2026): **พิมพ์ได้แล้ว** บน MacBook Pro M1 Pro macOS 27.2 ต่อ G2010 ด้วยสาย USB
ส่วนการสแกนเคยทดลองสำเร็จ (SANE, 300 DPI) แต่ยังไม่อยู่ในแอป

<a id="app"></a>

## แอป

Print G2010 เป็นหน้าต่างเดียว:

- เพิ่มไฟล์ PDF รูปภาพ หรือข้อความด้วย **Add Files…** หรือลากมาวางที่หน้าต่าง
- ติ๊กไฟล์ที่ต้องการแล้วกด **Print Selected** หรือกดปุ่มเครื่องพิมพ์ที่ไฟล์นั้นเพื่อเลือกจำนวนชุดและหน้า
  (ทุกหน้า เลขคี่ เลขคู่ หรือระบุเอง เช่น `1, 3, 5-9`)
- ลากแถวเพื่อสลับลำดับการพิมพ์ ไฟล์จะพิมพ์เป็นคิว แต่ละไฟล์มีป้ายสถานะ
  (Queued, Printed 2/5 pages, Printed, Failed) และแถบสถานะบอกความคืบหน้าของเครื่องพิมพ์
- ป้ายสถานะเครื่องพิมพ์บอกว่าพร้อม กำลังทำงาน ปิดอยู่ หรือยังไม่มีคิวพิมพ์
- **Print last page first** (เปิดไว้เป็นค่าเริ่มต้น): G2010 ปล่อยกระดาษหงายหน้าขึ้น การพิมพ์จากหน้าสุดท้ายก่อน
  ทำให้กองกระดาษเรียงหน้า 1 อยู่บนสุด
- เอกสาร Word, Pages และไฟล์ Office อื่นต้องส่งออกเป็น PDF ก่อน

แอปมีทุกอย่างในตัว: สคริปต์พิมพ์ เครื่องมือแยกหน้า Gutenprint และไฟล์อธิบายเครื่องพิมพ์ จึงรันได้โดยไม่ต้องมี
repository นี้ และหาคิวพิมพ์ของ G2010 เอง

<a id="how"></a>

## ทำงานอย่างไร

```
PDF / รูปภาพ / ข้อความ
  → PDF แยกทีละหน้า                         (tools/pdf-tool, PDFKit)
  → CUPS raster                             (cupsfilter, ตัวกรองของ Apple)
  → คำสั่งเครื่องพิมพ์                        (Gutenprint, โปรไฟล์ "Canon G2000 series")
  → งาน CUPS แบบ raw หนึ่งงานต่อหน้า         (lp -o raw → USB backend → เครื่องพิมพ์)
```

การส่งแบบ raw ข้ามตัวกรองของคิวพิมพ์ ซึ่งเป็นจุดที่ไดรเวอร์ Canon ค้าง และการส่งทีละหน้าทำให้แอปนับได้ว่า
เครื่องรับไปกี่หน้าแล้ว G2010 (USB ID `04a9:183a`) ไม่อยู่ในชุดไดรเวอร์ G2000 ของ Canon แต่ device ID ระบุชุดคำสั่งเดียวกัน
(`BJRaster3`) และโปรไฟล์ G2000 ของ Gutenprint พิมพ์ได้ ส่วน Gutenprint ระบุว่ารุ่น Canon G-series ยังเป็นรุ่นทดลอง

## สิ่งที่ต้องมี

ใช้แอป: Mac **ชิป Apple** **macOS 14 ขึ้นไป** ต่อ G2010 ด้วยสาย USB และเพิ่มเครื่องพิมพ์ครั้งเดียวใน
System Settings → Printers & Scanners (ไดรเวอร์อะไรก็ได้ แอปแปลงข้อมูลเอง)

สร้างแอป: Xcode, Homebrew, และ `pkgconf` กับ `xcodegen` จาก Homebrew ทดสอบเฉพาะ macOS 27.2 กับ Xcode 27.2

<a id="build"></a>

## สร้างและรัน

```sh
brew install pkgconf xcodegen
scripts/build-gutenprint.sh     # ครั้งแรก: ดาวน์โหลดและคอมไพล์ Gutenprint 5.3.5 ไว้ใน build/
scripts/build-app.sh            # สร้าง build/Print G2010.app
open "build/Print G2010.app"
```

ถ้าไม่ใช้แอป พิมพ์จาก Terminal:

```sh
scripts/g2010-print file.pdf
scripts/g2010-print -n 2 --pages 1,3,5-9 file.pdf     # จำนวนชุด, หน้า (หรือ odd / even)
scripts/g2010-print --dry-run file.pdf                # แปลงอย่างเดียว ไม่ส่งเครื่องพิมพ์
```

`G2010_DRY_RUN=1 "build/Print G2010.app/Contents/MacOS/Print G2010" --selftest file.pdf` รันโค้ดพิมพ์ของแอป
โดยไม่ใช้เครื่องพิมพ์และกระดาษ

<a id="share"></a>

## แจกแอปให้คนอื่น

`scripts/make-dmg.sh` สร้าง `dist/PrintG2010-<เวอร์ชัน>.dmg` มีแอป ทางลัด Applications และ Read Me
ถ้าจะให้เครื่องอื่นเปิดได้โดยไม่มีคำเตือน ต้องเซ็นแอปด้วย Developer ID และ notarize
(`NOTARY_PROFILE=<โปรไฟล์ notarytool> scripts/make-dmg.sh` วิธีตั้งค่าครั้งแรกอยู่ที่หัวสคริปต์)
ถ้าไม่ทำ เครื่องอื่นจะขึ้น "Apple could not verify…" และผู้ใช้ต้องกด Open Anyway ครั้งเดียว
(Read Me ในไฟล์ DMG อธิบายไว้)

## โครงสร้าง repository

| พาธ | คืออะไร |
| --- | --- |
| `app/` | แอป SwiftUI, Info.plist และ asset catalog |
| `tools/pdf-tool/` | เครื่องมือบรรทัดคำสั่งแยก PDF เป็นรายหน้า |
| `scripts/g2010-print` | ขั้นตอนพิมพ์ |
| `scripts/build-gutenprint.sh` | ดาวน์โหลด ตรวจสอบ และคอมไพล์ Gutenprint สำหรับชิป Apple |
| `scripts/build-app.sh`, `make-dmg.sh` | สร้างแอป และแพ็กเกจสำหรับแจก |
| `scripts/xcode-bundle-helpers.sh` | build phase ของ Xcode ที่ใส่ตัวช่วยเข้าไปในแอป |
| `project.yml`, `PrintG2010.xcodeproj` | โปรเจกต์ Xcode (สร้างจาก `project.yml` ด้วย XcodeGen) |
| `docs/` | บันทึกและงานวิจัย **ภาษาไทย** |

<a id="limits"></a>

## ข้อจำกัดตอนนี้

- ใช้ได้เฉพาะ Mac ชิป Apple และ macOS 14 ขึ้นไป
- ยังพิมพ์จากหน้าต่าง Print ปกติ (⌘P) ไม่ได้ ใช้แอปหรือสคริปต์แทน
- ยังไม่ได้ตรวจคุณภาพงานพิมพ์ ขอบกระดาษ และสีอย่างละเอียด และยังไม่มีตัวเลือกขาวดำหรือคุณภาพ
- ยังไม่มีสแกนในแอป
- ยังไม่เคยลองบน Mac เครื่องที่สอง

## เอกสาร

- [การพิมพ์บน G2010: ลองอะไรไปบ้าง อะไรใช้ได้ ใช้อย่างไร](docs/printing-g2010.md)
- บันทึกวิจัยจากการทดลองช่วงแรก: [handoff](docs/project-handoff.md),
  [R-01 / R-02](docs/research/2026-10-30-r01-r02.md),
  [R-03 / R-04](docs/research/2026-10-30-r03-r04-hardware.md),
  [แก้ปลายทางคิวพิมพ์](docs/research/2026-10-30-print-queue-uri.md),
  [งานทดสอบถัดไป](docs/research/next-hardware-task.md),
  [roadmap ที่รีวิวแล้ว](docs/research/reviewed-roadmap.md)

ผลของบางคำสั่งระบบมีหมายเลขซีเรียลของเครื่องพิมพ์ ควรลบก่อนเผยแพร่ log

<a id="license"></a>

## สัญญาอนุญาต

แอปแนบ [Gutenprint](https://gutenprint.sourceforge.io/) 5.3.5 ซึ่งเป็นซอฟต์แวร์เสรีภายใต้ GNU General Public
License (เวอร์ชัน 2 ขึ้นไป) `scripts/build-gutenprint.sh` ดาวน์โหลดซอร์สต้นฉบับที่ไม่ได้แก้ไขจาก SourceForge
และตรวจ SHA-256 จึงหาซอร์สของไบนารีที่แนบได้จากที่นั่น Print G2010 ไม่เกี่ยวข้องกับ Canon หรือโครงการ
Gutenprint "Canon" และ "PIXMA" เป็นเครื่องหมายการค้าของเจ้าของ

© 2026 Peerapat Jardrit
