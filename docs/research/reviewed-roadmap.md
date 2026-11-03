# Roadmap review — 2026-10-30

**ลำดับความสำคัญล่าสุดจากผู้ใช้: Printing first.** พัก scanner adapter/UI ไว้หลัง SANE hardware proof ให้แก้และยืนยันเส้นทางพิมพ์ก่อน การตรวจใหม่พบ serial ใน device URI ของคิวไม่ตรงเครื่องจริงและได้แก้เฉพาะ URI แล้ว ดู [printing follow-up](2026-10-30-print-queue-uri.md) การทดลองเก่าก่อนแก้คิวไม่ควรใช้สรุปว่า driver G2000 ไม่เข้ากัน

**สถานะใหม่หลังกลับมาต่อเครื่อง:** อ่าน [ผล R-03/R-04 ล่าสุด](2026-10-30-r03-r04-hardware.md) — สแกน SANE Color/A4/300 DPI และ reconnect ผ่านแล้ว ฝั่งพิมพ์มี failure evidence จาก CUPS offline การพัก hardware ที่กล่าวในรีวิวเดิมด้านล่างสิ้นสุดแล้ว; รอบใหม่ได้รับอนุญาตให้ติดตั้ง SANE และทดสอบจริง แต่ยังไม่ได้รับอนุมัติให้สร้าง Issues

แผนฉบับปรับปรุงจาก [handoff ต้นฉบับ](../project-handoff.md), [หลักฐาน R-01/R-02](2026-10-30-r01-r02.md) และคำขอผู้ใช้ให้พัก hardware testing ก่อนถอดสาย รอบรีวิวนี้อ่านเอกสาร/repository เท่านั้น ไม่ตรวจ USB ซ้ำ ไม่เริ่ม print/scan หรือติดตั้ง dependency

## สถานะขณะรีวิวก่อนรอบติดตั้ง SANE และทดสอบจริง

- ทำแล้ว: ตรวจ repository/environment, USB descriptor/interfaces, CUPS discovery/queue, PPD, architecture ของ print filters, installed package receipts และเครื่องมือที่มีอยู่ พร้อมบันทึกแบบปกปิด serial
- พิสูจน์ได้ ณ รอบ hardware ก่อนพัก: macOS และ CUPS พบ G2010 `04a9:183a`; มีคิวที่ใช้ G2000 16.80.0.0 ชี้ USB อุปกรณ์นั้น
- ยังไม่พิสูจน์: พิมพ์ออกจริง, สแกนจริง, app integration, reconnect/sleep recovery, clean installation หรือ macOS รุ่นอื่น
- ไม่มีผลทดสอบที่ยืนยันว่า G2010 พิมพ์/สแกนไม่ได้ ข้อผิดพลาด CUPS ใน sandbox ตรวจแยกแล้วว่าไม่ใช่หลักฐานว่า scheduler บนเครื่องหยุด
- Repository ยังไม่มี executable implementation หรือ build/tests เอกสารอยู่ local และยังไม่ commit/push; GitHub metadata ยังรายงาน size 0 และ issue search ไม่พบรายการ ณ รอบรีวิว
- งานที่ใช้ hardware พักรอผู้ใช้กลับมาเชื่อมต่อและพร้อมตรวจเอกสาร/กระดาษจริง งานเอกสาร/แผนทำต่อได้

## สิ่งที่ควรปรับจาก roadmap เดิม

