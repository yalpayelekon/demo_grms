package main

import "testing"

func TestProcessEventOccupancyDoorPosition(t *testing.T) {
	r := newRealRcuClient("Demo 101", RcuConfig{})

	r.processEvent(&rcuFrame{CmdType: 4, CmdNo: 5, SubCmdNo: 0})

	r.mu.RLock()
	if !r.isDoorOpened {
		r.mu.RUnlock()
		t.Fatal("expected doorOpen=true after door opened event")
	}
	r.mu.RUnlock()

	r.processEvent(&rcuFrame{CmdType: 4, CmdNo: 5, SubCmdNo: 1})

	r.mu.RLock()
	defer r.mu.RUnlock()
	if r.isDoorOpened {
		t.Fatal("expected doorOpen=false after door closed event")
	}
}

func TestProcessEventOccupancyRoomSituation(t *testing.T) {
	r := newRealRcuClient("Demo 101", RcuConfig{})
	r.isRoomOccupied = true

	r.processEvent(&rcuFrame{CmdType: 4, CmdNo: 5, SubCmdNo: 4})

	r.mu.RLock()
	if r.isRoomOccupied {
		r.mu.RUnlock()
		t.Fatal("expected occupied=false after room empty event")
	}
	r.mu.RUnlock()

	r.processEvent(&rcuFrame{CmdType: 4, CmdNo: 5, SubCmdNo: 5})

	r.mu.RLock()
	defer r.mu.RUnlock()
	if !r.isRoomOccupied {
		t.Fatal("expected occupied=true after room occupied event")
	}
}

func TestProcessEventServiceEventsDoNotMutateOccupancy(t *testing.T) {
	r := newRealRcuClient("Demo 101", RcuConfig{})
	r.isRoomOccupied = true
	r.isDoorOpened = false

	for _, subCmdNo := range []int{2, 4, 6, 7, 5, 3} {
		r.processEvent(&rcuFrame{CmdType: 4, CmdNo: 6, SubCmdNo: subCmdNo})
	}

	r.mu.RLock()
	defer r.mu.RUnlock()
	if !r.isRoomOccupied {
		t.Fatal("expected occupancy to remain unchanged after DND/MUR/laundry events")
	}
	if r.isDoorOpened {
		t.Fatal("expected doorOpen to remain unchanged after DND/MUR/laundry events")
	}
}

func TestProcessEventSequenceKeepsOccupancyCanonical(t *testing.T) {
	r := newRealRcuClient("Demo 101", RcuConfig{})
	r.isRoomOccupied = true
	r.isDoorOpened = false

	for _, subCmdNo := range []int{2, 4, 6} {
		r.processEvent(&rcuFrame{CmdType: 4, CmdNo: 6, SubCmdNo: subCmdNo})
	}
	r.processEvent(&rcuFrame{CmdType: 4, CmdNo: 5, SubCmdNo: 0})

	r.mu.RLock()
	if !r.isRoomOccupied {
		r.mu.RUnlock()
		t.Fatal("expected occupancy to remain true after service events and door open event")
	}
	if !r.isDoorOpened {
		r.mu.RUnlock()
		t.Fatal("expected doorOpen=true after door opened event")
	}
	r.mu.RUnlock()

	r.processEvent(&rcuFrame{CmdType: 4, CmdNo: 5, SubCmdNo: 4})

	r.mu.RLock()
	defer r.mu.RUnlock()
	if r.isRoomOccupied {
		t.Fatal("expected occupancy=false after room empty event")
	}
	if !r.isDoorOpened {
		t.Fatal("expected doorOpen to stay true until door closed event arrives")
	}
}

