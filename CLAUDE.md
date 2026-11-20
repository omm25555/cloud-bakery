# CLAUDE.md: กติกาโค้ด Cloud Bakery

กฎฉบับเต็มอยู่ที่ [docs/RULES.md](docs/RULES.md) ให้อ่านก่อนเริ่มทุก TASK เอกสารเกมอยู่ที่ [docs/GDD.md](docs/GDD.md) และ [docs/ROADMAP.md](docs/ROADMAP.md)

## โค้ด
- ภาษา Luau ใส่ `--!strict` ทุกไฟล์ ไม่มี type error/warning ห้ามใช้ `::any` เพื่อหลบ type
- ฝั่ง server เป็น **Service**, ฝั่ง client เป็น **Controller** ตั้งชื่อ PascalCase (เช่น `BakeService`, `HudController`)
- Service/Controller เป็น ModuleScript ใน `Services/` / `Controllers/` มี `Start()` (ไม่บังคับ) ที่ bootstrap เรียกให้
- ตัวเลขทั้งหมดอยู่ใน `src/shared/Config` ห้าม hardcode
- remote ทั้งหมดสร้าง/ดึงผ่าน `src/shared/Remotes.luau` เท่านั้น
- path/require ต้องตรงกับ `default.project.json` จัดการ nil ทุกจุด
- ห้ามมี TODO, print ทดสอบ หรือโค้ดที่ปิดคอมเมนต์ไว้ ตัดการเชื่อมต่อ event เมื่อผู้เล่นออก
- log ขึ้นต้นด้วยชื่อ Service เช่น `[BakeService]`

## Server เป็นผู้ตัดสินเสมอ
เหรียญ ของ รางวัล เวลาโต และผลมินิเกม คำนวณที่ server เท่านั้น client ส่งได้แค่คำขอ server ต้องตรวจทุกคำขอ (ชนิดข้อมูล ช่วงค่า สิทธิ์ rate limit)

## การทำงาน
- หนึ่ง PR ต่อหนึ่ง TASK branch `task-XXX-ชื่อสั้น` PR ชื่อ `TASK-XXX: ...` ใส่ `Closes #N`
- ไม่ merge PR ของตัวเอง
- **ตรวจเองก่อนเปิด PR** แล้วเขียนรายงานการตรวจและขั้นตอนทดสอบใน Studio ทีละข้อ
- **ห้ามแตะงานที่ merge แล้ว** ถ้าจำเป็นต้องแก้ ให้หยุดและคอมเมนต์ถามก่อน
- **ผู้เล่นต้องไม่งง** ทุกกรณีที่ทำไม่สำเร็จ/ถูกปฏิเสธ/บันทึกข้อมูล ต้องมีแจ้งเตือนในเกม และมี `warn`/`error` ฝั่ง dev
- **ไม่ชัดให้ถามก่อนเขียนโค้ด** ห้ามเดา คุยใน Issue/PR เท่านั้น
- สคริปต์ทั้งหมดอยู่ใน repo ห้ามแก้ใน Studio โดยไม่ sync กลับ ห้ามติดตั้งโปรแกรม publish เกม หรือเปลี่ยนการตั้งค่า Roblox โดยไม่ได้รับอนุญาต