1. **แยกทางพิมพ์และสแกน:** ไม่มีเหตุให้ print validation รอ SANE หรือ scanner development รอ print encoder เริ่ม R-04 ด้วยคิวเดิมได้เมื่อ hardware พร้อม
2. **ใช้สิ่งที่ติดตั้งอยู่ก่อน:** R-03 เพิ่มการลอง Image Capture/Canon ICA เดิมก่อนตัดสินใจติดตั้ง SANE; R-04 ทดสอบ G2000 version ปัจจุบันก่อนเปลี่ยน version
3. **ไม่ล็อก backend ก่อนผลจริง:** เปลี่ยน S-01 จาก “Integrate SANE” เป็น “Integrate the selected scanner backend” SANE เป็น candidate; P-01 สร้าง abstraction เท่าที่ผล backend ต้องใช้ ไม่ตั้งต้นด้วย encoder/USB implementation ใหม่
4. **ดึง license/distribution มาต้นงาน:** R-05 แยกจาก reverse engineering ทำก่อนนำ third-party code/library มารวม; Q-03/Q-04 มี feasibility review ก่อนเลือก architecture ไม่รอท้ายโครงการ
5. **ย้าย CI และ test fixtures มาเมื่อเริ่ม code:** Q-01 เริ่มกับ executable slice แรก Q-02 ยึด options/errors ที่พบจริงและไม่แทน hardware acceptance
6. **ลดงานซ้ำเรื่อง session:** ให้ S-04 ดู acquisition lifecycle (scan next page, progress, cancel) ส่วน D-01/D-03 ดู session/page model, editing, undo/redo, persistence และ recovery หลีกเลี่ยงสองชุด state
7. **เพิ่มลำดับตาม dependency:** D-01 ต้องมี model ก่อน S-04 แบบหลายหน้า; U-01 เริ่ม shell บาง ๆ พร้อม scanner slice แรก ไม่ทำ backend หลายชั้นจนจบทั้งหมดแล้วค่อยตรวจ UI
8. **ระบุ preview/recovery ให้ชัด:** scan preview อยู่ S-02/U-01, document preview อยู่ D-02/U-02, session recovery อยู่ D-01/D-03; recovery ต้องเก็บทั้ง page assets และ session metadata และมีวิธีทดสอบ restart
9. **เก็บเป้าหมาย v0.1 เดิม:** staged milestones ด้านล่างเป็นจุดตรวจภายใน ไม่ได้ลด requirement ของ multi-page/edit/export/installation หรือเรียก proof-of-concept ว่า v0.1

## ลำดับทำงานที่ปรับแล้ว

| ช่วง | งาน | เกณฑ์ผ่านก่อนขยายงาน |
| --- | --- | --- |
| A: หลักฐานการเชื่อมต่อ | R-01/R-02 | baseline บันทึกแล้วและ USB/CUPS พบเครื่อง; ยังต้องตกลง support matrix |
| B: พิสูจน์พิมพ์และสแกน | R-04 กับ R-03 แยกกัน; R-05 ทำส่วนเอกสารได้ | แต่ละทางมีผลจริง/ข้อผิดพลาดทำซ้ำได้ ไม่ใช้ชื่อคิวหรือ receipt แทนผลใช้งาน |
| C: ตัดสินใจราย subsystem | R-06 และปรับ R-01 | backend, integration, license constraints, support scope และงานแรกชัดเจน ทางที่พร้อมเดินต่อได้โดยไม่ต้องรออีกทาง แต่ยังไม่ถือว่า v0.1 พร้อม |
| D: ฟังก์ชันแรกครบเส้นทาง | scanner: S-01/S-02/S-03 บางส่วน + U-01; print: P-01/P-02 เท่าที่จำเป็น + เริ่ม P-05 | สแกนหนึ่งหน้าเป็นไฟล์/preview จริง และพิมพ์จากแอปภายนอกโดยไม่เปิดแอปโครงการ; Q-01/Q-02 เริ่มร่วมกับ code |
| E: document workflow | D-01 → D-02/D-03 → S-04/D-04/D-05, ต่อ S-05 | หลายหน้า แก้ไข เรียง/แทนที่ undo/redo export และ session recovery ผ่าน; S-05 ระดับพื้นฐานเริ่มตั้งแต่ D |
| F: ครบ MVP และส่งมอบ | P-03/P-04/P-05, U-02/U-03, Q-03/Q-04/Q-05 | option/job errors, print workspace, installer/uninstaller, distribution checks และ hardware QA ครบ |

P-04/S-05 ขั้นพื้นฐาน (disconnect, cancel, failure) ต้องมีตั้งแต่ฟังก์ชันแรก ไม่เลื่อน error handling ทั้งหมดไปท้าย Q-03/Q-04 ทบทวน feasibility ใน B/C แล้วจึงทำ installer/signing จริงใน F

## สถานะและขอบเขตของงานเดิมทุกงาน

