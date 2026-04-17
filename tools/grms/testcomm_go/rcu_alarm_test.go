package main

import "testing"

func TestParseDaliDeviceMastheadSetsAlarmOnPendent(t *testing.T) {
	client := newRealRcuClient("Demo 101", RcuConfig{Host: "127.0.0.1", Port: 5556})
	dev := &outputDeviceState{Address: 12, Onboard: false}

	client.parseDaliDeviceMasthead(dev, []byte{0x02, 0x05, 0x03})

	if dev.DaliSituation != daliSituationPendent {
		t.Fatalf("expected dali situation %d, got %d", daliSituationPendent, dev.DaliSituation)
	}
	if !dev.Alarm {
		t.Fatal("expected alarm=true for pendent situation")
	}
}

func TestParseDaliDeviceMastheadClearsAlarmForNonPendent(t *testing.T) {
	tests := []struct {
		name      string
		situation int
	}{
		{name: "idle", situation: daliSituationIdle},
		{name: "active", situation: daliSituationActive},
		{name: "passive", situation: daliSituationPassive},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			client := newRealRcuClient("Demo 101", RcuConfig{Host: "127.0.0.1", Port: 5556})
			dev := &outputDeviceState{
				Address:       13,
				Onboard:       false,
				DaliSituation: daliSituationPendent,
				Alarm:         true,
			}

			client.parseDaliDeviceMasthead(dev, []byte{0x02, 0x05, byte(tt.situation)})

			if dev.DaliSituation != tt.situation {
				t.Fatalf("expected dali situation %d, got %d", tt.situation, dev.DaliSituation)
			}
			if dev.Alarm {
				t.Fatalf("expected alarm=false for situation=%d", tt.situation)
			}
		})
	}
}

func TestMapHasAlarmLockedIncludesDaliMastheadAlarm(t *testing.T) {
	client := newRealRcuClient("Demo 101", RcuConfig{Host: "127.0.0.1", Port: 5556})
	client.outputs[21] = &outputDeviceState{
		Address:       21,
		Onboard:       false,
		DaliSituation: daliSituationPendent,
		Alarm:         true,
		Status:        "No",
	}

	client.mu.RLock()
	hasAlarm := client.mapHasAlarmLocked()
	client.mu.RUnlock()

	if !hasAlarm {
		t.Fatal("expected room alarm=true when a DALI device alarm is active")
	}
}

func TestLightingPayloadIncludesAlarmAndDaliSituation(t *testing.T) {
	client := newRealRcuClient("Demo 101", RcuConfig{Host: "127.0.0.1", Port: 5556})
	client.outputs[5] = &outputDeviceState{
		Address:       5,
		Name:          "Bedside",
		Onboard:       false,
		DaliSituation: daliSituationPendent,
		Alarm:         true,
		ActualLevel:   75,
		TargetLevel:   80,
		Status:        "No",
	}

	client.mu.RLock()
	summary := client.LightingSummary()
	legacy := client.buildLightingDevicesLocked()
	client.mu.RUnlock()

	daliOutputs, ok := summary["daliOutputs"].([]map[string]interface{})
	if !ok {
		t.Fatalf("expected typed daliOutputs slice, got %T", summary["daliOutputs"])
	}
	if len(daliOutputs) != 1 {
		t.Fatalf("expected 1 dali output, got %d", len(daliOutputs))
	}
	if got := daliOutputs[0]["alarm"]; got != true {
		t.Fatalf("expected summary alarm=true, got %#v", got)
	}
	if got := daliOutputs[0]["daliSituation"]; got != daliSituationPendent {
		t.Fatalf("expected summary daliSituation=%d, got %#v", daliSituationPendent, got)
	}

	if len(legacy) != 1 {
		t.Fatalf("expected 1 legacy device, got %d", len(legacy))
	}
	if got := legacy[0]["alarm"]; got != true {
		t.Fatalf("expected legacy alarm=true, got %#v", got)
	}
	if got := legacy[0]["daliSituation"]; got != daliSituationPendent {
		t.Fatalf("expected legacy daliSituation=%d, got %#v", daliSituationPendent, got)
	}
}

func TestSnapshotIncludesDoorAlarmState(t *testing.T) {
	client := newRealRcuClient("Demo 101", RcuConfig{Host: "127.0.0.1", Port: 5556})
	client.hasDoorAlarm = true

	client.mu.RLock()
	snapshot := client.Snapshot(nil)
	client.mu.RUnlock()

	if got := snapshot["hasDoorAlarm"]; got != true {
		t.Fatalf("expected snapshot hasDoorAlarm=true, got %#v", got)
	}
	if got := snapshot["hasAlarm"]; got != true {
		t.Fatalf("expected snapshot hasAlarm=true when door alarm is active, got %#v", got)
	}
}

func TestSnapshotIncludesCanonicalOccupancyState(t *testing.T) {
	client := newRealRcuClient("Demo 101", RcuConfig{Host: "127.0.0.1", Port: 5556})
	client.isRoomOccupied = false
	client.isDoorOpened = false
	client.hasDoorAlarm = false

	client.mu.RLock()
	snapshot := client.Snapshot(nil)
	client.mu.RUnlock()

	occupancy, ok := snapshot["occupancy"].(map[string]interface{})
	if !ok {
		t.Fatalf("expected occupancy map, got %T", snapshot["occupancy"])
	}
	if got := occupancy["occupied"]; got != false {
		t.Fatalf("expected occupancy.occupied=false, got %#v", got)
	}
	if got := occupancy["rented"]; got != true {
		t.Fatalf("expected occupancy.rented=true, got %#v", got)
	}
	if got := occupancy["doorOpen"]; got != false {
		t.Fatalf("expected occupancy.doorOpen=false, got %#v", got)
	}
	if got := occupancy["hasDoorAlarm"]; got != false {
		t.Fatalf("expected occupancy.hasDoorAlarm=false, got %#v", got)
	}
	if got := snapshot["status"]; got != "Rented Vacant" {
		t.Fatalf("expected status=Rented Vacant, got %#v", got)
	}
}

func TestSnapshotMapsActiveMurToHousekeepingWithoutChangingOccupancy(t *testing.T) {
	client := newRealRcuClient("Demo 101", RcuConfig{Host: "127.0.0.1", Port: 5556})
	client.isRoomOccupied = false
	client.murState = murActive

	client.mu.RLock()
	snapshot := client.Snapshot(nil)
	client.mu.RUnlock()

	if got := snapshot["status"]; got != "Rented HK" {
		t.Fatalf("expected status=Rented HK, got %#v", got)
	}
	occupancy, ok := snapshot["occupancy"].(map[string]interface{})
	if !ok {
		t.Fatalf("expected occupancy map, got %T", snapshot["occupancy"])
	}
	if got := occupancy["occupied"]; got != false {
		t.Fatalf("expected occupancy.occupied=false, got %#v", got)
	}
}

func TestProcessEventLogsUnhandledCmd4Payload(t *testing.T) {
	client := newRealRcuClient("Demo 101", RcuConfig{Host: "127.0.0.1", Port: 5556})

	client.processEvent(&rcuFrame{
		CmdType:  4,
		CmdNo:    4,
		SubCmdNo: 0,
		Payload:  []byte{0x01, 0x02, 0x03},
	})
}
