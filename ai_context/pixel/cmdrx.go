package pixel

import (
	"encoding/binary"
	"time"
)

type MessageIAmADie struct {
	Id               uint8
	LedCount         uint8
	DesignAndColor   uint8
	Reserved         uint8
	DataSetHash      uint32
	PixelId          uint32
	AvailableFlash   uint16
	BuildTimestamp   uint32
	RollState        uint8
	CurrentFaceIndex uint8
	CurrentFaceValue uint8
	BatteryLevel     uint8
	BatteryState     uint8
}

func parseIAmADieMessage(buf []byte) MessageIAmADie {
	msg := MessageIAmADie{
		Id:               buf[0],
		LedCount:         buf[1],
		DesignAndColor:   buf[2],
		Reserved:         buf[3],
		DataSetHash:      binary.LittleEndian.Uint32(buf[4:]),
		PixelId:          binary.LittleEndian.Uint32(buf[8:]),
		AvailableFlash:   binary.LittleEndian.Uint16(buf[12:]),
		BuildTimestamp:   binary.LittleEndian.Uint32(buf[14:]),
		RollState:        buf[18],
		CurrentFaceIndex: buf[19],
		CurrentFaceValue: buf[19] + 1,
		BatteryLevel:     buf[20],
		BatteryState:     buf[21],
	}
	return msg
}

func (die *Die) readIAmADieMsg(msg MessageIAmADie) {
	die.PixelId = msg.PixelId
	die.ledCount = msg.LedCount
	die.designAndColor = msg.DesignAndColor
	die.CurrentFaceIndex = msg.CurrentFaceIndex
	die.CurrentFaceValue = msg.CurrentFaceValue
	die.rollState = msg.RollState
	die.batteryLevel = msg.BatteryLevel
	die.buildTimestamp = msg.BuildTimestamp
	die.batteryCharging = msg.BatteryState == BattStateCharging
	die.LastRolled = time.Now()
}
