package main

import (
	"fmt"
	"hash/fnv"
	"strings"
	"sync"
	"time"
)

type simulatorRcuClient struct {
	room       string
	mu         sync.RWMutex
	hvac       SimHvacState
	outputs    []map[string]interface{}
	dnd        string
	mur        string
	laundry    string
	occupied   bool
	hasDoor    bool
	doorOpen   bool
	status     string
	sceneValue int
}

func newSimulatorRcuClient(room string) *simulatorRcuClient {
	base := DemoRoom()
	devs := make([]map[string]interface{}, 0, len(base.LightingDevices))
	for _, dev := range base.LightingDevices {
		devs = append(devs, cloneMap(dev))
	}
	return &simulatorRcuClient{
		room:     room,
		hvac:     base.HVAC,
		outputs:  devs,
		dnd:      "Off",
		mur:      "Off",
		laundry:  "Off",
		occupied: true,
		status:   "Rented Occupied",
	}
}

func (s *simulatorRcuClient) Room() string { return s.room }
func (s *simulatorRcuClient) Shutdown()    {}

func (s *simulatorRcuClient) InitializeAndUpdate() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.applyScenarioLocked()
	return true
}

func (s *simulatorRcuClient) Snapshot(serviceEvents []map[string]interface{}) map[string]interface{} {
	s.mu.RLock()
	defer s.mu.RUnlock()

	hvacDetail := buildSimHvacDetail(s.hvac)
	hasDaliLineShortCircuit := s.currentPhaseLocked() == 4
	hvacComError := 0
	if s.currentPhaseLocked() == 3 || s.currentPhaseLocked() == 4 {
		hvacComError = 1
	}
	hvacDetail["comError"] = hvacComError

	lighting := "Off"
	hasLightingAlarm := false
	devices := make([]map[string]interface{}, 0, len(s.outputs))
	for _, dev := range s.outputs {
		cloned := cloneMap(dev)
		if alarm, _ := cloned["alarm"].(bool); alarm {
			hasLightingAlarm = true
		}
		if intFrom(cloned["actualLevel"]) > 0 {
			lighting = "On"
		}
		devices = append(devices, cloned)
	}

	hasAlarm := hasLightingAlarm || hvacComError == 1 || hasDaliLineShortCircuit || s.hasDoor
	simServiceEvents := append(serviceEvents, s.syntheticServiceEventsLocked(hasAlarm)...)

	return map[string]interface{}{
		"number":                  s.room,
		"hvac":                    mapSimHvacState(s.hvac),
		"hvacDetail":              hvacDetail,
		"lighting":                lighting,
		"lightingOn":              lighting == "On",
		"dnd":                     s.dnd,
		"mur":                     s.mur,
		"laundry":                 s.laundry,
		"occupancy":               map[string]interface{}{"occupied": s.occupied, "rented": true, "doorOpen": s.doorOpen, "hasDoorAlarm": s.hasDoor},
		"status":                  s.status,
		"hasAlarm":                hasAlarm,
		"hasDoorAlarm":            s.hasDoor,
		"hasDaliLineShortCircuit": hasDaliLineShortCircuit,
		"lightingDevices":         devices,
		"serviceEvents":           simServiceEvents,
	}
}

func (s *simulatorRcuClient) LightingSummary() map[string]interface{} {
	s.mu.RLock()
	defer s.mu.RUnlock()
	onboard := []map[string]interface{}{}
	dali := []map[string]interface{}{}
	for _, dev := range s.outputs {
		entry := map[string]interface{}{
			"address":     dev["address"],
			"name":        dev["name"],
			"actualLevel": dev["actualLevel"],
			"targetLevel": dev["targetLevel"],
			"status":      dev["status"],
			"alarm":       dev["alarm"],
		}
		if b, _ := dev["onboard"].(bool); b {
			entry["type"] = "onboard"
			onboard = append(onboard, entry)
		} else {
			entry["type"] = "dali"
			dali = append(dali, entry)
		}
	}
	return map[string]interface{}{"onboardOutputs": onboard, "daliOutputs": dali}
}

func (s *simulatorRcuClient) LightingLegacy() map[string]interface{} {
	s.mu.RLock()
	defer s.mu.RUnlock()
	devs := make([]map[string]interface{}, 0, len(s.outputs))
	for _, dev := range s.outputs {
		devs = append(devs, cloneMap(dev))
	}
	return map[string]interface{}{"lightingDevices": devs}
}

func (s *simulatorRcuClient) OutputTargets() map[string]interface{} {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]map[string]interface{}, 0, len(s.outputs))
	for _, dev := range s.outputs {
		out = append(out, map[string]interface{}{
			"address":     dev["address"],
			"name":        dev["name"],
			"targetLevel": dev["targetLevel"],
		})
	}
	return map[string]interface{}{"outputs": out}
}

func (s *simulatorRcuClient) HvacSnapshot() map[string]interface{} {
	s.mu.RLock()
	defer s.mu.RUnlock()
	payload := buildSimHvacDetail(s.hvac)
	if s.currentPhaseLocked() >= 3 {
		payload["comError"] = 1
	} else {
		payload["comError"] = 0
	}
	return payload
}

