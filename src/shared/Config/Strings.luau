--!strict
-- ข้อความทั้งหมดที่แสดงให้ผู้เล่น (ไทย/อังกฤษ) ใช้ {ชื่อ} เป็นตัวแทนค่า

export type Entry = { th: string, en: string }

local UnknownError: Entry = {
	th = "เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้ง",
	en = "Something went wrong. Please try again.",
}

local Messages: { [string]: Entry } = {
	UnknownError = UnknownError,
	DataLoaded = {
		th = "โหลดข้อมูลของคุณสำเร็จแล้ว",
		en = "Your data has been loaded.",
	},
	TemporaryMode = {
		th = "โหมดทดสอบ: ข้อมูลของคุณจะไม่ถูกบันทึก",
		en = "Test mode: your progress will not be saved.",
	},
	SaveRetrying = {
		th = "บันทึกข้อมูลไม่สำเร็จ กำลังลองใหม่...",
		en = "Couldn't save your data. Retrying...",
	},
	SaveFailed = {
		th = "บันทึกข้อมูลไม่สำเร็จ ระบบจะลองใหม่อีกครั้งในรอบถัดไป",
		en = "Saving failed. We'll try again shortly.",
	},
	RateLimited = {
		th = "ส่งคำขอถี่เกินไป กรุณารอสักครู่",
		en = "Too many requests. Please wait a moment.",
	},
	KickLoadFailed = {
		th = "โหลดข้อมูลไม่สำเร็จ ข้อมูลของคุณปลอดภัย กรุณาเข้าเกมใหม่อีกครั้ง",
		en = "Couldn't load your data. Your data is safe. Please rejoin the game.",
	},
	KickDataLocked = {
		th = "ข้อมูลของคุณยังถูกใช้งานอยู่ในเซิร์ฟเวอร์อื่น ข้อมูลปลอดภัย กรุณารอสักครู่แล้วเข้าเกมใหม่",
		en = "Your data is still in use on another server. Your data is safe. Please wait a moment and rejoin.",
	},
	KickLockLost = {
		th = "ข้อมูลของคุณถูกเซิร์ฟเวอร์อื่นเข้าใช้งานแล้ว ระบบหยุดบันทึกเพื่อไม่ให้ข้อมูลทับกัน ข้อมูลปลอดภัย กรุณาเข้าเกมใหม่",
		en = "Your data was taken over by another server. Saving was stopped to avoid overwriting. Your data is safe. Please rejoin.",
	},
	KickDataNewer = {
		th = "ข้อมูลของคุณถูกบันทึกด้วยเกมเวอร์ชันที่ใหม่กว่าเซิร์ฟเวอร์นี้ ข้อมูลปลอดภัย กรุณาเข้าเกมใหม่",
		en = "Your data was saved by a newer game version than this server. Your data is safe. Please rejoin.",
	},
	KickDataCorrupt = {
		th = "ข้อมูลของคุณมีรูปแบบที่ไม่ถูกต้อง ระบบไม่ได้แก้ไขข้อมูลเดิม กรุณาติดต่อผู้พัฒนา",
		en = "Your data has an invalid format. It was not modified. Please contact the developers.",
	},
	PlantOk = {
		th = "ปลูก{crop}แล้ว รอให้โตนะ",
		en = "Planted {crop}. Wait for it to grow!",
	},
	HarvestOk = {
		th = "เก็บ{crop}ได้ {amount} ชิ้น",
		en = "Harvested {amount} x {crop}.",
	},
	HarvestByOther = {
		th = "{player} เก็บ{crop} {amount} ชิ้นจากแปลงของคุณ",
		en = "{player} harvested {amount} x {crop} from your plot.",
	},
	NotReady = {
		th = "{crop}ยังไม่โต เหลืออีก {seconds} วินาที",
		en = "{crop} isn't ready yet. {seconds} seconds left.",
	},
	PlotOccupied = {
		th = "แปลงนี้มีพืชอยู่แล้ว",
		en = "This plot already has a crop.",
	},
	PlotEmpty = {
		th = "แปลงนี้ว่าง ไม่มีอะไรให้เก็บ",
		en = "This plot is empty. Nothing to harvest.",
	},
	InventoryFull = {
		th = "กระเป๋าเต็ม เก็บไม่ได้ พืชยังอยู่ในแปลง",
		en = "Your bag is full. The crop stays in the plot.",
	},
	DataNotReady = {
		th = "ข้อมูลของคุณยังโหลดไม่เสร็จ กรุณารอสักครู่",
		en = "Your data is still loading. Please wait a moment.",
	},
	TooFar = {
		th = "อยู่ไกลแปลงเกินไป เดินเข้าไปใกล้ ๆ ก่อน",
		en = "You're too far from the plot. Move closer.",
	},
	InvalidRequest = {
		th = "คำขอไม่ถูกต้อง ทำรายการไม่ได้",
		en = "Invalid request. Couldn't do that.",
	},
	NoPermission = {
		th = "แปลงนี้เก็บได้เฉพาะคนปลูก",
		en = "Only the planter can harvest this plot.",
	},
	NotEnoughCoins = {
		th = "เหรียญไม่พอ ต้องใช้ {cost} เหรียญ",
		en = "Not enough coins. You need {cost}.",
	},
	UiPlotEmpty = {
		th = "แปลงว่าง",
		en = "Empty plot",
	},
	UiPlotGrowing = {
		th = "{crop} กำลังโต\nเหลือ {seconds} วินาที",
		en = "{crop} growing\n{seconds}s left",
	},
	UiPlotReady = {
		th = "{crop} พร้อมเก็บ!",
		en = "{crop} ready!",
	},
	UiPromptPlant = {
		th = "ปลูก{crop}",
		en = "Plant {crop}",
	},
	UiPromptHarvest = {
		th = "เก็บเกี่ยว",
		en = "Harvest",
	},
	UiPromptObject = {
		th = "แปลงปลูก",
		en = "Farm plot",
	},
	UiInventoryTitle = {
		th = "กระเป๋า {used}/{capacity}",
		en = "Bag {used}/{capacity}",
	},
	UiInventoryItem = {
		th = "{name} x{count}",
		en = "{name} x{count}",
	},
	UiInventoryEmpty = {
		th = "(ว่าง)",
		en = "(empty)",
	},
	BakeStartOk = {
		th = "เริ่มอบ{dish}แล้ว รออีก {seconds} วินาที แล้วไปกดที่เตา",
		en = "Started baking {dish}. Wait {seconds}s, then use the oven.",
	},
	BakeMissingIngredients = {
		th = "วัตถุดิบไม่พอ ขาด {name} อีก {count}",
		en = "Not enough ingredients. Missing {count} x {name}.",
	},
	OvensBusy = {
		th = "เตาอบไม่ว่าง เตาที่ว่างเร็วที่สุดอีก {seconds} วินาที",
		en = "All ovens are busy. The soonest one is ready in {seconds}s.",
	},
	OvensBusyWaiting = {
		th = "เตาอบไม่ว่าง ทุกเตายังมีขนมรอเก็บหรือกำลังเล่นมินิเกม",
		en = "All ovens are busy. Each one has a bake waiting or a minigame in progress.",
	},
	BakeNotReady = {
		th = "{dish}ยังอบไม่เสร็จ เหลืออีก {seconds} วินาที",
		en = "{dish} isn't done baking yet. {seconds} seconds left.",
	},
	OvenIdle = {
		th = "เตานี้ว่าง ไม่มีขนมให้เก็บ",
		en = "This oven is empty. Nothing to collect.",
	},
	OvenNotYours = {
		th = "เตานี้เป็นของ {owner}",
		en = "This oven belongs to {owner}.",
	},
	BakeTooFar = {
		th = "อยู่ไกลเกินไป เดินเข้าไปใกล้โต๊ะหรือเตาก่อน",
		en = "You're too far away. Move closer to the table or oven.",
	},
	BakeNoRoom = {
		th = "กระเป๋าไม่มีที่พอสำหรับขนมที่จะได้ เหลือที่ {free} ต้องการ {need} กรุณาเคลียร์กระเป๋าก่อน",
		en = "Not enough bag space for the bake. Free: {free}, needed: {need}. Clear some space first.",
	},
	BakeCollectFull = {
		th = "กระเป๋าเต็ม เหลือที่ {free} ต้องการ {need} ขนมยังรออยู่ในเตา เคลียร์กระเป๋าแล้วกดเตาอีกครั้ง",
		en = "Your bag is full. Free: {free}, needed: {need}. The bake stays in the oven. Clear space and use the oven again.",
	},
	MinigameStart = {
		th = "มินิเกมเริ่มแล้ว! กดให้ตรงโซน {count} ครั้ง",
		en = "Minigame started! Tap in the zone {count} times.",
	},
	MinigameGradePerfect = {
		th = "ยอดเยี่ยม! ระดับ Perfect",
		en = "Perfect grade!",
	},
	MinigameGradeGood = {
		th = "ระดับ Good",
		en = "Good grade!",
	},
	MinigameGradeMiss = {
		th = "ระดับ Miss",
		en = "Miss grade.",
	},
	MinigameRejected = {
		th = "ผลการกดครั้งนี้ไม่ผ่านการตรวจ นับเป็น Miss",
		en = "That tap didn't pass validation. Counted as a Miss.",
	},
	MinigameTimeout = {
		th = "หมดเวลามินิเกม ครั้งที่ไม่ได้กดนับเป็น Miss",
		en = "Minigame timed out. Missed taps count as Miss.",
	},
	MinigameNotActive = {
		th = "ตอนนี้ไม่มีมินิเกมที่เตานี้ (อาจหมดเวลาแล้ว)",
		en = "There's no minigame at this oven right now (it may have timed out).",
	},
	BakeCollected = {
		th = "ได้{dish} {amount} ชิ้น ใส่กระเป๋าแล้ว",
		en = "Got {amount} x {dish}. Added to your bag.",
	},
	UiBakeMixObject = {
		th = "โต๊ะผสม",
		en = "Mixing table",
	},
	UiBakeMixPrompt = {
		th = "ผสมขนม",
		en = "Mix a bake",
	},
	UiBakeMixLabel = {
		th = "โต๊ะผสม\nเลือกสูตรแล้วใส่เตาที่ว่าง",
		en = "Mixing table\nPick a recipe for a free oven",
	},
	UiOvenObject = {
		th = "เตาอบ",
		en = "Oven",
	},
	UiOvenPromptCollect = {
		th = "เก็บขนม",
		en = "Collect bake",
	},
	UiOvenPromptCheck = {
		th = "ดูเตา",
		en = "Check oven",
	},
	UiOvenIdle = {
		th = "เตาว่าง",
		en = "Oven empty",
	},
	UiOvenBaking = {
		th = "{dish} กำลังอบ\nเหลือ {seconds} วินาที\nของ {owner}",
		en = "{dish} baking\n{seconds}s left\n{owner}'s oven",
	},
	UiOvenReady = {
		th = "{dish} อบเสร็จ!\nกดเพื่อเล่นมินิเกม\nของ {owner}",
		en = "{dish} is done!\nUse it to play the minigame\n{owner}'s oven",
	},
	UiOvenMinigame = {
		th = "{owner} กำลังเล่นมินิเกม",
		en = "{owner} is playing the minigame",
	},
	UiOvenDone = {
		th = "{dish} x{amount} รอเก็บ\nของ {owner}",
		en = "{dish} x{amount} waiting\n{owner}'s oven",
	},
	UiMixTitle = {
		th = "เลือกสูตร",
		en = "Choose a recipe",
	},
	UiMixClose = {
		th = "ปิด",
		en = "Close",
	},
	UiMixRecipe = {
		th = "{dish}\nต้องใช้: {needs}",
		en = "{dish}\nNeeds: {needs}",
	},
	UiMixNeedItem = {
		th = "{name} {have}/{need}",
		en = "{name} {have}/{need}",
	},
	UiMinigameTitle = {
		th = "กดให้ตรงโซน ({index}/{count})",
		en = "Tap in the zone ({index}/{count})",
	},
	UiMinigameTap = {
		th = "กด!",
		en = "Tap!",
	},
	UiJudgePerfect = {
		th = "Perfect!",
		en = "Perfect!",
	},
	UiJudgeGood = {
		th = "Good!",
		en = "Good!",
	},
	UiJudgeMiss = {
		th = "Miss",
		en = "Miss",
	},
}

local Strings = {}

Strings.Messages = Messages

function Strings.Has(key: string): boolean
	return Messages[key] ~= nil
end

-- แปลข้อความตามภาษา ("en" หรืออย่างอื่นใช้ไทย) ถ้าไม่พบ key ใช้ข้อความกลาง
function Strings.Format(key: string, language: string, args: { [string]: string | number }?): string
	local entry = Messages[key] or UnknownError
	local text = if language == "en" then entry.en else entry.th
	if args == nil then
		return text
	end
	local result = string.gsub(text, "{(%w+)}", function(name: string): string
		local value = args[name]
		if value == nil then
			return "{" .. name .. "}"
		end
		return tostring(value)
	end)
	return result
end

-- สองภาษาในข้อความเดียว (ไทยบรรทัดแรก อังกฤษบรรทัดสอง) ใช้กับ kick
function Strings.Bilingual(key: string): string
	local entry = Messages[key] or UnknownError
	return entry.th .. "\n" .. entry.en
end

return Strings
