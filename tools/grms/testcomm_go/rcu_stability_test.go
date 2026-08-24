package main

import (
	"bytes"
	"errors"
	"strings"
	"testing"
	"time"
)

func buildReplyFrames(count int) []byte {
	out := make([]byte, 0, count*8)
	for i := 0; i < count; i++ {
		out = append(out, buildFrameBytes(3, 0, 0, 0x00)...)
	}
	return out
}

func TestRefreshSkippedDuringCommandWindow(t *testing.T) {
	r := newRealRcuClient("Demo 101", RcuConfig{Host: "127.0.0.1", Port: 5556})
	t.Cleanup(r.stopCommandWorker)

	r.deferRefresh(sceneRefreshBlock)
	outcome, err := r.enqueueRefreshOps(opPriorityNormal)
	if err != nil {
		t.Fatalf("enqueueRefreshOps() error: %v", err)
	}
	if outcome != "skipped_command_window" {
		t.Fatalf("outcome=%q want skipped_command_window", outcome)
	}
}

func TestRefreshCooldownProfiles(t *testing.T) {
	r := newRealRcuClient("Demo 101", RcuConfig{Host: "127.0.0.1", Port: 5556})
	t.Cleanup(r.stopCommandWorker)

	r.deferRefresh(sceneRefreshBlock)
	_, sceneRemaining := r.refreshWindowRemainingMs()
	if sceneRemaining < 400 || sceneRemaining > sceneRefreshBlock.Milliseconds() {
		t.Fatalf("scene remainingMs=%d want approximately %d", sceneRemaining, sceneRefreshBlock.Milliseconds())
	}

	r.deferRefresh(masterLightingRefreshBlock)
	_, masterRemaining := r.refreshWindowRemainingMs()
	if masterRemaining < 4900 || masterRemaining > masterLightingRefreshBlock.Milliseconds() {
		t.Fatalf("master remainingMs=%d want approximately %d", masterRemaining, masterLightingRefreshBlock.Milliseconds())
	}

	r.deferOutputRefresh(masterLightingOutputRefreshBlock)
	_, outputRemaining := r.outputRefreshWindowRemainingMs()
	if outputRemaining < 14900 || outputRemaining > masterLightingOutputRefreshBlock.Milliseconds() {
		t.Fatalf("master output remainingMs=%d want approximately %d", outputRemaining, masterLightingOutputRefreshBlock.Milliseconds())
	}
}

func TestRefreshPathsIssueNoQueriesDuringCommandWindow(t *testing.T) {
	r := newRealRcuClient("Demo 101", RcuConfig{Host: "127.0.0.1", Port: 5556})
	t.Cleanup(r.stopCommandWorker)
	conn := &fakeConn{readBuf: bytes.NewBuffer(buildReplyFrames(24))}
	r.initialized = true
	r.conn = conn
	r.deferRefresh(masterLightingRefreshBlock)

	if outcome, err := r.enqueueRefreshOps(opPriorityNormal); err != nil || outcome != "skipped_command_window" {
		t.Fatalf("enqueueRefreshOps() outcome=%q error=%v", outcome, err)
	}
	if err := r.refreshUnlockedLockedConn(); err != nil {
		t.Fatalf("refreshUnlockedLockedConn() error: %v", err)
	}
	if err := r.refreshDynamicStateLockedConn(); err != nil {
		t.Fatalf("refreshDynamicStateLockedConn() error: %v", err)
	}
	if got := conn.writeBuf.Len(); got != 0 {
		t.Fatalf("query bytes written during command window=%d want 0", got)
	}
}

func TestDecodeMasterLightingCommands(t *testing.T) {
	for _, tc := range []struct {
		name    string
		last    byte
		enabled bool
	}{
		{name: "on", last: 0x00, enabled: true},
		{name: "off", last: 0x01, enabled: false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			frame := []byte{0x3E, 0x0B, 0x00, 0x03, 0x04, 0x03, 0x01, 0x10, 0x04, 0x05, 0x00, 0x07, 0x00, tc.last}
			enabled, ok := decodeMasterLightingCommand(frame)
			if !ok || enabled != tc.enabled {
				t.Fatalf("decodeMasterLightingCommand() enabled=%t ok=%t", enabled, ok)
			}
		})
	}
}

