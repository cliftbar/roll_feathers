package pixel

import "time"

type MessageRollState struct {
	Id               uint8
	RollState        uint8
	CurrentFaceIndex uint8
	CurrentFaceValue uint8
}

func parseRollStateMessage(buf []byte) MessageRollState {
	msg := MessageRollState{
		Id:               buf[0],
		RollState:        buf[1],
		CurrentFaceIndex: buf[2],
		CurrentFaceValue: buf[2] + 1,
	}
	return msg
}

func (die *Die) readRollStateMessage(msg MessageRollState) {
	die.rollState = msg.RollState
	die.CurrentFaceIndex = msg.CurrentFaceIndex
	die.CurrentFaceValue = msg.CurrentFaceValue
	die.LastRolled = time.Now()
}
