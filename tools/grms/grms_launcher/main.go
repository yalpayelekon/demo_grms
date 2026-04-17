package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"time"
)

const (
	defaultPort = 8082
)

func main() {
	log.SetFlags(log.Ldate | log.Ltime | log.Lmicroseconds)

	exePath, err := os.Executable()
	if err != nil {
		log.Fatalf("failed to resolve executable path: %v", err)
	}
	exePath, err = filepath.EvalSymlinks(exePath)
	if err != nil {
		log.Printf("warning: EvalSymlinks failed, continuing with original path: %v", err)
	}
	exeDir := filepath.Dir(exePath)

	bundleRoot := filepath.Clean(filepath.Join(exeDir, ".."))
	backendDir := filepath.Join(bundleRoot, "backend")
	frontendDir := filepath.Join(bundleRoot, "frontend", "web")
	configDir := filepath.Join(backendDir, "config")
	dbPath := filepath.Join(backendDir, "testcomm.db")
	backendPath := filepath.Join(backendDir, resolveBackendExecutable())

	if _, err := os.Stat(backendPath); err != nil {
		log.Fatalf("backend executable missing. expected=%s err=%v", backendPath, err)
	}
	if _, err := os.Stat(frontendDir); err != nil {
		log.Fatalf("frontend web assets missing. expected=%s err=%v", frontendDir, err)
	}
	if st, err := os.Stat(configDir); err != nil || !st.IsDir() {
		if err != nil {
			log.Fatalf("backend config directory missing. expected=%s err=%v", configDir, err)
		}
		log.Fatalf("backend config path is not a directory. expected=%s", configDir)
	}

	port := resolvePort()
	baseURL := fmt.Sprintf("http://127.0.0.1:%d", port)
	healthURL := baseURL + "/health"

	log.Printf("Starting TestComm backend from %s", backendPath)
	log.Printf("Serving web assets from %s", frontendDir)
	log.Printf("Using backend config dir %s", configDir)
	log.Printf("Using backend db path %s", dbPath)

	env := buildBackendEnv(frontendDir, configDir, dbPath, port)

	cmd := exec.Command(backendPath)
	cmd.Dir = backendDir
	cmd.Env = env
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Start(); err != nil {
		log.Fatalf("failed to start backend process: %v", err)
	}

	go func() {
		err := cmd.Wait()
		if err != nil {
			log.Printf("backend exited with error: %v", err)
		} else {
			log.Printf("backend exited normally")
		}
		os.Exit(0)
	}()

	log.Printf("Waiting for backend health at %s ...", healthURL)
	if err := waitForHealth(healthURL, 30*time.Second); err != nil {
		log.Printf("warning: backend health check failed: %v", err)
	} else {
		log.Printf("Backend reported healthy.")
	}

	log.Printf("Opening browser at %s ...", baseURL)
	if err := openBrowser(baseURL); err != nil {
		log.Printf("failed to open browser: %v", err)
		log.Printf("You can open the application manually at %s", baseURL)
	}

	// Keep launcher alive while backend runs.
	select {}
}

func resolvePort() int {
	if v := strings.TrimSpace(os.Getenv("TESTCOMM_PORT")); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			return n
		}
	}
	return defaultPort
}

func resolveBackendExecutable() string {
	if runtime.GOOS == "windows" {
		return "testcomm_go.exe"
	}
	return "testcomm_go"
}

func buildBackendEnv(webRoot, configDir, dbPath string, port int) []string {
	env := os.Environ()

	setOrReplace := func(key, value string) {
		prefix := key + "="
		for i, e := range env {
			if strings.HasPrefix(e, prefix) {
				env[i] = prefix + value
				return
			}
		}
		env = append(env, prefix+value)
	}

	setOrReplace("TESTCOMM_WEB_ROOT", webRoot)
	setOrReplace("TESTCOMM_CONFIG_DIR", configDir)
	setOrReplace("TESTCOMM_DB_PATH", dbPath)
	setOrReplace("TESTCOMM_PORT", strconv.Itoa(port))

	if v := os.Getenv("TESTCOMM_KILL_PREVIOUS"); strings.TrimSpace(v) == "" {
		setOrReplace("TESTCOMM_KILL_PREVIOUS", "1")
	}

	return env
}

func waitForHealth(url string, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	for {
		resp, err := http.Get(url) // #nosec G107
		if err == nil {
			_ = resp.Body.Close()
			if resp.StatusCode == http.StatusOK {
				return nil
			}
		}
		if time.Now().After(deadline) {
			if err != nil {
				return fmt.Errorf("health check failed after %s: %w", timeout, err)
			}
			return fmt.Errorf("health check did not return 200 within %s (last status %d)", timeout, resp.StatusCode)
		}
		time.Sleep(1 * time.Second)
	}
}

func openBrowser(url string) error {
	switch runtime.GOOS {
	case "windows":
		// Use system default browser.
		return exec.Command("rundll32", "url.dll,FileProtocolHandler", url).Start() // #nosec G204
	case "darwin":
		return exec.Command("open", url).Start() // #nosec G204
	default:
		return exec.Command("xdg-open", url).Start() // #nosec G204
	}
}
