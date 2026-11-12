# พิมพ์ Canon G2010 บน macOS 27 (Apple Silicon) ด้วย Gutenprint

สถานะ 3 พ.ย. 2026: **พิมพ์ออกจริงแล้ว** (เอกสาร A4 3 หน้า) ผ่านคำสั่ง `scripts/g2010-print` ยังพิมพ์จากเมนู Print ของแอปไม่ได้ และยังไม่ได้ตรวจคุณภาพ ขอบ หรือสี

## สิ่งที่ทำและผล

| ลำดับ | ทำอะไร | ผล |
| --- | --- | --- |
| 1 | ไดรเวอร์ Canon G2000 v16.80 (ติดตั้งอยู่เดิม) | งานค้าง "Printing" ไม่มีกระดาษออก |
| 2 | ไดรเวอร์ Canon G2000 v16.91 (ติดตั้งใหม่) | ผลเหมือนเดิม; ตัวกรองหลักเหมือน v16.80 ทุกไบต์ ฐานข้อมูลรุ่นไม่มี G2010 (`04a9:183a`) |
| 3 | Gutenprint 5.3.3 แบบสำเร็จรูป | ใช้ไม่ได้: ตัวกรองเป็น Intel อย่างเดียว ต้องมี Rosetta ซึ่งไม่ได้ติดตั้ง |
| 4 | คอมไพล์ Gutenprint 5.3.5 เป็น arm64 เอง | สำเร็จ ต้องใส่ `-D_DARWIN_C_SOURCE` |
| 5 | แปลง PDF เป็นข้อมูลพิมพ์ แล้วส่งเป็น raw job | **พิมพ์ออกจริง** งานจบใน ~50 วินาที |

ข้อสังเกต: งานที่ผ่านไดรเวอร์ Canon ไม่เคยจบ แต่งานข้อมูลจาก Gutenprint ผ่านคิวเดิมและสาย USB เดิมจบ จึงไม่น่าใช่ปัญหาสายหรือตัวเครื่อง

## Driver ที่ใช้ตอนนี้

- **Gutenprint 5.3.5** รุ่นโปรไฟล์ "Canon G2000 series" (`bjc-G2000-series`) ซึ่งเป็นรุ่นใกล้ G2010 ที่สุดในรายการ ไม่มี G2010 โดยตรง และ Gutenprint ติดป้าย Canon รุ่นตระกูล G ว่า EXPERIMENTAL
- Gutenprint เป็นชุดไดรเวอร์โอเพนซอร์ส (GPL) ประกอบด้วย **ไลบรารี** (`libgutenprint`) ที่แปลงภาพเป็นคำสั่งเฉพาะของเครื่องพิมพ์ กับ **ตัวกรอง CUPS** (`rastertogutenprint`) และตัวสร้าง PPD (`cups-genppd`) ที่ผูกไลบรารีเข้ากับระบบพิมพ์ ไม่ใช่แอป
- ไม่ได้ใช้ไดรเวอร์ Canon เลยในขั้นตอนพิมพ์: งานถูกส่งแบบ raw ข้ามตัวกรองของ Canon ในคิว

## ขั้นตอนข้อมูล

```
PDF -> (cupsfilter / Apple cgpdftoraster) CUPS raster
    -> rastertogutenprint (Gutenprint, arm64, ใช้ PPD G2000)
    -> คำสั่ง Canon IVEC/BJRaster3
    -> lp -o raw -> คิว Canon_G2010_series -> USB backend -> เครื่อง
```

## วิธีใช้

ครั้งแรก (ต้องมี Xcode command line tools และ Homebrew):

```sh
brew install pkgconf
scripts/build-gutenprint.sh      # ~2 นาที ผลอยู่ใน build/ (ไม่ commit)
scripts/build-sane.sh            # ส่วนสแกน: libusb + SANE (เฉพาะ backend pixma) ผลอยู่ใน build/sane/
```

พิมพ์ทุกครั้ง:

```sh
scripts/g2010-print "/path/to/file.pdf"
scripts/g2010-print -n 2 file.pdf          # 2 ชุด
scripts/g2010-print --dry-run file.pdf     # แปลงอย่างเดียว ไม่ส่งเครื่อง
scripts/g2010-print --pages 1,3,5-9 file.pdf  # เฉพาะบางหน้า (หรือ odd / even)
```

แบบกดเลือกไฟล์ (ไม่ต้องพิมพ์คำสั่ง):

```sh
scripts/build-app.sh             # สร้าง build/Print G2010.app (ต้องมี Xcode และ `brew install xcodegen`)
```

เปิด `build/Print G2010.app` จะได้หน้าต่างเดียว: กด "Add Files…" หรือลาก PDF/รูปมาวาง ไฟล์ที่เพิ่มจะถูกติ๊กไว้ทุกไฟล์

- **Print Selected (ปุ่มใหญ่สีฟ้า):** ปุ่มเดียวที่สั่งพิมพ์ พิมพ์ไฟล์ที่ติ๊กไว้ เรียงจากบนลงล่าง โดยแต่ละไฟล์ใช้จำนวนชุดและหน้าของตัวเอง ลากแถวขึ้นลงเพื่อเปลี่ยนลำดับ (เมาส์เป็นรูปมือเมื่อชี้ที่ไอคอน/ชื่อไฟล์ ซึ่งเป็นส่วนที่จับลากได้) ไฟล์ที่พิมพ์เสร็จจะถูกติ๊กออกอัตโนมัติ (ติ๊กอยู่ = ยังต้องพิมพ์) ถ้าต้องการพิมพ์ซ้ำให้ติ๊กกลับ
- **ป้ายตั้งค่าที่บรรทัดล่างของแต่ละไฟล์:** เช่น `1 copy · All pages` หรือ `2 copies · Pages 3-5` (สีเทา = ค่าเริ่มต้น สีน้ำเงิน = เปลี่ยนไปจากค่าเริ่มต้น) กดป้ายเพื่อเปิดหน้าต่างเล็กแก้ Copies และ Pages (All / Odd / Even / Custom เช่น `1, 3, 5-9` หรือ `8`) กด Done เพื่อบันทึก ยังไม่พิมพ์ ถ้าเป็น PDF แอปบอกจำนวนหน้าและเตือนเมื่อระบุหน้าเกิน ค่าที่ตั้งไว้จะค้างอยู่หลังพิมพ์เสร็จ เพื่อพิมพ์ซ้ำแบบเดิมได้
- **คิว:** กดพิมพ์เพิ่มระหว่างที่เครื่องกำลังพิมพ์ได้ ไฟล์ที่เพิ่มเข้ามาจะขึ้นป้าย "Queued" แล้วพิมพ์ต่อตามลำดับ ถ้าไฟล์ใดพิมพ์ไม่สำเร็จ คิวที่เหลือจะถูกยกเลิกเพื่อไม่ให้ป้อนงานต่อเมื่อเครื่องมีปัญหา
- **ป้ายสถานะที่ไฟล์:** "Queued" (น้ำเงิน) → "Printed 2/5 pages" (ส้ม) → "✓ Printed" (เขียว) หรือ "Failed" (แดง) แถบด้านล่างบอกความคืบหน้าของไฟล์ที่กำลังพิมพ์
- หน้าต่างไม่ปิดเอง
- ข้อความในแอปทั้งหมดเป็นภาษาอังกฤษ

แอปเรียก `scripts/g2010-print` ข้างใน และเก็บสคริปต์ เครื่องมือแยกหน้า Gutenprint และ PPD ไว้ใน `Contents/Resources/g2010` ของตัวแอปเอง จึงย้ายแอปไปที่อื่นหรือเครื่องอื่นได้โดยไม่ต้องมี repo แอปหาคิวพิมพ์ของ G2010 เองจากชื่ออุปกรณ์ (`lpstat -v`) ไม่ต้องตั้งชื่อคิวเฉพาะ ครั้งแรกที่เปิดไฟล์ใน Downloads หรือ Documents macOS อาจถามขอสิทธิ์เข้าถึงโฟลเดอร์ ให้กดอนุญาต