func TestMasterLightingCommandEstablishesCooldownAndWritesOnce(t *testing.T) {
	r := newRealRcuClient("Demo 101", RcuConfig{Host: "127.0.0.1", Port: 5556})
	t.Cleanup(r.stopCommandWorker)
	conn := &fakeConn{readBuf: bytes.NewBuffer(nil)}
	r.conn = conn
	r.outputs[8] = &outputDeviceState{Address: 8, ActualLevel: 0, TargetLevel: 0, Status: "No"}
	frame := []byte{0x3E, 0x0B, 0x00, 0x03, 0x04, 0x03, 0x01, 0x10, 0x04, 0x05, 0x00, 0x07, 0x00, 0x00}

	result := r.ExecuteRawCommand(frame, "master-on-test")
	if triggered, _ := result["triggered"].(bool); !triggered {
		t.Fatalf("ExecuteRawCommand() result=%v", result)
	}
	if got := conn.writeBuf.Len(); got != len(frame) {
		t.Fatalf("command bytes written=%d want %d", got, len(frame))
	}
	if active, remaining := r.refreshWindowRemainingMs(); !active || remaining < 4900 {
		t.Fatalf("refresh block active=%t remainingMs=%d", active, remaining)
	}
	r.mu.RLock()
	dev := r.outputs[8]
	actual, target, status, source := dev.ActualLevel, dev.TargetLevel, dev.Status, dev.levelSource
	r.mu.RUnlock()
	if actual != 100 || target != 100 || status != "LAMP_ON" || source != "optimistic_master" {
		t.Fatalf("master-on cache actual=%d target=%d status=%q source=%q", actual, target, status, source)
	}

	r.refreshBlockedUntil.Store(time.Now().Add(-time.Millisecond).UnixNano())
	if active, remaining := r.refreshWindowRemainingMs(); active || remaining != 0 {
		t.Fatalf("expired refresh block active=%t remainingMs=%d", active, remaining)
	}
}

func TestMasterLightingCorrelationCoversOnlyFirstPostDeadlineRefresh(t *testing.T) {
	r := newRealRcuClient("Demo 101", RcuConfig{})
	t.Cleanup(r.stopCommandWorker)

	r.startMasterLightingCorrelation("master-correlation-test", true, masterLightingRefreshBlock)
	if r.beginMasterLightingReconciliation() {
		t.Fatal("correlation began before refresh deadline")
	}

	r.mu.Lock()
	r.masterCorrelation.RefreshDeadline = time.Now().Add(-time.Millisecond)
	r.mu.Unlock()
	if !r.beginMasterLightingReconciliation() {
		t.Fatal("correlation did not begin after refresh deadline")
	}
	trace, active := r.masterLightingTraceContext()
	if !active || trace.RequestID != "master-correlation-test" || !trace.Enabled {
		t.Fatalf("unexpected active trace: %+v active=%t", trace, active)
	}

	r.finishMasterLightingReconciliation()
	trace, active = r.masterLightingTraceContext()
	if active || !trace.FirstRefreshDone {
		t.Fatalf("trace not completed: %+v active=%t", trace, active)
	}
	if r.beginMasterLightingReconciliation() {
		t.Fatal("correlation began for a second refresh")
	}
}

func TestRefreshBudgetProcessesOnlyConfiguredBatch(t *testing.T) {
	r := newRealRcuClient("Demo 101", RcuConfig{Host: "127.0.0.1", Port: 5556})
	t.Cleanup(r.stopCommandWorker)
	r.initialized = true
	r.conn = &fakeConn{readBuf: bytes.NewBuffer(buildReplyFrames(24))}

	r.mu.Lock()
	for i := 1; i <= 6; i++ {
		r.outputs[i] = &outputDeviceState{Address: i, Onboard: true}
	}
	r.mu.Unlock()

	outcome, err := r.enqueueRefreshOps(opPriorityNormal)
	if err != nil {
		t.Fatalf("enqueueRefreshOps() error: %v", err)
	}
	if outcome != "partial" {
		t.Fatalf("outcome=%q want partial", outcome)
	}
	r.mu.RLock()
	cursor := r.refreshOutputCursor
	r.mu.RUnlock()
	if cursor != 4 {
		t.Fatalf("refreshOutputCursor=%d want 4", cursor)
	}
}

func TestRefreshCursorWrapsAcrossCycles(t *testing.T) {
	r := newRealRcuClient("Demo 101", RcuConfig{Host: "127.0.0.1", Port: 5556})
	t.Cleanup(r.stopCommandWorker)
	r.initialized = true
	r.conn = &fakeConn{readBuf: bytes.NewBuffer(buildReplyFrames(48))}

	r.mu.Lock()
	for i := 1; i <= 6; i++ {
		r.outputs[i] = &outputDeviceState{Address: i, Onboard: true}
	}
	r.mu.Unlock()

	if _, err := r.enqueueRefreshOps(opPriorityNormal); err != nil {
		t.Fatalf("first enqueueRefreshOps() error: %v", err)
	}
	r.mu.Lock()
	r.lastUpdate = time.Now().Add(-2 * time.Second)
	r.mu.Unlock()

	if _, err := r.enqueueRefreshOps(opPriorityNormal); err != nil {
		t.Fatalf("second enqueueRefreshOps() error: %v", err)
	}
	r.mu.RLock()
	cursor := r.refreshOutputCursor
	r.mu.RUnlock()
	if cursor != 2 {
		t.Fatalf("refreshOutputCursor=%d want 2", cursor)
	}
}

