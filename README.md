# Canon PIXMA Driver

**พิมพ์ได้แล้ว (3 พ.ย. 2026):** ใช้ Gutenprint 5.3.5 ที่คอมไพล์เองสำหรับ Apple Silicon ดู [วิธีใช้และสรุปงาน](docs/printing-g2010.md) ส่วนข้อความด้านล่างเป็นบันทึกวิจัยช่วงก่อนหน้า

โครงการวิจัยการใช้งาน Canon PIXMA G2010 ผ่าน USB บน macOS โดยนำ backend ที่มีอยู่มาใช้ก่อนพัฒนาใหม่ เป้าหมายคือพิมพ์ผ่านระบบ macOS โดยไม่ต้องเปิดแอป และมีแอปสแกนเอกสารหลายหน้าในภายหลัง

สถานะ 30 ตุลาคม 2026: **สแกน G2010 ผ่าน SANE ได้จริงที่ 300 DPI และสแกนซ้ำหลัง reconnect สำเร็จ** ผู้ใช้ยืนยันภาพแรกครบหน้า ส่วนการทดลองพิมพ์ด้วยคิว G2000 เดิมทั้งก่อนและหลัง reconnect ติด CUPS offline; ยกเลิกงานทดสอบแล้ว ยังไม่ยืนยันการพิมพ์สำเร็จ Repository นี้ยังไม่มี implementation ของไดรเวอร์หรือแอป

**อัปเดตฝั่งพิมพ์:** พบ serial ใน USB URI ของคิวไม่ตรงกับเครื่องจริงและแก้แล้ว โดย PPD/ไดรเวอร์/default printer ไม่เปลี่ยน งานทดสอบหลังแก้แสดง `Printing` แต่ไม่มีหน้ากระดาษออก ผู้ใช้ยืนยันไม่มีรหัสเตือนและเครื่องเงียบ การแปลงไฟล์แบบไม่ส่ง USB พบ Canon filter ล้มด้วย signal 11 และได้ output 0 bytes รวมถึงเมื่อระบุชื่อคิวจริง ยังต้องตรวจเทียบกับ scheduler execution และทดสอบพิมพ์จากตัวเครื่อง งานหลักปัจจุบันคือ printing; พัก scanner development

ผู้ใช้ยืนยันว่าถ่ายเอกสารจากปุ่มเครื่องได้อยู่แล้ว การตรวจ scheduler เพิ่มด้วยงาน 2300 ยืนยันว่า USB เชื่อมต่อ/อ่าน device ID ได้ แต่รอประมาณ 3 นาทีแล้วยังไม่เสร็จและมี Canon warning 311 ยกเลิกงานและคืน logging เดิมแล้ว ผลนี้ยังไม่ยืนยันว่า scheduler เกิด crash แบบ offline test ขั้นถัดไปคือ controlled driver/runtime evaluation ตามรายงาน

- [Project handoff จากผู้ใช้](docs/project-handoff.md) — เก็บข้อความต้นฉบับ; ข้อมูลสถานะเครื่องบางส่วนได้รับการตรวจใหม่ด้านล่าง
- [ผล R-01 / R-02 และ baseline จากเครื่องจริง](docs/research/2026-10-30-r01-r02.md)
- [ผลสแกนจริงและการทดลองพิมพ์ R-03 / R-04](docs/research/2026-10-30-r03-r04-hardware.md) — การทดลองก่อนแก้ปลายทางคิว
- [Printing follow-up: แก้ serial ปลายทางคิวที่ไม่ตรงอุปกรณ์](docs/research/2026-10-30-print-queue-uri.md) — งานหลักปัจจุบัน; พัก scanner development
- [งานทดสอบถัดไปและร่าง acceptance criteria](docs/research/next-hardware-task.md) — ยังไม่ใช่ GitHub Issues
- [รีวิวและปรับ roadmap พร้อมสถานะทุกงาน](docs/research/reviewed-roadmap.md) — ใช้วางลำดับงานต่อจากผล hardware; handoff ด้านบนยังเก็บต้นฉบับ

บนเครื่องที่ตรวจ คำสั่ง `system_profiler SPUSBDataType` ไม่แสดงผล ให้ตรวจชนิดข้อมูลที่รองรับก่อน:

```sh
system_profiler -listDataTypes | rg -i USB
system_profiler SPUSBHostDataType
```

ผลคำสั่งอาจมี serial number ควรปกปิดก่อนเผยแพร่ การเห็นชื่อเครื่องหรือคิวพิมพ์ยังไม่พิสูจน์ว่าพิมพ์หรือสแกนสำเร็จ
