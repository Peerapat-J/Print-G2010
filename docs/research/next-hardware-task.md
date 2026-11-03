# งานถัดไปที่เสนอ — ยังไม่ได้สร้าง GitHub Issues

**Printing first ตามคำขอล่าสุด:** พัก S-01/scanner development ไว้ก่อน ตรวจ [ผลแก้ USB URI ของคิว](2026-10-30-print-queue-uri.md) และยืนยัน output/Command+P ก่อนเลือกงาน implementation ฝั่ง printing ข้อเสนอ scanner ด้านล่างเป็นงานที่เก็บไว้ทำภายหลัง

R-04 follow-up พบ Canon filter crash ใน offline conversion และงานหลังแก้ URI ยังไม่มี output จริง ขั้นถัดไปคือผล nozzle-check จากตัวเครื่องและ debug log ของ scheduler หนึ่งงานโดยคืนค่า logging หลังตรวจ ก่อนประเมิน driver update ที่รองรับ OS ปัจจุบัน ยังไม่สรุปว่า G2010 ต้องใช้ driver ที่เขียนใหม่

**อัปเดตหลังทดสอบจริง:** [ผล R-03/R-04](2026-10-30-r03-r04-hardware.md) ยืนยัน SANE scan 300 DPI และ reconnect ผ่านแล้ว การทดลองพิมพ์ครั้งแรกติด offline ร่าง R-03 ด้านล่างเป็น checklist ของงานวิจัยที่ทำไปแล้วบางส่วน ไม่ควรเปิดซ้ำโดยไม่ปรับ scope งานถัดไปเน้น R-04 วิเคราะห์ failure, R-05 และร่าง S-01 ที่รอ license/integration decision

อ้างอิง [ผลตรวจ R-01/R-02 วันที่ 2026-10-30](2026-10-30-r01-r02.md) การเปิด issue วิจัยที่มีคำถามและเกณฑ์จบชัดเจนมีประโยชน์แม้ผลสุดท้ายจะเป็น “ใช้ไม่ได้” เพราะช่วยตัดทางเลือกโดยมีหลักฐาน แต่ยังไม่ควรเปิด backlog implementation ทั้งหมดก่อนผลพิมพ์/สแกนจริง

หลังทดสอบจริง: เสนอปรับ R-04 ให้เจาะสาเหตุ CUPS offline, ทำ R-05 ต่อ และร่าง S-01 ตามผล SANE ที่ผ่านแล้ว ดู [แผนฉบับปรับปรุง](reviewed-roadmap.md) รายการด้านล่างเก็บขอบเขต validation และสถานะหลักฐาน ยังไม่ได้ส่งไป GitHub

## R-03 — Validate G2010 USB scanning and select ICA or SANE backend

**คำถาม:** สามารถสแกน G2010 `04a9:183a` บน Mac นี้ด้วยเครื่องมือเดิมหรือ SANE pixma ได้หรือไม่ และ backend ใดเหมาะกับแอปที่จะพัฒนา?

**หลักฐานตั้งต้น:** USB และ CUPS ตรวจพบอุปกรณ์แล้ว; SANE/libusb formula ยังไม่ติดตั้ง ข้อมูล upstream ระบุรุ่นนี้ แต่ยังไม่มี local scan result

### ขั้นตอนที่เสนอสำหรับรอบถัดไป

