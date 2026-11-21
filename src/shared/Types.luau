--!strict
-- ชนิดข้อมูลที่ server และ client ใช้ร่วมกัน

export type Counts = { [string]: number }

export type OvenSlot = {
	recipeId: string,
	pieces: number,
	readyAt: number, -- os.time() ฝั่ง server
}

export type Settings = {
	language: string, -- "th" | "en"
}

export type SaveData = {
	version: number,
	coins: number,
	reputation: number,
	ingredients: Counts,
	goods: Counts,
	upgrades: Counts,
	questDay: number,
	questProgress: Counts,
	questClaimed: boolean,
	oven: { OvenSlot },
	settings: Settings,
	totalServed: number,
	totalBaked: number,
}

-- สิ่งที่ server ส่งให้ client (SaveData + ค่าที่คำนวณแล้ว)
export type PlayerState = {
	coins: number,
	reputation: number,
	level: number,
	levelFloor: number,
	levelCeil: number, -- 0 = เลเวลสูงสุดแล้ว
	ingredients: Counts,
	goods: Counts,
	upgrades: Counts,
	questProgress: Counts,
	questClaimed: boolean,
	oven: { OvenSlot },
	ovenSlots: number,
	settings: Settings,
	dataSaving: boolean, -- false = รอบนี้บันทึกไม่ได้ (โหลดล้มเหลว / Studio ปิด API)
	serverTime: number,
}

export type Order = {
	id: number,
	animalId: string,
	recipeId: string,
	amount: number,
	createdAt: number, -- workspace:GetServerTimeNow()
	expiresAt: number,
	seated: boolean,
}

export type NotifyKind = "success" | "info" | "warn" | "error"

export type NotifyPayload = {
	kind: NotifyKind,
	key: string,
	args: { [string]: string | number }?,
}

export type StartMixResult = {
	ok: boolean,
	reason: string?,
	sessionId: number?,
	recipeId: string?,
	beats: { number }?,
	leadIn: number?,
	duration: number?,
}

export type FinishMixResult = {
	ok: boolean,
	reason: string?,
	quality: string?, -- "Perfect" | "Good" | "Okay"
	score: number?,
	pieces: number?,
	readyIn: number?,
}

export type SimpleResult = {
	ok: boolean,
	reason: string?,
}

return {}
