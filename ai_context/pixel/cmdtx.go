package pixel

import (
	"encoding/binary"
	"image/color"
)

type TxMessage interface {
	ToBuffer() []byte
}

func (die *Die) SendMsg(msg TxMessage) error {
	_, err := die.writeChar.WriteWithoutResponse(msg.ToBuffer())
	return err
}

type MessageWhoAreYou struct {
}

func (msg MessageWhoAreYou) ToBuffer() []byte {
	return []byte{MsgTypeWhoAreYou}
}

type MessageBlink struct {
	Count     uint8
	Duration  uint16
	Color     color.RGBA
	FaceMask  uint32
	Fade      uint8
	LoopCount uint8
}

func (msg MessageBlink) ToBuffer() (buf []byte) {
	buf = make([]byte, 14)
	buf[0] = MsgTypeBlink
	buf[1] = msg.Count
	binary.LittleEndian.PutUint16(buf[2:], msg.Duration)
	buf[4] = msg.Color.B
	buf[5] = msg.Color.G
	buf[6] = msg.Color.R
	buf[7] = msg.Color.A
	binary.LittleEndian.PutUint32(buf[8:], msg.FaceMask)
	buf[12] = msg.Fade
	buf[13] = msg.LoopCount

	return buf
}
