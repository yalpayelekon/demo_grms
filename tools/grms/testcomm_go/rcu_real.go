package main

import (
	"bytes"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"log"
	"math"
	"net"
	"os"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

const (
	rcuHeader byte = 0x3E
)

const minRefreshInterval = 1 * time.Second
const sceneRefreshBlock = 500 * time.Millisecond
const refreshOutputBudgetPerCycle = 4

const (
	connectTimeout        = 3 * time.Second
	sceneCommandTimeout   = 1800 * time.Millisecond
	sceneWriteOnlyTimeout = 238 * time.Millisecond
	lightingWriteTimeout  = 2 * time.Second
	refreshCoreTimeout    = 1200 * time.Millisecond
	refreshOutputTimeout  = 900 * time.Millisecond
	timeoutCap            = 5 * time.Second
)

const (
	deviceVarietyDaliGear    = 2
	deviceVarietyDigidimGear = 4
	deviceVarietyElekonGear  = 6
	deviceVarietyOnboardGear = 8
)

const (
	deviceFeatureFCUContact = 3
)

const (
	murPassive  = 0
	murActive   = 1
	murProgress = 2
)

const (
	hvacRegRoomTemperature = 0x0E
	hvacRegSetPoint        = 0x0F
	hvacRegLowerSetpoint   = 0x10
	hvacRegUpperSetpoint   = 0x11
	hvacRegMode            = 0x28
	hvacRegFanMode         = 0x29
	hvacRegOccupancyInput  = 0x2B
	hvacRegRunningStatus   = 0x33
	hvacRegOnOff           = 0x34
	hvacRegKeylock         = 0x3A
	modbusAckOK            = 0x00
	modbusDeviceShortAddr  = 0x01
	sceneMin               = 1
	sceneMax               = 5
	sceneGroupByte         = 0x02
)

var thermostatBootstrapRegisters = []int{
	hvacRegRoomTemperature,
	hvacRegSetPoint,
	hvacRegMode,
	hvacRegFanMode,
	hvacRegOnOff,
	hvacRegRunningStatus,
}

var (
	timingThresholdOnce sync.Once
	timingThreshold     time.Duration
	queueSizeOnce       sync.Once
	queueSizeValue      int
	queueRetryOnce      sync.Once
	queueRetryEnabled   bool
	queueRetryMax       int
	pollingLogsOnce     sync.Once
	pollingLogsEnabled  bool
)

type queuedCommandKind string

const (
	queuedCommandScene         queuedCommandKind = "scene"
	queuedCommandLightingLevel queuedCommandKind = "lighting_level"
)

type queuedCommand struct {
	kind       queuedCommandKind
	scene      int
	address    int
	level      int
	seq        uint64
	requestID  string
	enqueuedAt time.Time
	resultCh   chan commandResult
}

type commandResult struct {
	ok         bool
	payload    map[string]interface{}
	err        error
	attempts   int
	durationMs int64
}

type opPriority string

const (
	opPriorityHigh   opPriority = "high"
	opPriorityNormal opPriority = "normal"
)

type opKind string

const (
	opKindScene         opKind = "scene"
	opKindLightingLevel opKind = "lighting_level"
	opKindRefreshCore   opKind = "refresh_core"
	opKindRefreshOutput opKind = "refresh_output"
	opKindRefreshMisc   opKind = "refresh_misc"
)

type opResult struct {
	payload    map[string]interface{}
	err        error
	lockWaitMs int64
}

type opRequest struct {
	kind     opKind
	priority opPriority
	timeout  time.Duration
	metadata string
	resultCh chan opResult
	exec     func(timeout time.Duration) (map[string]interface{}, error)
}

type sceneCallError struct {
	payload map[string]interface{}
	err     error
}

func (e *sceneCallError) Error() string {
	if e == nil || e.err == nil {
		return "scene call failed"
	}
	return e.err.Error()
}

func (e *sceneCallError) Unwrap() error {
	if e == nil {
		return nil
	}
	return e.err
}

type rcuFrame struct {
	CmdType  int
	CmdNo    int
	SubCmdNo int
	Payload  []byte
}

type rcuEventInfo struct {
	Name        string
	Description string
}

type modbusReadReturnEvent struct {
	ShortAddr int
	Ack       int
	StartReg  int
	Count     int
	Values    []int
}

type modbusWriteReturnEvent struct {
	ShortAddr int
	Ack       int
	StartReg  int
	Count     int
}

type outputDeviceState struct {
	Address           int
	Name              string
	Onboard           bool
	Variety           int
	Type              string
	Feature           int
	DaliSituation     int
	Alarm             bool
	ActualLevel       int
	TargetLevel       int
	Status            string
	PowerW            *int
	WattHourCounter   *int
	ActiveEnergy      []int
	ApparentEnergy    []int
	lastPendentLogAt  time.Time
	lastMastheadDebug time.Time
}

const (
	daliSituationIdle    = 0
	daliSituationActive  = 1
	daliSituationPassive = 2
	daliSituationPendent = 3
)

const (
	daliLineStatusNormal       = 0
	daliLineStatusShortCircuit = 1
)

const (
	daliLineStatusQueryTimeout = 1200 * time.Millisecond
	daliLineStatusDisableAfter = 2
	daliLineStatusDisableFor   = 5 * time.Minute
	pendentAlarmHeartbeat      = 60 * time.Second
	mastheadParsedDebugEvery   = 30 * time.Second
)

type hvacState struct {
	OnOff              *int
	RoomTemperature    *float64
	SetPoint           *float64
	Mode               *int
	FanMode            *int
	ComfortTemperature *float64
	LowerSetpoint      *float64
	UpperSetpoint      *float64
	KeylockFunction    *int
	OccupancyInput     *int
	RunningStatus      *int
	ComError           *int
	Fidelio            *int
}

type realRcuClient struct {
	room string
	cfg  RcuConfig

	connMu sync.Mutex
	conn   net.Conn

	mu sync.RWMutex

	initialized bool
	gtinName    string

	isDoorOpened                      bool
	hasDoorAlarm                      bool
	isRoomOccupied                    bool
	isDndActive                       bool
	isLaundryOn                       bool
	murState                          int
	daliLineStatus                    int
	daliLineShortCircuit              bool
	daliLineStatusSupported           bool
	daliLineStatusProbeDone           bool
	daliLineStatusConsecutiveTimeouts int
	daliLineStatusDisabledUntil       time.Time

	hvac    hvacState
	outputs map[int]*outputDeviceState

	lastUpdate  time.Time
	lastSceneAt atomic.Int64

	syncLoopOnce sync.Once

	cmdQueue   chan queuedCommand
	queueOnce  sync.Once
	queueStop  chan struct{}
	queueStopM sync.Once

	priorityOpCh chan opRequest
	normalOpCh   chan opRequest
	opOnce       sync.Once
	opStop       chan struct{}
	opStopM      sync.Once

	pendingWrites      atomic.Int32
	refreshSkipCounter atomic.Int64

	refreshOutputCursor int

	sceneSeq              atomic.Uint64
	latestSceneSeq        atomic.Uint64
	latestSceneNumber     atomic.Int32
	sceneCoalescingActive bool

	reconnectFailCount    int
	reconnectBlockedUntil time.Time
}

func newRealRcuClient(room string, cfg RcuConfig) *realRcuClient {
	client := &realRcuClient{
		room:                    room,
		cfg:                     cfg,
		murState:                murPassive,
		outputs:                 make(map[int]*outputDeviceState),
		daliLineStatusSupported: true,
		cmdQueue:                make(chan queuedCommand, commandQueueSize()),
		queueStop:               make(chan struct{}),
		priorityOpCh:            make(chan opRequest, 64),
		normalOpCh:              make(chan opRequest, 128),
		opStop:                  make(chan struct{}),
		sceneCoalescingActive:   sceneCoalescingEnabled(),
		hvac: hvacState{
			OnOff:              intPtr(1),
			SetPoint:           floatPtr(22.0),
			ComfortTemperature: floatPtr(22.0),
			LowerSetpoint:      floatPtr(20.0),
			UpperSetpoint:      floatPtr(26.0),
			Mode:               intPtr(3),
			FanMode:            intPtr(4),
			RoomTemperature:    floatPtr(22.5),
			RunningStatus:      intPtr(1),
		},
	}
	client.startCommandWorker()
	client.startOperationWorker()
	return client
}

func (r *realRcuClient) Room() string { return r.room }

func (r *realRcuClient) Shutdown() {
	r.stopCommandWorker()
	r.connMu.Lock()
	defer r.connMu.Unlock()
	r.closeConnLocked()
}

func (r *realRcuClient) InitializeAndUpdate() bool {
	if refreshTemporarilyDisabled() {
		log.Printf("rcu.refresh.disabled room=%s reason=temporary_scene_only_mode", r.room)
		return true
	}

	startedAt := time.Now()
	outcome, err := r.enqueueRefreshOps(opPriorityNormal)
	if err != nil {
		log.Printf("rcu.refresh failed room=%s host=%s port=%d error=%v", r.room, r.cfg.Host, r.cfg.Port, err)
		logSlowDuration(
			"rcu.initialize_and_update.duration",
			startedAt,
			" room=%s success=false refreshOutcome=%s",
			r.room,
			outcome,
		)
		return false
	}
	logSlowDuration(
		"rcu.initialize_and_update.duration",
		startedAt,
		" room=%s success=true refreshOutcome=%s",
		r.room,
		outcome,
	)
	return true
}

func (r *realRcuClient) Snapshot(serviceEvents []map[string]interface{}) map[string]interface{} {
	r.mu.RLock()
	defer r.mu.RUnlock()

	hvacStateStr := r.mapHvacStateLocked()
	hvacPayload := r.buildHvacPayloadLocked(hvacStateStr)
	status := r.mapStatusLocked()
	dndRaw := r.mapDndLocked()
	murRaw := r.mapMurLocked()
	laundryRaw := r.mapLaundryLocked()
	occupancy := map[string]interface{}{
		"occupied":     r.isRoomOccupied,
		"rented":       true,
		"doorOpen":     r.isDoorOpened,
		"hasDoorAlarm": r.hasDoorAlarm,
	}
	dndNormalized, murNormalized, laundryNormalized, normalized := normalizeServiceStates(
		dndRaw,
		murRaw,
		laundryRaw,
	)
	if normalized {
		log.Printf(
			"rcu.service.policy normalized room=%s dnd=%s->%s mur=%s->%s laundry=%s->%s",
			r.room,
			dndRaw, dndNormalized,
			murRaw, murNormalized,
			laundryRaw, laundryNormalized,
		)
	}

	m := map[string]interface{}{
		"number":          r.room,
		"hvac":            hvacStateStr,
		"hvacDetail":      hvacPayload,
		"lighting":        r.mapLightingStringLocked(),
		"lightingOn":      r.isLightingOnLocked(),
		"dnd":             dndNormalized,
		"mur":             murNormalized,
		"laundry":         laundryNormalized,
		"occupancy":       occupancy,
		"status":          status,
		"hasAlarm":        r.mapHasAlarmLocked(),
		"hasDoorAlarm":    r.hasDoorAlarm,
		"lightingDevices": r.buildLightingDevicesLocked(),
		"serviceEvents":   serviceEvents,
	}
	if m["mur"] == "Delayed" {
		m["murDelayedMinutes"] = 15
	}
	return m
}

func normalizeServiceStates(dnd, mur, laundry string) (string, string, string, bool) {
	initialDnd, initialMur, initialLaundry := dnd, mur, laundry
	dndActive := strings.EqualFold(dnd, "Yellow") || strings.EqualFold(dnd, "On")
	murRequested := strings.EqualFold(mur, "Requested")
	laundryRequested := strings.EqualFold(laundry, "Requested")

	// If laundry or MUR request is active, they cancel DND request.
	if dndActive && (murRequested || laundryRequested) {
		dnd = "Off"
	}

	changed := !strings.EqualFold(initialDnd, dnd) ||
		!strings.EqualFold(initialMur, mur) ||
		!strings.EqualFold(initialLaundry, laundry)
	return dnd, mur, laundry, changed
}

func (r *realRcuClient) LightingSummary() map[string]interface{} {
	r.mu.RLock()
	defer r.mu.RUnlock()
	onboard := make([]map[string]interface{}, 0)
	dali := make([]map[string]interface{}, 0)
	for _, d := range r.sortedOutputsLocked() {
		entry := map[string]interface{}{
			"address":     d.Address,
			"name":        d.Name,
			"actualLevel": d.ActualLevel,
			"targetLevel": d.TargetLevel,
			"status":      d.Status,
			"type":        map[bool]string{true: "onboard", false: "dali"}[d.Onboard],
			"alarm":       d.Alarm,
		}
		if d.PowerW != nil {
			entry["powerW"] = *d.PowerW
		}
		if d.WattHourCounter != nil {
			entry["wattHourCounter"] = *d.WattHourCounter
		}
		if len(d.ActiveEnergy) > 0 {
			entry["activeEnergy"] = append([]int(nil), d.ActiveEnergy...)
		}
		if len(d.ApparentEnergy) > 0 {
			entry["apparentEnergy"] = append([]int(nil), d.ApparentEnergy...)
		}
		if d.Onboard {
			onboard = append(onboard, entry)
		} else {
			entry["daliSituation"] = d.DaliSituation
			dali = append(dali, entry)
		}
	}
	return map[string]interface{}{
		"onboardOutputs": onboard,
		"daliOutputs":    dali,
	}
}

func (r *realRcuClient) LightingLegacy() map[string]interface{} {
	return map[string]interface{}{"lightingDevices": r.buildLightingDevicesLocked()}
}

func (r *realRcuClient) OutputTargets() map[string]interface{} {
	r.mu.RLock()
	defer r.mu.RUnlock()
	outputs := make([]map[string]interface{}, 0, len(r.outputs))
	for _, d := range r.sortedOutputsLocked() {
		entry := map[string]interface{}{
			"address":     d.Address,
			"name":        d.Name,
			"targetLevel": d.TargetLevel,
		}
		if d.PowerW != nil {
			entry["powerW"] = *d.PowerW
		}
		outputs = append(outputs, entry)
	}
	return map[string]interface{}{"outputs": outputs}
}

func (r *realRcuClient) HvacSnapshot() map[string]interface{} {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return r.buildHvacPayloadLocked(r.mapHvacStateLocked())
}

func (r *realRcuClient) UpdateHvac(updates map[string]interface{}) map[string]interface{} {
	regWrites := make([][2]int, 0)
	for k, v := range updates {
		switch k {
		case "onOff":
			if i, ok := coerceInt(v); ok {
				regWrites = append(regWrites, [2]int{hvacRegOnOff, i})
			}
		case "mode":
			if i, ok := coerceInt(v); ok {
				regWrites = append(regWrites, [2]int{hvacRegMode, i})
			}
		case "fanMode":
			if i, ok := coerceInt(v); ok {
				fanModeWrite := normalizeFanModeWriteValue(i)
				if fanModeWrite != i {
					log.Printf("rcu.hvac.fanmode.coerce room=%s raw=%d coerced=%d", r.room, i, fanModeWrite)
				}
				regWrites = append(regWrites, [2]int{hvacRegFanMode, fanModeWrite})
			}
		case "setPoint", "comfortTemperature":
			if f, ok := coerceFloat(v); ok {
				regWrites = append(regWrites, [2]int{hvacRegSetPoint, encodeTemperature(f)})
			}
		case "lowerSetpoint":
			if f, ok := coerceFloat(v); ok {
				regWrites = append(regWrites, [2]int{hvacRegLowerSetpoint, encodeTemperature(f)})
			}
		case "upperSetpoint":
			if f, ok := coerceFloat(v); ok {
				regWrites = append(regWrites, [2]int{hvacRegUpperSetpoint, encodeTemperature(f)})
			}
		}
	}

	if len(regWrites) == 0 {
		return r.HvacSnapshot()
	}

	r.connMu.Lock()
	defer r.connMu.Unlock()
	if err := r.ensureConnectedLocked(); err != nil {
		log.Printf("rcu.hvac connect failed room=%s error=%v", r.room, err)
		return nil
	}

	for _, w := range regWrites {
		msg := buildModbusWriteRegisterMessage(w[0], w[1])
		log.Printf("cmd.sent room=%s kind=hvac reg=0x%X value=%d", r.room, w[0], w[1])
		ev, err := r.sendModbusWriteAndAwaitAckLocked(msg, modbusDeviceShortAddr)
		if err != nil {
			log.Printf("rcu.hvac write failed room=%s reg=0x%X value=%d error=%v", r.room, w[0], w[1], err)
			r.closeConnLocked()
			return nil
		}
		// log.Printf("rcu.modbus.write.ack room=%s short_addr=%d ack=0x%X start_reg=0x%X count=%d", r.room, ev.ShortAddr, ev.Ack, ev.StartReg, ev.Count)
		if ev.Ack != modbusAckOK {
			log.Printf("rcu.hvac write nack room=%s reg=0x%X ack=0x%X", r.room, w[0], ev.Ack)
			return nil
		}
		r.applyHvacRegisterLocal(w[0], w[1])
	}

	if err := r.refreshUnlockedLockedConn(); err != nil {
		log.Printf("rcu.hvac refresh after write failed room=%s error=%v", r.room, err)
	}

	return r.HvacSnapshot()
}

func (r *realRcuClient) UpdateLightingLevel(address, level int, requestID string) map[string]interface{} {
	if level < 0 || level > 100 {
		return nil
	}
	res := r.enqueueCommand(queuedCommand{
		kind:      queuedCommandLightingLevel,
		address:   address,
		level:     level,
		requestID: requestID,
	})
	if !res.ok {
		return nil
	}
	out := cloneMap(res.payload)
	out["queueAttempts"] = res.attempts
	out["queueDurationMs"] = res.durationMs
	return out
}

func (r *realRcuClient) doUpdateLightingLevel(address, level int) (map[string]interface{}, error) {
	r.markWriteStart()
	defer r.markWriteDone()

	opRes := r.enqueueOperation(opRequest{
		kind:     opKindLightingLevel,
		priority: opPriorityHigh,
		timeout:  timeoutFor(opKindLightingLevel),
		metadata: fmt.Sprintf("address=%d level=%d", address, level),
		exec: func(timeout time.Duration) (map[string]interface{}, error) {
			device := r.findOutput(address)
			if device == nil {
				return nil, fmt.Errorf("rcu.lighting unknown output room=%s address=%d", r.room, address)
			}

			var msg []byte
			if device.Onboard {
				msg = []byte{rcuHeader, 0x05, 0x00, 0x03, 0x02, 0x00, byte(address), byte(percentToRcuLevel(level))}
			} else {
				msg = []byte{rcuHeader, 0x06, 0x00, 0x03, 0x04, 0x02, 0x00, byte(address), byte(percentToDaliLevel(level))}
			}
			if _, err := r.sendRequestLockedWithTimeout(msg, timeout); err != nil {
				log.Printf("rcu.lighting set target failed room=%s address=%d level=%d error=%v", r.room, address, level, err)
				r.closeConnLocked()
				return nil, err
			}
			log.Printf("cmd.sent room=%s kind=lighting_level address=%d level=%d", r.room, address, level)

			r.mu.RLock()
			defer r.mu.RUnlock()
			updated := r.outputs[address]
			if updated == nil {
				return nil, fmt.Errorf("rcu.lighting output missing after update room=%s address=%d", r.room, address)
			}
			return map[string]interface{}{
				"address":     updated.Address,
				"name":        updated.Name,
				"actualLevel": updated.ActualLevel,
				"targetLevel": updated.TargetLevel,
				"status":      updated.Status,
				"type":        map[bool]string{true: "onboard", false: "dali"}[updated.Onboard],
			}, nil
		},
	})
	if opRes.err != nil {
		return nil, opRes.err
	}
	if opRes.payload == nil {
		return nil, fmt.Errorf("empty lighting operation response")
	}
	opRes.payload["lockWaitMs"] = opRes.lockWaitMs
	return opRes.payload, nil
}

func (r *realRcuClient) CallLightingScene(scene int, requestID string) map[string]interface{} {
	if scene < sceneMin || scene > sceneMax {
		return nil
	}
	res := r.enqueueCommand(queuedCommand{
		kind:      queuedCommandScene,
		scene:     scene,
		requestID: requestID,
	})
	if !res.ok {
		if res.payload != nil {
			out := cloneMap(res.payload)
			out["queueAttempts"] = res.attempts
			out["queueDurationMs"] = res.durationMs
			return out
		}
		return map[string]interface{}{
			"scene":           scene,
			"group":           sceneGroupByte,
			"triggered":       false,
			"source":          "live",
			"status":          "failed",
			"attemptsMade":    res.attempts,
			"queueAttempts":   res.attempts,
			"queueDurationMs": res.durationMs,
			"error":           fmt.Sprintf("%v", res.err),
		}
	}
	out := cloneMap(res.payload)
	out["queueAttempts"] = res.attempts
	out["queueDurationMs"] = res.durationMs
	return out
}

func (r *realRcuClient) ExecuteRawCommand(frame []byte, requestID string) map[string]interface{} {
	if len(frame) == 0 {
		return nil
	}
	opRes := r.enqueueOperation(opRequest{
		kind:     opKindScene,
		priority: opPriorityHigh,
		timeout:  sceneWriteOnlyTimeout,
		metadata: fmt.Sprintf("raw_hex=% X", frame),
		exec: func(timeout time.Duration) (map[string]interface{}, error) {
			if err := r.sendCommandNoResponseLockedWithTimeout(frame, timeout); err != nil {
				log.Printf("rcu.raw.trigger failed room=%s error=%v frame_hex=% X", r.room, err, frame)
				r.closeConnLocked()
				return nil, err
			}
			// Treat raw scene-like writes as scene activity so refresh polling
			// waits for the same cool-down window and avoids read/write races.
			r.lastSceneAt.Store(time.Now().UnixNano())
			log.Printf("rcu.raw.trigger sent room=%s frame_hex=% X requestId=%s", r.room, frame, requestID)
			return map[string]interface{}{
				"triggered": true,
				"source":    "live",
				"status":    "accepted",
				"frameHex":  fmt.Sprintf("% X", frame),
			}, nil
		},
	})
	if opRes.err != nil {
		return map[string]interface{}{
			"triggered": false,
			"source":    "live",
			"status":    "failed",
			"frameHex":  fmt.Sprintf("% X", frame),
			"error":     fmt.Sprintf("%v", opRes.err),
		}
	}
	if opRes.payload == nil {
		return nil
	}
	out := cloneMap(opRes.payload)
	out["lockWaitMs"] = opRes.lockWaitMs
	return out
}

func (r *realRcuClient) doCallLightingScene(scene int) (map[string]interface{}, error) {
	startedAt := time.Now()
	r.markWriteStart()
	defer r.markWriteDone()

	msg := buildDaliEventTriggerScene(scene)
	if sceneDebugEnabled() {
		log.Printf(
			"rcu.scene.debug room=%s scene=%d group=%d frame_hex=% X",
			r.room,
			scene,
			sceneGroupByte,
			msg,
		)
	}

	requireResponse := sceneRequireResponse()
	var lastErr error
	var lastLockWaitMs int64
	attemptsMade := 0
	maxAttempts := 2
	sawTimeout := false
	for attempt := 1; attempt <= maxAttempts; attempt++ {
		attemptsMade = attempt
		timeout := sceneWriteOnlyTimeout
		if requireResponse {
			timeout = timeoutFor(opKindScene)
		}
		opRes := r.enqueueOperation(opRequest{
			kind:     opKindScene,
			priority: opPriorityHigh,
			timeout:  timeout,
			metadata: fmt.Sprintf("scene=%d attempt=%d requireResponse=%t", scene, attempt, requireResponse),
			exec: func(timeout time.Duration) (map[string]interface{}, error) {
				if requireResponse {
					if _, err := r.sendRequestLockedWithTimeout(msg, timeout); err != nil {
						log.Printf("rcu.scene.trigger failed room=%s scene=%d error=%v", r.room, scene, err)
						r.closeConnLocked()
						return nil, err
					}
				} else {
					if err := r.sendCommandNoResponseLockedWithTimeout(msg, timeout); err != nil {
						log.Printf("rcu.scene.trigger write failed room=%s scene=%d error=%v", r.room, scene, err)
						r.closeConnLocked()
						return nil, err
					}
				}
				log.Printf("rcu.scene.trigger sent room=%s scene=%d group=%d", r.room, scene, sceneGroupByte)
				return map[string]interface{}{}, nil
			},
		})
		lastLockWaitMs = opRes.lockWaitMs
		if opRes.err == nil {
			r.lastSceneAt.Store(time.Now().UnixNano())
			status := "accepted"
			resp := map[string]interface{}{
				"scene":           scene,
				"group":           sceneGroupByte,
				"triggered":       true,
				"source":          "live",
				"refreshDeferred": r.refreshSkipCounter.Load() > 0,
				"lockWaitMs":      lastLockWaitMs,
				"executedAt":      time.Now().UTC().Format(time.RFC3339),
				"status":          status,
				"attemptsMade":    attemptsMade,
			}
			if requireResponse {
				resp["status"] = "confirmed"
				resp["confirmedAt"] = time.Now().UTC().Format(time.RFC3339)
			}
			return resp, nil
		}
		lastErr = opRes.err
		if isTimeoutError(opRes.err) {
			sawTimeout = true
		}
		if attempt < maxAttempts && isTransientCommandError(opRes.err) {
			time.Sleep(150 * time.Millisecond)
			continue
		}
		break
	}

	status := "failed"
	if sawTimeout || isTransientCommandError(lastErr) || isTimeoutError(lastErr) {
		status = "timeout"
	}
	logSlowDuration("rcu.scene.duration", startedAt, " room=%s scene=%d", r.room, scene)
	return nil, &sceneCallError{
		payload: map[string]interface{}{
			"scene":           scene,
			"group":           sceneGroupByte,
			"triggered":       false,
			"source":          "live",
			"refreshDeferred": r.refreshSkipCounter.Load() > 0,
			"lockWaitMs":      lastLockWaitMs,
			"executedAt":      time.Now().UTC().Format(time.RFC3339),
			"status":          status,
			"attemptsMade":    attemptsMade,
			"error":           fmt.Sprintf("%v", lastErr),
		},
		err: lastErr,
	}
}

func (r *realRcuClient) startCommandWorker() {
	r.queueOnce.Do(func() {
		go r.commandWorker()
	})
}

func (r *realRcuClient) stopCommandWorker() {
	r.queueStopM.Do(func() {
		close(r.queueStop)
	})
	r.opStopM.Do(func() {
		close(r.opStop)
	})
}

func (r *realRcuClient) startOperationWorker() {
	r.opOnce.Do(func() {
		go r.opWorkerLoop()
	})
}

func (r *realRcuClient) enqueueOperation(req opRequest) opResult {
	req.resultCh = make(chan opResult, 1)
	if req.timeout <= 0 {
		req.timeout = timeoutFor(req.kind)
	}
	target := r.normalOpCh
	if req.priority == opPriorityHigh {
		target = r.priorityOpCh
	}
	select {
	case <-r.opStop:
		return opResult{err: fmt.Errorf("operation queue stopped")}
	case target <- req:
	case <-time.After(2 * time.Second):
		return opResult{err: fmt.Errorf("operation queue enqueue timeout")}
	}

	select {
	case res := <-req.resultCh:
		return res
	case <-time.After(30 * time.Second):
		return opResult{err: fmt.Errorf("operation queue result timeout")}
	}
}

func (r *realRcuClient) opWorkerLoop() {
	for {
		select {
		case <-r.opStop:
			return
		case req := <-r.priorityOpCh:
			r.executeOperation(req)
			continue
		default:
		}

		select {
		case <-r.opStop:
			return
		case req := <-r.priorityOpCh:
			r.executeOperation(req)
		case req := <-r.normalOpCh:
			r.executeOperation(req)
		}
	}
}

func (r *realRcuClient) executeOperation(req opRequest) {
	if !isPollingOp(req.kind) || verbosePollingLogsEnabled() {
		log.Printf(
			"rcu.op.exec room=%s kind=%s priority=%s timeoutMs=%d metadata=%s",
			r.room,
			req.kind,
			req.priority,
			req.timeout.Milliseconds(),
			strings.TrimSpace(req.metadata),
		)
	}

	lockWaitStartedAt := time.Now()
	r.connMu.Lock()
	lockWaitMs := time.Since(lockWaitStartedAt).Milliseconds()
	defer r.connMu.Unlock()

	if err := r.ensureConnectedWithTimeoutLocked(connectTimeout); err != nil {
		req.resultCh <- opResult{err: err, lockWaitMs: lockWaitMs}
		return
	}

	payload, err := req.exec(req.timeout)
	if err != nil {
		if isTimeoutError(err) {
			log.Printf("rcu.op.timeout room=%s kind=%s error=%v", r.room, req.kind, err)
		}
		if shouldResetConnOnError(err) {
			r.closeConnLocked()
		}
		req.resultCh <- opResult{err: err, lockWaitMs: lockWaitMs}
		return
	}
	req.resultCh <- opResult{payload: payload, lockWaitMs: lockWaitMs}
}

func (r *realRcuClient) enqueueCommand(cmd queuedCommand) commandResult {
	cmd.enqueuedAt = time.Now()
	if cmd.requestID == "" {
		cmd.requestID = fmt.Sprintf("%s-%d", cmd.kind, cmd.enqueuedAt.UnixMilli())
	}
	if cmd.kind == queuedCommandScene && r.sceneCoalescingActive {
		seq := r.sceneSeq.Add(1)
		cmd.seq = seq
		r.latestSceneSeq.Store(seq)
		r.latestSceneNumber.Store(int32(cmd.scene))
	}
	cmd.resultCh = make(chan commandResult, 1)

	select {
	case <-r.queueStop:
		return commandResult{ok: false, err: fmt.Errorf("command queue stopped")}
	case r.cmdQueue <- cmd:
		log.Printf(
			"cmd.queue.enqueue room=%s kind=%s requestId=%s queueDepth=%d",
			r.room, cmd.kind, cmd.requestID, len(r.cmdQueue),
		)
	case <-time.After(2 * time.Second):
		return commandResult{ok: false, err: fmt.Errorf("command queue enqueue timeout")}
	}

	select {
	case res := <-cmd.resultCh:
		return res
	case <-time.After(30 * time.Second):
		return commandResult{ok: false, err: fmt.Errorf("command queue result timeout")}
	}
}

func (r *realRcuClient) commandWorker() {
	for {
		select {
		case <-r.queueStop:
			return
		case cmd := <-r.cmdQueue:
			r.executeQueuedCommand(cmd)
		}
	}
}

func (r *realRcuClient) executeQueuedCommand(cmd queuedCommand) {
	startedAt := time.Now()
	if cmd.kind == queuedCommandScene && r.sceneCoalescingActive {
		latest := r.latestSceneSeq.Load()
		if cmd.seq > 0 && cmd.seq < latest {
			latestScene := int(r.latestSceneNumber.Load())
			log.Printf(
				"cmd.queue.scene.superseded room=%s dropped=1 latestScene=%d requestId=%s",
				r.room, latestScene, cmd.requestID,
			)
			cmd.resultCh <- commandResult{
				ok: false,
				payload: map[string]interface{}{
					"scene":        cmd.scene,
					"triggered":    false,
					"status":       "superseded",
					"attemptsMade": 0,
					"error":        "superseded by newer scene request",
				},
				err:        fmt.Errorf("scene superseded by newer request"),
				attempts:   0,
				durationMs: time.Since(startedAt).Milliseconds(),
			}
			return
		}
	}
	maxAttempts := 1
	if commandRetryEnabled() {
		maxAttempts += commandRetryMax()
	}
	if cmd.kind == queuedCommandScene {
		// Scene retry policy is handled inside doCallLightingScene to keep status payload coherent.
		maxAttempts = 1
	}
	backoffs := []time.Duration{
		100 * time.Millisecond,
		300 * time.Millisecond,
		900 * time.Millisecond,
	}

	var lastErr error
	var lastPayload map[string]interface{}
	for attempt := 1; attempt <= maxAttempts; attempt++ {
		log.Printf(
			"cmd.queue.exec room=%s kind=%s requestId=%s attempt=%d/%d",
			r.room, cmd.kind, cmd.requestID, attempt, maxAttempts,
		)

		var payload map[string]interface{}
		var err error
		switch cmd.kind {
		case queuedCommandScene:
			payload, err = r.doCallLightingScene(cmd.scene)
		case queuedCommandLightingLevel:
			payload, err = r.doUpdateLightingLevel(cmd.address, cmd.level)
		default:
			err = fmt.Errorf("unknown command kind: %s", cmd.kind)
		}

		if err == nil && payload != nil {
			cmd.resultCh <- commandResult{
				ok:         true,
				payload:    payload,
				attempts:   attempt,
				durationMs: time.Since(startedAt).Milliseconds(),
			}
			log.Printf(
				"cmd.queue.success room=%s kind=%s requestId=%s attempts=%d durationMs=%d",
				r.room, cmd.kind, cmd.requestID, attempt, time.Since(startedAt).Milliseconds(),
			)
			return
		}

		lastErr = err
		if payload != nil {
			lastPayload = payload
		}
		var sceneErr *sceneCallError
		if errors.As(err, &sceneErr) && sceneErr != nil && sceneErr.payload != nil {
			lastPayload = cloneMap(sceneErr.payload)
		}
		if attempt >= maxAttempts || !isTransientCommandError(err) {
			break
		}
		backoff := backoffs[minInt(attempt-1, len(backoffs)-1)]
		log.Printf(
			"cmd.queue.retry room=%s kind=%s requestId=%s attempt=%d backoffMs=%d err=%v",
			r.room, cmd.kind, cmd.requestID, attempt, backoff.Milliseconds(), err,
		)
		time.Sleep(backoff)
	}

	log.Printf(
		"cmd.queue.fail room=%s kind=%s requestId=%s attempts=%d durationMs=%d err=%v",
		r.room, cmd.kind, cmd.requestID, maxAttempts, time.Since(startedAt).Milliseconds(), lastErr,
	)
	cmd.resultCh <- commandResult{
		ok:         false,
		payload:    lastPayload,
		err:        lastErr,
		attempts:   maxAttempts,
		durationMs: time.Since(startedAt).Milliseconds(),
	}
}

func (r *realRcuClient) refresh() error {
	_, err := r.enqueueRefreshOps(opPriorityNormal)
	return err
}

func (r *realRcuClient) enqueueRefreshOps(priority opPriority) (string, error) {
	if r.hasPendingWrite() {
		r.refreshSkipCounter.Add(1)
		logPollingf("rcu.refresh.skip room=%s reason=pending_write", r.room)
		logPollingf("rcu.refresh.outcome room=%s outcome=skipped", r.room)
		return "skipped", nil
	}
	if active, remainingMs := r.sceneWindowRemainingMs(); active {
		r.refreshSkipCounter.Add(1)
		logPollingf("rcu.refresh.skip room=%s reason=scene_window remainingMs=%d", r.room, remainingMs)
		logPollingf("rcu.refresh.outcome room=%s outcome=skipped_scene_window", r.room)
		return "skipped_scene_window", nil
	}

	r.mu.RLock()
	last := r.lastUpdate
	r.mu.RUnlock()
	if !last.IsZero() && time.Since(last) < minRefreshInterval {
		remainingMs := (minRefreshInterval - time.Since(last)).Milliseconds()
		if remainingMs < 0 {
			remainingMs = 0
		}
		logPollingf("rcu.refresh.skip room=%s reason=min_interval remainingMs=%d", r.room, remainingMs)
		logPollingf("rcu.refresh.outcome room=%s outcome=skipped", r.room)
		return "skipped", nil
	}

	if !r.initialized {
		initRes := r.enqueueOperation(opRequest{
			kind:     opKindRefreshMisc,
			priority: priority,
			timeout:  timeoutFor(opKindRefreshMisc),
			metadata: "initialize",
			exec: func(timeout time.Duration) (map[string]interface{}, error) {
				return nil, r.initializeLockedConn()
			},
		})
		if initRes.err != nil {
			return "cache", initRes.err
		}
	}

	coreRes := r.enqueueOperation(opRequest{
		kind:     opKindRefreshCore,
		priority: priority,
		timeout:  timeoutFor(opKindRefreshCore),
		metadata: "refresh_core",
		exec: func(timeout time.Duration) (map[string]interface{}, error) {
			return nil, r.refreshCoreStateLockedConnWithTimeout(timeout)
		},
	})
	if coreRes.err != nil {
		return "cache", coreRes.err
	}

	partial := false
	addresses := r.outputAddresses()
	total := len(addresses)
	processed := 0
	remaining := 0
	if total > 0 {
		budget := refreshOutputBudgetPerCycle
		if budget <= 0 || budget > total {
			budget = total
		}
		r.mu.RLock()
		start := r.refreshOutputCursor % total
		r.mu.RUnlock()
		for i := 0; i < budget; i++ {
			if len(r.priorityOpCh) > 0 {
				partial = true
				break
			}
			if active, _ := r.sceneWindowRemainingMs(); active {
				r.refreshSkipCounter.Add(1)
				logPollingf("rcu.refresh.preempt room=%s phase=scene_window", r.room)
				partial = true
				break
			}
			addr := addresses[(start+i)%total]
			res := r.enqueueOperation(opRequest{
				kind:     opKindRefreshOutput,
				priority: priority,
				timeout:  timeoutFor(opKindRefreshOutput),
				metadata: fmt.Sprintf("address=%d", addr),
				exec: func(address int) func(time.Duration) (map[string]interface{}, error) {
					return func(timeout time.Duration) (map[string]interface{}, error) {
						return nil, r.refreshOutputLockedConnWithTimeout(address, timeout)
					}
				}(addr),
			})
			if res.err != nil {
				logPollingf("rcu.output refresh warn room=%s address=%d error=%v", r.room, addr, res.err)
			}
			processed++
			if r.hasPendingWrite() {
				r.refreshSkipCounter.Add(1)
				logPollingf("rcu.refresh.preempt room=%s phase=dynamic_outputs", r.room)
				partial = true
				break
			}
		}
		remaining = total - processed
		if remaining < 0 {
			remaining = 0
		}
		r.mu.Lock()
		if processed > 0 {
			r.refreshOutputCursor = (start + processed) % total
		}
		r.mu.Unlock()
	}
	r.mu.Lock()
	r.lastUpdate = time.Now().UTC()
	r.mu.Unlock()

	outcome := "live"
	if partial || (total > 0 && remaining > 0) {
		outcome = "partial"
	}
	if total > 0 {
		logPollingf(
			"rcu.refresh.budget room=%s processed=%d remaining=%d outcome=%s",
			r.room,
			processed,
			remaining,
			outcome,
		)
	}
	logPollingf("rcu.refresh.outcome room=%s outcome=%s", r.room, outcome)
	return outcome, nil
}

func (r *realRcuClient) sceneWindowRemainingMs() (bool, int64) {
	lastSceneNs := r.lastSceneAt.Load()
	if lastSceneNs <= 0 {
		return false, 0
	}
	elapsed := time.Since(time.Unix(0, lastSceneNs))
	if elapsed >= sceneRefreshBlock {
		return false, 0
	}
	remaining := (sceneRefreshBlock - elapsed).Milliseconds()
	if remaining < 0 {
		remaining = 0
	}
	return true, remaining
}

func (r *realRcuClient) refreshUnlockedLockedConn() error {
	startedAt := time.Now()
	defer logSlowDuration("rcu.refresh.duration", startedAt, " room=%s", r.room)

	if r.hasPendingWrite() {
		r.refreshSkipCounter.Add(1)
		logPollingf("rcu.refresh.skip room=%s reason=pending_write", r.room)
		return nil
	}

	if !r.initialized {
		if err := r.initializeLockedConn(); err != nil {
			return err
		}
	}
	if err := r.refreshDynamicStateLockedConn(); err != nil {
		return err
	}
	r.mu.Lock()
	r.lastUpdate = time.Now().UTC()
	r.mu.Unlock()
	return nil
}

func (r *realRcuClient) refreshCoreStateLockedConnWithTimeout(timeout time.Duration) error {
	occFrame, err := r.sendRequestLockedWithTimeout([]byte{rcuHeader, 0x03, 0x00, 0x02, 0x05, 0x02}, timeout)
	if err != nil {
		return fmt.Errorf("occupancy request failed: %w", err)
	}
	doorFrame, err := r.sendRequestLockedWithTimeout([]byte{rcuHeader, 0x03, 0x00, 0x02, 0x05, 0x04}, timeout)
	if err != nil {
		return fmt.Errorf("door request failed: %w", err)
	}
	dndFrame, err := r.sendRequestLockedWithTimeout([]byte{rcuHeader, 0x03, 0x00, 0x02, 0x06, 0x00}, timeout)
	if err != nil {
		return fmt.Errorf("dnd summary request failed: %w", err)
	}
	r.mu.Lock()
	if len(occFrame.Payload) > 0 {
		r.isRoomOccupied = occFrame.Payload[0] == 1
	}
	if len(doorFrame.Payload) > 0 {
		r.isDoorOpened = doorFrame.Payload[0] == 1
	}
	if len(dndFrame.Payload) > 0 {
		r.isDndActive = dndFrame.Payload[0] == 1
	}
	if len(dndFrame.Payload) > 1 {
		r.murState = mapMurStateFromSummaryByte(dndFrame.Payload[1])
	}
	if len(dndFrame.Payload) > 2 {
		r.isLaundryOn = dndFrame.Payload[2] == 1
	}
	occupied := r.isRoomOccupied
	doorOpen := r.isDoorOpened
	doorAlarm := r.hasDoorAlarm
	dndActive := r.isDndActive
	murState := r.murState
	laundryOn := r.isLaundryOn
	r.mu.Unlock()
	logPollingf(
		"rcu.refresh.core_state room=%s occupied=%t doorOpen=%t hasDoorAlarm=%t dnd=%t mur=%d laundry=%t",
		r.room,
		occupied,
		doorOpen,
		doorAlarm,
		dndActive,
		murState,
		laundryOn,
	)
	return nil
}

func (r *realRcuClient) initializeLockedConn() error {
	if _, err := r.sendRequestLocked([]byte{rcuHeader, 0x03, 0x00, 0x02, 0x00, 0x00}); err == nil {
		// optional GTIN payload
	}

	if err := r.refreshCoreStateLockedConn(); err != nil {
		return err
	}

	onboardOutputs, err := r.fetchOnboardOutputAddressesLockedConn()
	if err != nil {
		return err
	}
	daliOutputs, err := r.fetchDaliOutputAddressesLockedConn()
	if err != nil {
		return err
	}

	r.mu.Lock()
	for _, addr := range onboardOutputs {
		if _, ok := r.outputs[addr]; !ok {
			r.outputs[addr] = &outputDeviceState{Address: addr, Onboard: true, Variety: deviceVarietyOnboardGear, Type: "Onboard"}
		}
	}
	for _, addr := range daliOutputs {
		if _, ok := r.outputs[addr]; !ok {
			r.outputs[addr] = &outputDeviceState{Address: addr, Onboard: false, Variety: deviceVarietyDaliGear, Type: "DALI Gear"}
		}
	}
	r.applyExpectedDeviceNamesLocked()
	r.mu.Unlock()

	r.initialized = true
	log.Printf("rcu.initialized room=%s outputs=%d", r.room, len(r.outputs))
	r.bootstrapThermostatRegistersLockedConn()
	// Temporary: disable periodic thermostat polling loop.
	// r.startModbusSyncLoop()
	return nil
}

func (r *realRcuClient) refreshCoreStateLockedConn() error {
	return r.refreshCoreStateLockedConnWithTimeout(timeoutFor(opKindRefreshCore))
}

func (r *realRcuClient) refreshDynamicStateLockedConn() error {
	startedAt := time.Now()
	defer logSlowDuration(
		"rcu.refresh_dynamic.duration",
		startedAt,
		" room=%s",
		r.room,
	)
	if r.hasPendingWrite() {
		r.refreshSkipCounter.Add(1)
		logPollingf("rcu.refresh.preempt room=%s phase=dynamic_outputs", r.room)
		return nil
	}

	if err := r.refreshCoreStateLockedConn(); err != nil {
		return err
	}
	_ = r.refreshDaliLineStatusLockedConn()

	addresses := r.outputAddresses()
	for _, addr := range addresses {
		if active, _ := r.sceneWindowRemainingMs(); active {
			r.refreshSkipCounter.Add(1)
			logPollingf("rcu.refresh.preempt room=%s phase=scene_window", r.room)
			break
		}
		if r.hasPendingWrite() {
			r.refreshSkipCounter.Add(1)
			logPollingf("rcu.refresh.preempt room=%s phase=dynamic_outputs", r.room)
			break
		}
		if err := r.refreshOutputLockedConn(addr); err != nil {
			logPollingf("rcu.output refresh warn room=%s address=%d error=%v", r.room, addr, err)
		}
	}
	return nil
}

func (r *realRcuClient) refreshDaliLineStatusLockedConn() error {
	now := time.Now()
	if r.shouldSkipDaliLineStatusQuery(now) {
		return nil
	}

	frame, err := r.sendRequestLockedWithTimeout(buildDaliLineStatusQuery(), daliLineStatusQueryTimeout)
	if err != nil {
		if isTimeoutError(err) {
			if disabled, until := r.registerDaliLineStatusTimeout(now); disabled {
				log.Printf(
					"WARN rcu.dali.line_status disabled room=%s reason=no_response until=%s",
					r.room,
					until.Format(time.RFC3339),
				)
			}
			return nil
		}
		log.Printf("WARN rcu.dali.line_status query failed room=%s error=%v", r.room, err)
		return nil
	}

	recovered := r.markDaliLineStatusSuccess()
	if recovered {
		log.Printf("INFO rcu.dali.line_status recovered room=%s", r.room)
	}

	if frame == nil {
		return nil
	}
	r.parseDaliLineStatus(frame.Payload)
	return nil
}

func (r *realRcuClient) shouldSkipDaliLineStatusQuery(now time.Time) bool {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return !r.daliLineStatusDisabledUntil.IsZero() && now.Before(r.daliLineStatusDisabledUntil)
}

func (r *realRcuClient) registerDaliLineStatusTimeout(now time.Time) (bool, time.Time) {
	r.mu.Lock()
	defer r.mu.Unlock()

	r.daliLineStatusProbeDone = true
	r.daliLineStatusConsecutiveTimeouts++
	if r.daliLineStatusConsecutiveTimeouts < daliLineStatusDisableAfter {
		return false, time.Time{}
	}
	alreadyDisabled := !r.daliLineStatusSupported && now.Before(r.daliLineStatusDisabledUntil)
	r.daliLineStatusSupported = false
	r.daliLineStatusDisabledUntil = now.Add(daliLineStatusDisableFor)
	if alreadyDisabled {
		return false, r.daliLineStatusDisabledUntil
	}
	return true, r.daliLineStatusDisabledUntil
}

func (r *realRcuClient) markDaliLineStatusSuccess() bool {
	r.mu.Lock()
	defer r.mu.Unlock()

	recovered := r.daliLineStatusProbeDone && !r.daliLineStatusSupported
	r.daliLineStatusProbeDone = true
	r.daliLineStatusSupported = true
	r.daliLineStatusConsecutiveTimeouts = 0
	r.daliLineStatusDisabledUntil = time.Time{}
	return recovered
}

func (r *realRcuClient) parseDaliLineStatus(payload []byte) {
	if len(payload) < 1 {
		log.Printf("DEBUG rcu.dali.line_status payload too short room=%s payloadLen=%d", r.room, len(payload))
		return
	}
	status := int(payload[0])
	shortCircuit := status == daliLineStatusShortCircuit

	r.mu.Lock()
	prevStatus := r.daliLineStatus
	prevShortCircuit := r.daliLineShortCircuit
	r.daliLineStatus = status
	r.daliLineShortCircuit = shortCircuit
	r.mu.Unlock()

	if prevStatus == status && prevShortCircuit == shortCircuit {
		return
	}
	if shortCircuit && !prevShortCircuit {
		log.Printf(
			"WARN rcu.dali.line_status room=%s status=%d short_circuit=%t prev_status=%d prev_short_circuit=%t",
			r.room, status, shortCircuit, prevStatus, prevShortCircuit,
		)
		return
	}
	log.Printf(
		"INFO rcu.dali.line_status room=%s status=%d short_circuit=%t prev_status=%d prev_short_circuit=%t",
		r.room, status, shortCircuit, prevStatus, prevShortCircuit,
	)
}

func (r *realRcuClient) markWriteStart() {
	r.pendingWrites.Add(1)
}

func (r *realRcuClient) markWriteDone() {
	for {
		current := r.pendingWrites.Load()
		if current <= 0 {
			return
		}
		if r.pendingWrites.CompareAndSwap(current, current-1) {
			return
		}
	}
}

func (r *realRcuClient) hasPendingWrite() bool {
	return r.pendingWrites.Load() > 0
}

func (r *realRcuClient) bootstrapThermostatRegistersLockedConn() {
	for _, reg := range thermostatBootstrapRegisters {
		ev, err := r.sendModbusReadAndAwaitAckLocked(reg, 1, modbusDeviceShortAddr)
		if err != nil {
			// log.Printf("rcu.modbus.bootstrap.read failed room=%s reg=0x%X error=%v", r.room, reg, err)
			continue
		}
		if ev.Ack != modbusAckOK {
			// log.Printf("rcu.modbus.bootstrap.read nack room=%s reg=0x%X ack=0x%X", r.room, reg, ev.Ack)
			continue
		}
		r.applyModbusReadReturnEvent(ev)
	}
}

func (r *realRcuClient) startModbusSyncLoop() {
	r.syncLoopOnce.Do(func() {
		go func() {
			ticker := time.NewTicker(10 * time.Second)
			defer ticker.Stop()
			for range ticker.C {
				r.connMu.Lock()
				if err := r.ensureConnectedLocked(); err != nil {
					r.connMu.Unlock()
					continue
				}
				r.drainEventsLockedConn(200 * time.Millisecond)
				for _, reg := range thermostatBootstrapRegisters {
					ev, err := r.sendModbusReadAndAwaitAckLocked(reg, 1, modbusDeviceShortAddr)
					if err != nil {
						// log.Printf("rcu.modbus.poll.read failed room=%s reg=0x%X error=%v", r.room, reg, err)
						r.closeConnLocked()
						break
					}
					if ev.Ack != modbusAckOK {
						// log.Printf("rcu.modbus.poll.read nack room=%s reg=0x%X ack=0x%X", r.room, reg, ev.Ack)
						continue
					}
					r.applyModbusReadReturnEvent(ev)
				}
				r.connMu.Unlock()
			}
		}()
	})
}

func (r *realRcuClient) drainEventsLockedConn(wait time.Duration) {
	deadline := time.Now().Add(wait)
	for {
		if err := r.conn.SetReadDeadline(deadline); err != nil {
			return
		}
		frame, err := readFrame(r.conn)
		if err != nil {
			if isTimeoutError(err) {
				return
			}
			log.Printf("rcu.event.drain error room=%s error=%v", r.room, err)
			r.closeConnLocked()
			return
		}
		if frame.CmdType == 4 {
			r.processEvent(frame)
		}
	}
}

func (r *realRcuClient) drainIncomingFramesLockedConn(wait time.Duration) error {
	if r.conn == nil {
		return nil
	}
	deadline := time.Now().Add(wait)
	for {
		if err := r.conn.SetReadDeadline(deadline); err != nil {
			return err
		}
		frame, err := readFrame(r.conn)
		if err != nil {
			if isTimeoutError(err) {
				return nil
			}
			return err
		}
		if frame.CmdType == 4 {
			r.processEvent(frame)
		}
	}
}

func (r *realRcuClient) sendModbusReadAndAwaitAckLocked(register int, count int, shortAddr int) (*modbusReadReturnEvent, error) {
	msg := buildModbusReadRegisterMessage(register, count, shortAddr)
	if err := r.conn.SetWriteDeadline(time.Now().Add(5 * time.Second)); err != nil {
		return nil, err
	}
	if _, err := r.conn.Write(msg); err != nil {
		return nil, err
	}
	// log.Printf("rcu.modbus.read room=%s reg=0x%X count=%d frame_hex=% X", r.room, register, count, msg)

	deadline := time.Now().Add(5 * time.Second)
	for {
		if err := r.conn.SetReadDeadline(deadline); err != nil {
			return nil, err
		}
		frame, err := readFrame(r.conn)
		if err != nil {
			return nil, err
		}
		if frame.CmdType != 4 {
			continue
		}
		r.processEvent(frame)
		if frame.CmdNo != 7 || frame.SubCmdNo != 0 {
			continue
		}
		ev, ok := parseModbusReadReturnEvent(frame.Payload)
		if !ok {
			continue
		}
		if ev.ShortAddr != shortAddr || ev.StartReg != register {
			continue
		}
		// log.Printf("rcu.modbus.read.ack room=%s short_addr=%d ack=0x%X start_reg=0x%X count=%d", r.room, ev.ShortAddr, ev.Ack, ev.StartReg, ev.Count)
		return ev, nil
	}
}

func (r *realRcuClient) sendModbusWriteAndAwaitAckLocked(msg []byte, shortAddr int) (*modbusWriteReturnEvent, error) {
	if err := r.conn.SetWriteDeadline(time.Now().Add(5 * time.Second)); err != nil {
		return nil, err
	}
	if _, err := r.conn.Write(msg); err != nil {
		return nil, err
	}

	deadline := time.Now().Add(5 * time.Second)
	for {
		if err := r.conn.SetReadDeadline(deadline); err != nil {
			return nil, err
		}
		frame, err := readFrame(r.conn)
		if err != nil {
			return nil, err
		}
		if frame.CmdType != 4 {
			continue
		}
		r.processEvent(frame)
		if frame.CmdNo != 7 || frame.SubCmdNo != 1 {
			continue
		}
		ev, ok := parseModbusWriteReturnEvent(frame.Payload)
		if !ok {
			continue
		}
		if ev.ShortAddr != shortAddr {
			continue
		}
		return ev, nil
	}
}

func (r *realRcuClient) applyModbusReadReturnEvent(ev *modbusReadReturnEvent) {
	if ev == nil {
		return
	}
	for i, value := range ev.Values {
		r.applyHvacRegisterLocal(ev.StartReg+i, value)
	}
}

func (r *realRcuClient) refreshOutputLockedConn(address int) error {
	return r.refreshOutputLockedConnWithTimeout(address, timeoutFor(opKindRefreshOutput))
}

func (r *realRcuClient) refreshOutputLockedConnWithTimeout(address int, timeout time.Duration) error {
	dev := r.findOutput(address)
	if dev == nil {
		return fmt.Errorf("missing output %d", address)
	}

	if dev.Onboard {
		if frame, err := r.sendRequestLockedWithTimeout([]byte{rcuHeader, 0x04, 0x00, 0x02, 0x02, 0x10, byte(address)}, timeout); err == nil {
			name := parseName(frame.Payload)
			if name != "" {
				r.mu.Lock()
				dev.Name = name
				r.mu.Unlock()
			}
		}
		if frame, err := r.sendRequestLockedWithTimeout([]byte{rcuHeader, 0x04, 0x00, 0x02, 0x02, 0x0C, byte(address)}, timeout); err == nil {
			r.parseOnboardOutputFeatures(dev, frame.Payload)
		}
		if frame, err := r.sendRequestLockedWithTimeout([]byte{rcuHeader, 0x04, 0x00, 0x02, 0x02, 0x12, byte(address)}, timeout); err == nil {
			r.parseOutputFeature(dev, frame.Payload)
		}
		return nil
	}

	if frame, err := r.sendRequestLockedWithTimeout([]byte{rcuHeader, 0x04, 0x00, 0x02, 0x04, 0x0A, byte(address)}, timeout); err == nil {
		name := parseName(frame.Payload)
		if name != "" {
			r.mu.Lock()
			dev.Name = name
			r.mu.Unlock()
		}
	}
	if frame, err := r.sendRequestLockedWithTimeout([]byte{rcuHeader, 0x04, 0x00, 0x02, 0x04, 0x06, byte(address)}, timeout); err == nil {
		r.parseDaliRam(dev, frame.Payload)
	}
	if frame, err := r.sendRequestLockedWithTimeout([]byte{rcuHeader, 0x04, 0x00, 0x02, 0x04, 0x04, byte(address)}, timeout); err == nil {
		r.parseDaliNvmPower(dev, frame.Payload)
	}
	if frame, err := r.sendRequestLockedWithTimeout([]byte{rcuHeader, 0x04, 0x00, 0x02, 0x04, 0x0C, byte(address)}, timeout); err == nil {
		r.parseOutputFeature(dev, frame.Payload)
	}
	if frame, err := r.sendRequestLockedWithTimeout(buildDaliMastheadQuery(address), timeout); err == nil {
		r.parseDaliDeviceMasthead(dev, frame.Payload)
	} else {
		logPollingf("rcu.dali.masthead query failed room=%s address=%d error=%v", r.room, address, err)
	}
	return nil
}

func (r *realRcuClient) parseOnboardOutputFeatures(dev *outputDeviceState, payload []byte) {
	if len(payload) < 11 {
		return
	}
	r.mu.Lock()
	dev.TargetLevel = rcuLevelToPercent(int(payload[7]))
	dev.ActualLevel = rcuLevelToPercent(int(payload[8]))
	dev.Status = gearStatusInfo(int(payload[10]))
	r.mu.Unlock()
}

func (r *realRcuClient) parseDaliRam(dev *outputDeviceState, payload []byte) {
	if len(payload) < 4 {
		return
	}
	r.mu.Lock()
	dev.ActualLevel = daliLevelToPercent(int(payload[0]))
	dev.TargetLevel = daliLevelToPercent(int(payload[1]))
	dev.Status = gearStatusInfo(int(payload[3]))
	r.mu.Unlock()
}

func (r *realRcuClient) parseDaliNvmPower(dev *outputDeviceState, payload []byte) {
	// Mirrors tools/rcu_manager python payload layout for Q_dali_gear_nvm_content.
	if len(payload) < 67 {
		return
	}

	wattage := int(binary.BigEndian.Uint32(payload[45:49]))
	wattHourCounter := int(binary.BigEndian.Uint32(payload[49:53]))
	activeEnergy := make([]int, 7)
	apparentEnergy := make([]int, 7)
	for i := 0; i < 7; i++ {
		activeEnergy[i] = int(payload[53+i])
		apparentEnergy[i] = int(payload[60+i])
	}

	r.mu.Lock()
	dev.PowerW = intPtr(wattage)
	dev.WattHourCounter = intPtr(wattHourCounter)
	dev.ActiveEnergy = activeEnergy
	dev.ApparentEnergy = apparentEnergy
	r.mu.Unlock()
}

func (r *realRcuClient) parseDaliDeviceMasthead(dev *outputDeviceState, payload []byte) {
	if len(payload) < 3 {
		logPollingf("rcu.dali.masthead payload too short room=%s address=%d payloadLen=%d", r.room, dev.Address, len(payload))
		return
	}
	now := time.Now().UTC()
	situation := int(payload[2])
	alarm := situation == daliSituationPendent

	r.mu.Lock()
	address := dev.Address
	prevSituation := dev.DaliSituation
	prevAlarm := dev.Alarm
	prevPendentLogAt := dev.lastPendentLogAt
	prevDebugAt := dev.lastMastheadDebug
	dev.DaliSituation = situation
	dev.Alarm = alarm
	statusLabel := statusForMastheadLog(dev.Status)
	actualLevel := dev.ActualLevel
	targetLevel := dev.TargetLevel
	situationChanged := prevSituation != situation
	debugDue := situationChanged || prevDebugAt.IsZero() || now.Sub(prevDebugAt) >= mastheadParsedDebugEvery
	if debugDue {
		dev.lastMastheadDebug = now
	}
	logState := ""
	if !prevAlarm && alarm {
		logState = "enter"
		dev.lastPendentLogAt = now
	} else if prevAlarm && !alarm {
		logState = "clear"
		dev.lastPendentLogAt = time.Time{}
	} else if alarm && (prevPendentLogAt.IsZero() || now.Sub(prevPendentLogAt) >= pendentAlarmHeartbeat) {
		logState = "heartbeat"
		dev.lastPendentLogAt = now
	}
	r.mu.Unlock()

	if debugDue && verbosePollingLogsEnabled() {
		if situationChanged || alarm {
			log.Printf(
				"DEBUG rcu.dali.masthead parsed room=%s address=%d situation=%d alarm=%t payload=% X",
				r.room, address, situation, alarm, payload,
			)
		} else {
			log.Printf(
				"DEBUG rcu.dali.masthead parsed room=%s address=%d situation=%d alarm=%t payloadLen=%d",
				r.room, address, situation, alarm, len(payload),
			)
		}
	}

	switch logState {
	case "enter":
		logPollingf(
			"WARN rcu.dali.masthead pendent room=%s address=%d situation=%d status=%s actual=%d target=%d",
			r.room, address, situation, statusLabel, actualLevel, targetLevel,
		)
	case "heartbeat":
		logPollingf(
			"INFO rcu.dali.masthead pendent.still_active room=%s address=%d situation=%d status=%s actual=%d target=%d heartbeat=%s",
			r.room, address, situation, statusLabel, actualLevel, targetLevel, pendentAlarmHeartbeat,
		)
	case "clear":
		logPollingf(
			"INFO rcu.dali.masthead cleared room=%s address=%d prev_situation=%d new_situation=%d prev_alarm=%t new_alarm=%t",
			r.room, address, prevSituation, situation, prevAlarm, alarm,
		)
	}
}

func (r *realRcuClient) parseOutputFeature(dev *outputDeviceState, payload []byte) {
	if len(payload) == 0 {
		return
	}
	r.mu.Lock()
	dev.Feature = int(payload[0])
	r.mu.Unlock()
}

func buildDaliMastheadQuery(address int) []byte {
	return []byte{rcuHeader, 0x04, 0x00, 0x02, 0x04, 0x02, byte(address)}
}

func buildDaliLineStatusQuery() []byte {
	return []byte{rcuHeader, 0x03, 0x00, 0x02, 0x04, 0x10}
}

func statusForMastheadLog(status string) string {
	if strings.TrimSpace(status) == "" {
		return "<unknown>"
	}
	return status
}

func (r *realRcuClient) fetchOnboardOutputAddressesLockedConn() ([]int, error) {
	frame, err := r.sendRequestLocked([]byte{rcuHeader, 0x03, 0x00, 0x02, 0x02, 0x02})
	if err != nil {
		return nil, fmt.Errorf("onboard masthead request failed: %w", err)
	}
	payload := frame.Payload
	addresses := make([]int, 0)
	for i := 0; i+4 < len(payload); i += 5 {
		variety := int(payload[i])
		addr := int(payload[i+2])
		if variety == deviceVarietyOnboardGear {
			addresses = append(addresses, addr)
		}
	}
	return addresses, nil
}

func (r *realRcuClient) fetchDaliOutputAddressesLockedConn() ([]int, error) {
	frame, err := r.sendRequestLocked([]byte{rcuHeader, 0x03, 0x00, 0x02, 0x04, 0x00})
	if err != nil {
		return nil, fmt.Errorf("dali discover request failed: %w", err)
	}
	payload := frame.Payload
	if len(payload) == 0 {
		return nil, nil
	}
	addresses := make([]int, 0)
	for i := 1; i < len(payload); i++ {
		addr := int(payload[i])
		info, err := r.sendRequestLocked([]byte{rcuHeader, 0x04, 0x00, 0x02, 0x04, 0x02, byte(addr)})
		if err != nil || len(info.Payload) == 0 {
			continue
		}
		variety := int(info.Payload[0])
		if variety == deviceVarietyDaliGear || variety == deviceVarietyDigidimGear || variety == deviceVarietyElekonGear {
			addresses = append(addresses, addr)
		}
	}
	return addresses, nil
}

func (r *realRcuClient) ensureConnectedLocked() error {
	return r.ensureConnectedWithTimeoutLocked(connectTimeout)
}

func (r *realRcuClient) ensureConnectedWithTimeoutLocked(timeout time.Duration) error {
	if r.conn != nil {
		return nil
	}
	now := time.Now()
	if now.Before(r.reconnectBlockedUntil) {
		waitMs := time.Until(r.reconnectBlockedUntil).Milliseconds()
		if waitMs < 0 {
			waitMs = 0
		}
		return fmt.Errorf("reconnect cooldown active waitMs=%d", waitMs)
	}
	if timeout <= 0 {
		timeout = connectTimeout
	}
	if timeout > timeoutCap {
		timeout = timeoutCap
	}
	addr := net.JoinHostPort(r.cfg.Host, strconv.Itoa(r.cfg.Port))
	conn, err := net.DialTimeout("tcp", addr, timeout)
	if err != nil {
		r.reconnectFailCount++
		pow := r.reconnectFailCount - 1
		if pow < 0 {
			pow = 0
		}
		if pow > 8 {
			pow = 8
		}
		delay := 150 * time.Millisecond * time.Duration(1<<pow)
		if delay > 2*time.Second {
			delay = 2 * time.Second
		}
		jitter := time.Duration(time.Now().UnixNano()%121) * time.Millisecond
		delay += jitter
		r.reconnectBlockedUntil = time.Now().Add(delay)
		log.Printf(
			"rcu.connect.backoff room=%s delayMs=%d reason=%v failCount=%d",
			r.room,
			delay.Milliseconds(),
			err,
			r.reconnectFailCount,
		)
		return err
	}
	if tcp, ok := conn.(*net.TCPConn); ok {
		_ = tcp.SetKeepAlive(true)
		_ = tcp.SetNoDelay(true)
	}
	r.conn = conn
	r.reconnectFailCount = 0
	r.reconnectBlockedUntil = time.Time{}
	log.Printf("rcu.connect room=%s host=%s port=%d", r.room, r.cfg.Host, r.cfg.Port)
	return nil
}

func (r *realRcuClient) closeConnLocked() {
	if r.conn != nil {
		_ = r.conn.Close()
		r.conn = nil
		log.Printf("rcu.disconnect room=%s", r.room)
	}
}

func (r *realRcuClient) sendRequestLocked(msg []byte) (*rcuFrame, error) {
	return r.sendRequestLockedWithTimeout(msg, timeoutFor(opKindRefreshMisc))
}

func (r *realRcuClient) sendRequestLockedWithTimeout(msg []byte, timeout time.Duration) (*rcuFrame, error) {
	if r.conn == nil {
		return nil, fmt.Errorf("rcu connection is nil")
	}
	if timeout <= 0 {
		timeout = timeoutFor(opKindRefreshMisc)
	}
	if timeout > timeoutCap {
		timeout = timeoutCap
	}
	if err := r.conn.SetDeadline(time.Now().Add(timeout)); err != nil {
		return nil, err
	}
	if _, err := r.conn.Write(msg); err != nil {
		return nil, err
	}
	for {
		frame, err := readFrame(r.conn)
		if err != nil {
			return nil, err
		}
		if frame.CmdType == 4 {
			r.processEvent(frame)
			continue
		}
		return frame, nil
	}
}

func (r *realRcuClient) sendCommandNoResponseLocked(msg []byte) error {
	return r.sendCommandNoResponseLockedWithTimeout(msg, timeoutFor(opKindScene))
}

func (r *realRcuClient) sendCommandNoResponseLockedWithTimeout(msg []byte, timeout time.Duration) error {
	if r.conn == nil {
		return fmt.Errorf("rcu connection is nil")
	}
	if timeout <= 0 {
		timeout = sceneWriteOnlyTimeout
	}
	if timeout > timeoutCap {
		timeout = timeoutCap
	}
	if err := r.conn.SetWriteDeadline(time.Now().Add(timeout)); err != nil {
		return err
	}
	_, err := r.conn.Write(msg)
	return err
}

func sceneDebugEnabled() bool {
	v := strings.TrimSpace(os.Getenv("TESTCOMM_DEBUG_SCENES"))
	return v == "1" || strings.EqualFold(v, "true")
}

func verbosePollingLogsEnabled() bool {
	pollingLogsOnce.Do(func() {
		raw := strings.TrimSpace(os.Getenv("TESTCOMM_LOG_POLLING"))
		pollingLogsEnabled = raw == "1" || strings.EqualFold(raw, "true")
	})
	return pollingLogsEnabled
}

func logPollingf(format string, args ...interface{}) {
	if verbosePollingLogsEnabled() {
		log.Printf(format, args...)
	}
}

func isPollingOp(kind opKind) bool {
	switch kind {
	case opKindRefreshCore, opKindRefreshOutput, opKindRefreshMisc:
		return true
	default:
		return false
	}
}

func debugTimingThreshold() time.Duration {
	timingThresholdOnce.Do(func() {
		timingThreshold = 200 * time.Millisecond
		raw := strings.TrimSpace(os.Getenv("TESTCOMM_DEBUG_TIMING_THRESHOLD_MS"))
		if raw == "" {
			return
		}
		ms, err := strconv.Atoi(raw)
		if err != nil || ms < 0 {
			return
		}
		timingThreshold = time.Duration(ms) * time.Millisecond
	})
	return timingThreshold
}

func commandQueueSize() int {
	queueSizeOnce.Do(func() {
		queueSizeValue = 128
		raw := strings.TrimSpace(os.Getenv("TESTCOMM_CMD_QUEUE_SIZE"))
		if raw == "" {
			return
		}
		v, err := strconv.Atoi(raw)
		if err != nil || v <= 0 {
			return
		}
		queueSizeValue = v
	})
	return queueSizeValue
}

func commandRetryEnabled() bool {
	queueRetryOnce.Do(func() {
		queueRetryEnabled = true
		queueRetryMax = 3
		if raw := strings.TrimSpace(os.Getenv("TESTCOMM_CMD_RETRY_ENABLED")); raw != "" {
			queueRetryEnabled = raw == "1" || strings.EqualFold(raw, "true")
		}
		if raw := strings.TrimSpace(os.Getenv("TESTCOMM_CMD_RETRY_MAX")); raw != "" {
			if v, err := strconv.Atoi(raw); err == nil && v >= 0 {
				queueRetryMax = v
			}
		}
	})
	return queueRetryEnabled
}

func commandRetryMax() int {
	_ = commandRetryEnabled()
	return queueRetryMax
}

func refreshTemporarilyDisabled() bool {
	raw := strings.TrimSpace(os.Getenv("TESTCOMM_DISABLE_REFRESH"))
	return raw == "1" || strings.EqualFold(raw, "true")
}

func sceneCoalescingEnabled() bool {
	raw := strings.TrimSpace(os.Getenv("TESTCOMM_SCENE_COALESCE"))
	if raw == "" {
		return true
	}
	return raw == "1" || strings.EqualFold(raw, "true")
}

func sceneRequireResponse() bool {
	raw := strings.TrimSpace(os.Getenv("TESTCOMM_SCENE_REQUIRE_RESPONSE"))
	return raw == "1" || strings.EqualFold(raw, "true")
}

func timeoutFor(kind opKind) time.Duration {
	var timeout time.Duration
	switch kind {
	case opKindScene:
		timeout = sceneCommandTimeout
	case opKindLightingLevel:
		timeout = lightingWriteTimeout
	case opKindRefreshCore:
		timeout = refreshCoreTimeout
	case opKindRefreshOutput:
		timeout = refreshOutputTimeout
	case opKindRefreshMisc:
		timeout = connectTimeout
	default:
		timeout = connectTimeout
	}
	if timeout <= 0 {
		timeout = connectTimeout
	}
	if timeout > timeoutCap {
		return timeoutCap
	}
	return timeout
}

func isTransientCommandError(err error) bool {
	if err == nil {
		return false
	}
	switch classifyNetworkFault(err) {
	case faultTimeout, faultConnReset, faultBrokenPipe:
		return true
	}
	msg := strings.ToLower(err.Error())
	return strings.Contains(msg, "timeout") ||
		strings.Contains(msg, "temporarily unavailable") ||
		strings.Contains(msg, "eof") ||
		strings.Contains(msg, "forcibly closed")
}

func shouldResetConnOnError(err error) bool {
	if err == nil {
		return false
	}
	switch classifyNetworkFault(err) {
	case faultTimeout, faultConnReset, faultBrokenPipe, faultNilConn:
		return true
	}
	return isTransientCommandError(err)
}

type networkFault string

const (
	faultTimeout    networkFault = "timeout"
	faultConnReset  networkFault = "conn_reset"
	faultBrokenPipe networkFault = "broken_pipe"
	faultNilConn    networkFault = "nil_conn"
	faultUnknown    networkFault = "unknown"
)

func classifyNetworkFault(err error) networkFault {
	if err == nil {
		return faultUnknown
	}
	if isTimeoutError(err) {
		return faultTimeout
	}
	msg := strings.ToLower(err.Error())
	switch {
	case strings.Contains(msg, "wsarecv"),
		strings.Contains(msg, "wsasend"),
		strings.Contains(msg, "forcibly closed"),
		strings.Contains(msg, "connection reset"):
		return faultConnReset
	case strings.Contains(msg, "broken pipe"):
		return faultBrokenPipe
	case strings.Contains(msg, "connection is nil"),
		strings.Contains(msg, "rcu connection is nil"):
		return faultNilConn
	default:
		return faultUnknown
	}
}

func minInt(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func logSlowDuration(metric string, startedAt time.Time, extraFmt string, args ...interface{}) {
	elapsed := time.Since(startedAt)
	if elapsed < debugTimingThreshold() {
		return
	}
	if extraFmt == "" {
		log.Printf("%s durationMs=%d", metric, elapsed.Milliseconds())
		return
	}
	log.Printf(
		"%s durationMs=%d%s",
		metric,
		elapsed.Milliseconds(),
		fmt.Sprintf(extraFmt, args...),
	)
}

func (r *realRcuClient) processEvent(frame *rcuFrame) {
	if frame == nil {
		return
	}
	if frame.CmdType != 4 {
		return
	}
	eventInfo := mapRcuEvent(frame.CmdNo, frame.SubCmdNo)
	if frame.CmdNo != 7 {
		payloadHex := strings.ToUpper(hex.EncodeToString(frame.Payload))
		log.Printf(
			"rcu.event room=%s cmdType=%d cmdNo=%d subCmdNo=%d payloadLen=%d payloadHex=%s",
			r.room,
			frame.CmdType,
			frame.CmdNo,
			frame.SubCmdNo,
			len(frame.Payload),
			payloadHex,
		)
		log.Printf(
			"rcu.event.type room=%s eventType=%s detail=%s",
			r.room,
			eventInfo.Name,
			eventInfo.Description,
		)
	}
	switch frame.CmdNo {
	case 4:
		log.Printf(
			"rcu.event.unhandled room=%s cmdNo=%d subCmdNo=%d payloadHex=%s detail=awaiting_mapping",
			r.room,
			frame.CmdNo,
			frame.SubCmdNo,
			strings.ToUpper(hex.EncodeToString(frame.Payload)),
		)
	case 5: // occupancy
		switch frame.SubCmdNo {
		case 0:
			r.mu.Lock()
			r.isDoorOpened = true
			r.mu.Unlock()
			log.Printf("rcu.event.decoded room=%s event=door state=open", r.room)
		case 1:
			r.mu.Lock()
			r.isDoorOpened = false
			r.mu.Unlock()
			log.Printf("rcu.event.decoded room=%s event=door state=closed", r.room)
		case 2:
			r.mu.Lock()
			r.hasDoorAlarm = true
			r.mu.Unlock()
			log.Printf("rcu.event.decoded room=%s event=door_alarm state=on", r.room)
		case 3:
			r.mu.Lock()
			r.hasDoorAlarm = false
			r.mu.Unlock()
			log.Printf("rcu.event.decoded room=%s event=door_alarm state=off", r.room)
		case 4:
			r.mu.Lock()
			r.isRoomOccupied = false
			r.mu.Unlock()
			log.Printf("rcu.event.decoded room=%s event=occupancy state=vacant", r.room)
		case 5:
			r.mu.Lock()
			r.isRoomOccupied = true
			r.mu.Unlock()
			log.Printf("rcu.event.decoded room=%s event=occupancy state=occupied", r.room)
		}
	case 6: // dnd app
		switch frame.SubCmdNo {
		case 0:
			r.mu.Lock()
			r.murState = murProgress
			r.mu.Unlock()
			log.Printf("rcu.event.decoded room=%s event=mur state=progress", r.room)
		case 1:
			r.mu.Lock()
			r.murState = murPassive
			r.mu.Unlock()
			log.Printf("rcu.event.decoded room=%s event=mur state=passive", r.room)
		case 2:
			r.mu.Lock()
			r.isLaundryOn = true
			r.mu.Unlock()
			log.Printf("rcu.event.decoded room=%s event=laundry state=on", r.room)
		case 3:
			r.mu.Lock()
			r.isLaundryOn = false
			r.mu.Unlock()
			log.Printf("rcu.event.decoded room=%s event=laundry state=off", r.room)
		case 4:
			r.mu.Lock()
			r.isDndActive = true
			r.mu.Unlock()
			log.Printf("rcu.event.decoded room=%s event=dnd state=on", r.room)
		case 5:
			r.mu.Lock()
			r.isDndActive = false
			r.mu.Unlock()
			log.Printf("rcu.event.decoded room=%s event=dnd state=off", r.room)
		case 6:
			r.mu.Lock()
			r.murState = murActive
			r.mu.Unlock()
			log.Printf("rcu.event.decoded room=%s event=mur state=active", r.room)
		case 7:
			r.mu.Lock()
			r.murState = murPassive
			r.mu.Unlock()
			log.Printf("rcu.event.decoded room=%s event=mur state=passive", r.room)
		}
	case 7: // modbus hvac
		switch frame.SubCmdNo {
		case 0:
			if ev, ok := parseModbusReadReturnEvent(frame.Payload); ok {
				r.applyModbusReadReturnEvent(ev)
				// log.Printf("rcu.event.decoded room=%s event=modbus_read_return short_addr=%d ack=0x%X reg=0x%X count=%d", r.room, ev.ShortAddr, ev.Ack, ev.StartReg, ev.Count)
			}
		case 1:
			if _, ok := parseModbusWriteReturnEvent(frame.Payload); ok {
				// log.Printf("rcu.event.decoded room=%s event=modbus_write_return short_addr=%d ack=0x%X reg=0x%X count=%d", r.room, ev.ShortAddr, ev.Ack, ev.StartReg, ev.Count)
			}
		case 2:
			if register, raw, ok := parseModbusSpecialRegisterEvent(frame.Payload); ok {
				r.applyHvacRegisterLocal(register, raw)
				// log.Printf("rcu.event.decoded room=%s event=hvac_register_update register=0x%X raw=%d", r.room, register, raw)
			}
		}
	}
	r.mu.Lock()
	r.lastUpdate = time.Now().UTC()
	r.mu.Unlock()
}

func mapRcuEvent(cmdNo, subCmdNo int) rcuEventInfo {
	switch cmdNo {
	case 5:
		switch subCmdNo {
		case 0:
			return rcuEventInfo{Name: "Event_occapp_door_opened", Description: "door opened"}
		case 1:
			return rcuEventInfo{Name: "Event_occapp_door_closed", Description: "door closed"}
		case 2:
			return rcuEventInfo{Name: "Event_occapp_open_door_alarm", Description: "open door alarm raised"}
		case 3:
			return rcuEventInfo{Name: "Event_occapp_open_door_alarm_deleted", Description: "open door alarm cleared"}
		case 4:
			return rcuEventInfo{Name: "Event_occapp_room_empty", Description: "room changed to empty"}
		case 5:
			return rcuEventInfo{Name: "Event_occapp_room_occupied", Description: "room changed to occupied"}
		}
	case 6:
		switch subCmdNo {
		case 0:
			return rcuEventInfo{Name: "Event_dndapp_mur_requested", Description: "MUR requested"}
		case 1:
			return rcuEventInfo{Name: "Event_dndapp_mur_request_canceled", Description: "MUR request canceled"}
		case 2:
			return rcuEventInfo{Name: "Event_dndapp_loundry_requested", Description: "laundry requested"}
		case 3:
			return rcuEventInfo{Name: "Event_dndapp_loundry_request_canceled", Description: "laundry request canceled"}
		case 4:
			return rcuEventInfo{Name: "Event_dndapp_dnd_active", Description: "DND active"}
		case 5:
			return rcuEventInfo{Name: "Event_dndapp_dnd_passive", Description: "DND passive"}
		case 6:
			return rcuEventInfo{Name: "Event_dndapp_mur_started", Description: "MUR started"}
		case 7:
			return rcuEventInfo{Name: "Event_dndapp_mur_finished", Description: "MUR finished"}
		}
	case 7:
		switch subCmdNo {
		case 0:
			return rcuEventInfo{Name: "Event_modbus_read_reg_rtrn", Description: "modbus read register return"}
		case 1:
			return rcuEventInfo{Name: "Event_modbus_write_reg_rtrn", Description: "modbus write register return"}
		case 2:
			return rcuEventInfo{Name: "Event_modbus_special_reg_events", Description: "modbus special register event"}
		}
	}
	return rcuEventInfo{
		Name:        fmt.Sprintf("Event_cmd%d_sub%d_unknown", cmdNo, subCmdNo),
		Description: "unknown event mapping",
	}
}

func (r *realRcuClient) applyHvacRegisterLocal(register int, rawValue int) {
	r.mu.Lock()
	defer r.mu.Unlock()
	switch register {
	case hvacRegRoomTemperature:
		r.hvac.RoomTemperature = floatPtr(decodeTemperature(rawValue))
	case hvacRegSetPoint:
		t := decodeTemperature(rawValue)
		r.hvac.SetPoint = floatPtr(t)
		r.hvac.ComfortTemperature = floatPtr(t)
	case hvacRegLowerSetpoint:
		r.hvac.LowerSetpoint = floatPtr(decodeTemperature(rawValue))
	case hvacRegUpperSetpoint:
		r.hvac.UpperSetpoint = floatPtr(decodeTemperature(rawValue))
	case hvacRegMode:
		r.hvac.Mode = intPtr(rawValue)
	case hvacRegFanMode:
		r.hvac.FanMode = intPtr(rawValue)
	case hvacRegOccupancyInput:
		r.hvac.OccupancyInput = intPtr(rawValue)
	case hvacRegRunningStatus:
		r.hvac.RunningStatus = intPtr(rawValue)
	case hvacRegOnOff:
		r.hvac.OnOff = intPtr(rawValue)
	case hvacRegKeylock:
		r.hvac.KeylockFunction = intPtr(rawValue)
	}
}

func buildModbusReadRegisterMessage(startReg int, count int, shortAddr int) []byte {
	payload := []byte{byte(shortAddr), byte((startReg >> 8) & 0xFF), byte(startReg & 0xFF), byte((count >> 8) & 0xFF), byte(count & 0xFF)}
	length := len(payload) + 3
	buf := bytes.NewBuffer(make([]byte, 0, 1+2+length))
	buf.WriteByte(rcuHeader)
	buf.WriteByte(byte(length & 0xFF))
	buf.WriteByte(byte((length >> 8) & 0xFF))
	buf.WriteByte(0x03)
	buf.WriteByte(0x07)
	buf.WriteByte(0x00)
	buf.Write(payload)
	return buf.Bytes()
}

func buildModbusWriteRegisterMessage(register int, value int) []byte {
	payload := []byte{modbusDeviceShortAddr, byte((register >> 8) & 0xFF), byte(register & 0xFF), 0x00, 0x01, byte((value >> 8) & 0xFF), byte(value & 0xFF)}
	length := len(payload) + 3
	buf := bytes.NewBuffer(make([]byte, 0, 1+2+length))
	buf.WriteByte(rcuHeader)
	buf.WriteByte(byte(length & 0xFF))
	buf.WriteByte(byte((length >> 8) & 0xFF))
	buf.WriteByte(0x03)
	buf.WriteByte(0x07)
	buf.WriteByte(0x01)
	buf.Write(payload)
	return buf.Bytes()
}

func parseModbusReadReturnEvent(payload []byte) (*modbusReadReturnEvent, bool) {
	if len(payload) < 6 {
		return nil, false
	}
	count := int(payload[4])<<8 | int(payload[5])
	if count < 0 || len(payload) < 6+(count*2) {
		return nil, false
	}
	ev := &modbusReadReturnEvent{
		ShortAddr: int(payload[0]),
		Ack:       int(payload[1]),
		StartReg:  int(payload[2])<<8 | int(payload[3]),
		Count:     count,
		Values:    make([]int, 0, count),
	}
	for i := 0; i < count; i++ {
		base := 6 + (i * 2)
		ev.Values = append(ev.Values, int(payload[base])<<8|int(payload[base+1]))
	}
	return ev, true
}

func parseModbusWriteReturnEvent(payload []byte) (*modbusWriteReturnEvent, bool) {
	if len(payload) < 6 {
		return nil, false
	}
	return &modbusWriteReturnEvent{
		ShortAddr: int(payload[0]),
		Ack:       int(payload[1]),
		StartReg:  int(payload[2])<<8 | int(payload[3]),
		Count:     int(payload[4])<<8 | int(payload[5]),
	}, true
}

func parseModbusSpecialRegisterEvent(payload []byte) (int, int, bool) {
	if len(payload) < 5 {
		return 0, 0, false
	}
	register := int(payload[1])<<8 | int(payload[2])
	raw := int(payload[3])<<8 | int(payload[4])
	return register, raw, true
}

func buildDaliEventTriggerScene(scene int) []byte {
	return []byte{rcuHeader, 0x0B, 0x00, 0x03, 0x04, 0x03, sceneGroupByte, 0x10, 0x02, 0x01, byte(scene), 0x00, 0x00, 0x00}
}

func readFrame(conn net.Conn) (*rcuFrame, error) {
	header := []byte{0}
	if _, err := io.ReadFull(conn, header); err != nil {
		return nil, err
	}
	if header[0] != rcuHeader {
		return nil, fmt.Errorf("invalid frame header: 0x%X", header[0])
	}
	lenBytes := make([]byte, 2)
	if _, err := io.ReadFull(conn, lenBytes); err != nil {
		return nil, err
	}
	length := int(binary.LittleEndian.Uint16(lenBytes))
	if length < 3 {
		return nil, fmt.Errorf("invalid frame length: %d", length)
	}
	body := make([]byte, length)
	if _, err := io.ReadFull(conn, body); err != nil {
		return nil, err
	}
	frame := &rcuFrame{CmdType: int(body[0]), CmdNo: int(body[1]), SubCmdNo: int(body[2])}
	if len(body) > 3 {
		frame.Payload = body[3:]
	}
	return frame, nil
}

func parseName(payload []byte) string {
	if len(payload) == 0 {
		return ""
	}
	name := strings.ReplaceAll(string(payload), "\x00", "")
	return strings.TrimSpace(name)
}

func (r *realRcuClient) findOutput(address int) *outputDeviceState {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return r.outputs[address]
}

func (r *realRcuClient) outputAddresses() []int {
	r.mu.RLock()
	defer r.mu.RUnlock()
	out := make([]int, 0, len(r.outputs))
	for k := range r.outputs {
		out = append(out, k)
	}
	sort.Ints(out)
	return out
}

func (r *realRcuClient) sortedOutputsLocked() []*outputDeviceState {
	out := make([]*outputDeviceState, 0, len(r.outputs))
	for _, v := range r.outputs {
		out = append(out, v)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Address < out[j].Address })
	return out
}

func (r *realRcuClient) applyExpectedDeviceNamesLocked() {
	expected := map[int]string{
		12: "Bed Left",
		4:  "Bed Right",
		3:  "Cove Top",
		6:  "Cove Bottom",
		13: "Spot Floor Lamp",
		10: "Bed Top",
		16: "Corridor Left",
		8:  "Corridor Right",
		7:  "Bathroom Left",
		14: "Bathroom Right",
	}
	for addr, name := range expected {
		if d, ok := r.outputs[addr]; ok {
			if strings.TrimSpace(d.Name) == "" || strings.EqualFold(d.Name, "DNH") {
				d.Name = name
			}
		}
	}
}

func (r *realRcuClient) mapHvacStateLocked() string {
	// Power should primarily follow the on/off register; running status can lag
	// (e.g. idle) and must not force power-off in UI snapshots.
	//
	// Mode register contract (aligned with tools/rcu_manager):
	// 0=Heat, 1=Cool, 2=FanOnly, 3=Auto
	if r.hvac.OnOff != nil && *r.hvac.OnOff == 0 {
		return "Off"
	}
	if r.hvac.Mode != nil {
		switch *r.hvac.Mode {
		case 0:
			return "Hot"
		case 1:
			return "Cold"
		case 2:
			return "Active"
		case 3:
			return "Active"
		}
	}
	if r.derivedPowerOnOffLocked() == 1 {
		return "Active"
	}
	for _, d := range r.outputs {
		if d.Feature == deviceFeatureFCUContact && (d.ActualLevel > 0 || strings.Contains(strings.ToUpper(d.Status), "LAMP_ON")) {
			return "Active"
		}
	}
	return "Off"
}

func (r *realRcuClient) buildHvacPayloadLocked(state string) map[string]interface{} {
	m := map[string]interface{}{"state": state}
	m["onOff"] = r.derivedPowerOnOffLocked()
	if r.hvac.RoomTemperature != nil {
		m["roomTemperature"] = round1(*r.hvac.RoomTemperature)
	}
	if r.hvac.SetPoint != nil {
		m["setPoint"] = round1(*r.hvac.SetPoint)
	}
	if r.hvac.Mode != nil {
		m["mode"] = *r.hvac.Mode
	}
	if r.hvac.FanMode != nil {
		m["fanMode"] = *r.hvac.FanMode
	}
	if r.hvac.ComfortTemperature != nil {
		m["comfortTemperature"] = round1(*r.hvac.ComfortTemperature)
	}
	if r.hvac.LowerSetpoint != nil {
		m["lowerSetpoint"] = round1(*r.hvac.LowerSetpoint)
	}
	if r.hvac.UpperSetpoint != nil {
		m["upperSetpoint"] = round1(*r.hvac.UpperSetpoint)
	}
	if r.hvac.KeylockFunction != nil {
		m["keylockFunction"] = *r.hvac.KeylockFunction
	}
	if r.hvac.OccupancyInput != nil {
		m["occupancyInput"] = *r.hvac.OccupancyInput
	}
	if r.hvac.RunningStatus != nil {
		m["runningStatus"] = *r.hvac.RunningStatus
	}
	if r.hvac.ComError != nil {
		m["comError"] = *r.hvac.ComError
	}
	if r.hvac.Fidelio != nil {
		m["fidelio"] = *r.hvac.Fidelio
	}
	return m
}

func (r *realRcuClient) derivedPowerOnOffLocked() int {
	if r.hvac.OnOff != nil {
		if *r.hvac.OnOff == 0 {
			return 0
		}
		return 1
	}
	if r.hvac.RunningStatus != nil {
		// Fallback when on/off register is unknown.
		switch *r.hvac.RunningStatus {
		case 0, 4:
			return 0
		default:
			return 1
		}
	}
	return 0
}

func (r *realRcuClient) isLightingOnLocked() bool {
	for _, d := range r.outputs {
		if d.ActualLevel > 0 || strings.Contains(strings.ToUpper(d.Status), "LAMP_ON") {
			return true
		}
	}
	return false
}

func (r *realRcuClient) mapLightingStringLocked() string {
	if r.isLightingOnLocked() {
		return "On"
	}
	return "Off"
}

func (r *realRcuClient) mapDndLocked() string {
	if r.isDndActive {
		return "Yellow"
	}
	return "Off"
}

func (r *realRcuClient) mapMurLocked() string {
	switch r.murState {
	case murActive:
		return "Yellow"
	case murProgress:
		if r.isRoomOccupied {
			return "Delayed"
		}
		return "Requested"
	default:
		return "Off"
	}
}

func mapMurStateFromSummaryByte(raw byte) int {
	switch raw {
	case 0:
		return murPassive
	case 1:
		return murActive
	case 2:
		return murProgress
	default:
		return murPassive
	}
}

func (r *realRcuClient) mapLaundryLocked() string {
	if !r.isLaundryOn {
		return "Off"
	}
	if r.isRoomOccupied {
		return "Delayed"
	}
	return "Requested"
}

func (r *realRcuClient) mapStatusLocked() string {
	if r.murState == murActive {
		return "Rented HK"
	}
	if r.isRoomOccupied {
		return "Rented Occupied"
	}
	return "Rented Vacant"
}

func (r *realRcuClient) mapHasAlarmLocked() bool {
	if r.hasDoorAlarm {
		return true
	}
	if r.daliLineShortCircuit {
		return true
	}
	for _, d := range r.outputs {
		if d.Alarm {
			return true
		}
		s := strings.ToUpper(d.Status)
		if strings.Contains(s, "FALIURE") || strings.Contains(s, "FAILURE") || strings.Contains(s, "LIMIT_ERROR") {
			return true
		}
	}
	return false
}

func (r *realRcuClient) buildLightingDevicesLocked() []map[string]interface{} {
	devices := make([]map[string]interface{}, 0)
	for _, d := range r.sortedOutputsLocked() {
		entry := map[string]interface{}{
			"address":     d.Address,
			"name":        d.Name,
			"variety":     d.Variety,
			"type":        map[bool]string{true: "onboard", false: "dali"}[d.Onboard],
			"actualLevel": d.ActualLevel,
			"targetLevel": d.TargetLevel,
			"status":      d.Status,
			"onboard":     d.Onboard,
			"alarm":       d.Alarm,
		}
		if d.PowerW != nil {
			entry["powerW"] = *d.PowerW
		}
		if d.WattHourCounter != nil {
			entry["wattHourCounter"] = *d.WattHourCounter
		}
		if len(d.ActiveEnergy) > 0 {
			entry["activeEnergy"] = append([]int(nil), d.ActiveEnergy...)
		}
		if len(d.ApparentEnergy) > 0 {
			entry["apparentEnergy"] = append([]int(nil), d.ApparentEnergy...)
		}
		if !d.Onboard {
			entry["daliSituation"] = d.DaliSituation
		}
		devices = append(devices, entry)
	}
	return devices
}

func gearStatusInfo(value int) string {
	if value == 0 {
		return "No"
	}
	flags := []struct {
		mask int
		name string
	}{
		{0x01, "CONTROL_GEAR_FALIURE"},
		{0x02, "LAMP_FALIURE"},
		{0x04, "LAMP_ON"},
		{0x08, "LIMIT_ERROR"},
		{0x10, "FADE_RUNNING"},
		{0x20, "RESET_STATE"},
		{0x40, "SHORT_ADDRESS_MASK"},
		{0x80, "POWER_CYCLE_SEEN"},
	}
	parts := make([]string, 0)
	for _, f := range flags {
		if value&f.mask != 0 {
			parts = append(parts, f.name)
		}
	}
	if len(parts) == 0 {
		return "No"
	}
	return strings.Join(parts, ",")
}

var rcuDimmLevelCurve = [...]int{
	0, 27, 31, 34, 38, 40, 43, 45, 49, 52, 54, 57, 58, 61, 64, 66, 67, 69, 73, 75, 78, 80, 81, 83, 86, 89, 90, 93, 96, 98, 101, 103, 105, 107, 109, 112, 116, 117, 120, 121, 124, 128, 131, 133, 138, 140, 141, 142, 143, 144, 146, 147, 148, 148, 149, 150, 150, 151, 152, 153, 154, 154, 154, 157, 161, 163, 166, 170, 172, 175, 178, 183, 185, 187, 190, 192, 194, 197, 200, 203, 205, 208, 211, 213, 215, 217, 219, 222, 226, 228, 231, 234, 237, 240, 242, 243, 245, 247, 250, 252, 254, 255,
}

var daliDimmLevelCurve = [...]int{
	0, 85, 110, 125, 136, 144, 150, 156, 161, 165, 169, 173, 176, 179, 181, 184, 186, 189, 191, 193, 195, 196, 198, 200, 201, 203, 204, 206, 207, 208, 209, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 223, 224, 225, 226, 227, 227, 228, 229, 230, 230, 231, 232, 232, 233, 234, 234, 235, 235, 236, 237, 237, 238, 238, 239, 239, 240, 240, 241, 241, 242, 242, 243, 243, 244, 244, 245, 245, 246, 246, 247, 247, 248, 248, 248, 249, 249, 250, 250, 250, 251, 251, 252, 252, 252, 253, 253, 254, 255,
}

func percentToRcuLevel(percent int) int  { return pctToLevelWithCurve(percent, rcuDimmLevelCurve[:]) }
func percentToDaliLevel(percent int) int { return pctToLevelWithCurve(percent, daliDimmLevelCurve[:]) }
func rcuLevelToPercent(level int) int    { return levelToPctWithCurve(level, rcuDimmLevelCurve[:]) }
func daliLevelToPercent(level int) int   { return levelToPctWithCurve(level, daliDimmLevelCurve[:]) }

func pctToLevelWithCurve(percent int, curve []int) int {
	if percent <= 0 {
		return 0
	}
	if percent >= 100 {
		return curve[100]
	}
	return curve[percent]
}

func levelToPctWithCurve(level int, curve []int) int {
	if level <= 0 {
		return 0
	}
	if level >= 255 {
		return 100
	}
	for pct := 100; pct >= 1; pct-- {
		if level >= curve[pct] {
			return pct
		}
	}
	return 0
}

func normalizeFanModeWriteValue(raw int) int {
	if raw == 0 {
		return 4
	}
	return raw
}

func encodeTemperature(v float64) int { return int(math.Round(v * 10.0)) }
func decodeTemperature(v int) float64 { return float64(v) / 10.0 }

func intPtr(v int) *int           { return &v }
func floatPtr(v float64) *float64 { return &v }

func round1(v float64) float64 {
	return math.Round(v*10) / 10
}

func coerceInt(v interface{}) (int, bool) {
	switch t := v.(type) {
	case int:
		return t, true
	case int32:
		return int(t), true
	case int64:
		return int(t), true
	case float32:
		return int(t), true
	case float64:
		return int(t), true
	case string:
		if strings.TrimSpace(t) == "" {
			return 0, false
		}
		var out int
		_, err := fmt.Sscanf(strings.TrimSpace(t), "%d", &out)
		return out, err == nil
	default:
		return 0, false
	}
}

func coerceFloat(v interface{}) (float64, bool) {
	switch t := v.(type) {
	case float64:
		return t, true
	case float32:
		return float64(t), true
	case int:
		return float64(t), true
	case int64:
		return float64(t), true
	case string:
		if strings.TrimSpace(t) == "" {
			return 0, false
		}
		var out float64
		_, err := fmt.Sscanf(strings.TrimSpace(t), "%f", &out)
		return out, err == nil
	default:
		return 0, false
	}
}

func isTimeoutError(err error) bool {
	if err == nil {
		return false
	}
	if ne, ok := err.(net.Error); ok && ne.Timeout() {
		return true
	}
	return strings.Contains(strings.ToLower(err.Error()), "i/o timeout")
}
