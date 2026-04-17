package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestUpdateLightingLevelHasNoAppStateGate(t *testing.T) {
	src := mustReadRcuRealSource(t)
	body := mustExtractFuncBlock(t, src, "func (r *realRcuClient) UpdateLightingLevel(")
	if strings.Contains(body, "ensureRunStateLocked(") {
		t.Fatalf("UpdateLightingLevel must not gate by RUN state")
	}
	if strings.Contains(body, "ensureConfigurationStateLocked(") {
		t.Fatalf("UpdateLightingLevel must not gate by CONFIGURATION state")
	}
}

func TestCallLightingSceneHasNoAppStateGate(t *testing.T) {
	src := mustReadRcuRealSource(t)
	body := mustExtractFuncBlock(t, src, "func (r *realRcuClient) CallLightingScene(")
	if strings.Contains(body, "ensureRunStateLocked(") {
		t.Fatalf("CallLightingScene must not gate by RUN state")
	}
	if strings.Contains(body, "ensureConfigurationStateLocked(") {
		t.Fatalf("CallLightingScene must not gate by CONFIGURATION state")
	}
}

func mustReadRcuRealSource(t *testing.T) string {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(".", "rcu_real.go"))
	if err != nil {
		t.Fatalf("read rcu_real.go: %v", err)
	}
	return string(data)
}

func mustExtractFuncBlock(t *testing.T, src string, signature string) string {
	t.Helper()
	start := strings.Index(src, signature)
	if start < 0 {
		t.Fatalf("signature not found: %s", signature)
	}
	next := strings.Index(src[start+1:], "\nfunc ")
	if next < 0 {
		return src[start:]
	}
	return src[start : start+1+next]
}
