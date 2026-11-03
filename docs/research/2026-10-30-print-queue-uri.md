# Printing priority — ตรวจและแก้ USB URI ของคิว Canon

วันที่: 2026-10-30 (Asia/Bangkok)

ผู้ใช้ให้ทำฝั่งพิมพ์เป็นงานหลัก เพราะใช้งานพิมพ์มากกว่า พัก scanner development หลังผล SANE proof-of-concept โดยยังไม่เริ่ม implement printer driver หรือสร้าง GitHub Issues

## ข้อค้นพบที่แก้ข้อสรุปเดิม

ตรวจเปรียบเทียบค่าเต็มภายในเครื่องระหว่าง:

- `lpstat -v Canon_G2010_series`: device URI ที่คิวใช้
- `lpinfo -v`: USB URI ที่ CUPS ค้นพบจากเครื่องที่ต่ออยู่จริง

ทั้งสองระบุ Canon / G2010 series แต่ **serial query parameter ไม่ตรงกันแม้เทียบแบบไม่สนตัวพิมพ์เล็ก/ใหญ่** และ URI เต็มไม่ตรงกัน พบอุปกรณ์ G2010 ที่ discovery เพียงหนึ่งตัว ส่วน manufacturer/model ที่ URL-decode แล้วตรงกันแบบไม่สนตัวพิมพ์เล็ก/ใหญ่

ผลนี้แก้ข้อสรุปเดิมใน baseline ที่ระบุว่า serial ตรงกัน ซึ่งตอนนั้นยังไม่ได้ตรวจเทียบค่าเต็มอย่างถูกต้อง การปกปิด serial ในข้อความผลตรวจทำให้ดูเหมือน URI เหมือนกัน แต่ไม่ใช่หลักฐานว่าเปรียบเทียบแล้วตรง ต้องใช้ boolean comparison ก่อน redaction

เก็บ original/current URI และ rollback data เฉพาะ `/private/tmp/canon-g2010-print-diagnosis-20261030/` นอก repository ไม่เผยแพร่ serial

## การแก้ไขที่ทำจริง

1. ตรวจว่าคิวไม่มี active jobs และ URI ยังไม่เปลี่ยนจาก snapshot
2. สำรอง URI เดิม แล้วเรียก `lpadmin -p Canon_G2010_series -v '<URI-from-current-discovery>'`
3. อ่านกลับเพื่อยืนยัน URI ใหม่ตรงกับ discovery
4. เปรียบเทียบ SHA-256 ของ PPD ก่อน/หลังและตรวจ default printer

ผล: `lpadmin` exit 0, URI ตรง discovery, PPD SHA-256 ไม่เปลี่ยน และ default printer ไม่เปลี่ยน ไม่ reinstall/update Canon driver ไม่แก้ queue options ไม่ reset printing system และไม่แก้คิวอื่น

ยังใช้ PPD Canon G2000 series 16.80.0.0 เหมือนเดิม การเปลี่ยนปัจจัยเดียวช่วยแยก queue addressing ออกจาก raster/driver compatibility

## หลักฐานจาก upstream

