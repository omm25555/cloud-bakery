--!strict
-- กติกาล้วนของ lobby (ไม่มี side effect) ใช้ร่วมกันทั้ง lobby และเกาะ

local Lobby = require(script.Parent.Config.Lobby)

export type TeleportData = {
	Version: number,
	GroupId: string,
	Size: number,
	MemberUserIds: { number },
}

export type JoinDecision = "Join" | "Leave" | "Full" | "Busy"

local LobbyRules = {}

local function isInteger(value: any): boolean
	return type(value) == "number" and value == value and value == math.floor(value) and math.abs(value) ~= math.huge
end

-- ตัดสินผลของการกดแท่น: เข้า / ออก / เต็ม / กำลัง teleport
function LobbyRules.DecideJoin(memberCount: number, isMember: boolean, isTeleporting: boolean): JoinDecision
	if isTeleporting then
		return "Busy"
	end
	if isMember then
		return "Leave"
	end
	if memberCount >= Lobby.MaxGroupSize then
		return "Full"
	end
	return "Join"
end

function LobbyRules.BuildTeleportData(groupId: string, memberUserIds: { number }): TeleportData
	return {
		Version = Lobby.TeleportDataVersion,
		GroupId = groupId,
		Size = #memberUserIds,
		MemberUserIds = memberUserIds,
	}
end

-- ตรวจ TeleportData ที่มากับผู้เล่น (ข้อมูลภายนอก ห้ามเชื่อ) คืน (ข้อมูล, nil) หรือ (nil, เหตุผล)
function LobbyRules.ValidateTeleportData(raw: any, userId: number): (TeleportData?, string?)
	if type(raw) ~= "table" then
		return nil, "TeleportData ไม่ใช่ table"
	end
	local data: { [string]: any } = raw
	if data.Version ~= Lobby.TeleportDataVersion then
		return nil, `Version ไม่ตรง (ได้ {tostring(data.Version)} ต้องการ {Lobby.TeleportDataVersion})`
	end
	local groupId = data.GroupId
	if type(groupId) ~= "string" or #groupId == 0 or #groupId > Lobby.MaxGroupIdLength then
		return nil, "GroupId ไม่ถูกต้อง"
	end
	local size = data.Size
	if not isInteger(size) or size < 1 or size > Lobby.MaxGroupSize then
		return nil, "Size อยู่นอกช่วง"
	end
	local members = data.MemberUserIds
	if type(members) ~= "table" then
		return nil, "MemberUserIds ไม่ใช่ table"
	end
	local list: { [any]: any } = members
	local count = 0
	for _ in list do
		count += 1
	end
	if count ~= #list or count ~= size then
		return nil, "MemberUserIds ไม่ใช่อาร์เรย์หรือจำนวนไม่ตรงกับ Size"
	end
	local seen: { [number]: boolean } = {}
	local clean: { number } = {}
	local containsUser = false
	for _, value in list do
		if not isInteger(value) or value <= 0 or seen[value] then
			return nil, "MemberUserIds มีค่าไม่ถูกต้องหรือซ้ำ"
		end
		seen[value] = true
		table.insert(clean, value)
		if value == userId then
			containsUser = true
		end
	end
	if not containsUser then
		return nil, "ผู้เล่นไม่อยู่ในรายชื่อกลุ่ม"
	end
	return {
		Version = Lobby.TeleportDataVersion,
		GroupId = groupId,
		Size = size,
		MemberUserIds = clean,
	}, nil
end

return LobbyRules
