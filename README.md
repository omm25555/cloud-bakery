# Cloud Bakery: เบเกอรี่ลอยฟ้า

เกม Roblox แนว cozy co-op bakery simulation บนเกาะลอยฟ้า
วงจรหลัก: Harvest → Bake → Serve → Upgrade ดูรายละเอียดใน [docs/GDD.md](docs/GDD.md)

## เอกสาร
- [CLAUDE.md](CLAUDE.md) กติกาโค้ด
- [docs/RULES.md](docs/RULES.md) กฎฉบับเต็มของโปรเจกต์
- [docs/GDD.md](docs/GDD.md) สรุปเกม
- [docs/ROADMAP.md](docs/ROADMAP.md) 8 เฟสของ MVP

## เริ่มใช้งาน
1. ติดตั้ง [Rokit](https://github.com/rojo-rbx/rokit) แล้วรันในโฟลเดอร์โปรเจกต์:
   ```
   rokit install
   ```
   (ติดตั้ง Rojo ตามเวอร์ชันที่ล็อกใน `rokit.toml`)
2. ติดตั้งปลั๊กอิน Rojo ใน Roblox Studio (`rojo plugin install` หรือจาก Creator Store)
3. รัน dev server:
   ```
   rojo serve
   ```
4. เปิด Studio (place ว่าง) กดปุ่ม Rojo > Connect
5. กด Play ต้องเห็นใน Output:
   ```
   [Server] Bootstrap ทำงานแล้ว (Services ที่เริ่ม: 0)
   [Client] Bootstrap ทำงานแล้ว (Controllers ที่เริ่ม: 0)
   ```

ตรวจว่า build ผ่าน: `rojo build -o build/CloudBakery.rbxl`

## โครงสร้าง
| โฟลเดอร์ | ปลายทางใน Studio |
|---|---|
| `src/server` | `ServerScriptService.Server` |
| `src/client` | `StarterPlayer.StarterPlayerScripts.Client` |
| `src/shared` | `ReplicatedStorage.Shared` |