- [CUPS lpadmin manual](https://openprinting.github.io/cups/doc/man-lpadmin.html) ระบุว่า `-v` ตั้ง device URI ของคิวและ `lpinfo -v` ใช้ดู URI ที่รองรับ
- [Apple CUPS USB backend](https://github.com/apple/cups/blob/master/backend/usb-darwin.c) ฟังก์ชัน `find_device_cb` เปรียบเทียบ manufacturer/model และ serial เมื่อ URI ระบุ serial ไว้ จึงสนับสนุนคำอธิบายว่าคิวที่ serial ไม่ตรงอาจรออุปกรณ์ที่ไม่มีอยู่ ข้อมูล source upstream เป็นคำอธิบายกลไก ไม่ได้พิสูจน์ว่า binary ใน macOS นี้เหมือน source ทุกบรรทัด

## การทดลองหลังแก้ URI

ใช้ PDF ทดสอบเดิม A4 หนึ่งหน้า สี/ค่าเดิม ผ่าน CUPS `lp` เป็นงาน **2299** ไม่เปลี่ยน driver หรือเริ่ม scanner ไปพร้อมกัน

- คิวรับงานสำเร็จ
- หลังแก้ URI ข้อความเปลี่ยนเป็น `Printing` และมี Canon-specific status reasons กลับมา ต่างจาก `connecting-to-device` ในรอบก่อน
- ขณะอ่านยังมี `offline-report` ค้างร่วมกับเหตุผลอื่น จึงไม่ถือว่า string เดียวพิสูจน์ว่าเครื่องไม่เชื่อมต่อ
- ไม่ตีความ proprietary ink/eid status fields ว่าเป็น ink-empty หรือ hardware error โดยไม่มีเอกสารหรือผลตรวจหน้าเครื่อง
- ตัว monitor จำกัดเวลาไว้ 60 วินาทีและยกเลิกเฉพาะงานทดสอบด้วย exit 0 เมื่อยังเป็น processing/0 sheets completed
- ตรวจหลังยกเลิกแล้ว active queue ของ Canon ว่าง การอ่าน attributes ของ job ย้อนหลังครั้งถัดมาไม่ให้ attributes กลับมา จึงไม่อ้างว่าได้ final job-state จากการอ่านครั้งนั้น
- ผู้ใช้ยืนยันภายหลังว่ายังไม่มีหน้ากระดาษออก หน้าเครื่องไม่มีรหัสเตือน ไฟ Power ติดปกติและเครื่องเงียบ จึงยังไม่ผ่าน printing compatibility

การจำกัดเวลา 60 วินาทีเป็นข้อจำกัดการทดลอง หากเครื่องกำลังพิมพ์จริงต้องให้เวลาทดสอบรอบถัดไปเพียงพอ ไม่สรุปว่า driver ใช้ไม่ได้จากการยกเลิกก่อน job จบ

## ลำดับถัดไปสำหรับฝั่งพิมพ์

1. ยืนยัน output จริงและไฟ/ข้อความหน้าเครื่องหลังแก้ URI หากไม่มี output ให้แยกสถานะ hardware กับ driver/runtime ต่อ ไม่ส่งซ้ำขณะมีงาน active
2. ถ้าพิมพ์ได้ ให้ทดสอบ Command+P จาก Preview และอีกแอป โดยเลือก Canon queue ชัดเจนและไม่ต้องมีแอปโครงการเปิดอยู่
3. ตรวจ A4, grayscale/color และ copies จาก output จริง ก่อนกล่าวว่าตัวเลือกทำงานได้
4. ทดสอบ reconnect และ setup บนเครื่องที่ไม่มี installation เดิม พร้อมตรวจ license/distribution ของเส้นทางที่เลือก
5. หลังผลยืนยันค่อยกำหนดช่องว่าง implementation ฝั่ง printing; scanner adapter ให้พักตามลำดับความสำคัญของผู้ใช้

ข้อจำกัด Preview automation จากรอบก่อนยังอยู่: เปิดไฟล์ผ่าน native dialog ไม่สำเร็จ จึงยังไม่อ้างว่าผ่าน Preview/Command+P งาน 2299 ใช้ system queue ผ่าน `lp`

## ผลตรวจ rendering หลังผู้ใช้ยืนยันว่าเครื่องยังเงียบ

### Filter chain

`cupsfilter --list-filters` ด้วย PPD เดิมระบุ:

```text
cgpdftoraster
/Library/Printers/Canon/BJPrinter/Filters/Raster2CanonIJ/Raster2CanonIJS.bundle/Contents/MacOS/Raster2CanonIJS
```

สิทธิ์ executable ของ Canon filters ตรวจผ่าน จากนั้นทดสอบแปลง PDF เดิมเป็นไฟล์ภายใน `/private/tmp` โดยไม่เรียก USB backend:

| การทดลอง | ผล |
| --- | --- |
| ระบุ PPD, ใช้ชื่อ printer เริ่มต้นของ cupsfilter | exit 1, output 0 bytes; Canon Raster2CanonIJS ล้มด้วย signal 11 |
| ระบุชื่อคิวด้วย `-d` อย่างเดียว | cupsfilter เองล้มหลังรายงาน NULL PPD; เป็นข้อจำกัดการเรียกเครื่องมือนี้ ไม่ใช่หลักฐานว่า Canon filter ล้มในคิวจริง |
| ระบุทั้ง `-d Canon_G2010_series` และ `-p <PPD>` | exit 1, output 0 bytes; ยืนยันว่า `PRINTER` เป็นชื่อคิวจริงแล้ว แต่ Canon Raster2CanonIJS ยังล้มด้วย signal 11 |

สองการทดลองที่อ่าน PPD สำเร็จพบ PDF มีหนึ่งหน้าและ `cgpdftoraster` จบโดยไม่มี exit error แต่ปลายทาง Canon ล้มก่อนสร้างข้อมูลพิมพ์ `rasterWriteData` ของตัวแปลง PDF มี error ร่วมอยู่ จึงไม่ถือว่าทุกส่วนของ raster pipeline ผ่านสมบูรณ์

Crash report ของ process `Raster2CanonIJS` ยืนยัน ARM-64, `EXC_BAD_ACCESS` / `SIGSEGV`, invalid address 0 เฟรมบนสุดผ่าน CoreFoundation `CFDictionaryGetValue`, Canon `CIJPrinterUtility` และ `Raster2CanonIJS` เก็บเฉพาะสรุปที่ไม่ระบุตัวเครื่องใน findings ไม่เผยแพร่ crash dump เต็มหรือ binary ของ Canon

**ขอบเขตข้อสรุป:** มีปัญหา runtime ที่ทำซ้ำได้ใน offline conversion ด้วย driver ที่ติดตั้งอยู่ ยังไม่ถือว่าพิสูจน์สาเหตุของ scheduler job ทุกครั้ง เพราะ [CUPS cupsfilter manual](https://openprinting.github.io/cups/doc/man-cupsfilter.html) ระบุว่าการรันเครื่องมือนี้ใช้ user/security session ต่างจากการพิมพ์จริง ต้องตรวจ execution ผ่าน scheduler เพิ่มก่อนสรุปว่า binary crash เป็นสาเหตุเดียวของงาน 2299

### Existing scheduler logs

อ่าน log ของงานทดสอบย้อนหลังพบ `No pages found!` ในงาน 2297, 2298 และ 2299 ณ เวลาจบ/ยกเลิกงาน ยังไม่มี debug log พอจะระบุว่าเกิดใน stage ใด และยังแยกไม่ได้ว่าเกี่ยวกับการ cancel หรือเป็น error ก่อนหน้านั้น จึงไม่ใช้ข้อความนี้เป็นหลักฐานว่า PDF ต้นฉบับไม่มีหน้า

ขณะตรวจไม่มี active jobs ในคิว Canon; `LogLevel warn`, `_debug_logging=0` ยังไม่ได้เปิด debug logging หรือส่ง print job เพิ่มระหว่างผู้ใช้ทดสอบหน้าเครื่อง

### Hardware isolation และ candidate ถัดไป

ขอให้ผู้ใช้ทดสอบ nozzle-check จากตัวเครื่องตาม [คู่มือ Canon G2010](https://ij.manual.canon/ij/webmanual/Manual/All/G2010%20series/EN/UG/ug_m_01_02_c.html): A4, Setup ให้แสดง 1 แล้วกด Black/Color หนึ่งครั้ง รอผลเพื่อแยก printing mechanism ออกจาก software บน Mac ยังไม่บันทึกว่าทดสอบนี้ผ่านจนกว่าผู้ใช้ยืนยัน

ผู้ใช้ตอบว่า “เงียบกริบเลย” หลังคำขอทดสอบจากตัวเครื่อง จึงยังไม่มี standalone print proof ขณะนี้ต้องยืนยันก่อนว่าจอแสดง Setup icon/เลข 1 จริงและไฟ Power เปลี่ยนอย่างไรหลังสั่ง ห้ามสรุปว่า print mechanism เสียจากคำตอบนี้อย่างเดียว พักงานส่งพิมพ์จาก Mac ระหว่างแยกสถานะหน้าเครื่อง

ผู้ใช้ชี้แจงต่อว่าเลข 1 แสดงอยู่ตามปกติและหมายถึงจำนวนสำเนา จึงต้องถอนข้อสรุประหว่างสนทนาที่ว่าเข้า nozzle-check menu ถูกต้องแล้ว: เลข 1 อย่างเดียวไม่แยก copy count ออกจาก maintenance code ยังไม่ถือว่าทดสอบ standalone nozzle-check ตามขั้นตอนครบหรือยืนยัน hardware failure เปลี่ยนไปใช้การถ่ายเอกสารธรรมดาเป็นการทดสอบ print mechanism ที่สื่อสารง่ายกว่า โดยต้องตรวจว่าพิมพ์ออกจริงก่อนบันทึกว่าผ่าน

**คำยืนยันล่าสุดจากผู้ใช้:** ตัวเครื่องถ่ายเอกสารจากปุ่มได้อยู่แล้ว จึงมี standalone copy/print proof ตามคำยืนยันของผู้ใช้ ไม่ได้ทดสอบ nozzle-check สำเร็จและไม่ได้ตรวจคุณภาพทุกสี ใช้ผลนี้ตัดการถามให้ทดสอบปุ่มซ้ำ และกลับไปวิเคราะห์ software pipeline บน Mac โดยไม่สรุปว่า hardware เสีย

## Scheduler diagnostic job 2300

หลังผู้ใช้ยืนยัน standalone copying ได้ เก็บ log ของ PDF ทดสอบเดิมหนึ่งหน้า A4 ผ่านคิวที่แก้ URI แล้ว ให้เวลาประมาณ 180.8 วินาทีแทนรอบเดิม 60 วินาที

- Snapshot logging เดิม: `LogLevel warn`, `_debug_logging=0`
- เปิด debug logging ชั่วคราวเฉพาะช่วงตรวจ (เป็น config ระดับ CUPS server) และเก็บเฉพาะ log ของ job 2300 มาใช้วิเคราะห์ ไม่เผยแพร่ raw log ทั้งระบบ
- Scheduler เริ่ม `cgpdftoraster`, `Raster2CanonIJS` และ USB backend จริง อ่าน PDF พบหนึ่งหน้าและอ่าน PPD ได้
- USB generic class driver เปิดสำเร็จ (`kr:0x00000000`) และถอน `connecting-to-device`
- CUPS side channel อ่าน device ID ของ G2010 สำเร็จ โดยอุปกรณ์รายงาน `CMD:BJRaster3,IVEC` ข้อมูลนี้เป็น capability string ที่อ่านได้ ไม่ใช่ผล protocol compatibility test
- มี back-channel data และ polling status แต่ job ยังเป็น processing/Printing และ `job-media-sheets-completed=0` จนครบช่วงรอ
- หลังประมาณสองนาทีมี `com.canon-0311-warning` ข้อความใน PPD Canon ที่ติดตั้งระบุเพียงเครื่องกำลังใช้งานหรือมีข้อผิดพลาด จึงไม่เจาะจงว่าเป็น ink/paper/hardware fault
- Log ที่อ่านได้ของ scheduler job นี้ยังไม่ยืนยัน Canon filter crash แบบเดียวกับ offline test จึงแยกสองผลไว้ ไม่อ้างว่า offline SIGSEGV เป็นสาเหตุเดียวของ scheduler hang
- ยกเลิกเฉพาะงาน 2300: cancel exit 0, job-state canceled ขณะกำลังหยุด; คิว active ว่างหลังตรวจ
- คืน logging สำเร็จ: restore exit 0, `LogLevel warn`, `_debug_logging=0` ตรวจยืนยันอีกครั้ง

เก็บสรุป machine-readable และ log เฉพาะงานที่ปกปิด serial ใน `/private/tmp/canon-g2010-print-diagnosis-20261030/` ไม่คัดลอก raw crash dump หรือ vendor binary เข้า repository

### การทดลองถัดไปที่เตรียมเสนอ

ประเมิน Canon G2000 16.91.0.0 จากหน้า official เป็น controlled update candidate สำหรับ macOS 27 โดยยังไม่รับรอง G2010: ก่อนเปลี่ยนระบบให้ตรวจลายเซ็น/รายละเอียดแพ็กเกจและเงื่อนไข เก็บ baseline ของ version เดิม, URI ที่แก้แล้ว, PPD และ default printer แล้วแยกผลก่อน/หลัง การดาวน์โหลด software ยังไม่เริ่มเพราะหน้าดาวน์โหลดระบุการยอมรับเงื่อนไขเมื่อดาวน์โหลด ต้องให้ผู้ใช้ตัดสินใจเรื่องเงื่อนไขก่อน

[หน้า Canon G2000 CUPS 16.91.0.0](https://asia.canon/en/support/0101155713) ระบุ macOS 27 เป็น supported OS และ G2000 เป็น supported model ต่างจาก version 16.80.0.0 ที่ติดตั้งอยู่ จึงเป็น candidate ของการทดลอง update/runtime ครั้งถัดไป แต่ไม่ได้ระบุ G2010 ยังไม่ได้ดาวน์โหลด/ติดตั้ง/ทดสอบ version ใหม่

หน้า download ของ Canon ระบุว่าการดาวน์โหลดถือเป็นการยอมรับเงื่อนไขการใช้งาน ต้องให้ผู้ใช้ตัดสินใจก่อนดำเนินการดังกล่าว ไม่ bundle/แจก binary เข้า repository ระหว่างการทดลอง
