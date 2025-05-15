package pixel

const (
	PixelsService             = "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
	Information               = "180a"
	NordicsDFU                = "fe59"
	PixelNotifyCharacteristic = "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
	PixelWriteCharacteristic  = "6e400002-b5a3-f393-e0a9-e50e24dcca9e"
)

// DieType
const (
	DieTypeUnknown = iota
	DieTypeD4
	DieTypeD6
	DieTypeD8
	DieTypeD10
	DieTypeD00
	DieTypeD12
	DieTypeD20
	DieTypeD6Pipped
	DieTypeD6Fudge
)

// DesignAndColor
const (
	DnCUnknown = iota
	DnCOnyxBlack
	DnCHematiteGrey
	DnCMidnightGalaxy
	DnCAuroraSky
	DnCClear
	DnCWhiteAurora
	DnCCustom = 255
)

// Roll States
const (
	RollStateUnknown = iota
	RollStateRolled
	RollStateHandling
	RollStateRolling
	RollStateCrooked
	RollStateOnFace
)

// Battery States
const (
	BattStateUnknown = iota
	BattStateOk
	BattStateLow
	BattStateTransition
	BattStateBadCharging
	BattStateError
	BattStateCharging
	BattStateTrickleCharge
	BattStateDone
	BattStateLowTemp
	BattStateHighTemp
)

const (
	MsgTypeNone = iota
	MsgTypeWhoAreYou
	MsgTypeIAmADie
	MsgTypeRollState
	MsgTypeTelemetry
	MsgTypeBulkSetup
	MsgTypeBulkSetupAck
	MsgTypeBulkData
	MsgTypeBulkDataAck
	MsgTypeTransferAnimationSet
	MsgTypeTransferAnimationSetAck
	MsgTypeTransferAnimationSetFinished
	MsgTypeTransferSettings
	MsgTypeTransferSettingsAck
	MsgTypeTransferSettingsFinished
	MsgTypeTransferTestAnimationSet
	MsgTypeTransferTestAnimationSetAck
	MsgTypeTransferTestAnimationSetFinished
	MsgTypeDebugLog
	MsgTypePlayAnimation
	MsgTypePlayAnimationEvent
	MsgTypeStopAnimation
	MsgTypeRemoteAction
	MsgTypeRequestRollState
	MsgTypeRequestAnimationSet
	MsgTypeRequestSettings
	MsgTypeRequestTelemetry
	MsgTypeProgramDefaultAnimationSet
	MsgTypeProgramDefaultAnimationSetFinished
	MsgTypeBlink
	MsgTypeBlinkAck
	MsgTypeRequestDefaultAnimationSetColor
	MsgTypeDefaultAnimationSetColor
	MsgTypeRequestBatteryLevel
	MsgTypeBatteryLevel
	MsgTypeRequestRssi
	MsgTypeRssi
	MsgTypeCalibrate
	MsgTypeCalibrateFace
	MsgTypeNotifyUser
	MsgTypeNotifyUserAck
	MsgTypeTestHardware
	MsgTypeTestLEDLoopback
	MsgTypeLedLoopback
	MsgTypeSetTopLevelState
	MsgTypeProgramDefaultParameters
	MsgTypeProgramDefaultParametersFinished
	MsgTypeSetDesignAndColor
	MsgTypeSetDesignAndColorAck
	MsgTypeSetCurrentBehavior
	MsgTypeSetCurrentBehaviorAck
	MsgTypeSetName
	MsgTypeSetNameAck
	MsgTypeSleep
	MsgTypeExitValidation
	MsgTypeTransferInstantAnimationSet
	MsgTypeTransferInstantAnimationSetAck
	MsgTypeTransferInstantAnimationSetFinished
	MsgTypePlayInstantAnimation
	MsgTypeStopAllAnimations
	MsgTypeRequestTemperature
	MsgTypeTemperature
	MsgTypeEnableCharging
	MsgTypeDisableCharging
	MsgTypeDischarge
)
