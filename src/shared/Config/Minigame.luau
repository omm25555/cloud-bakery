--!strict
-- มินิเกมจังหวะตอนผสมแป้ง (server สุ่มจังหวะ + ตัดสินผล)

local Minigame = {
	BeatCount = 6,
	LeadInSeconds = 1.5,
	BeatIntervalMinSeconds = 0.7,
	BeatIntervalMaxSeconds = 1.1,
	TailSeconds = 0.8,

	PerfectWindowSeconds = 0.12,
	GoodWindowSeconds = 0.25,
	GoodHitScore = 0.5,
	PerfectQualityThreshold = 0.85,
	GoodQualityThreshold = 0.5,

	MaxTaps = 20,
	-- เวลาเผื่อ latency ระหว่างเวลาที่ client รายงานกับเวลาที่ server นับ
	LatencyToleranceSeconds = 1.0,
	SessionTimeoutSeconds = 30,
	-- ถ้าทุกจังหวะคลาดเคลื่อนน้อยกว่านี้ ถือว่าน่าสงสัย (กดด้วยสคริปต์) ให้ผลไม่เกิน Good
	SuspiciousErrorSeconds = 0.004,

	PerfectBonusPieces = 1,
	BasePieces = 1,
	QualityReputation = { Perfect = 15, Good = 8, Okay = 3 } :: { [string]: number },

	-- client: ความกว้างแถบมินิเกม (สัดส่วนจอ) และเวลาแสดงผลลัพธ์
	ResultDisplaySeconds = 1.6,
}

return Minigame
