--!strict
-- Place ID ของเกม เจ้าของเกมกรอกเองหลังสร้าง place แล้ว (0 = ยังไม่ได้ตั้ง)

local Places = {
	LobbyPlaceId = 0,
	IslandPlaceId = 0,
}

function Places.IsSet(placeId: number): boolean
	return type(placeId) == "number" and placeId > 0 and placeId == math.floor(placeId)
end

return Places