func TestSceneSupersedesOlderQueuedScenes(t *testing.T) {
	r := newRealRcuClient("Demo 101", RcuConfig{Host: "127.0.0.1", Port: 5556})
	t.Cleanup(r.stopCommandWorker)
	r.sceneCoalescingActive = true
	r.latestSceneSeq.Store(2)
	r.latestSceneNumber.Store(5)

	cmd := queuedCommand{
		kind:      queuedCommandScene,
		scene:     1,
		seq:       1,
		requestID: "scene-old",
		resultCh:  make(chan commandResult, 1),
	}
	r.executeQueuedCommand(cmd)
	res := <-cmd.resultCh
	if res.ok {
		t.Fatalf("expected superseded command to fail")
	}
	if status := strings.ToLower(strings.TrimSpace(stringFromAny(res.payload["status"]))); status != "superseded" {
		t.Fatalf("status=%q want superseded", status)
	}
}

func TestReconnectBackoffAppliesAfterNetworkFault(t *testing.T) {
	r := newRealRcuClient("Demo 101", RcuConfig{Host: "127.0.0.1", Port: 1})
	t.Cleanup(r.stopCommandWorker)

	r.connMu.Lock()
	defer r.connMu.Unlock()

	if err := r.ensureConnectedWithTimeoutLocked(50 * time.Millisecond); err == nil {
		t.Fatalf("expected first connect attempt to fail")
	}
	if !time.Now().Before(r.reconnectBlockedUntil) {
		t.Fatalf("expected reconnectBlockedUntil to be in the future")
	}
	err := r.ensureConnectedWithTimeoutLocked(50 * time.Millisecond)
	if err == nil || !strings.Contains(strings.ToLower(err.Error()), "reconnect cooldown active") {
		t.Fatalf("expected reconnect cooldown error, got: %v", err)
	}
}

func TestNetworkFaultClassification(t *testing.T) {
	cases := []struct {
		err  error
		want networkFault
	}{
		{err: errors.New("read tcp 1.1.1.1:1->2.2.2.2:2: i/o timeout"), want: faultTimeout},
		{err: errors.New("wsasend: forcibly closed"), want: faultConnReset},
		{err: errors.New("write: broken pipe"), want: faultBrokenPipe},
		{err: errors.New("rcu connection is nil"), want: faultNilConn},
		{err: errors.New("something else"), want: faultUnknown},
	}
	for _, tc := range cases {
		if got := classifyNetworkFault(tc.err); got != tc.want {
			t.Fatalf("classifyNetworkFault(%q)=%q want=%q", tc.err, got, tc.want)
		}
	}
}

func TestSceneResponseStatusSuperseded(t *testing.T) {
	r := newRealRcuClient("Demo 101", RcuConfig{Host: "127.0.0.1", Port: 5556})
	t.Cleanup(r.stopCommandWorker)
	r.sceneCoalescingActive = true
	r.latestSceneSeq.Store(10)
	r.latestSceneNumber.Store(5)

	cmd := queuedCommand{
		kind:      queuedCommandScene,
		scene:     2,
		seq:       3,
		requestID: "scene-old-2",
		resultCh:  make(chan commandResult, 1),
	}
	r.executeQueuedCommand(cmd)
	res := <-cmd.resultCh
	if res.ok {
		t.Fatalf("expected superseded result to be non-ok")
	}
	if got := stringFromAny(res.payload["error"]); !strings.Contains(strings.ToLower(got), "superseded") {
		t.Fatalf("error=%q must mention superseded", got)
	}
}

func TestSceneAcceptedModeRemainsDefault(t *testing.T) {
	t.Setenv("TESTCOMM_SCENE_REQUIRE_RESPONSE", "")
	r := newRealRcuClient("Demo 101", RcuConfig{Host: "127.0.0.1", Port: 5556})
	t.Cleanup(r.stopCommandWorker)
	r.conn = &fakeConn{readBuf: bytes.NewBuffer(nil)}

	resp, err := r.doCallLightingScene(2)
	if err != nil {
		t.Fatalf("doCallLightingScene() error: %v", err)
	}
	if status := strings.ToLower(strings.TrimSpace(stringFromAny(resp["status"]))); status != "accepted" {
		t.Fatalf("status=%q want accepted", status)
	}
}