func TestMapRcuEventIncludesDoorPositionNames(t *testing.T) {
	tests := []struct {
		subCmdNo int
		wantName string
	}{
		{subCmdNo: 0, wantName: "Event_occapp_door_opened"},
		{subCmdNo: 1, wantName: "Event_occapp_door_closed"},
	}

	for _, tt := range tests {
		t.Run(tt.wantName, func(t *testing.T) {
			info := mapRcuEvent(5, tt.subCmdNo)
			if info.Name != tt.wantName {
				t.Fatalf("mapRcuEvent(5, %d)=%q want=%q", tt.subCmdNo, info.Name, tt.wantName)
			}
		})
	}
}

func TestMapMurStateFromSummaryByte(t *testing.T) {
	tests := []struct {
		name string
		raw  byte
		want int
	}{
		{name: "passive", raw: 0, want: murPassive},
		{name: "active", raw: 1, want: murActive},
		{name: "requested", raw: 2, want: murProgress},
		{name: "unknown_defaults_to_passive", raw: 99, want: murPassive},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := mapMurStateFromSummaryByte(tt.raw); got != tt.want {
				t.Fatalf("mapMurStateFromSummaryByte(%d)=%d want=%d", tt.raw, got, tt.want)
			}
		})
	}
}

func TestMurStateSourcesPreserveRequestedStartedFinishedSequence(t *testing.T) {
	r := newRealRcuClient("Demo 101", RcuConfig{})
	t.Cleanup(r.stopCommandWorker)

	r.setMurState(murProgress, "async_event", 0, "Event_dndapp_mur_requested", []byte{0xAA})
	if got := r.mapMurLocked(); got != "Requested" {
		t.Fatalf("requested map=%q", got)
	}
	r.setMurState(murActive, "async_event", 6, "Event_dndapp_mur_started", []byte{0xBB})
	if got := r.mapMurLocked(); got != "Yellow" {
		t.Fatalf("started map=%q", got)
	}
	if got := r.mapStatusLocked(); got != "Rented HK" {
		t.Fatalf("started status=%q", got)
	}
	r.setMurState(murPassive, "async_event", 7, "Event_dndapp_mur_finished", []byte{0xCC})
	if got := r.mapMurLocked(); got != "Off" {
		t.Fatalf("finished map=%q", got)
	}
	if got := r.mapStatusLocked(); got != "Rented Vacant" {
		t.Fatalf("finished status=%q", got)
	}
}

func TestStartedMurIgnoresStaleRequestedSummaryUntilFinished(t *testing.T) {
	r := newRealRcuClient("Demo 101", RcuConfig{})
	t.Cleanup(r.stopCommandWorker)
	r.setMurState(murActive, "async_event", 6, "Event_dndapp_mur_started", nil)

	r.mu.Lock()
	r.applyMurSummaryLocked(2)
	gotAfterRequested := r.murState
	r.applyMurSummaryLocked(0)
	gotAfterFinished := r.murState
	r.mu.Unlock()

	if gotAfterRequested != murActive {
		t.Fatalf("stale requested summary downgraded active MUR to %d", gotAfterRequested)
	}
	if gotAfterFinished != murPassive {
		t.Fatalf("passive summary did not finish MUR: %d", gotAfterFinished)
	}
}

func TestLaundryEventIgnoresStaleOffSummaryUntilCanceled(t *testing.T) {
	r := newRealRcuClient("Demo 101", RcuConfig{})
	t.Cleanup(r.stopCommandWorker)
	r.processEvent(&rcuFrame{CmdType: 4, CmdNo: 6, SubCmdNo: 2})

	r.mu.Lock()
	r.applyLaundrySummaryLocked(0)
	stillOn := r.isLaundryOn
	r.mu.Unlock()
	if !stillOn {
		t.Fatal("stale off summary cleared event-latched laundry request")
	}

	r.processEvent(&rcuFrame{CmdType: 4, CmdNo: 6, SubCmdNo: 3})
	r.mu.RLock()
	defer r.mu.RUnlock()
	if r.isLaundryOn || r.laundryEventLatched {
		t.Fatal("laundry cancel event did not clear latched request")
	}
}