func (s *simulatorRcuClient) UpdateHvac(updates map[string]interface{}) map[string]interface{} {
	s.mu.Lock()
	defer s.mu.Unlock()
	for key, value := range updates {
		switch key {
		case "onOff":
			if i, ok := intFromAny(value); ok {
				s.hvac.OnOff = i
			}
		case "mode":
			if i, ok := intFromAny(value); ok {
				s.hvac.Mode = i
			}
		case "fanMode":
			if i, ok := intFromAny(value); ok {
				s.hvac.FanMode = i
			}
		case "setPoint":
			if f, ok := coerceFloat(value); ok {
				s.hvac.SetPoint = f
			}
		case "roomTemperature":
			if f, ok := coerceFloat(value); ok {
				s.hvac.RoomTemperature = f
			}
		}
	}
	payload := buildSimHvacDetail(s.hvac)
	if s.currentPhaseLocked() >= 3 {
		payload["comError"] = 1
	} else {
		payload["comError"] = 0
	}
	return payload
}

func (s *simulatorRcuClient) UpdateLightingLevel(address, level int, requestID string) map[string]interface{} {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, dev := range s.outputs {
		if intFrom(dev["address"]) != address {
			continue
		}
		dev["targetLevel"] = level
		dev["actualLevel"] = level
		if level > 0 {
			dev["status"] = "LAMP_ON"
		} else {
			dev["status"] = "No"
		}
		return map[string]interface{}{
			"address":     address,
			"name":        dev["name"],
			"actualLevel": dev["actualLevel"],
			"targetLevel": dev["targetLevel"],
			"status":      dev["status"],
			"type":        map[bool]string{true: "onboard", false: "dali"}[dev["onboard"].(bool)],
			"source":      "simulation",
			"requestId":   requestID,
		}
	}
	return nil
}

func (s *simulatorRcuClient) CallLightingScene(scene int, requestID string) map[string]interface{} {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.sceneValue = scene
	target := 0
	if scene > 0 {
		target = 65
	}
	for _, dev := range s.outputs {
		dev["targetLevel"] = target
		dev["actualLevel"] = target
		if target > 0 {
			dev["status"] = "LAMP_ON"
		} else {
			dev["status"] = "No"
		}
	}
	return map[string]interface{}{
		"scene":       scene,
		"group":       sceneGroupByte,
		"triggered":   true,
		"source":      "simulation",
		"status":      "accepted",
		"attemptsMade": 1,
		"requestId":   requestID,
	}
}

func (s *simulatorRcuClient) ExecuteRawCommand(frame []byte, requestID string) map[string]interface{} {
	return map[string]interface{}{
		"triggered": true,
		"source":    "simulation",
		"status":    "accepted",
		"frameHex":  fmt.Sprintf("% X", frame),
		"requestId": requestID,
	}
}

func (s *simulatorRcuClient) applyScenarioLocked() {
	phase := s.currentPhaseLocked()
	s.hasDoor = phase == 5
	s.doorOpen = phase == 5
	s.occupied = phase != 1
	s.dnd = "Off"
	s.mur = "Off"
	s.laundry = "Off"
	if phase == 1 {
		s.status = "Rented Vacant"
	} else {
		s.status = "Rented Occupied"
	}
	if phase == 2 {
		s.mur = "Requested"
	}
	if phase == 3 {
		s.laundry = "Requested"
	}
	if phase == 4 {
		s.dnd = "Yellow"
	}

	for i, dev := range s.outputs {
		dev["alarm"] = false
		if phase == 4 && i == len(s.outputs)-1 {
			dev["alarm"] = true
			dev["status"] = "LAMP_FALIURE"
		}
		if intFrom(dev["actualLevel"]) > 0 && strings.TrimSpace(stringFromAny(dev["status"])) == "" {
			dev["status"] = "LAMP_ON"
		}
	}
}

func (s *simulatorRcuClient) syntheticServiceEventsLocked(hasAlarm bool) []map[string]interface{} {
	now := time.Now().Unix()
	base := []map[string]interface{}{}
	if s.dnd == "Yellow" {
		base = append(base, map[string]interface{}{"roomNumber": s.room, "serviceType": "dnd", "eventType": "activated", "timestamp": now})
	}
	if s.mur == "Requested" || s.mur == "Delayed" {
		base = append(base, map[string]interface{}{"roomNumber": s.room, "serviceType": "mur", "eventType": "requested", "timestamp": now})
	}
	if s.laundry == "Requested" || s.laundry == "Delayed" {
		base = append(base, map[string]interface{}{"roomNumber": s.room, "serviceType": "laundry", "eventType": "requested", "timestamp": now})
	}
	if hasAlarm {
		base = append(base, map[string]interface{}{"roomNumber": s.room, "serviceType": "alarm", "eventType": "active", "timestamp": now})
	}
	return base
}

func (s *simulatorRcuClient) currentPhaseLocked() int {
	seed := hashString(s.room) % 6
	slot := int(time.Now().Unix()/30) % 6
	return (slot + seed) % 6
}

func hashString(v string) int {
	h := fnv.New32a()
	_, _ = h.Write([]byte(v))
	return int(h.Sum32())
}