ทดสอบแอปโดยไม่ใช้กระดาษ: `G2010_DRY_RUN=1 "build/Print G2010.app/Contents/MacOS/Print G2010" --selftest file.pdf`

เอกสาร Word/Pages: ส่งออกเป็น PDF ก่อน (File > Export As > PDF) แล้วพิมพ์ PDF นั้น สคริปต์ไม่เปิด Word เอง เพราะ Word ที่ sandbox จะขึ้นหน้าต่าง "Grant File Access" ถ้าต้องเขียนไฟล์นอกโฟลเดอร์ของมัน

ข้อควรรู้: ใส่กระดาษ A4 (ค่าเริ่มต้น `-p A4`), ความละเอียด 600 dpi, สี ยังไม่มีตัวเลือกขาวดำ/คุณภาพ

## ที่ยังไม่ได้ทำ

- ติดตั้งตัวกรอง Gutenprint ลงระบบ (ต้อง sudo) เพื่อพิมพ์จาก Command+P ได้ ตัวกรองต้องอยู่ในที่ที่ cupsd อ่านได้ (เช่น `/Library/Printers/...`) และคิวใหม่ควรใช้ PPD จาก `build/ppd`
- ตรวจคุณภาพ ขอบกระดาษ สี และหลายหน้า/สองหน้า
- สแกน: มีหน้า Scan ในแอปแล้ว (ดูหัวข้อสแกนด้านล่าง) ที่ยังไม่ได้ทำ: ตัวอย่างก่อนสแกนจริง และปุ่มส่งหน้าที่สแกนไปพิมพ์ต่อ
- ลบ Gutenprint 5.3.3 (Intel) ที่ติดตั้งไว้ที่ `/Library/Printers/Gutenprint.printerDriver` ใช้ `uninstall-gutenprint.command` จาก dmg

## โปรเจกต์ Xcode และการแจกให้คนอื่น

