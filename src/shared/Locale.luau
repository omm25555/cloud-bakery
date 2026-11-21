--!strict
-- ข้อความ 2 ภาษา (ไทย / English) และไอคอน emoji
-- ใช้ {name} ในข้อความเพื่อแทนค่าจาก args

type Entry = { th: string, en: string }

local Strings: { [string]: Entry } = {
	-- ชื่อของ
	["item.Wheat"] = { th = "ข้าวสาลี", en = "Wheat" },
	["item.StarMilk"] = { th = "น้ำนมดาว", en = "Star Milk" },
	["item.Strawberry"] = { th = "สตรอว์เบอรี", en = "Strawberry" },
	["item.CloudBread"] = { th = "ขนมปังเมฆ", en = "Cloud Bread" },
	["item.Croissant"] = { th = "ครัวซองต์", en = "Croissant" },
	["item.StrawberryCake"] = { th = "เค้กสตรอว์เบอรี", en = "Strawberry Cake" },
	["animal.Panda"] = { th = "แพนด้า", en = "Panda" },
	["animal.Fox"] = { th = "สุนัขจิ้งจอก", en = "Fox" },
	["animal.Bunny"] = { th = "กระต่าย", en = "Bunny" },

	-- ProximityPrompt (server ตั้งเป็น 2 ภาษา)
	["hud.harvest"] = { th = "เก็บเกี่ยว", en = "Harvest" },
	["hud.mix"] = { th = "ผสมแป้ง", en = "Mix Dough" },
	["hud.collect"] = { th = "เก็บขนม", en = "Collect" },
	["hud.serve"] = { th = "เสิร์ฟ", en = "Serve" },
	["station.MixingTable"] = { th = "โต๊ะผสม", en = "Mixing Table" },
	["station.Oven"] = { th = "เตาอบ", en = "Oven" },

	-- HUD
	["hud.reputation"] = { th = "ชื่อเสียง", en = "Reputation" },
	["hud.level"] = { th = "Lv. {level}", en = "Lv. {level}" },
	["hud.maxLevel"] = { th = "เลเวลสูงสุด", en = "Max level" },
	["hud.quests"] = { th = "ภารกิจวันนี้", en = "Daily Quest" },
	["hud.reward"] = { th = "รางวัล", en = "Reward" },
	["hud.claim"] = { th = "รับรางวัล", en = "Claim" },
	["hud.claimed"] = { th = "รับแล้ว พรุ่งนี้มาใหม่นะ", en = "Claimed, come back tomorrow" },
	["hud.orders"] = { th = "ออเดอร์ที่รออยู่", en = "Orders" },
	["hud.noOrders"] = { th = "ยังไม่มีลูกค้า รอสักครู่นะ", en = "No customers yet" },
	["hud.walking"] = { th = "กำลังเดินมา", en = "On the way" },
	["hud.unsaved"] = { th = "รอบนี้ไม่บันทึกข้อมูล", en = "Progress is not being saved" },

	["quest.HarvestWheat"] = { th = "เก็บข้าวสาลี {goal} ช่อ", en = "Harvest Wheat {goal}" },
	["quest.BakeCloudBread"] = { th = "อบขนมปังเมฆ {goal} ชิ้น", en = "Bake Cloud Bread {goal}" },
	["quest.ServeOrders"] = { th = "เสิร์ฟออเดอร์ {goal} รายการ", en = "Serve {goal} Orders" },

	-- เมนูล่าง
	["menu.Bag"] = { th = "กระเป๋า", en = "Bag" },
	["menu.Recipes"] = { th = "สูตรขนม", en = "Recipes" },
	["menu.Upgrade"] = { th = "อัปเกรด", en = "Upgrade" },
	["menu.Pets"] = { th = "สัตว์เลี้ยง", en = "Pets" },
	["menu.Decor"] = { th = "ตกแต่ง", en = "Decor" },
	["menu.Settings"] = { th = "ตั้งค่า", en = "Settings" },
	["menu.close"] = { th = "ปิด", en = "Close" },

	["bag.ingredients"] = { th = "วัตถุดิบ", en = "Ingredients" },
	["bag.goods"] = { th = "ขนมพร้อมเสิร์ฟ", en = "Baked Goods" },
	["bag.oven"] = { th = "ในเตาอบ", en = "In the Oven" },
	["bag.ovenEmpty"] = { th = "เตาว่าง ไปผสมแป้งที่โต๊ะผสมได้เลย", en = "Oven is empty. Mix dough at the Mixing Table." },
	["bag.ovenReady"] = { th = "พร้อมแล้ว! ไปเก็บที่เตาอบ", en = "Ready! Collect at the Oven" },
	["bag.ovenTime"] = { th = "อีก {time}", en = "{time} left" },

	["recipes.needs"] = { th = "ใช้", en = "Needs" },
	["recipes.price"] = { th = "ราคา {coins} เหรียญ", en = "Sells for {coins} coins" },
	["recipes.bakeTime"] = { th = "อบ {seconds} วินาที", en = "Bakes in {seconds}s" },
	["recipes.locked"] = { th = "ปลดล็อกที่ Lv. {level}", en = "Unlocks at Lv. {level}" },
	["recipes.mix"] = { th = "ผสม!", en = "Mix!" },

	["upgrade.Garden"] = { th = "สวนลอยฟ้า", en = "Sky Garden" },
	["upgrade.Oven"] = { th = "เตาอบ", en = "Oven" },
	["upgrade.Counter"] = { th = "หน้าร้าน", en = "Order Counter" },
	["upgrade.GardenEffect"] = { th = "เก็บเกี่ยวได้ +{value} ต่อครั้ง", en = "+{value} per harvest" },
	["upgrade.OvenEffect"] = { th = "อบเร็วขึ้น {value}% · {slots} ช่องอบ", en = "{value}% faster · {slots} oven slots" },
	["upgrade.CounterEffect"] = { th = "ทิปจากลูกค้า +{value}%", en = "+{value}% customer tips" },
	["upgrade.level"] = { th = "เลเวล {level}/{max}", en = "Level {level}/{max}" },
	["upgrade.buy"] = { th = "อัปเกรด {coins}", en = "Upgrade {coins}" },
	["upgrade.max"] = { th = "สูงสุดแล้ว", en = "Maxed" },

	["settings.language"] = { th = "ภาษา", en = "Language" },
	["settings.saveOk"] = { th = "บันทึกข้อมูลอัตโนมัติอยู่", en = "Progress saves automatically" },
	["settings.saveOff"] = {
		th = "รอบนี้ไม่บันทึกข้อมูล (โหลดข้อมูลไม่สำเร็จ หรือ Studio ปิด API)",
		en = "Progress is not saved this session (load failed or Studio API access is off)",
	},
	["coming.soon"] = { th = "เร็วๆ นี้", en = "Coming soon" },

	-- มินิเกม
	["mix.title"] = { th = "ผสมแป้ง: {recipe}", en = "Mixing: {recipe}" },
	["mix.hint"] = { th = "กดตอนเส้นวิ่งถึงดาว ⭐ (คลิก / Space / แตะ)", en = "Tap when the line reaches a star ⭐ (Click / Space / Tap)" },
	["mix.tap"] = { th = "กด!", en = "Tap!" },
	["mix.pick"] = { th = "เลือกสูตรที่จะผสม", en = "Choose a recipe to mix" },
	["mix.Perfect"] = { th = "Perfect!", en = "Perfect!" },
	["mix.Good"] = { th = "Good!", en = "Good!" },
	["mix.Miss"] = { th = "Miss", en = "Miss" },
	["mix.Okay"] = { th = "พอใช้", en = "Okay" },

	-- แจ้งเตือน (server ส่ง key มา)
	["n.loading"] = { th = "กำลังโหลดข้อมูล รอสักครู่นะ", en = "Loading your data, please wait" },
	["n.dataLoadFailed"] = {
		th = "โหลดข้อมูลไม่สำเร็จ เล่นต่อได้แต่รอบนี้จะไม่บันทึก ลองออกแล้วเข้าใหม่ภายหลัง",
		en = "Couldn't load your data. You can play, but this session won't be saved. Try rejoining later.",
	},
	["n.dataStudioNoApi"] = {
		th = "Studio ยังไม่เปิด API Services รอบนี้จะไม่บันทึกข้อมูล",
		en = "Studio API access is off, so this session won't be saved",
	},
	["n.saveRetry"] = { th = "บันทึกข้อมูลไม่สำเร็จ กำลังลองใหม่ ({attempt}/{max})", en = "Save failed, retrying ({attempt}/{max})" },
	["n.saveFailed"] = { th = "บันทึกข้อมูลไม่สำเร็จ จะลองอีกครั้งในรอบถัดไป", en = "Couldn't save. Will try again shortly." },
	["n.tooFast"] = { th = "ใจเย็นๆ ลองใหม่อีกครั้งในอีกสักครู่", en = "Slow down a little and try again" },
	["n.tooFar"] = { th = "อยู่ไกลเกินไป เดินเข้าไปใกล้อีกนิด", en = "You're too far away, move closer" },
	["n.rejected"] = { th = "ตอนนี้ทำแบบนี้ไม่ได้ ลองใหม่อีกครั้งนะ", en = "That can't be done right now, please try again" },
	["n.unexpected"] = { th = "เกิดข้อผิดพลาด ลองใหม่อีกครั้งนะ", en = "Something went wrong, please try again" },

	["n.harvested"] = { th = "เก็บ {item} +{amount}", en = "Harvested {item} +{amount}" },
	["n.notReady"] = { th = "{item} ยังไม่พร้อม อีก {seconds} วินาที", en = "{item} isn't ready yet ({seconds}s)" },
	["n.bagFull"] = { th = "{item} เต็มกระเป๋าแล้ว ใช้ทำขนมก่อนนะ", en = "Your bag is full of {item}. Use some first." },

	["n.recipeLocked"] = { th = "{recipe} ปลดล็อกที่ Lv. {level}", en = "{recipe} unlocks at Lv. {level}" },
	["n.missingIngredients"] = { th = "วัตถุดิบไม่พอ ขาด {missing}", en = "Not enough ingredients: need {missing}" },
	["n.ovenFull"] = { th = "เตาอบเต็ม ({slots} ช่อง) เก็บขนมที่เตาก่อนนะ", en = "Oven is full ({slots} slots). Collect from the oven first." },
	["n.mixBusy"] = { th = "กำลังผสมอยู่ ทำให้เสร็จก่อนนะ", en = "You're already mixing" },
	["n.mixExpired"] = { th = "หมดเวลาผสม ลองผสมใหม่อีกครั้ง", en = "Mixing timed out, please try again" },
	["n.mixDone"] = { th = "{quality} เข้าเตาแล้ว {recipe} x{pieces} อีก {seconds} วินาทีเสร็จ", en = "{quality} {recipe} x{pieces} is baking ({seconds}s)" },
	["n.ovenCollected"] = { th = "เก็บขนมจากเตา: {list}", en = "Collected from oven: {list}" },
	["n.ovenNotReady"] = { th = "ขนมยังอบไม่เสร็จ อีก {seconds} วินาที", en = "Still baking, {seconds}s left" },
	["n.ovenEmpty"] = { th = "เตาว่างอยู่ ไปผสมแป้งที่โต๊ะผสมก่อนนะ", en = "The oven is empty. Mix dough at the Mixing Table first." },

	["n.customerArrived"] = { th = "{animal} มาแล้ว! อยากได้ {recipe} x{amount}", en = "{animal} arrived and wants {recipe} x{amount}" },
	["n.served"] = { th = "เสิร์ฟ {animal} สำเร็จ! +{coins} เหรียญ +{rep} ชื่อเสียง", en = "Served {animal}! +{coins} coins +{rep} reputation" },
	["n.servedByOther"] = { th = "{player} เสิร์ฟ {animal} แล้ว", en = "{player} served {animal}" },
	["n.notEnoughGoods"] = { th = "{animal} อยากได้ {recipe} x{amount} แต่มีแค่ {have}", en = "{animal} wants {recipe} x{amount}, you have {have}" },
	["n.customerLeft"] = { th = "{animal} รอไม่ไหว กลับไปแล้ว", en = "{animal} got tired of waiting and left" },
	["n.customerNotSeated"] = { th = "รอให้ลูกค้านั่งก่อนนะ", en = "Wait for the customer to sit down" },

	["n.upgraded"] = { th = "อัปเกรด {line} เป็นเลเวล {level} แล้ว!", en = "{line} upgraded to level {level}!" },
	["n.upgradeMax"] = { th = "{line} อัปเกรดสูงสุดแล้ว", en = "{line} is already maxed" },
	["n.notEnoughCoins"] = { th = "เหรียญไม่พอ ต้องใช้ {cost} (มี {have})", en = "Not enough coins: need {cost} (have {have})" },
	["n.levelUp"] = { th = "ร้านเลเวลอัป! Lv. {level}", en = "Bakery leveled up! Lv. {level}" },
	["n.recipeUnlocked"] = { th = "ปลดล็อกสูตรใหม่: {recipe}", en = "New recipe unlocked: {recipe}" },

	["n.questsIncomplete"] = { th = "ทำภารกิจให้ครบ 3 ข้อก่อนนะ", en = "Finish all 3 quests first" },
	["n.questsClaimed"] = { th = "รับรางวัลวันนี้ไปแล้ว พรุ่งนี้มาใหม่นะ", en = "Already claimed today, come back tomorrow" },
	["n.questReward"] = { th = "รับรางวัลภารกิจ! +{coins} เหรียญ +{rep} ชื่อเสียง", en = "Quest reward! +{coins} coins +{rep} reputation" },
	["n.questComplete"] = { th = "ภารกิจสำเร็จ: {quest}", en = "Quest complete: {quest}" },
	["n.languageSet"] = { th = "เปลี่ยนภาษาแล้ว (Language changed)", en = "Language changed (เปลี่ยนภาษาแล้ว)" },
}

