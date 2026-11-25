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

## Day/Night (TASK-012)
- วงจร `Day → Dusk → Night → Dawn → Day` ช่วงที่ยาว 0 วินาทีถูกข้าม เลขคืน = เลขวันเดียวกัน (Dusk/Night/Dawn ของวันที่ N คือคืนที่ N)
- เริ่มนับเมื่อผู้เล่นคนแรกเข้า หยุดเมื่อไม่มีผู้เล่น และนับต่อจากเวลาที่เหลือเดิม เลขวันไม่รีเซ็ต สถานะอยู่ในหน่วยความจำ ไม่บันทึก DataStore
- ความยาวช่วงตามโหมด (วินาที วัน/ค่ำ/คืน/รุ่งเช้า): Easy 180/60/180/60, Hard 180/60/240/60, Nightmare 180/60/300/60 เตือนก่อนค่ำ 30 วิ ครั้งเดียวต่อวัน
- ใน Studio ใช้ค่าสั้น: Easy 40/6/40/6, Hard 40/6/55/6, Nightmare 40/6/70/6 เตือน 10 วิ ทุกค่าอยู่ใน `Config/DayNight`
- โหมดอ่านจาก attribute `DayNightMode` บน `ReplicatedStorage` ตอนเริ่มรอบ (ผู้เล่นคนแรกเข้า) ไม่มี = Easy ค่าที่ไม่รู้จัก = Easy พร้อม `warn` (และ toast ใน Studio) ระบบเลือกโหมด (TASK-019) ต้องตั้ง attribute นี้ก่อนผู้เล่นคนแรกเข้า
- sync ไป client ด้วย attributes บน `ReplicatedStorage` อย่างเดียว ไม่มี remote ใหม่: `DayNightPhase`, `DayNightDay`, `DayNightPhaseSeconds`, `DayNightPhaseEndsAt` (เวลา server)
- API ฝั่ง server (`DayNightService`): `GetMode()`, `GetPhase()`, `GetDayNumber()`, `GetNightNumber()`, `GetTimeRemaining()`, `IsNight()`, `IsRunning()`
- สัญญาณฝั่ง server (ฟังก์ชันที่มี type คืน `RBXScriptConnection`): `OnPhaseChanged(callback: (phase, dayNumber) -> ())`, `OnNightStarted(callback: (nightNumber) -> ())` ตอนเริ่ม Night, `OnMorningStarted(callback: (dayNumber) -> ())` ตอนเริ่ม Day หลัง Dawn (วันที่ 1 ตอนเริ่มรอบยิงเฉพาะ `OnPhaseChanged`)
- `GetNightNumber()` = คืนของ "วันนี้" ตอน Day วันที่ N คืน N ยังไม่เกิด ใช้ `IsNight()` เช็คว่าอยู่ในคืนหรือไม่
- client (`DayNightController`) แสดงกล่อง phase/วัน-คืน/เวลาที่เหลือกลางบนจอ และปรับ Lighting/Atmosphere (ถ้ามี Atmosphere อยู่แล้วใน Lighting จะถูกเขียนทับค่า)

## Anomaly framework (TASK-013)
- ทุกคืน (`DayNightService.OnNightStarted`) `AnomalyService` สุ่มชนิดคืน `Normal`/`Anomaly` จาก `Config/Anomalies.Modes[โหมด].NightTypeWeights` (โหมดอ่านจาก `DayNightService.GetMode()`) คืนที่ 1..`GuaranteedNormalNights` (ตอนนี้ 1) เป็นคืนปกติเสมอ
- คืน anomaly: กรอง entry ที่ valid และ `Subtlety <= MaxSubtlety` ของโหมด สุ่มตาม `Weight` ไม่ซ้ำ จำนวน `AnomaliesMin..Max` เกิดในช่วง `SpawnWindow` (สัดส่วนของเวลาคืน) เวลานับเฉพาะตอน DayNight กำลังนับ ไม่มี anomaly ที่ใช้ได้เลย = ถือเป็นคืนปกติ + `warn`
- ล้างทุกอย่างตอน `OnMorningStarted` (`Revert` + ลบของใน Workspace `AnomalyProps`) และ log จำนวนที่ล้าง/ของค้าง
- Subtlety สเกล 1-5 (1 = เห็นชัด) Category: `customer`, `oven`, `farm`, `shop`, `sky`, `sound` anomaly ทดสอบ: `ColorShift`, `Relocate` (หมวด `shop` เฉพาะ `Workspace.ServeStations`)
- เพิ่ม anomaly ใหม่ = เพิ่ม Entry ใน `Config/Anomalies` + `src/server/Anomalies/<Id>.luau` (`Spawn(context)` คืน `Handle`) ไม่ต้องแก้ `AnomalyService` ไม่มี remote client ไม่รู้ว่ามี anomaly
- API ฝั่ง server: `GetNightType`, `GetActiveAnomalies`, `ResolveAnomaly(instanceId)`, `GetCategories`, `HasActiveOfCategory(category, customerId?)`, `GetActiveOfCategory`, `GetNightRoster`, `MarkCustomerHandled(slotId, "Served" | "Reported")` สัญญาณ: `OnNightType`, `OnAnomalySpawned`, `OnAnomalyResolved(anomaly, byPlayer)`, `OnRosterComplete`, `OnNightEnded(night, missed)`
- โควตาลูกค้ากลางคืน (roster ตัวนับใน `AnomalyService` ยังไม่ผูกลูกค้าจริง): สุ่ม `BaseMin..BaseMax` เพิ่ม `GrowthAmount` ทุก `GrowthEveryNights` คืน clamp `HardMin..HardMax` (1..5) `Pending == 0` ยิง `OnRosterComplete` ครั้งเดียว ตอน Dawn slot ที่ค้างเป็น `Missed` แล้วยิง `OnNightEnded`
- `DayNightService.RequestEndNight(countdownSeconds)` ย่อเวลาที่เหลือของคืน (ไม่ยืดคืน เหลือน้อยกว่า countdown อยู่แล้ว = ไม่ทำอะไร คืน `true`) ตรวจค่าด้วย `DayNightRules.ClampEndCountdown`
- เครื่องมือ Studio (เฉพาะ `RunService:IsStudio()`) attribute บน `ServerStorage`: `AnomalyForceNight` (`Anomaly`/`Normal`), `AnomalyForceIds` (เช่น `ColorShift,Relocate` เกิดทันที), `AnomalyDebugHandle` (จำนวนลูกค้าที่ให้ถือว่าเสิร์ฟแล้ว)