0. ทดลอง Image Capture/Canon scanner utility ที่มีอยู่กับเอกสารทดสอบก่อน บันทึกผล ICA แยกต่างหาก ไม่ถือว่า package receipt พิสูจน์การรองรับ และไม่เปิดหลาย scanner client พร้อมกัน ถ้าใช้ได้ ให้ประเมิน native integration API ก่อนตัดสินใจเพิ่ม SANE; ถ้าไม่ต้องทดลอง SANE ต่อให้ระบุเหตุผลและข้อจำกัดชัดเจน
1. ติดตั้ง `sane-backends` ผ่าน Homebrew และบันทึก version ของ SANE/libusb, binary architecture และ options จริง ยังไม่ผูกกับแอป
2. ขณะเครื่องเปิดและต่อ USB รัน `sane-find-scanner` แล้ว `scanimage -L`; แยก “USB device พบ” ออกจาก “backend พบ scanner”
3. ใช้ device identifier ที่ค้นพบจริงและอ่าน options เช่น `scanimage -d '<device-id>' --help` ไม่เดาชื่อ device หรือยึด resolution จาก handoff
4. เมื่อผู้ใช้วางเอกสารทดสอบที่ไม่เป็นความลับบนกระจกและพร้อมแล้ว ทดลองสแกน PNG 300 DPI ด้วยค่าที่ backend รองรับ ตรวจไฟล์เปิดได้และภาพตรงกับเอกสารจริง
5. ทดสอบ scan ซ้ำและถอด/เสียบใหม่เมื่อไม่มีงานทำงาน ตรวจ discovery/scan อีกครั้ง เก็บเฉพาะผลสรุป/ภาพทดสอบที่ไม่มีข้อมูลส่วนตัว
6. ถ้าไม่ผ่าน บันทึก exit status, error, backend/library versions และแยก discovery, permissions, interface ownership หรือ protocol failure ก่อนเสนอวิธีแก้ ไม่ส่งคำสั่ง USB ที่เดาขึ้นเอง

คำสั่งสแกนด้านล่างเป็นเพียงตัวอย่างสำหรับรอบทดสอบ **ยังไม่ได้รัน** ต้องแทน device และยืนยันตัวเลือกจริงก่อน:

```sh
scanimage -d '<device-id-from-scanimage-L>' --format=png --resolution 300 --output-file='/tmp/g2010-test.png'
```

### Acceptance criteria

- [x] บันทึก OS, architecture, ผลทดสอบ ICA เดิม และ version ของ backend ที่ทดลองจริง
- [x] ถ้าทดลอง SANE: บันทึก SANE/libusb versions และผล USB finder/backend discovery แยกกัน พร้อม device ID ที่ปกปิด serial; หากไม่ทดลองให้ระบุเหตุผล
- [x] บันทึก options/resolutions ที่ scanner รายงานจริง
- [x] ถ้าสแกนได้: PNG 300 DPI เปิดได้ ภาพถูกต้อง และผู้ใช้ตรวจภาพแล้ว; บันทึกผลสแกนซ้ำ/reconnect
- [ ] ถ้าสแกนไม่ได้: มีขั้นทำซ้ำ error/exit status และขอบเขต blocker ที่ชัดเจน โดยไม่อ้างว่า integration พร้อม
- [ ] สรุป reuse/adapt/reject และงานถัดไป พร้อมระบุสิ่งที่ยังไม่ผ่าน

ผลเป็น “ไม่ผ่านพร้อมหลักฐาน” ถือว่าจบงานวิจัยนี้ได้ แต่ไม่ถือว่า scanner รองรับแล้ว

## R-04 — Validate the existing G2000 queue with G2010

**คำถาม:** คิว `Canon_G2010_series` ที่ใช้ G2000 PPD 16.80.0.0 พิมพ์บนเครื่องจริงได้หรือไม่?

1. เปิด Printers & Scanners และ Preview → Command+P ตรวจชื่อคิวที่มีอยู่ ไม่ reset ระบบพิมพ์และไม่ลบคิวอื่น
2. เมื่อผู้ใช้พร้อมและเตรียม A4 แล้ว ส่งเอกสารทดสอบหนึ่งหน้าจาก Preview โดยเลือก Canon คิวนี้อย่างชัดเจน เพราะเครื่องตั้ง default เป็น printer อื่น
3. ดู output จริงและสถานะงาน; ถ้าไม่ผ่านเก็บ error ของ job นั้นโดยปกปิดชื่อเอกสาร/ผู้ใช้/serial ก่อนพิจารณา update driver
4. ถ้าผ่าน ทดสอบ grayscale/color, ขนาดกระดาษ, copies และอีกแอปหนึ่งตามขอบเขตจำเป็น ไม่ถือว่าตัวเลือกใน PPD ทำงานได้ทั้งหมดโดยอัตโนมัติ
5. ทดสอบโดยไม่เปิดแอปของโครงการ และยืนยันข้อจำกัด/ขั้นติดตั้งซ้ำสำหรับผู้ใช้ใหม่

