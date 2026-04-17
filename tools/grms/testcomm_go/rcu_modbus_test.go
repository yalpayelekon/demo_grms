package main

import "testing"

func TestBuildModbusReadRegisterMessage(t *testing.T) {
	got := buildModbusReadRegisterMessage(0x000E, 0x0001, 0x01)
	want := []byte{
		0x3E, 0x08, 0x00,
		0x03, 0x07, 0x00,
		0x01, 0x00, 0x0E, 0x00, 0x01,
	}
	assertBytesEqual(t, got, want)
}

func TestBuildModbusWriteRegisterMessage(t *testing.T) {
	tests := []struct {
		name     string
		register int
		value    int
		want     []byte
	}{
		{
			name:     "set_point_reg_15",
			register: 0x000F,
			value:    0x00E6,
			want: []byte{
				0x3E, 0x0A, 0x00,
				0x03, 0x07, 0x01,
				0x01, 0x00, 0x0F, 0x00, 0x01, 0x00, 0xE6,
			},
		},
		{
			name:     "mode_reg_40",
			register: 0x0028,
			value:    0x0002,
			want: []byte{
				0x3E, 0x0A, 0x00,
				0x03, 0x07, 0x01,
				0x01, 0x00, 0x28, 0x00, 0x01, 0x00, 0x02,
			},
		},
		{
			name:     "fan_reg_41",
			register: 0x0029,
			value:    0x0001,
			want: []byte{
				0x3E, 0x0A, 0x00,
				0x03, 0x07, 0x01,
				0x01, 0x00, 0x29, 0x00, 0x01, 0x00, 0x01,
			},
		},
		{
			name:     "onoff_reg_52",
			register: 0x0034,
			value:    0x0001,
			want: []byte{
				0x3E, 0x0A, 0x00,
				0x03, 0x07, 0x01,
				0x01, 0x00, 0x34, 0x00, 0x01, 0x00, 0x01,
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := buildModbusWriteRegisterMessage(tt.register, tt.value)
			assertBytesEqual(t, got, tt.want)
		})
	}
}

func TestParseModbusReadReturnEvent(t *testing.T) {
	payload := []byte{
		0x01, 0x00,
		0x00, 0x0E,
		0x00, 0x01,
		0x00, 0xD7,
	}
	ev, ok := parseModbusReadReturnEvent(payload)
	if !ok || ev == nil {
		t.Fatalf("expected parse success")
	}
	if ev.ShortAddr != 1 || ev.Ack != 0 || ev.StartReg != 14 || ev.Count != 1 {
		t.Fatalf("unexpected parsed fields: %#v", ev)
	}
	if len(ev.Values) != 1 || ev.Values[0] != 0x00D7 {
		t.Fatalf("unexpected values: %#v", ev.Values)
	}
}

func TestParseModbusWriteReturnEvent(t *testing.T) {
	payload := []byte{
		0x01, 0x00,
		0x00, 0x34,
		0x00, 0x01,
	}
	ev, ok := parseModbusWriteReturnEvent(payload)
	if !ok || ev == nil {
		t.Fatalf("expected parse success")
	}
	if ev.ShortAddr != 1 || ev.Ack != 0 || ev.StartReg != 0x34 || ev.Count != 1 {
		t.Fatalf("unexpected parsed fields: %#v", ev)
	}
}

func TestSpecialRegisterEventUpdatesHvac(t *testing.T) {
	r := newRealRcuClient("Demo 101", RcuConfig{})
	frame := &rcuFrame{
		CmdType:  4,
		CmdNo:    7,
		SubCmdNo: 2,
		Payload:  []byte{0x01, 0x00, 0x33, 0x00, 0x02}, // reg 51 -> Heating
	}
	r.processEvent(frame)

	r.mu.RLock()
	defer r.mu.RUnlock()
	if r.hvac.RunningStatus == nil || *r.hvac.RunningStatus != 2 {
		t.Fatalf("running status not updated: %#v", r.hvac.RunningStatus)
	}
}

func TestMapHvacStateModeMappingAndPowerPriority(t *testing.T) {
	tests := []struct {
		name   string
		status int
		want   string
		onOff  int
		mode   int
	}{
		{name: "heat_mode_0", status: 1, want: "Hot", onOff: 1, mode: 0},
		{name: "cool_mode_1", status: 1, want: "Cold", onOff: 1, mode: 1},
		{name: "fan_only_mode_2", status: 1, want: "Active", onOff: 1, mode: 2},
		{name: "auto_mode_3", status: 1, want: "Active", onOff: 1, mode: 3},
		{name: "off", status: 1, want: "Off", onOff: 0, mode: 1},
		{name: "idle_but_power_on", status: 0, want: "Active", onOff: 1, mode: 3},
		{name: "ventilating", status: 3, want: "Active", onOff: 1, mode: 3},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			r := newRealRcuClient("Demo 101", RcuConfig{})
			r.hvac.OnOff = intPtr(tt.onOff)
			r.hvac.RunningStatus = intPtr(tt.status)
			r.hvac.Mode = intPtr(tt.mode)
			got := r.mapHvacStateLocked()
			if got != tt.want {
				t.Fatalf("mapHvacStateLocked()=%q want=%q", got, tt.want)
			}
			detail := r.buildHvacPayloadLocked(got)
			if gotOnOff, _ := detail["onOff"].(int); gotOnOff != tt.onOff {
				t.Fatalf("payload onOff=%v want=%d", detail["onOff"], tt.onOff)
			}
		})
	}
}

func TestParseModbusWriteReturnEventNack(t *testing.T) {
	payload := []byte{
		0x01, 0x02,
		0x00, 0x34,
		0x00, 0x01,
	}
	ev, ok := parseModbusWriteReturnEvent(payload)
	if !ok || ev == nil {
		t.Fatalf("expected parse success")
	}
	if ev.Ack == modbusAckOK {
		t.Fatalf("expected nack ack code, got ok")
	}
}

func TestNormalizeFanModeWriteValue(t *testing.T) {
	tests := []struct {
		name string
		raw  int
		want int
	}{
		{name: "auto_zero_to_four", raw: 0, want: 4},
		{name: "low_unchanged", raw: 1, want: 1},
		{name: "med_unchanged", raw: 2, want: 2},
		{name: "high_unchanged", raw: 3, want: 3},
		{name: "auto_four_unchanged", raw: 4, want: 4},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := normalizeFanModeWriteValue(tt.raw)
			if got != tt.want {
				t.Fatalf("normalizeFanModeWriteValue(%d)=%d want=%d", tt.raw, got, tt.want)
			}
		})
	}
}

func assertBytesEqual(t *testing.T, got, want []byte) {
	t.Helper()
	if len(got) != len(want) {
		t.Fatalf("len=%d want=%d got=% X want=% X", len(got), len(want), got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("byte[%d]=0x%X want=0x%X got=% X want=% X", i, got[i], want[i], got, want)
		}
	}
}
