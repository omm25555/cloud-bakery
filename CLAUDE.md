# CLAUDE.md: กติกาโค้ดของ Cloud Bakery

ทุกงานใน repo นี้ต้องทำตามไฟล์นี้ ถ้ากติกาขัดกับใบงานใน Issue ให้ถามใน Issue ก่อนลงมือ

## ภาษาและเครื่องมือ
- เขียนด้วย **Luau** นามสกุล `.luau` และบรรทัดแรกของทุกไฟล์ต้องเป็น `--!strict`
- ซิงก์เข้า Studio ด้วย **Rojo 7** (เวอร์ชันล็อกไว้ใน `rokit.toml`) แมปตาม `default.project.json`
  - `src/server` → `ServerScriptService.Server`
  - `src/client` → `StarterPlayer.StarterPlayerScripts.Client`
  - `src/shared` → `ReplicatedStorage.Shared`
- ห้าม commit ไฟล์ `.rbxl` / `.rbxlx` เพราะโค้ดต้องอยู่ใน `src/` เท่านั้น

## สถาปัตยกรรม
- **Server**: แต่ละระบบเป็น ModuleScript ใน `src/server/Services/` ชื่อ PascalCase ลงท้ายด้วย `Service` เช่น `FarmService`, `BakeService`
- **Client**: แต่ละระบบเป็น ModuleScript ใน `src/client/Controllers/` ชื่อ PascalCase ลงท้ายด้วย `Controller` เช่น `FarmController`
- โมดูลคืนตารางที่มี `Init(self)` และ/หรือ `Start(self)` ได้ bootstrap (`init.server.luau` / `init.client.luau`) จะ require ทุกโมดูล แล้วเรียก `Init` ทั้งหมดก่อน จากนั้นจึงเรียก `Start` ทั้งหมด
  - `Init`: ตั้งค่าและอ้างอิงโมดูลอื่น ห้าม yield
  - `Start`: เริ่มลูป ต่อ event และ yield ได้
- โค้ดที่ใช้ทั้งสองฝั่ง (ชนิดข้อมูล, ฟังก์ชันคำนวณล้วน, Config) อยู่ใน `src/shared/`
- RemoteEvent / RemoteFunction ทุกตัวประกาศชื่อใน `src/shared/Remotes.luau` และเรียกผ่าน `Remotes.event(name)` / `Remotes.func(name)` เท่านั้น ห้ามสร้าง remote เองที่อื่น

## Server เป็นผู้ตัดสินเสมอ
- server เป็นคนตัดสิน **เหรียญ ไอเทม รางวัล เวลาโต และผลมินิเกม** ทุกครั้ง
- client ส่งได้แค่ **คำขอ** เช่น "ขอเก็บแปลงที่ 3" หรือ "กดจังหวะที่เวลา t" ห้ามส่งผลลัพธ์ เช่น "ได้ 50 เหรียญ" หรือ "ได้ Perfect"
- server ต้องตรวจทุกคำขอ:
  - ชนิดของอาร์กิวเมนต์ถูกต้อง (`typeof`) และอยู่ในช่วงที่ยอมรับ
  - ผู้เล่นมีสิทธิ์ทำ (เป็นเจ้าของแปลง หรืออยู่ในระยะ)
  - สถานะพร้อม (พืชโตแล้วตามเวลาของ server หรือวัตถุดิบครบ)
  - จำกัดความถี่ (rate limit) ของ remote ที่ถูกเรียกบ่อย
- คำขอที่ไม่ผ่านให้ปฏิเสธเงียบๆ หรือส่งเหตุผลกลับ ห้ามให้ server error
- เวลาให้ใช้ `os.time()` / `workspace:GetServerTimeNow()` ฝั่ง server ห้ามเชื่อเวลาจาก client

## Config
- ค่าตัวเลขของเกมทั้งหมด (ราคา เวลา จำนวน อัตรา ระดับปลดล็อก) อยู่ใน `src/shared/Config/` **ห้าม hardcode** ในโค้ด Service หรือ Controller
- ไฟล์ Config คืนตารางที่ผ่าน `table.freeze` และ export type ไว้ให้ใช้
- ค่าคงที่ทางเทคนิคล้วน (เช่น timeout ของ WaitForChild) ใส่ไว้บนสุดของไฟล์เป็น `UPPER_SNAKE_CASE` ได้

## สไตล์
- ตัวแปรและฟังก์ชันเป็น camelCase ส่วนโมดูล type และ Instance เป็น PascalCase ค่าคงที่เป็น UPPER_SNAKE_CASE
- ใช้ `task.wait` / `task.spawn` / `task.delay` ห้ามใช้ `wait` / `spawn` / `delay` แบบเก่า
- ใช้ `game:GetService(...)` เสมอ

## Git และ PR
- **หนึ่ง PR ต่อหนึ่ง TASK**
- ชื่อ branch: `task-XXX-ชื่อสั้น` เช่น `task-002-player-data`
- ชื่อ PR: `TASK-XXX: คำอธิบายสั้น` และในคำอธิบายต้องใส่ `Closes #<เลข Issue>`
- ก่อนเปิด PR: `rojo build -o build.rbxlx` ต้องผ่าน และกด Play ใน Studio แล้วไม่มี error ใน Output
- ห้ามแก้ไฟล์นอกขอบเขตของ TASK ถ้าเห็นปัญหาอื่น ให้เปิด Issue ใหม่แทน
