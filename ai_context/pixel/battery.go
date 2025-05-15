package pixel

type MessageBatteryLevel struct {
	Id           uint8
	BatteryLevel uint8
	BatteryState uint8
}

func parseBatteryLevelMessage(buf []byte) MessageBatteryLevel {
	msg := MessageBatteryLevel{
		Id:           buf[0],
		BatteryLevel: buf[1],
		BatteryState: buf[2],
	}
	return msg
}

func (die *Die) readBatteryBuffer(buf []byte) {
	msg := parseBatteryLevelMessage(buf)
	die.readBatteryMsg(msg)
}

func (die *Die) readBatteryMsg(msg MessageBatteryLevel) {
	die.batteryLevel = msg.BatteryLevel
	die.batteryCharging = msg.BatteryState == BattStateCharging
}