- `project.yml` คือไฟล์ต้นทางของโปรเจกต์ Xcode (ใช้ XcodeGen) ส่วน `PrintG2010.xcodeproj` กับ `app/Info.plist` สร้างจากมันแล้ว commit ไว้เพื่อเปิดใน Xcode ได้เลย แก้ `project.yml` แล้วรัน `xcodegen` เพื่อสร้างใหม่ (`scripts/build-app.sh` ทำให้เองถ้ามี xcodegen)
- มี 2 target: `pdf-tool` (เครื่องมือแยกหน้า PDF จาก `tools/pdf-tool`) และ `PrintG2010` (ตัวแอป จาก `app/`) phase "Bundle helpers" (`scripts/xcode-bundle-helpers.sh`) คัดลอกของที่แอปต้องใช้เข้าไปใน `.app` ต้องรัน `scripts/build-gutenprint.sh` และ `scripts/build-sane.sh` ก่อนอย่างน้อยหนึ่งครั้ง (ถ้าไม่มี build/sane/ phase นี้จะหยุดพร้อมข้อความบอก)
- ค่าเริ่มต้นแอปเซ็นแบบ ad-hoc (ใช้ได้เฉพาะเครื่องนี้) ไม่ใช้ sandbox (ต้องเรียกโปรเซสอื่น) และรองรับเฉพาะ Mac ชิป Apple (arm64) macOS 14 ขึ้นไป เพราะ Gutenprint ที่แนบไปคอมไพล์เป็น arm64 อย่างเดียว
- ไอคอนสร้างด้วย `swift scripts/make-icon.swift` (ผลอยู่ใน `app/Assets.xcassets`)
- `scripts/make-dmg.sh` สร้าง `dist/PrintG2010-<เวอร์ชัน>.dmg` (หน้าต่างติดตั้งที่มีแอป ลูกศร และทางลัด Applications) เพื่อส่งให้เพื่อนร่วมงาน สร้างด้วย `dmgbuild` (ติดตั้งครั้งเดียวด้วย `pipx install dmgbuild`) หน้าต่างกำหนดใน `scripts/dmg/settings.py` และรูปพื้นหลังสร้างด้วย `swift scripts/make-dmg-background.swift`
- **เซ็นและ notarize เพื่อแจกให้เครื่องอื่น (ทำครั้งเดียว):**
  1. สร้างใบรับรอง "Developer ID Application" ใน Xcode: Settings > Accounts > เลือกทีม > Manage Certificates > + > Developer ID Application (ต้องเป็น Account Holder) ใบรับรอง "Apple Development" ใช้แจกคนอื่นไม่ได้ ต้องเป็น Developer ID ใบรับรองนี้ติดตั้งในเครื่องนี้แล้ว (ตรวจด้วย `security find-identity -v -p codesigning`) ถ้า Xcode สร้างไม่สำเร็จ ให้สร้างไฟล์ CSR ด้วย openssl แล้วขอใบรับรองที่ developer.apple.com แทน ถ้านำคีย์เข้า keychain ด้วย `security import` ต้องรัน `security set-key-partition-list` ด้วย ไม่เช่นนั้น `codesign` จะขึ้นหน้าต่างขอรหัสผ่านซ้ำๆ
  2. สร้าง app-specific password ที่ appleid.apple.com แล้วเก็บไว้ใน keychain: `xcrun notarytool store-credentials G2010-notary --apple-id <Apple ID> --team-id <Team ID>` (ระบบถามรหัสผ่านเอง)
  3. สร้างไฟล์แจก: `NOTARY_PROFILE=G2010-notary scripts/make-dmg.sh` สคริปต์จะเซ็นแอป (hardened runtime) ส่ง notarize ทั้งแอปและ DMG แล้ว staple ผลคือเครื่องอื่นเปิดได้โดยไม่มีคำเตือน
  - ถ้ายังไม่มีใบรับรองหรือข้อมูล notarize สคริปต์ยังสร้าง DMG ให้ แต่เครื่องอื่นจะเจอคำเตือน "could not verify" ผู้ใช้ต้องเปิดแอปด้วยตัวเลือก Open Anyway ใน System Settings > Privacy & Security หรือรันคำสั่ง `xattr -dr com.apple.quarantine "/Applications/Print G2010.app"`
  - ตรวจผลลัพธ์: `spctl --assess --type execute -vv "build/Print G2010.app"` ควรได้ `accepted` และ `source=Notarized Developer ID`
- `scripts/build-app.sh` เลือกใบรับรอง Developer ID ในเครื่องให้อัตโนมัติ หรือระบุเองด้วย `SIGN_IDENTITY="ชื่อใบรับรอง"` และบังคับเซ็นแบบ ad-hoc ด้วย `SIGN_IDENTITY=-`
- ที่ยังไม่ได้ทดสอบ: ติดตั้งจาก DMG บนเครื่องอื่นจริง และการเพิ่มคิวพิมพ์บนเครื่องที่ไม่เคยลง driver ของ Canon

## สแกน

