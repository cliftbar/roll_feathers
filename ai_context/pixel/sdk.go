package pixel

import (
	"fmt"
	"log"
	"time"
	"tinygo.org/x/bluetooth"
)

var pixelServiceUuid, _ = bluetooth.ParseUUID(PixelsService)
var notifyCharacterUuid, _ = bluetooth.ParseUUID(PixelNotifyCharacteristic)
var writeCharacteristicUUid, _ = bluetooth.ParseUUID(PixelWriteCharacteristic)

type Die struct {
	device           bluetooth.Device
	writeChar        bluetooth.DeviceCharacteristic
	notifyChar       bluetooth.DeviceCharacteristic
	ledCount         uint8
	PixelId          uint32
	CurrentFaceIndex uint8
	CurrentFaceValue uint8
	rollState        uint8
	batteryLevel     uint8
	batteryCharging  bool
	buildTimestamp   uint32
	designAndColor   uint8
	LastRolled       time.Time
}

func WatchForDice(adapter *bluetooth.Adapter, dieChan chan<- *Die) {
	seenPixelDice := make(map[string]bool)
	adapter.SetConnectHandler(func(device bluetooth.Device, connected bool) {
		seenPixelDice[device.Address.String()] = connected
		fmt.Printf("Device %s status: %v\n", device.Address, connected)
	})

	for {
		devCh := make(chan bluetooth.ScanResult, 1)
		err := adapter.Scan(func(adapter *bluetooth.Adapter, device bluetooth.ScanResult) {
			if !device.HasServiceUUID(pixelServiceUuid) {
				return
			}
			connected := seenPixelDice[device.Address.String()]
			println(fmt.Sprintf("scanned: %v", device.Address))
			if !connected {
				println(fmt.Sprintf("Found device: %s", device.Address))
				devCh <- device
				adapter.StopScan()
				//time.Sleep(100 * time.Millisecond)
			}
		})
		if err != nil {
			println(fmt.Errorf("scan failed: %v", err))
		}

		device := <-devCh
		connected := seenPixelDice[device.Address.String()]
		//println(fmt.Sprintf("connected: %v", connected))
		if connected {
			continue
		}
		result, err := adapter.Connect(device.Address, bluetooth.ConnectionParams{})
		if err != nil {
			println(fmt.Errorf("connection failed: %v", err))
			return
		}
		die, _ := ConnectDev(&result, 5*time.Second)
		dieChan <- die

		//println(fmt.Sprintf("Connect device: %s", result.Address))
		time.Sleep(3 * time.Second)
	}
}

func ConnectDev(device *bluetooth.Device, timeout time.Duration) (*Die, error) {
	var die Die
	die.device = *device

	services, err := device.DiscoverServices([]bluetooth.UUID{pixelServiceUuid})
	if err != nil {
		return nil, fmt.Errorf("service discovery failed: %v", err)
	}

	for _, service := range services {
		if service.UUID().String() != PixelsService {
			continue
		}

		chars, _ := service.DiscoverCharacteristics([]bluetooth.UUID{notifyCharacterUuid, writeCharacteristicUUid})
		for _, char := range chars {
			if char.UUID().String() == PixelNotifyCharacteristic {
				die.notifyChar = char
				err = die.notifyChar.EnableNotifications(die.PixelCharacteristicReceiver)
			} else if char.UUID().String() == PixelWriteCharacteristic {
				die.writeChar = char
			}
		}
	}

	_ = die.SendMsg(MessageWhoAreYou{})
	end := time.Now().Add(timeout)
	for time.Now().Before(end) {
		if die.PixelId != 0 {
			break
		}
		time.Sleep(100 * time.Millisecond)
	}
	return &die, nil
}

func (die *Die) Connect(adapter *bluetooth.Adapter) error {
	ch := make(chan bluetooth.ScanResult, 1)
	err := adapter.Scan(func(adapter *bluetooth.Adapter, device bluetooth.ScanResult) {

		if device.HasServiceUUID(pixelServiceUuid) {
			_ = adapter.StopScan()
			ch <- device
		}
	})
	if err != nil {
		return fmt.Errorf("scan failed: %v", err)
	}

	result := <-ch
	device, err := adapter.Connect(result.Address, bluetooth.ConnectionParams{})
	if err != nil {
		return fmt.Errorf("connection failed: %v", err)
	}
	die.device = device

	services, err := device.DiscoverServices([]bluetooth.UUID{pixelServiceUuid})
	if err != nil {
		return fmt.Errorf("service discovery failed: %v", err)
	}

	for _, service := range services {
		if service.UUID().String() != PixelsService {
			continue
		}

		chars, _ := service.DiscoverCharacteristics([]bluetooth.UUID{notifyCharacterUuid, writeCharacteristicUUid})
		for _, char := range chars {
			if char.UUID().String() == PixelNotifyCharacteristic {
				die.notifyChar = char
				err = die.notifyChar.EnableNotifications(die.PixelCharacteristicReceiver)
			} else if char.UUID().String() == PixelWriteCharacteristic {
				die.writeChar = char
			}
		}
	}

	if err != nil {
		return fmt.Errorf("notification failed: %v", err)
	}
	return nil
}

func (die *Die) PixelCharacteristicReceiver(buf []byte) {
	if len(buf) == 0 {
		return
	}

	switch buf[0] {
	case MsgTypeIAmADie:
		msg := parseIAmADieMessage(buf)
		die.readIAmADieMsg(msg)

		log.Printf("Received IAmADie: %+v", msg)
	case MsgTypeRollState:
		msg := parseRollStateMessage(buf)
		log.Printf("Received RollState: %+v", msg)
		if msg.RollState == RollStateOnFace || msg.RollState == RollStateRolled {
			die.CurrentFaceIndex = msg.CurrentFaceIndex
			die.CurrentFaceValue = msg.CurrentFaceValue
			die.LastRolled = time.Now()
		}
	case MsgTypeBlinkAck:
		log.Printf("Blink Ack: %x", buf)
	case MsgTypeBatteryLevel:
		msg := parseBatteryLevelMessage(buf)
		die.readBatteryBuffer(buf)
		log.Printf("Received BatteryLevel: %+v", msg)
	default:

		log.Printf("received %d: %x", buf[0], buf)

	}

}