local Icons: { [string]: string } = {
	Wheat = "🌾",
	StarMilk = "🥛",
	Strawberry = "🍓",
	CloudBread = "🍞",
	Croissant = "🥐",
	StrawberryCake = "🍰",
	Panda = "🐼",
	Fox = "🦊",
	Bunny = "🐰",
	Coin = "💰",
	Star = "⭐",
	Heart = "❤️",
	HeartEmpty = "🤍",
	Timer = "⏱",
	Bag = "🎒",
	Recipes = "📖",
	Upgrade = "🔨",
	Pets = "🐾",
	Decor = "🛋️",
	Settings = "⚙️",
	Garden = "🌾",
	Oven = "🔥",
	Counter = "🧁",
	Note = "♪",
	Lock = "🔒",
	Check = "✔",
}

local Locale = {}

Locale.Languages = { "th", "en" }

function Locale.has(key: string): boolean
	return Strings[key] ~= nil
end

function Locale.get(language: string, key: string, args: { [string]: string | number }?): string
	local entry = Strings[key]
	if entry == nil then
		warn(`[Locale] ไม่พบข้อความ key "{key}"`)
		return key
	end
	local text = if language == "en" then entry.en else entry.th
	if args then
		text = string.gsub(text, "{(%w+)}", function(name: string): string
			local value = args[name]
			if value == nil then
				return `\{{name}\}`
			end
			return tostring(value)
		end)
	end
	return text
end

-- ภาษารอง (ใช้แสดงตัวเล็กในวงเล็บแบบ concept)
function Locale.other(language: string): string
	return if language == "en" then "th" else "en"
end

function Locale.icon(id: string): string
	return Icons[id] or "•"
end

function Locale.formatTime(seconds: number): string
	local total = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", total // 60, total % 60)
end

return Locale
