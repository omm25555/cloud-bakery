# Cloud Bakery: เบเกอรี่ลอยฟ้า

เกม Roblox แนว cozy co-op bakery simulation บนเกาะลอยฟ้า วงจรหลักคือ Harvest → Bake → Serve → Upgrade

- เอกสารเกม: [docs/GDD.md](docs/GDD.md)
- แผนงาน: [docs/ROADMAP.md](docs/ROADMAP.md)
- กติกาโค้ด: [CLAUDE.md](CLAUDE.md)

## สิ่งที่ต้องมี
- [Roblox Studio](https://create.roblox.com/)
- [Rokit](https://github.com/rojo-rbx/rokit) (ตัวจัดการเวอร์ชันของ Rojo)
- ปลั๊กอิน Rojo ใน Studio (ติดตั้งด้วย `rojo plugin install` หรือจาก Creator Store)

## เริ่มใช้งาน
```sh
rokit install        # ติดตั้ง Rojo ตามเวอร์ชันใน rokit.toml
rojo serve           # เริ่มเซิร์ฟเวอร์ซิงก์ที่ localhost:34872
```
จากนั้นเปิด place ใน Studio ไปที่แท็บ **Plugins**, เปิด **Rojo** แล้วกด **Connect** จากนั้นกด **Play** แล้ว Output จะแสดง:
```
[Server] Cloud Bakery bootstrap complete (0 services)
[Client] Cloud Bakery bootstrap complete (0 controllers)
```

## Build เป็นไฟล์ place
```sh
rojo build -o build.rbxlx
```

## โครงสร้าง
```
src/
  server/   → ServerScriptService.Server            (Services/)
  client/   → StarterPlayer.StarterPlayerScripts.Client (Controllers/)
  shared/   → ReplicatedStorage.Shared              (Config/, Remotes.luau)
docs/       GDD.md, ROADMAP.md
```
