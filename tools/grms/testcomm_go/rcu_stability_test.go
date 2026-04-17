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

func TestRefreshSkippedDuringSceneWindow(t *testing.T) {
	r := newRealRcuClient("Demo 101", RcuConfig{Host: "127.0.0.1", Port: 5556})
	t.Cleanup(r.stopCommandWorker)

	r.lastSceneAt.Store(time.Now().UnixNano())
	outcome, err := r.enqueueRefreshOps(opPriorityNormal)
	if err != nil {
		t.Fatalf("enqueueRefreshOps() error: %v", err)
	}
	if outcome != "skipped_scene_window" {
		t.Fatalf("outcome=%q want skipped_scene_window", outcome)
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

