# ROADMAP: Cloud Bakery MVP (8 เฟส)

แต่ละเฟสแตกเป็น TASK ย่อย (หนึ่ง Issue = หนึ่ง PR) ตามกติกาใน `CLAUDE.md`

| เฟส | ชื่อ | เป้าหมาย | ผลลัพธ์ที่ตรวจได้ |
|---|---|---|---|
| 1 | Foundation | โครง repo, Rojo, bootstrap, Remotes, Config เบื้องต้น, CLAUDE.md | `rojo serve` แล้วเชื่อม Studio ได้ และ Play แล้ว bootstrap ทำงาน (TASK-001) |
| 2 | Player Data | `PlayerDataService` โหลดตอนเข้า เซฟตอนออกและตอน BindToClose ใช้ UpdateAsync พร้อมโครงข้อมูลผู้เล่น | ออกแล้วเข้าใหม่ เหรียญและของยังอยู่ |
| 3 | Harvest | `FarmService` / `FarmController`: แปลงปลูก เวลาโตฝั่ง server เก็บเกี่ยวผ่านคำขอที่ server ตรวจ | ปลูก รอ เก็บ แล้ววัตถุดิบเข้ากระเป๋า |
| 4 | Bake | `BakeService`: ตรวจสูตรและหักวัตถุดิบ มินิเกมจังหวะที่ client ส่งเวลากด แล้ว server ให้คะแนน | อบ 3 สูตรได้ และคุณภาพมีผลกับราคา |
| 5 | Serve | `CustomerService`: NPC Panda, Fox, Bunny เดินเข้ามาสั่ง รอ แล้วรับขนม จ่ายเหรียญตามคุณภาพ | วงจร Harvest → Bake → Serve ครบ |
| 6 | Upgrade | `UpgradeService`: อัปเกรด 3 สาย ราคาและผลอยู่ใน Config แล้วบันทึกลง DataStore | ซื้ออัปเกรดแล้วเห็นผลจริงและยังอยู่หลังเข้าใหม่ |
| 7 | Co-op | ผู้เล่นหลายคนใช้ร้านเดียวกัน มีสิทธิ์ช่วยเก็บ อบ และเสิร์ฟ แบ่งรางวัลที่ server | 2 ผู้เล่นใน Studio Test เล่นร่วมกันได้ ไม่ desync |
| 8 | Polish & UI | HUD, เมนู, เสียง, juice, tutorial แรกเข้า, ตรวจ performance และ remote abuse | เล่นวงจรเต็มจากต้นถึงอัปเกรดแรกได้โดยไม่ต้องอธิบาย |

## หมายเหตุ
- โมเดลและแผนที่ทำคู่ขนานไปได้ ไม่ผูกกับเฟสโค้ด
- การ publish และการตั้งค่าเกมบน Roblox ให้ผู้จัดการเป็นคนทำ
