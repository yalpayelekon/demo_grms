package main

import (
	"bytes"
	"encoding/binary"
	"io"
	"net"
	"strings"
	"testing"
	"time"
)

type timeoutErr struct{}

func (e timeoutErr) Error() string   { return "i/o timeout" }
func (e timeoutErr) Timeout() bool   { return true }
func (e timeoutErr) Temporary() bool { return true }

type fakeConn struct {
	readBuf  *bytes.Buffer
	writeBuf bytes.Buffer
	readErr  error
}

func (c *fakeConn) Read(b []byte) (int, error) {
	if c.readErr != nil {
		return 0, c.readErr
	}
	if c.readBuf == nil {
		return 0, io.EOF
	}
	return c.readBuf.Read(b)
}
func (c *fakeConn) Write(b []byte) (int, error) { return c.writeBuf.Write(b) }
func (c *fakeConn) Close() error                { return nil }
func (c *fakeConn) LocalAddr() net.Addr         { return &net.TCPAddr{} }
func (c *fakeConn) RemoteAddr() net.Addr        { return &net.TCPAddr{} }
func (c *fakeConn) SetDeadline(_ time.Time) error {
	return nil
}
func (c *fakeConn) SetReadDeadline(_ time.Time) error {
	return nil
}
func (c *fakeConn) SetWriteDeadline(_ time.Time) error {
	return nil
}

func buildFrameBytes(cmdType, cmdNo, sub int, payload ...byte) []byte {
	body := []byte{byte(cmdType), byte(cmdNo), byte(sub)}
	body = append(body, payload...)
	out := []byte{rcuHeader}
	lenBytes := make([]byte, 2)
	binary.LittleEndian.PutUint16(lenBytes, uint16(len(body)))
	out = append(out, lenBytes...)
	out = append(out, body...)
	return out
}

func TestSceneUsesRequestResponseNotFireAndForget(t *testing.T) {
	src := mustReadRcuRealSource(t)
	body := mustExtractFuncBlock(t, src, "func (r *realRcuClient) doCallLightingScene(")
	if !strings.Contains(body, "sceneRequireResponse()") {
		t.Fatalf("doCallLightingScene must switch behavior by TESTCOMM_SCENE_REQUIRE_RESPONSE")
	}
	if !strings.Contains(body, "sendRequestLockedWithTimeout(") {
		t.Fatalf("doCallLightingScene must support request-response send path")
	}
	if !strings.Contains(body, "sendCommandNoResponseLockedWithTimeout(") {
		t.Fatalf("doCallLightingScene must support write-only fast path")
	}
}

func TestSceneReturnsTimeoutWhenNoResponse(t *testing.T) {
	t.Setenv("TESTCOMM_SCENE_REQUIRE_RESPONSE", "1")
	r := newRealRcuClient("Demo 101", RcuConfig{Host: "127.0.0.1", Port: 5556})
	t.Cleanup(r.stopCommandWorker)
	r.conn = &fakeConn{readErr: timeoutErr{}}

	_, err := r.doCallLightingScene(1)
	if err == nil {
		t.Fatalf("expected scene call error")
	}
	var sceneErr *sceneCallError
	if !errorAs(err, &sceneErr) || sceneErr == nil {
		t.Fatalf("expected sceneCallError, got: %v", err)
	}
	if got := strings.ToLower(strings.TrimSpace(stringFromAny(sceneErr.payload["status"]))); got != "timeout" {
		t.Fatalf("status=%q want timeout", got)
	}
	if sceneErr.payload["error"] == "" {
		t.Fatalf("expected error message in payload")
	}
}

func TestRefreshCoreUsesShortTimeoutProfile(t *testing.T) {
	got := timeoutFor(opKindRefreshCore)
	if got != refreshCoreTimeout {
		t.Fatalf("timeoutFor(refresh_core)=%s want=%s", got, refreshCoreTimeout)
	}
	if got > timeoutCap {
		t.Fatalf("refresh core timeout must be <= timeoutCap")
	}
}

func TestSchedulerPrioritizesSceneOverRefresh(t *testing.T) {
	src := mustReadRcuRealSource(t)
	body := mustExtractFuncBlock(t, src, "func (r *realRcuClient) opWorkerLoop(")
	firstPriority := strings.Index(body, "case req := <-r.priorityOpCh")
	normalCase := strings.LastIndex(body, "case req := <-r.normalOpCh")
	if firstPriority < 0 || normalCase < 0 {
		t.Fatalf("priority/normal channel cases not found in opWorkerLoop")
	}
	if firstPriority > normalCase {
		t.Fatalf("priority channel must be checked before normal channel")
	}
}

func TestSceneResponseStatusConfirmedContainsConfirmedAt(t *testing.T) {
	t.Setenv("TESTCOMM_SCENE_REQUIRE_RESPONSE", "1")
	r := newRealRcuClient("Demo 101", RcuConfig{Host: "127.0.0.1", Port: 5556})
	t.Cleanup(r.stopCommandWorker)
	r.conn = &fakeConn{readBuf: bytes.NewBuffer(buildFrameBytes(3, 4, 3))}

	resp, err := r.doCallLightingScene(2)
	if err != nil {
		t.Fatalf("doCallLightingScene() error: %v", err)
	}
	if resp == nil {
		t.Fatalf("expected response")
	}
	if status := strings.ToLower(strings.TrimSpace(stringFromAny(resp["status"]))); status != "confirmed" {
		t.Fatalf("status=%q want confirmed", status)
	}
	if confirmedAt := stringFromAny(resp["confirmedAt"]); confirmedAt == "" {
		t.Fatalf("confirmedAt must be present for confirmed response")
	}
}

func TestSceneResponseStatusAcceptedInFastMode(t *testing.T) {
	t.Setenv("TESTCOMM_SCENE_REQUIRE_RESPONSE", "0")
	r := newRealRcuClient("Demo 101", RcuConfig{Host: "127.0.0.1", Port: 5556})
	t.Cleanup(r.stopCommandWorker)
	r.conn = &fakeConn{readBuf: bytes.NewBuffer(nil)}

	resp, err := r.doCallLightingScene(2)
	if err != nil {
		t.Fatalf("doCallLightingScene() error: %v", err)
	}
	if resp == nil {
		t.Fatalf("expected response")
	}
	if status := strings.ToLower(strings.TrimSpace(stringFromAny(resp["status"]))); status != "accepted" {
		t.Fatalf("status=%q want accepted", status)
	}
	if confirmedAt := stringFromAny(resp["confirmedAt"]); confirmedAt != "" {
		t.Fatalf("confirmedAt must be empty in fast mode")
	}
}

func TestSceneNoAppStateGateStillValid(t *testing.T) {
	TestCallLightingSceneHasNoAppStateGate(t)
}

func errorAs(err error, target **sceneCallError) bool {
	if err == nil || target == nil {
		return false
	}
	se, ok := err.(*sceneCallError)
	if !ok {
		return false
	}
	*target = se
	return true
}
