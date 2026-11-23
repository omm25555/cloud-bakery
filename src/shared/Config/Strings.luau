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
	BakeCollectWarn = {
		th = "{dish} รอเก็บอยู่ในเตา อีก {seconds} วินาทีจะใส่กระเป๋าให้อัตโนมัติ",
		en = "Your {dish} is waiting in the oven. It will be moved to your bag automatically in {seconds}s.",
	},
	BakeAutoCollected = {
		th = "หมดเวลารอเก็บ ใส่{dish} {amount} ชิ้นเข้ากระเป๋าให้แล้ว เตาว่างแล้ว",
		en = "Time's up. Added {amount} x {dish} to your bag. The oven is free again.",
	},
	BakeAutoCollectedPartial = {
		th = "หมดเวลารอเก็บ ใส่{dish}ได้ {amount} ชิ้น แต่เสียไป {lost} ชิ้นเพราะกระเป๋าเต็ม เตาว่างแล้ว",
		en = "Time's up. Added {amount} x {dish}, but lost {lost} because your bag was full. The oven is free again.",
	},
	BakeAutoCollectedLost = {
		th = "หมดเวลารอเก็บ {dish} {lost} ชิ้นหายไปเพราะกระเป๋าเต็ม เตาว่างแล้ว",
		en = "Time's up. {lost} x {dish} was lost because your bag was full. The oven is free again.",
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
	ServeNewCustomer = {
		th = "ลูกค้าใหม่: {customer}สั่ง{dish} x{amount}",
		en = "New customer: {customer} ordered {amount} x {dish}.",
	},
	ServeOk = {
		th = "เสิร์ฟ{dish} x{amount} ให้{customer}แล้ว ได้ {coins} เหรียญ +{reputation} Reputation ({hearts} หัวใจ)",
		en = "Served {amount} x {dish} to {customer}. Got {coins} coins, +{reputation} Reputation ({hearts} hearts).",
	},
	ServeServedBy = {
		th = "{player}เสิร์ฟ{customer}ไปแล้ว",
		en = "{player} served {customer}.",
	},
	ServeMissingItems = {
		th = "ขนมไม่พอ ขาด{dish}อีก {count} ชิ้น",
		en = "Not enough baked goods. Missing {count} x {dish}.",
	},
	ServeOrderGone = {
		th = "ออเดอร์นี้ไม่มีแล้ว (ถูกเสิร์ฟไปแล้วหรือลูกค้ากลับไปแล้ว)",
		en = "That order is gone (already served, or the customer left).",
	},
	ServeTooFar = {
		th = "อยู่ไกลลูกค้าเกินไป เดินเข้าไปใกล้ ๆ ก่อน",
		en = "You're too far from the customer. Move closer.",
	},
	ServeCoinsCapped = {
		th = "เหรียญเต็มเพดานแล้ว ได้เพิ่มแค่ {coins} เหรียญ",
		en = "Your coins are at the cap. Only {coins} coins were added.",
	},
	ServeReputationCapped = {
		th = "Reputation เต็มเพดานแล้ว ได้เพิ่มแค่ {reputation}",
		en = "Your Reputation is at the cap. Only {reputation} was added.",
	},
	ServeOrderWarn = {
		th = "{customer}รอ{dish}อยู่ เหลืออีก {seconds} วินาที",
		en = "{customer} is waiting for {dish}. {seconds} seconds left.",
	},
	ServeOrderExpired = {
		th = "{customer}รอนานเกินไปและกลับไปแล้ว",
		en = "{customer} waited too long and left.",
	},
	ServeReputationLost = {
		th = "ลูกค้ากลับไป Reputation ลด {reputation}",
		en = "A customer left. Reputation decreased by {reputation}.",
	},
	UiServeCounterLabel = {
		th = "เคาน์เตอร์รับออเดอร์",
		en = "Order counter",
	},
	UiServeTableLabel = {
		th = "โต๊ะเสิร์ฟ",
		en = "Serving table",
	},
	UiServeLoadFailed = {
		th = "ระบบเสิร์ฟโหลดไม่สำเร็จ ลองเข้าเกมใหม่",
		en = "Serving failed to load. Please rejoin the game.",
	},
	UiServePromptAction = {
		th = "เสิร์ฟ",
		en = "Serve",
	},
	UiServeBubble = {
		th = "{dish} x{amount}\n{hearts}\nเหลือ {time}",
		en = "{dish} x{amount}\n{hearts}\n{time} left",
	},
	UpgradeBuyOk = {
		th = "อัปเกรด{line}เป็นเลเวล {level}/{max} แล้ว ({effect}) เหลือ {coins} เหรียญ",
		en = "Upgraded {line} to level {level}/{max} ({effect}). {coins} coins left.",
	},
	UpgradeShort = {
		th = "เหรียญไม่พอ ขาดอีก {missing} เหรียญ (ราคา {cost})",
		en = "Not enough coins. You're {missing} short (cost {cost}).",
	},
	UpgradeMaxed = {
		th = "อัปเกรดนี้เลเวลเต็มแล้ว",
		en = "This upgrade is already at max level.",
	},
	UpgradeEffectTime = {
		th = "เวลาลดลง {percent}%",
		en = "{percent}% less time",
	},
	UpgradeEffectCoin = {
		th = "เหรียญเพิ่ม {percent}%",
		en = "{percent}% more coins",
	},
	UiUpgradeButton = {
		th = "อัปเกรด",
		en = "Upgrade",
	},
	UiUpgradeTitle = {
		th = "อัปเกรดร้าน",
		en = "Shop Upgrades",
	},
	UiUpgradeClose = {
		th = "X",
		en = "X",
	},
	UiUpgradeCoins = {
		th = "เหรียญของคุณ: {coins}",
		en = "Your coins: {coins}",
	},
	UiUpgradeLevel = {
		th = "เลเวล {level}/{max}",
		en = "Level {level}/{max}",
	},
	UiUpgradeEffectChange = {
		th = "ตอนนี้: {now} → ถัดไป: {next}",
		en = "Now: {now} → Next: {next}",
	},
	UiUpgradeEffectMax = {
		th = "ตอนนี้: {now} (สูงสุด)",
		en = "Now: {now} (max)",
	},
	UiUpgradeBuy = {
		th = "ซื้อ {cost}",
		en = "Buy {cost}",
	},
	UiUpgradeMaxedButton = {
		th = "เต็มแล้ว",
		en = "Maxed",
	},
	UiUpgradeLoading = {
		th = "กำลังโหลด...",
		en = "Loading...",
	},
	UiServeCurrency = {
		th = "เหรียญ {coins}\nReputation {reputation}",
		en = "Coins {coins}\nReputation {reputation}",
	},
	UiMenuBag = {
		th = "กระเป๋า",
		en = "Bag",
	},
	UiMenuRecipes = {
		th = "สูตร",
		en = "Recipes",
	},
	UiMenuPets = {
		th = "สัตว์เลี้ยง 🔒",
		en = "Pets 🔒",
	},
	UiMenuDecor = {
		th = "ตกแต่ง 🔒",
		en = "Decor 🔒",
	},
	UiMenuSettings = {
		th = "ตั้งค่า",
		en = "Settings",
	},
	UiMenuClose = {
		th = "X",
		en = "X",
	},
	UiMenuLoading = {
		th = "กำลังโหลด...",
		en = "Loading...",
	},
	UiBagCapacity = {
		th = "ใช้ {used}/{capacity}",
		en = "Used {used}/{capacity}",
	},
	UiBagEmpty = {
		th = "กระเป๋าว่าง",
		en = "Your bag is empty",
	},
	UiBagSectionIngredients = {
		th = "วัตถุดิบ",
		en = "Ingredients",
	},
	UiBagSectionBakes = {
		th = "ขนมอบ",
		en = "Baked goods",
	},
	UiBagSectionOther = {
		th = "อื่น ๆ",
		en = "Other",
	},
	UiRecipesTitle = {
		th = "สูตรขนม",
		en = "Recipes",
	},
	UiRecipeNameBoth = {
		th = "{nameTh} ({nameEn})",
		en = "{nameEn} ({nameTh})",
	},
	UiRecipeNeed = {
		th = "{name} ต้องใช้ {need} (มี {have})",
		en = "{name}: need {need} (have {have})",
	},
	UiRecipeEnough = {
		th = "มีพอ",
		en = "Ready to bake",
	},
	UiRecipeShort = {
		th = "ไม่พอ",
		en = "Not enough",
	},
	UiRecipeTime = {
		th = "เวลาอบ {seconds} วินาที (ยังไม่รวมอัปเกรด)",
		en = "Bake time {seconds}s (before upgrades)",
	},
	UiSettingsTitle = {
		th = "ตั้งค่า",
		en = "Settings",
	},
	UiSettingsLanguage = {
		th = "ภาษา (Language)",
		en = "Language (ภาษา)",
	},
	LanguageChanged = {
		th = "เปลี่ยนภาษาเป็น {language} แล้ว",
		en = "Language changed to {language}.",
	},
	LanguageSame = {
		th = "ใช้ภาษา {language} อยู่แล้ว",
		en = "You're already using {language}.",
	},
	ComingSoon = {
		th = "เร็วๆ นี้ (Coming soon)",
		en = "Coming soon!",
	},
	UiHudLoading = {
		th = "กำลังโหลด...",
		en = "Loading...",
	},
	UiHudLevel = {
		th = "เลเวล {level}",
		en = "Lv {level}",
	},
	UiHudLevelMax = {
		th = "เลเวล {level} (สูงสุด)",
		en = "Lv {level} (max)",
	},
	UiOrdersTitle = {
		th = "ออเดอร์",
		en = "Orders",
	},
	UiOrdersTitleCount = {
		th = "ออเดอร์ ({count})",
		en = "Orders ({count})",
	},
	UiOrdersEmpty = {
		th = "ยังไม่มีลูกค้า",
		en = "No customers yet",
	},
	UiOrdersLoadFailed = {
		th = "โหลดรายการออเดอร์ไม่สำเร็จ ลองออกแล้วเข้าเกมใหม่",
		en = "Couldn't load orders. Please rejoin.",
	},
	UiOrdersDish = {
		th = "{dish} x{amount}",
		en = "{dish} x{amount}",
	},
	UiOrdersEnough = {
		th = "ขนมพอ",
		en = "Enough",
	},
	UiOrdersShort = {
		th = "ขาด {missing}",
		en = "Need {missing} more",
	},
	HudLevelUp = {
		th = "Reputation เลเวลขึ้น! ตอนนี้เลเวล {level}",
		en = "Reputation level up! You are now Lv {level}.",
	},
	HudLevelDown = {
		th = "Reputation เลเวลลดลงเป็นเลเวล {level}",
		en = "Reputation level dropped to Lv {level}.",
	},
	QuestHarvestWheat = {
		th = "เก็บข้าวสาลี {target}",
		en = "Harvest {target} Wheat",
	},
	QuestBakeCloudBread = {
		th = "อบขนมปังเมฆ {target}",
		en = "Bake {target} Cloud Bread",
	},
	QuestServeOrders = {
		th = "เสิร์ฟ {target} ออเดอร์",
		en = "Serve {target} orders",
	},
	UiQuestTitle = {
		th = "เควสประจำวัน",
		en = "Daily Quests",
	},
	UiQuestTitleCount = {
		th = "เควสประจำวัน {done}/{total}",
		en = "Daily Quests {done}/{total}",
	},
	UiQuestReset = {
		th = "รีเซ็ตใน {time}",
		en = "Resets in {time}",
	},
	UiQuestLoadFailed = {
		th = "โหลดเควสไม่สำเร็จ ลองออกแล้วเข้าเกมใหม่",
		en = "Couldn't load quests. Please rejoin.",
	},
	UiQuestProgress = {
		th = "{progress}/{target}",
		en = "{progress}/{target}",
	},
	UiQuestReward = {
		th = "รางวัล {coins} เหรียญ",
		en = "Reward: {coins} coins",
	},
	UiQuestRewardRep = {
		th = "รางวัล {coins} เหรียญ + {reputation} Rep",
		en = "Reward: {coins} coins + {reputation} Rep",
	},
	UiQuestClaim = {
		th = "รับรางวัล",
		en = "Claim",
	},
	UiQuestClaimed = {
		th = "รับแล้ว",
		en = "Claimed",
	},
	QuestComplete = {
		th = "เควสสำเร็จ: {quest} กดรับรางวัลได้ที่แผงเควส",
		en = "Quest complete: {quest}. Claim your reward in the quest panel!",
	},
	QuestClaimOk = {
		th = "รับรางวัลเควส {quest}: +{coins} เหรียญ",
		en = "Quest reward ({quest}): +{coins} coins",
	},
	QuestClaimOkRep = {
		th = "รับรางวัลเควส {quest}: +{coins} เหรียญ +{reputation} Reputation",
		en = "Quest reward ({quest}): +{coins} coins, +{reputation} Reputation",
	},
	QuestRewardCapped = {
		th = "ค่าสะสมเต็มเพดานแล้ว จึงได้รางวัลไม่ครบ",
		en = "You reached the cap, so part of the reward was not added.",
	},
	QuestNotComplete = {
		th = "เควส {quest} ยังไม่สำเร็จ ({progress}/{target})",
		en = "Quest not complete yet: {quest} ({progress}/{target})",
	},
	QuestAlreadyClaimed = {
		th = "คุณรับรางวัลเควส {quest} ไปแล้ววันนี้",
		en = "You already claimed the reward for {quest} today.",
	},
	QuestDayChanged = {
		th = "ข้ามวันใหม่แล้ว เควสถูกรีเซ็ต กรุณาดูเควสชุดใหม่",
		en = "A new day started and quests were reset. Please check the new quests.",
	},
	QuestNewDay = {
		th = "วันใหม่แล้ว! มีเควสประจำวันชุดใหม่",
		en = "A new day! New daily quests are available.",
	},
	QuestExpiring = {
		th = "มีเควสที่สำเร็จแล้วแต่ยังไม่ได้รับรางวัล เควสจะรีเซ็ตใน {minutes} นาที รีบกดรับ!",
		en = "You have completed quests with unclaimed rewards. Quests reset in {minutes} min, claim them now!",
	},
	CoopOfferSent = {
		th = "ส่งคำขอให้ {item} x{count} แก่ {player} แล้ว รอเขากดรับ",
		en = "Offered {item} x{count} to {player}. Waiting for them to accept.",
	},
	CoopOfferReceived = {
		th = "{player} อยากให้ {item} x{count} แก่คุณ กดรับหรือปฏิเสธได้",
		en = "{player} wants to give you {item} x{count}. Accept or decline.",
	},
	CoopAcceptedGiver = {
		th = "{player} รับ {item} x{count} จากคุณแล้ว",
		en = "{player} accepted {item} x{count} from you.",
	},
	CoopAcceptedReceiver = {
		th = "คุณได้รับ {item} x{count} จาก {player}",
		en = "You received {item} x{count} from {player}.",
	},
	CoopDeclinedGiver = {
		th = "{player} ปฏิเสธ {item} x{count} ของคุณ ของยังอยู่กับคุณ",
		en = "{player} declined your {item} x{count}. You keep the items.",
	},
	CoopDeclinedSelf = {
		th = "ปฏิเสธของจาก {player} แล้ว",
		en = "You declined the gift from {player}.",
	},
	CoopExpiredGiver = {
		th = "คำขอให้ {item} x{count} แก่ {player} หมดเวลา ของยังอยู่กับคุณ",
		en = "Your offer of {item} x{count} to {player} expired. You keep the items.",
	},
	CoopExpiredReceiver = {
		th = "คำขอจาก {player} ({item} x{count}) หมดเวลาแล้ว",
		en = "The offer from {player} ({item} x{count}) expired.",
	},
	CoopGiverLeft = {
		th = "{player} ออกจากเกม คำขอถูกยกเลิก",
		en = "{player} left the game. The offer was cancelled.",
	},
	CoopTargetLeft = {
		th = "{player} ออกจากเกม คำขอถูกยกเลิก ของยังอยู่กับคุณ",
		en = "{player} left the game. The offer was cancelled and you keep the items.",
	},
	CoopNotEnough = {
		th = "ของไม่พอ: {item} ต้องการ {count} ชิ้น",
		en = "Not enough {item}: you need {count}.",
	},
	CoopGiverNotEnough = {
		th = "ส่งไม่สำเร็จ: {player} มี {item} ไม่ครบแล้ว",
		en = "Transfer failed: {player} no longer has enough {item}.",
	},
	CoopReceiverFull = {
		th = "ส่งไม่ได้: กระเป๋าของ {player} เต็ม",
		en = "Can't give: {player}'s bag is full.",
	},
	CoopReceiverFullSelf = {
		th = "กระเป๋าคุณเต็ม รับ {item} x{count} ไม่ได้ ทิ้งหรือใช้ของก่อนแล้วขอให้เพื่อนส่งใหม่",
		en = "Your bag is full, so you can't take {item} x{count}. Free some space and ask again.",
	},
	CoopTooFar = {
		th = "อยู่ไกลเกินไป เข้าใกล้ {player} ก่อน",
		en = "Too far away. Move closer to {player}.",
	},
	CoopInvalid = {
		th = "คำขอ Co-op ไม่ถูกต้อง",
		en = "Invalid co-op request.",
	},
	CoopSelf = {
		th = "ให้ของตัวเองไม่ได้",
		en = "You can't give items to yourself.",
	},
	CoopTargetGone = {
		th = "ไม่พบผู้เล่นคนนั้นในเกมแล้ว",
		en = "That player is no longer in the game.",
	},
	CoopTooManyPending = {
		th = "คุณมีคำขอที่รอคำตอบเยอะเกินไป รอสักครู่",
		en = "You have too many pending offers. Please wait.",
	},
	CoopTargetBusy = {
		th = "{player} มีคำขอค้างอยู่เยอะเกินไป ลองใหม่ภายหลัง",
		en = "{player} has too many pending offers. Try again later.",
	},
	CoopOfferGone = {
		th = "คำขอนี้ไม่มีแล้ว (หมดเวลา ถูกยกเลิก หรือตอบไปแล้ว)",
		en = "This offer is gone (expired, cancelled or already answered).",
	},
	CoopDataNotReady = {
		th = "ข้อมูลยังโหลดไม่เสร็จ ลองใหม่อีกครั้ง",
		en = "Data isn't ready yet. Please try again.",
	},
	CoopBonusEarned = {
		th = "โบนัสผู้ช่วย +{coins} เหรียญ เพราะ {player} ใช้ขนมที่คุณให้เสิร์ฟลูกค้า",
		en = "Helper bonus +{coins} coins: {player} served a pastry you gave.",
	},
	CoopBonusCapped = {
		th = "โบนัสผู้ช่วยวันนี้เต็มเพดานแล้ว ได้ {coins} เหรียญ",
		en = "Today's helper bonus cap reached. You got {coins} coins.",
	},
	CoopHelperThanks = {
		th = "{player} ได้โบนัสผู้ช่วยจากขนมที่ให้คุณ ขอบคุณที่ช่วยกัน!",
		en = "{player} earned a helper bonus from the pastry they gave you. Teamwork!",
	},
	UiCoopPrompt = {
		th = "ให้ของ",
		en = "Give items",
	},
	UiCoopTitle = {
		th = "ให้ของแก่ {player}",
		en = "Give to {player}",
	},
	UiCoopSelectItem = {
		th = "เลือกของที่จะให้",
		en = "Choose an item to give",
	},
	UiCoopNoItems = {
		th = "กระเป๋าว่าง ไม่มีของให้",
		en = "Your bag is empty. Nothing to give.",
	},
	UiCoopItem = {
		th = "{name} x{count}",
		en = "{name} x{count}",
	},
	UiCoopAmount = {
		th = "จำนวน {count}",
		en = "Amount {count}",
	},
	UiCoopSend = {
		th = "ส่งคำขอ",
		en = "Send offer",
	},
	UiCoopCancel = {
		th = "ยกเลิก",
		en = "Cancel",
	},
	UiCoopOfferTitle = {
		th = "{player} อยากให้ของคุณ",
		en = "{player} wants to give you",
	},
	UiCoopOfferBody = {
		th = "{name} x{count}",
		en = "{name} x{count}",
	},
	UiCoopAccept = {
		th = "รับ",
		en = "Accept",
	},
	UiCoopDecline = {
		th = "ปฏิเสธ",
		en = "Decline",
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