- หน้าต่างหลักของแอปเปิดที่หน้า Home มีไอคอน Print กับ Scan ขนาดใหญ่ กรอบวางไฟล์ และแผงสถานะเครื่อง (`app/Home.swift`) กดไอคอนเพื่อเปลี่ยนหน้าในหน้าต่างเดิม (ไม่เปิดหน้าต่างใหม่) แล้วกด "‹ Home" (⌘[) เพื่อกลับ ⌘1 ไปหน้า Print ⌘2 ไปหน้า Scan ไฟล์ที่ลากมาวางบนหน้า Home หรือเปิดด้วยแอป (Dock, Open With) ข้าม Home ไปหน้า Print ทันที เริ่มที่ Home เสมอทุกครั้งที่เปิดแอป (ตั้ง `G2010_PAGE=print` หรือ `scan` เพื่อเปิดที่หน้านั้นตอนทดสอบ) หน้าต่างปรับขนาดเองตามหน้าที่เปิด: Home เล็กพอดีเนื้อหา Print และ Scan ใหญ่กว่า (`AppPage.contentSize` กับ `WindowSizer` ใน `app/Home.swift`) และยังลากปรับเองได้ โค้ดหน้าสแกนอยู่ใน `app/Scan.swift` (ตั้งค่า, เรียก scanimage, บันทึก PDF/PNG/JPEG/TIFF) และ `app/ScanView.swift` (หน้าตา)
- แอปเรียก `scanimage` ของ SANE เป็น process ย่อย ด้วย `--format=tiff` เก็บแต่ละหน้าเป็นไฟล์ TIFF ในโฟลเดอร์ชั่วคราว แล้วแปลงเป็น PDF/PNG/JPEG/TIFF ตอนกดบันทึก (PDF เลือกได้ว่ารวมไฟล์เดียวหรือแยกหน้าละไฟล์ TIFF บีบแบบ LZW) (ImageIO/CoreGraphics ของ macOS ไม่ต้องใช้เครื่องมือเพิ่ม) PDF แบบสีและเทาใช้ JPEG คุณภาพ 0.8 ข้างใน แบบขาวดำไม่บีบอัดแบบสูญเสียคุณภาพ ขนาดหน้า PDF ตรงกับกระดาษที่สแกน
- ปุ่มลูกศรขยายที่มุมของตัวอย่าง (หรือดับเบิลคลิกที่หน้า) เปิดหน้าต่างแยก "Scan Preview" (`app/ScanViewer.swift`) แสดงหน้าที่เลือกด้วยความละเอียดเต็มของไฟล์สแกน ซูมได้ (Fit, 100% = หนึ่งจุดสแกนต่อหนึ่งจุดหน้าจอ, ⌘+ ⌘−, pinch) เลื่อนดูได้ และกดลูกศรซ้าย/ขวาเปลี่ยนหน้า หน้าต่างนี้ตามหน้าที่เลือกในหน้าสแกน จึงเปิดค้างไว้ดูหน้าที่เพิ่งสแกนเสร็จได้
- `scripts/build-sane.sh` build libusb 1.0.30, libjpeg 10 (static) และ sane-backends 1.4.0 จากซอร์สโดยล็อก sha256 ตั้ง deployment target 14.0 เพราะ bottle ของ Homebrew ต้องใช้ macOS ใหม่สุด (libusb ของ Homebrew มี minos 27.0) เปิดเฉพาะ backend pixma แบบ `--enable-preload` ฝังใน scanimage เลย จึงต้องแนบแค่ `scanimage` และ `libusb-1.0.0.dylib` กับ `etc/dll.conf` `etc/pixma.conf` (ชี้ด้วย `SANE_CONFIG_DIR`) ต้องใส่ `-Wno-incompatible-function-pointer-types` เพราะ clang รุ่นใหม่ถือว่าตารางฟังก์ชันของ SANE เป็น error
- เครื่องพิมพ์กับสแกนเนอร์ใช้สาย USB เส้นเดียว แอปจึงไม่ให้ทำพร้อมกัน: สั่งสแกนตอนกำลังพิมพ์ หน้าสแกนรอให้คิวพิมพ์ว่างแล้วเริ่มเอง (กด Cancel ได้) และสั่งพิมพ์ตอนกำลังสแกน คิวพิมพ์รอให้สแกนเสร็จ (`ScanModel.run` กับ `PrintModel.drain`) การให้พิมพ์กับสแกนพร้อมกันจริงยังไม่เคยทดสอบ
- ทดสอบแล้วกับเครื่องจริง (กระจกวางกระดาษเปล่า) ผ่าน `--scan-selftest <โฟลเดอร์> <Color|Gray|Lineart> <dpi>`: Color/Gray 150 dpi, Lineart 300 dpi, Color 600 dpi (ตัดบางส่วน), บันทึกครบ 3 รูปแบบ, ยกเลิกกลางสแกนแล้วสแกนต่อได้ ยังไม่ได้ทดสอบ: ตัวหน้าต่างด้วยตา, sleep/wake, notarize แอปที่มี scanimage แนบ, การสแกนหลายหน้า