**Acceptance criteria:** มีผลจริงทั้ง job state และหน้ากระดาษ หรือ error ที่ทำซ้ำได้; บันทึก version และ queue/driver mapping; มีคำตัดสิน reuse/upgrade/research ต่อ ไม่สรุป compatibility จากคิว idle อย่างเดียว

ถ้ารอบแรกไม่ผ่าน ให้จบด้วยหลักฐานและเสนอการทดลองแยกที่เปลี่ยนทีละปัจจัย เช่น driver version ห้าม update driver แล้วรวมผลก่อน/หลังเป็นผลเดียว งานนี้ไม่จำเป็นต้องรอ R-03

## R-05 — Assess backend licensing and macOS distribution constraints

**คำถาม:** ทางเลือกจาก R-03/R-04 สามารถนำมาใช้ในแอปและส่งมอบให้ผู้ใช้อื่นอย่างไร โดยไม่สมมติว่าซอฟต์แวร์ที่ติดตั้งในเครื่องพร้อมแจกต่อ?

**ขอบเขต:** ตรวจเอกสาร/source ของ version ที่จะใช้ แยกใช้เครื่องมือภายนอก, linking, bundling และผู้ใช้ติดตั้ง dependency เอง บันทึกว่ามีอะไรทราบแล้ว/ต้องตรวจต่อ เปรียบเทียบการติดตั้งในเครื่องที่ไม่มี Canon software เดิม ยังไม่วิจัย protocol เชิงลึกถ้า backend เดิมอาจเพียงพอ

### Acceptance criteria

- [ ] มีตาราง candidate/version, upstream source, license/terms และวิธี integration ที่เสนอ
- [ ] แยกสิทธิ์ใช้ในเครื่องออกจากสิทธิ์แก้ไข/bundle/แจกจ่าย; รายการที่ยังไม่ชัดระบุเป็น blocker
- [ ] ประเมิน dependency installation, architecture, sandbox/helper/service และ signing/notarization ที่ต้องพิสูจน์ โดยไม่กล่าวว่าได้ทดสอบแล้ว
- [ ] มีแผน setup/uninstall ที่ไม่กระทบคิวหรือซอฟต์แวร์อื่น และวิธีทดสอบ clean installation ภายหลัง
- [ ] ให้ข้อเสนอใน R-06 โดยไม่คัดลอก binary/code เข้ามาก่อนตรวจเงื่อนไข

งานนี้ทำส่วนเอกสารได้โดยไม่ต่อ USB แต่การสรุป candidate สุดท้ายรอผล R-03/R-04 การมีรายงานข้อจำกัดไม่เท่ากับผ่าน license compliance สำหรับ release

## Implementation task ที่เหมาะสมหลังผล hardware

- ถ้า R-03 สแกนได้: เสนอ **S-01 ขอบเขตเล็ก — ทำ scanner backend adapter ที่ discover อุปกรณ์และสแกนหนึ่งหน้าเป็นไฟล์** พร้อม error/cancellation boundary และการทดสอบ disconnect โดยแยกจาก SwiftUI; ตรวจ license ก่อนนำ library มาใช้
- ถ้า R-04 พิมพ์ได้ด้วยของเดิม: ให้ความสำคัญกับ setup/validation workflow และ scanner/document workspace; ยังไม่มีเหตุให้เขียน raster encoder ใหม่ การแจก Canon binary ต้องแยกตรวจสิทธิ์ ไม่ถือว่าใช้ในเครื่องได้แล้วแจกต่อได้
- ถ้า R-03/R-04 ไม่ผ่าน: เปิดงานวิจัยเฉพาะ failure ที่ตรวจพบจริง เช่น backend USB access หรือ print filter runtime; ยังไม่ยกระดับเป็น full driver rewrite

ปัจจุบันมี real scan result และ print failure evidence แล้ว จึงมีหลักฐานสำหรับร่าง S-01 แบบ SANE single-page adapter โดยยังรอ R-05/integration decision ส่วนงานพิมพ์ต้องวิเคราะห์ offline ต่อ ยังไม่รับรองความสำเร็จของ v0.1 การสร้าง issue ต้องรอผู้ใช้อนุมัติ
