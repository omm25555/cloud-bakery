--!strict
-- บทพูดของผู้จัดการร้าน (th/en) แก้/เพิ่มบรรทัดได้โดยไม่ต้องแตะโค้ด ระบบสุ่มหนึ่งบรรทัดจากรายการของสถานการณ์นั้น
-- สถานการณ์: Praise (รายงานถูก), Wrong1/Wrong2/Wrong3 (ผิดครั้งที่ 1, 2, 3 ขึ้นไปของคืนนั้น ตรงกับระดับใน Config/Report.WrongHauntLevels),
--   MenuOpen (เปิดเมนู), WrongNone (ผิดครั้งที่ 1 ของคืนที่ไม่มี anomaly เลย ครั้งที่ 2 ขึ้นไปใช้ Wrong2/Wrong3 ตามปกติ)
-- ถ้าเพิ่มระดับใน WrongHauntLevels ต้องเพิ่มสถานการณ์ Wrong<N> ให้ครบ ถ้ารายการว่างระบบ warn และใช้ FallbackLine
-- เนื้อหาเหมาะกับเด็ก: หลอนนิดๆ ไม่ขู่ ไม่ทำร้าย แต่ละบรรทัดควรสั้น (ไม่เกิน ~60 ตัวอักษร)

export type Lines = { th: { string }, en: { string } }

local Situations: { [string]: Lines } = {
	Praise = {
		th = { "เก่งมาก! เห็นเหมือนกันเลย", "ตาไวจริงๆ! ขอบคุณนะ", "ถูกต้องเลย! ร้านเรากลับมาปกติแล้ว" },
		en = { "Great eye! I saw it too!", "Sharp eyes! Thank you!", "Correct! The shop is back to normal." },
	},
	Wrong1 = {
		th = { "อื้ม... ไม่เห็นมีอะไรนะ", "ตรงนั้นไม่มีอะไรหรอก...", "หืม? ผิดหรือเปล่านะ" },
		en = { "Hmm... I don't see anything.", "There's nothing there...", "Hm? Are you sure?" },
	},
	Wrong2 = {
		th = { "...ไม่มีอะไรนี่นา ...ใช่ไหม?", "ไม่มีอะไรทั้งนั้น... ไม่มีเลย...", "อย่าบอกนะว่าเธอเห็นอะไร..." },
		en = { "...There's nothing. ...Right?", "Nothing at all... nothing...", "Don't tell me you saw something..." },
	},
	Wrong3 = {
		th = { "ไม่มีอะไรทั้งนั้น~ ยิ้มไว้นะ :)", "ยิ้มสิ~ ยิ้มกว้างๆ เลย :)", "ไม่เป็นไรหรอก~ ไม่มีอะไรเลย :)" },
		en = { "Nothing at all~ Keep smiling :)", "Smile~ a big, big smile :)", "It's fine~ there's nothing :)" },
	},
	WrongNone = {
		th = { "คืนนี้เงียบสงบดีนะ... ไม่เห็นมีอะไรเลย", "ไม่มีอะไรให้รายงานหรอก..." },
		en = { "It's a calm night... I don't see anything.", "There's nothing to report..." },
	},
	MenuOpen = {
		th = { "มีอะไรจะบอกไหม?", "เห็นอะไรแปลกๆ หรือเปล่า?", "บอกผู้จัดการมาได้เลยนะ" },
		en = { "Anything to tell me?", "Did you see something odd?", "You can tell your manager!" },
	},
}

return {
	Situations = Situations,
	FallbackLine = { th = "...", en = "..." },
}
