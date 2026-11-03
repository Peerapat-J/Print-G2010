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
```

พิมพ์ทุกครั้ง:

```sh
scripts/g2010-print "/path/to/file.pdf"
scripts/g2010-print -n 2 file.pdf          # 2 ชุด
scripts/g2010-print --dry-run file.pdf     # แปลงอย่างเดียว ไม่ส่งเครื่อง
```

เอกสาร Word/Pages: ส่งออกเป็น PDF ก่อน (File > Export As > PDF) แล้วพิมพ์ PDF นั้น สคริปต์ไม่เปิด Word เอง เพราะ Word ที่ sandbox จะขึ้นหน้าต่าง "Grant File Access" ถ้าต้องเขียนไฟล์นอกโฟลเดอร์ของมัน

ข้อควรรู้: ใส่กระดาษ A4 (ค่าเริ่มต้น `-p A4`), ความละเอียด 600 dpi, สี ยังไม่มีตัวเลือกขาวดำ/คุณภาพ

## ที่ยังไม่ได้ทำ

- ติดตั้งตัวกรอง Gutenprint ลงระบบ (ต้อง sudo) เพื่อพิมพ์จาก Command+P ได้ ตัวกรองต้องอยู่ในที่ที่ cupsd อ่านได้ (เช่น `/Library/Printers/...`) และคิวใหม่ควรใช้ PPD จาก `build/ppd`
- ตรวจคุณภาพ ขอบกระดาษ สี และหลายหน้า/สองหน้า
- สแกน ยังทำผ่าน SANE ได้ตามเอกสารวิจัยเดิม ยังไม่รวมเป็นแอป
- ลบ Gutenprint 5.3.3 (Intel) ที่ติดตั้งไว้ที่ `/Library/Printers/Gutenprint.printerDriver` ใช้ `uninstall-gutenprint.command` จาก dmg