## รายงานผู้จัดการ + สติ (TASK-014)
- ผู้จัดการร้าน (`ReportService` สร้างโมเดลจาก Part ใน `Workspace.ShopManager` ตำแหน่งอิง SpawnLocation) มี ProximityPrompt "รายงาน" ผู้เล่นต้องเดินไปหาเอง server เปิดเมนูรายงาน (session ที่ server) ให้เฉพาะผู้ที่กด รายงานได้เฉพาะตอนกลางคืนที่กำลังนับเวลา
- remote ใหม่ 3 ตัว: `ReportSubmit` (client→server: `category`, `customerId?`), `ReportMenu`, `ReportResult` (server→client) rate limit `ReportSubmit`/`ReportPrompt` ใน `Config/RateLimits` สติและนับถอยหลังจบคืนส่งด้วย attribute (ไม่มี remote)
- server ตรวจ: rate limit, ชนิด/ค่า (หมวดต้องอยู่ใน `AnomalyService.GetCategories()`, `customerId` เฉพาะหมวด customer และต้องอยู่ในรายชื่อที่ server ส่งให้เมนู), session เมนู, ระยะจากผู้จัดการ, ช่วงคืน, cooldown, ข้อมูลผู้เล่น
- ถูก (`HasActiveOfCategory`): `ResolveAnomaly` + เหรียญเฉพาะผู้รายงาน (`CoinReward + CoinPerSubtlety x Subtlety`) + ตัวนับสูตรต่อรอบ (`ReportService.GetRecipeProgress()` อยู่ใน memory หน้าสูตรจริงเป็น TASK-018) + ลูกค้า anomaly ปิด slot เป็น `Reported` + ผู้จัดการชม
- ผิด (รวมคืนที่ไม่มี anomaly): ผู้รายงานเสียสติ `Sanity.Values.WrongReport` + ผู้จัดการหลอนขึ้นตามจำนวนครั้งที่ผิดในคืนนั้น (`Report.WrongHauntLevels`/`HauntStyles` ระดับ 1-3+) ไม่ทำร้ายใคร
- บทผู้จัดการอยู่ใน `Config/ManagerLines` (th/en แยกตามสถานการณ์ สุ่มบรรทัด) แก้ได้โดยไม่แตะโค้ด
- `SanityService`: สติต่อผู้เล่นใน memory (รีเซ็ตทุกคืน) API `Get`, `GetMax`, `Change(player, delta, reason)`, `Set`, `ResetAll`, `OnChanged`, `OnDepleted` (ยิงตอนข้ามลงถึง 0) ค่าอยู่ใน `Config/Sanity`
- `NightFlowService`: ออเดอร์ที่เสิร์ฟตอนคืน (`ServeService.OnOrderServed`) 1 ออเดอร์ = ปิด roster 1 slot เป็น `Served`; roster ครบ -> toast + นับถอยหลัง + `DayNightService.RequestEndNight(Report.EndNightCountdownSeconds)`; หมดเวลาแล้วลูกค้าเหลือ / anomaly ไม่ถูกรายงานจนเช้า -> ทุกคนเสียสติ
- ข้อยกเว้นที่เจ้าของอนุมัติ: เพิ่ม `ServeService.OnOrderServed` และ `ServeService.GetActiveCustomers` (เพิ่มอย่างเดียว)
- เครื่องมือ Studio (เฉพาะ `RunService:IsStudio()` attribute บน `ServerStorage`): `SanityDebugSet` (ตัวเลข = ตั้งสติทุกคน), `NightDebugRosterComplete` (true = roster ครบทันที) ร่วมกับ `AnomalyForceNight`/`AnomalyForceIds` ของ TASK-013
