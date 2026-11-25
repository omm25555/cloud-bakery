# Roadmap (MVP 8 เฟส)

แต่ละเฟสแตกเป็น TASK ย่อย หนึ่ง PR ต่อหนึ่ง TASK

| เฟส | ชื่อ | เนื้อหา | สถานะ |
|---|---|---|---|
| 1 | Foundation | Rojo, โครง repo, CLAUDE.md, RULES, Config เบื้องต้น, Remotes | TASK-001 |
| 2 | Core Services | PlayerData + DataStore (retry, save on leave/BindToClose), ระบบแจ้งเตือนกลาง, rate limit | - |
| 3 | Harvest | ปลูก/เก็บข้าวสาลี Star Milk สตรอว์เบอรี เวลาโตตัดสินที่ server, กระเป๋า | - |
| 4 | Bake | โต๊ะผสม เตาอบ มินิเกมจังหวะ (server ตรวจผล) | - |
| 5 | Serve | ลูกค้า NPC (Panda, Fox, Bunny) ออเดอร์ การเสิร์ฟ เหรียญ/Reputation | - |
| 6 | Upgrade | อัปเกรด 3 สาย, UI Upgrade/Recipes/Bag/Settings | - |
| 7 | HUD & Quest | HUD ตาม concept, Daily Quest, Orders panel, 2 ภาษา | - |
| 8 | Co-op & Polish | co-op แบบเบา, เสียง/เอฟเฟกต์, ปรับบาลานซ์, ทดสอบ | - |

## หลัง MVP (ยังไม่ทำ)
- สัตว์เลี้ยง: แมวเมฆมีปีก (นมเมฆ), กระต่ายสายหวาน (สตรอว์เบอรี), มังกรขนม (โกโก้), แกะ, นก
- เส้นทางเติบโต: ร้านเล็ก → ร้านคึกคัก → เบเกอรี่เวทมนตร์ → เกาะสวนกุหลาบ → เกาะน้ำตกช็อกโกแลต
- โซเชียล: Tea Time Plaza, ปาร์ตี้วันเกิด
- ลูกค้าเพนกวิน (ผ้าพันคอ)
- Monetization แบบ Non-Pay-to-Win: ชุดเชฟ, สกินเตาพาสเทล, ของตกแต่ง, VIP Decor Pack
- ปุ่ม Pets/Decor ใน HUD (MVP แสดงแต่ล็อก "เร็วๆ นี้")

## Lobby และ Teleport (TASK-011)
- repo มี 2 Rojo project: `default.project.json` (เกาะ) และ `lobby.project.json` (ล็อบบี้ `CloudBakeryLobby`)
- ล็อบบี้ไม่มี DataService ใช้ `NotifyService` / `NotifyController` ร่วมกับเกาะ โค้ดอยู่ใน `src/lobby/`
- ผู้เล่นเข้ากลุ่มที่แท่นผ่าน ProximityPrompt สูงสุด 4 คน นับถอยหลัง 15 วิ (เหลือ 5 วิเมื่อครบ 4 คน) ตัวเลขอยู่ใน `Config/Lobby`
- กลุ่มถูก teleport ไป reserved server ของเกาะผ่าน `TeleportOptions.ReservedServerId` (GUID ที่ server สร้าง) พร้อม retry ตาม Config
- ต้องกรอก Place ID ใน `Config/Places` (0 = ยังไม่ตั้ง จะแจ้งผู้เล่นและ `warn` ไม่ teleport)
- `RoundEntryService` ของเกาะมี 3 โหมด: `Local` (Studio), `Reserved` (ตรวจ TeleportData จาก lobby), `Direct` (เข้าตรงโดยไม่ผ่าน lobby แจ้งผู้เล่นและพากลับ lobby ได้)