รหัสทั้งหมดเป็น planning IDs ไม่ใช่ GitHub issue numbers “รอ” หมายถึงยังไม่เริ่มหรือ dependency ยังไม่ครบ ไม่ใช่ทดสอบแล้วล้มเหลว

| ID | สถานะ/ขอบเขตหลังรีวิว | Dependency หรือหลักฐานจบ |
| --- | --- | --- |
| R-01 | baseline เครื่องเสร็จบางส่วน; รอ support/deployment decision | finalize ใน R-06; ไม่ประกาศรองรับ OS อื่นโดยไม่มี QA |
| R-02 | enumeration/discovery เสร็จ ณ วันที่ตรวจ | reconnect/sleep QA อยู่ P-04/S-05/Q-05 ไม่ต้องเปิดงานตรวจไม่พบ USB ซ้ำ |
| R-03 | SANE discovery/scan 300 DPI และ reconnect ผ่าน; ICA เดิมไม่สำเร็จ | มี PNG จริงและผู้ใช้ตรวจภาพแรกแล้ว; ยังไม่ผ่านทุกโหมด/sleep/wake |
| R-04 | ทดลองคิว G2000 เดิมแล้วมี offline failure evidence | วิเคราะห์ CUPS backend/queue/runtime ต่อ; Preview Command+P ยังไม่ผ่าน |
| R-05 | พร้อมวาง issue; ส่วนเอกสารเริ่มได้ | license/distribution matrix; protocol research เพิ่มเมื่อจำเป็น |
| R-06 | รอผลเพื่อเลือก backend รายทาง; ใช้ findings ปัจจุบันเป็นฐาน | decision record พร้อมเหตุผล/ข้อจำกัดและ implementation slice แรก |
| P-01 | รอเลือก print path; ลด abstraction ตามจำเป็น | R-04/R-05/R-06 ฝั่งพิมพ์; อาจใช้ system APIs/คิวเดิมเป็นหลัก |
| P-02 | รอ; เป็น setup/integration ของ path ที่เลือก | system queue ใช้ได้เมื่อแอปไม่เปิด; ไม่สร้าง queue manager ใหม่ |
| P-03 | รอ; expose เฉพาะ options ที่พิสูจน์ได้ | hardware QA ของ paper/color/quality/copies; ไม่อิง PPD เพียงอย่างเดียว |
| P-04 | เริ่มขั้นต่ำพร้อม print slice แล้วขยาย | status/cancel/errors/disconnect/reconnect; ไม่ควบคุมคิวอื่น |
| P-05 | เริ่มจาก R-04 และตรวจซ้ำหลัง integration | Command+P หลายแอปจริงโดยไม่เปิดแอปโครงการ |
| S-01 | รอ; integrate backend ที่เลือก ไม่ล็อก SANE | R-03/R-05/R-06 ฝั่งสแกน; discover + scan หนึ่งหน้า |
| S-02 | รอ; options และ scan preview | capabilities จริง ไม่ hardcode ค่าที่ backend ไม่รองรับ |
| S-03 | เริ่มพร้อม single-page slice | background operation/progress/cancel ไม่บล็อก UI |
| S-04 | รอ; หลาย flatbed acquisitions ใน session เดียว | D-01 และ S-01–S-03; ไม่มี ADF assumption |
| S-05 | ขั้นพื้นฐานพร้อม single-page slice แล้วขยาย | disconnect/reconnect, error recovery ไม่ทำหน้าที่บันทึกแล้วสูญหาย |
| D-01 | รอ; model/page assets/session persistence | เริ่มก่อน S-04; กำหนด atomic save/recovery และ ownership ชัดเจน |
| D-02 | รอ; thumbnail/document preview | D-01; รับภาพ/เอกสารทดสอบได้แม้ไม่มี scanner |
| D-03 | รอ; rotate/delete/reorder, undo/redo, recovery | D-01/D-02; ทดสอบปิด/เปิดใหม่และไฟล์ไม่ครบ |
| D-04 | รอ; rescan replace | scan และ session model พร้อม; ผิดพลาดไม่ทำลายหน้าเดิม |
| D-05 | รอ; PDF หลายหน้า, PNG/JPEG | D-01; ตรวจลำดับหน้า/ภาพ/ขนาด export ที่เปิดได้จริง |
| U-01 | รอ; shell บาง ๆ พร้อมฟังก์ชันแรก | ไม่ทำ UI สมมติเต็มแอปก่อน backend proof |
| U-02 | รอ; PDF/image drop, preview, system print dialog | document preview + print path; priority หลังพื้นฐานพิมพ์/สแกน |
| U-03 | รอ; feedback/settings/accessibility | basic feedback ตั้งแต่ U-01; keyboard/focus/VoiceOver QA ก่อน release |
| Q-01 | ยังไม่เริ่ม; ย้ายมา executable slice แรก | build/unit checks ที่ตรงกับ code จริง; ไม่อ้างว่า CI พิสูจน์ hardware |
| Q-02 | ยังไม่เริ่ม; fixtures จากผล backend จริง | mock error/cancel/session scenarios และแยก hardware tests |
| Q-03 | feasibility เริ่มใน B/C; implementation รอ path | clean setup/uninstall ไม่พึ่งของเก่าที่ซ่อนอยู่ใน Mac นี้ |
| Q-04 | license feasibility เริ่ม R-05; signing รอ artifact | ตรวจ entitlements/service/bundling; signing/notarization จริงก่อนแจก |
| Q-05 | รอท้าย milestone | hardware regression + reconnect/sleep + docs/acceptance; v0.1 ตาม handoff ครบ |
| RD-01 | conditional; ยังไม่เปิด | ไม่มี print backend ที่เหมาะสมหลัง R-04/R-05 จึงศึกษา protocol |
| RD-02 | conditional; ยังไม่เปิด | RD-01 มี protocol/test plan ที่เข้าใจแล้วก่อนส่งข้อมูล |
| RD-03 | conditional; ยังไม่เปิด | minimal raster proof ผ่านและไม่มี reuse ทางเลือกที่เหมาะสม |

## Issue readiness และงานที่ทำได้ระหว่างไม่มีเครื่อง

หลังมีผล hardware แล้ว เสนอร่าง issue **R-04 วิเคราะห์ CUPS offline** กับ **R-05 license/distribution** และเก็บ **S-01 SANE single-page adapter** เป็น implementation draft ที่รอ R-05/decision ใช้ [ร่างขอบเขต/acceptance criteria](next-hardware-task.md) ร่วมกับผลทดสอบใหม่ ไม่เปิด R-03 ย้อนหลังโดยอ้างว่ายังไม่มี real scan result

ยังไม่สร้าง issue ย้อนหลัง R-01/R-02 เพื่อเปิดแล้วปิดทันที บันทึกผลที่ทำไว้เป็น baseline ของสามงานแทน R-06 เก็บเป็นจุดตัดสินใจในแผนก่อน ส่วน P/S/D/U/Q และ conditional R&D ยังไม่แตกทั้งหมดเป็น issue

ทำได้โดยไม่ต่อเครื่อง: ตรวจ license/build/distribution จาก upstream และจัดเอกสาร/draft issues ส่วน runtime/hardware QA ทำเมื่อผู้ใช้พร้อม ปัจจุบันอนุญาตให้ทดสอบ hardware และติดตั้ง SANE แล้ว ยังไม่ได้อนุมัติให้สร้าง GitHub Issues หรือ publish เอกสาร

ก่อนเปิด issue จริงให้แนบสรุปหลักฐานใน body หรือเผยแพร่เอกสารด้วย workflow ที่ผู้ใช้อนุมัติ ไม่ใส่ absolute local file links เป็นหลักฐานที่คนอื่นเปิดจาก GitHub ไม่ได้

หากผล R-03 ผ่านและ license path ชัด งาน implementation ถัดไปที่เสนอคือ **S-01 แบบหนึ่งหน้า + S-03 ขั้นพื้นฐาน** ถ้าฝั่งพิมพ์เดิมผ่าน ให้พัฒนาตามช่องว่าง setup/integration ที่เหลือจริง การใช้ได้บน Mac ที่มี Canon software อยู่แล้วไม่เท่ากับติดตั้งได้บน Mac ใหม่
