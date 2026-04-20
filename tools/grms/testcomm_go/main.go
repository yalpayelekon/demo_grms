package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"time"

	"testcommconfig"

	"github.com/gorilla/websocket"
	_ "github.com/mattn/go-sqlite3"
)

type ServerConfig struct {
	Port    int
	WebRoot string
	DBPath  string
}

type TestCommServer struct {
	cfg ServerConfig

	coordinatesStore CoordinatesService
	demoRcuStore     *DemoRcuConfigStore
	serviceStore     ServiceEventsStore

	// Room configuration and per-room clients (mirrors Java roomConfigs/roomClients flow).
	roomConfigs   map[string]RcuConfig
	roomClients   map[string]RcuClient
	roomClientsMu sync.Mutex
	menuStates    map[string]*RcuMenuState

	roomStreamsMu sync.RWMutex
	roomStreams   map[string][]*sseClient
	roomPollersMu sync.Mutex
	roomPollers   map[string]chan struct{}

	coordSocketsMu sync.RWMutex
	coordSockets   map[*websocket.Conn]struct{}

	snapshotCacheMu sync.RWMutex
	snapshotCache   map[string]cachedRoomSnapshot
}

type cachedRoomSnapshot struct {
	payload   map[string]interface{}
	updatedAt time.Time
}

func NewTestCommServer(cfg ServerConfig) *TestCommServer {
	demoRcuStore := NewDemoRcuConfigStore()
	s := &TestCommServer{
		cfg:              cfg,
		coordinatesStore: NewCoordinatesStore(),
		demoRcuStore:     demoRcuStore,
		serviceStore:     NewServiceEventStore(cfg.DBPath),
		roomStreams:      make(map[string][]*sseClient),
		roomPollers:      make(map[string]chan struct{}),
		coordSockets:     make(map[*websocket.Conn]struct{}),
		roomConfigs:      make(map[string]RcuConfig),
		roomClients:      make(map[string]RcuClient),
		menuStates:       make(map[string]*RcuMenuState),
		snapshotCache:    make(map[string]cachedRoomSnapshot),
	}

	s.roomConfigs["Demo 101"] = demoRcuStore.Load()

	return s
}

// RoomService defines the room-related operations used by HTTP handlers.
type RoomService interface {
	HasRoom(room string) bool
	Snapshot(room string, serviceEvents []map[string]interface{}) map[string]interface{}
	HvacSnapshot(room string) map[string]interface{}
	UpdateHvac(room string, updates map[string]interface{}) map[string]interface{}
	UpdateLightingLevel(room string, address, level int) map[string]interface{}
	BuildLightingSummary(room string) map[string]interface{}
	BuildLightingLegacy(room string) map[string]interface{}
	BuildOutputTargets(room string) map[string]interface{}
}

// CoordinatesService defines the coordinates-related operations used by HTTP handlers.
type CoordinatesService interface {
	BuildPayload() map[string]interface{}
	BuildUpdateMessage() map[string]interface{}
	LoadZonesJSON() string
	LoadLightingDevicesJSON() string
	SaveZonesJSON(jsonStr string) error
	SaveLightingDevicesJSON(jsonStr string) error
	SaveServiceIconsJSON(jsonStr string) error
}

// ServiceEventsStore defines service-event query/stream operations used by HTTP handlers.
type ServiceEventsStore interface {
	Query(roomNumber, serviceType string, limit int) []map[string]interface{}
	EventsForRoom(room string) []map[string]interface{}
	LastIndexBefore(t time.Time) int
	EventsSince(lastID int) []ServiceEventRecord
}

// RcuConfig mirrors Java's per-room RCU configuration (host/port).
type RcuConfig struct {
	Host string
	Port int
}

// RcuClient is an abstraction for per-room RCU-backed state, mirroring the Java
// TestComm flow (RCU + RoomData/RoomStateMapper). Initially backed by the
// existing in-memory RoomStore, but structured so it can later speak the real
// RCU protocol.
type RcuClient interface {
	Room() string
	InitializeAndUpdate() bool
	Snapshot(serviceEvents []map[string]interface{}) map[string]interface{}
	LightingSummary() map[string]interface{}
	LightingLegacy() map[string]interface{}
	OutputTargets() map[string]interface{}
	HvacSnapshot() map[string]interface{}
	UpdateHvac(updates map[string]interface{}) map[string]interface{}
	UpdateLightingLevel(address, level int, requestID string) map[string]interface{}
	CallLightingScene(scene int, requestID string) map[string]interface{}
	ExecuteRawCommand(frame []byte, requestID string) map[string]interface{}
	Shutdown()
}

// getOrCreateRcu returns a per-room RCU client using configured host/port.
func (s *TestCommServer) getOrCreateRcu(room string) RcuClient {
	s.roomClientsMu.Lock()
	defer s.roomClientsMu.Unlock()

	if client, ok := s.roomClients[room]; ok {
		return client
	}

	cfg, ok := s.roomConfigs[room]
	if !ok {
		return nil
	}

	client := newRealRcuClient(room, cfg)
	s.roomClients[room] = client
	log.Printf("rcu.client.created room=%s host=%s port=%d", room, cfg.Host, cfg.Port)
	return client
}

func (s *TestCommServer) updateRoomConfig(room string, cfg RcuConfig) {
	s.roomClientsMu.Lock()
	defer s.roomClientsMu.Unlock()

	s.roomConfigs[room] = cfg
	if client, ok := s.roomClients[room]; ok {
		client.Shutdown()
		delete(s.roomClients, room)
	}
	log.Printf("startup.room_config.updated room=%s host=%s port=%d", room, cfg.Host, cfg.Port)
}

// ========== Menu state & responses ==========

type MenuScreen string

const (
	MenuScreenMain    MenuScreen = "MAIN"
	MenuScreenControl MenuScreen = "CONTROL"
)

// RcuMenuState mirrors the Java RcuMenuState class in a simplified form.
type RcuMenuState struct {
	DebugMode          bool
	LastMenu           MenuScreen
	LastControlSubmenu string
}

func newRcuMenuState() *RcuMenuState {
	return &RcuMenuState{
		DebugMode:          false,
		LastMenu:           MenuScreenMain,
		LastControlSubmenu: "none",
	}
}

type MenuOption struct {
	ID    int    `json:"id"`
	Label string `json:"label"`
}

// RcuMenuResponse mirrors the JSON contract of Java's RcuMenuResponse.toJson().
type RcuMenuResponse struct {
	MenuText    string          `json:"menuText"`
	MenuOptions []MenuOption    `json:"menuOptions"`
	OutputText  string          `json:"outputText"`
	InputSchema json.RawMessage `json:"inputSchema"`
	DebugMode   bool            `json:"debugMode"`
}

func (s *TestCommServer) getMenuState(room string) *RcuMenuState {
	if st, ok := s.menuStates[room]; ok {
		return st
	}
	st := newRcuMenuState()
	s.menuStates[room] = st
	return st
}

// buildMainMenuResponse builds a simplified main menu equivalent to the Java main menu.
func buildMainMenuResponse(state *RcuMenuState, output string) RcuMenuResponse {
	options := []MenuOption{
		{ID: 1, Label: "View RCU Summary"},
		{ID: 2, Label: "List Input Devices"},
		{ID: 3, Label: "List Output Devices"},
		{ID: 4, Label: "Update Device Information"},
		{ID: 5, Label: "View Detailed Device Info"},
		{ID: 6, Label: "Toggle Debug Mode"},
		{ID: 7, Label: "Control Devices"},
		{ID: 0, Label: "Exit"},
	}
	// For now, provide an empty schema object (clients still get menu options).
	return RcuMenuResponse{
		MenuText:    "RCU Control Menu",
		MenuOptions: options,
		OutputText:  output,
		InputSchema: json.RawMessage(`{"menu":"main","choices":{}}`),
		DebugMode:   state.DebugMode,
	}
}

// buildControlMenuResponse builds a simplified control menu.
func buildControlMenuResponse(state *RcuMenuState, output string) RcuMenuResponse {
	options := []MenuOption{
		{ID: 1, Label: "Set Target Level"},
		{ID: 2, Label: "Set Max Level"},
		{ID: 3, Label: "Configure Device Fade Time"},
		{ID: 4, Label: "Configure Scene"},
		{ID: 5, Label: "Configure Device Groups"},
		{ID: 6, Label: "Configure Input Device"},
		{ID: 7, Label: "Change App State"},
		{ID: 0, Label: "Back to Main Menu"},
	}
	return RcuMenuResponse{
		MenuText:    "Device Control Menu",
		MenuOptions: options,
		OutputText:  output,
		InputSchema: json.RawMessage(`{"menu":"control","choices":{}}`),
		DebugMode:   state.DebugMode,
	}
}

// tryKillProcessOnPort attempts to find and kill the process listening on the
// given port. Implemented for Windows (netstat -ano + taskkill). Returns true
// if it ran taskkill (and it succeeded), false otherwise.
func tryKillProcessOnPort(port int) bool {
	if runtime.GOOS != "windows" {
		log.Printf("port %d in use; kill only supported on Windows (set TESTCOMM_KILL_PREVIOUS=0 to skip)", port)
		return false
	}
	portStr := strconv.Itoa(port)
	cmd := exec.Command("cmd", "/c", "netstat -ano | findstr :"+portStr)
	out, err := cmd.CombinedOutput()
	if err != nil || len(out) == 0 {
		log.Printf("port %d in use; netstat/findstr found no listener (run as admin?): %v", port, err)
		return false
	}
	// Parse lines: find one containing LISTENING and :<port>, last column is PID
	var pid string
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		line = strings.TrimSpace(strings.TrimRight(line, "\r"))
		if line == "" {
			continue
		}
		if !strings.Contains(line, "LISTENING") {
			continue
		}
		if !strings.Contains(line, ":"+portStr) {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) >= 1 {
			pid = fields[len(fields)-1]
			break
		}
	}
	if pid == "" {
		log.Printf("port %d in use; could not parse PID from netstat output", port)
		return false
	}
	killCmd := exec.Command("taskkill", "/F", "/PID", pid)
	if err := killCmd.Run(); err != nil {
		log.Printf("taskkill /F /PID %s failed: %v (try running as Administrator)", pid, err)
		return false
	}
	log.Printf("killed process %s that was using port %d", pid, port)
	return true
}

func (s *TestCommServer) Start() error {
	mux := http.NewServeMux()
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("OK"))
	})
	mux.HandleFunc("/testcomm/rooms/", s.handleRooms)
	mux.HandleFunc("/testcomm/logs", s.handleLogs)
	mux.HandleFunc("/testcomm/coordinates", s.handleCoordinates)
	mux.HandleFunc("/testcomm/coordinates/", s.handleCoordinates)
	mux.HandleFunc("/testcomm/settings/demo-rcu", s.handleDemoRcuSettings)
	mux.HandleFunc("/testcomm/service-events", s.handleServiceEvents)
	mux.HandleFunc("/testcomm/service-events/", s.handleServiceEvents)

	if s.cfg.WebRoot != "" {
		mux.Handle("/", s.staticFileHandler(s.cfg.WebRoot))
	}

	addr := ":" + strconv.Itoa(s.cfg.Port)
	server := &http.Server{
		Addr:         addr,
		Handler:      mux,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 0, // allow long-lived SSE / websockets
	}

	log.Printf("TestComm Go server listening on http://localhost:%d", s.cfg.Port)
	log.Printf("startup.config db_path=%s", s.cfg.DBPath)
	if coordinatesStore, ok := s.coordinatesStore.(*CoordinatesStore); ok {
		log.Printf("coordinates.config_dir=%s", coordinatesStore.configDir)
		log.Printf("coordinates.zones_file=%s", coordinatesStore.zonesFile)
		log.Printf("coordinates.lighting_devices_file=%s", coordinatesStore.lightingDevicesFile)
	}
	if s.demoRcuStore != nil {
		log.Printf("demo_rcu.config_file=%s", s.demoRcuStore.filePath)
	}
	for room, cfg := range s.roomConfigs {
		log.Printf("startup.room_config room=%s host=%s port=%d", room, cfg.Host, cfg.Port)
	}
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		if strings.Contains(err.Error(), "bind") {
			// Default: try to free the port (Windows). Set TESTCOMM_KILL_PREVIOUS=0 to disable.
			v := os.Getenv("TESTCOMM_KILL_PREVIOUS")
			if v != "0" && v != "false" && v != "False" {
				if tryKillProcessOnPort(s.cfg.Port) {
					time.Sleep(2 * time.Second)
					ln, err = net.Listen("tcp", addr)
				}
			}
		}
		if err != nil {
			return err
		}
	}
	return server.Serve(ln)
}

// ========== HTTP routing ==========

func (s *TestCommServer) handleRooms(w http.ResponseWriter, r *http.Request) {
	addCORSHeaders(w, r)
	if handleOptions(w, r) {
		return
	}

	const base = "/testcomm/rooms/"
	if !strings.HasPrefix(r.URL.Path, base) {
		sendText(w, http.StatusNotFound, "Not Found")
		return
	}

	rem := trimSlashes(strings.TrimPrefix(r.URL.Path, base))
	if rem == "" {
		sendText(w, http.StatusNotFound, "Room not specified")
		return
	}

	segments := strings.Split(rem, "/")
	roomSegment := segments[0]
	room, err := urlDecode(roomSegment)
	if err != nil {
		sendText(w, http.StatusBadRequest, "Invalid room")
		return
	}

	// Mirror Java: reject unknown rooms based on configured RCUs (roomConfigs).
	if _, ok := s.roomConfigs[room]; !ok {
		sendText(w, http.StatusNotFound, "Unknown room")
		return
	}

	rcu := s.getOrCreateRcu(room)

	extra := []string{}
	if len(segments) > 1 {
		extra = segments[1:]
	}

	if len(extra) > 0 && strings.EqualFold(extra[0], "stream") {
		if r.Method != http.MethodGet {
			sendText(w, http.StatusMethodNotAllowed, "Method Not Allowed")
			return
		}
		s.handleRoomStream(w, r, room)
		return
	}

	if len(extra) > 0 && strings.EqualFold(extra[0], "lighting") {
		s.handleLighting(w, r, room, extra[1:])
		return
	}

	if len(extra) > 0 && strings.EqualFold(extra[0], "hvac") {
		s.handleHvac(w, r, room)
		return
	}

	if len(extra) > 0 && strings.EqualFold(extra[0], "raw-command") {
		s.handleRawCommand(w, r, room)
		return
	}

	if len(extra) > 0 && strings.EqualFold(extra[0], "outputs") {
		if r.Method != http.MethodGet {
			sendText(w, http.StatusMethodNotAllowed, "Method Not Allowed")
			return
		}
		if !rcu.InitializeAndUpdate() {
			sendText(w, http.StatusBadGateway, "Failed to initialize RCU")
			return
		}
		payload := rcu.OutputTargets()
		writeJSON(w, payload)
		return
	}

	if len(extra) > 0 && strings.EqualFold(extra[0], "menu") {
		s.handleMenu(w, r, room)
		return
	}

	if r.Method != http.MethodGet {
		sendText(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}

	snapshot, ok := s.buildSnapshotWithFallback(room, rcu)
	if !ok {
		sendText(w, http.StatusBadGateway, "Failed to initialize RCU")
		return
	}
	writeJSON(w, snapshot)
}

func (s *TestCommServer) handleRoomStream(w http.ResponseWriter, r *http.Request, room string) {
	h := w.Header()
	h.Set("Content-Type", "text/event-stream")
	h.Set("Cache-Control", "no-cache")
	h.Set("Connection", "keep-alive")

	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "Streaming unsupported", http.StatusInternalServerError)
		return
	}

	client := newSseClient(w, flusher)

	s.roomStreamsMu.Lock()
	s.roomStreams[room] = append(s.roomStreams[room], client)
	s.roomStreamsMu.Unlock()
	s.ensureRoomPoller(room)

	// initial snapshot
	rcu := s.getOrCreateRcu(room)
	snapshot, okInit := s.buildSnapshotWithFallback(room, rcu)
	if !okInit {
		s.removeRoomClient(room, client)
		sendText(w, http.StatusBadGateway, "Failed to initialize RCU")
		return
	}
	if err := client.SendEvent("snapshot", snapshot); err != nil {
		s.removeRoomClient(room, client)
		return
	}

	notify := r.Context().Done()
	<-notify
	s.removeRoomClient(room, client)
}

func (s *TestCommServer) removeRoomClient(room string, c *sseClient) {
	s.roomStreamsMu.Lock()
	defer s.roomStreamsMu.Unlock()
	clients := s.roomStreams[room]
	n := 0
	for _, cl := range clients {
		if cl != c {
			clients[n] = cl
			n++
		}
	}
	if n == 0 {
		delete(s.roomStreams, room)
	} else {
		s.roomStreams[room] = clients[:n]
	}
	c.Close()
	if n == 0 {
		s.stopRoomPoller(room)
	}
}

func (s *TestCommServer) ensureRoomPoller(room string) {
	s.roomPollersMu.Lock()
	if _, exists := s.roomPollers[room]; exists {
		s.roomPollersMu.Unlock()
		return
	}
	stopCh := make(chan struct{})
	s.roomPollers[room] = stopCh
	s.roomPollersMu.Unlock()

	go s.runRoomPoller(room, stopCh)
}

func (s *TestCommServer) stopRoomPoller(room string) {
	s.roomPollersMu.Lock()
	stopCh, exists := s.roomPollers[room]
	if exists {
		delete(s.roomPollers, room)
	}
	s.roomPollersMu.Unlock()
	if exists {
		close(stopCh)
	}
}

func (s *TestCommServer) roomClientsSnapshot(room string) []*sseClient {
	s.roomStreamsMu.RLock()
	defer s.roomStreamsMu.RUnlock()
	clients := s.roomStreams[room]
	out := make([]*sseClient, len(clients))
	copy(out, clients)
	return out
}

func (s *TestCommServer) runRoomPoller(room string, stopCh <-chan struct{}) {
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			clients := s.roomClientsSnapshot(room)
			if len(clients) == 0 {
				s.stopRoomPoller(room)
				return
			}

			tickStartedAt := time.Now()
			rcu := s.getOrCreateRcu(room)
			nextSnapshot, ok := s.buildSnapshotWithFallback(room, rcu)
			logSlowDuration("room.stream.snapshot.duration", tickStartedAt, " room=%s", room)
			if !ok {
				for _, c := range clients {
					if err := c.SendComment("rcu-unavailable"); err != nil {
						s.removeRoomClient(room, c)
					}
				}
				continue
			}
			for _, c := range clients {
				if err := c.SendEvent("snapshot", nextSnapshot); err != nil {
					s.removeRoomClient(room, c)
				}
			}
		case <-stopCh:
			return
		}
	}
}

func (s *TestCommServer) handleLighting(w http.ResponseWriter, r *http.Request, room string, extra []string) {
	rcu := s.getOrCreateRcu(room)
	if rcu == nil {
		sendText(w, http.StatusNotFound, "Unknown room")
		return
	}
	if r.Method == http.MethodGet {
		action := ""
		if len(extra) > 0 {
			action = extra[0]
		}
		if !rcu.InitializeAndUpdate() {
			sendText(w, http.StatusBadGateway, "Failed to initialize RCU")
			return
		}
		if action == "" || strings.EqualFold(action, "devices") {
			payload := rcu.LightingSummary()
			writeJSON(w, payload)
		} else {
			payload := rcu.LightingLegacy()
			writeJSON(w, payload)
		}
		return
	}

	if r.Method == http.MethodPost {
		var body map[string]interface{}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			sendText(w, http.StatusBadRequest, "Invalid JSON")
			return
		}
		action := ""
		if len(extra) > 0 {
			action = strings.ToLower(strings.TrimSpace(extra[0]))
		}
		if action == "scene" {
			sceneRaw, ok := body["scene"]
			if !ok {
				sendText(w, http.StatusBadRequest, "Request must include numeric scene")
				return
			}
			scene, ok := intFromAny(sceneRaw)
			if !ok {
				sendText(w, http.StatusBadRequest, "Request must include numeric scene")
				return
			}
			if scene < sceneMin || scene > sceneMax {
				sendText(w, http.StatusBadRequest, "Scene must be between 1 and 5")
				return
			}

			requestId := strings.TrimSpace(stringFromAny(body["clientRequestId"]))
			clientTappedAtMs, _ := int64FromAny(body["clientTappedAtMs"])
			receivedAt := time.Now()
			serverNowMs := receivedAt.UnixMilli()
			clientToIngressMs := int64(-1)
			if clientTappedAtMs > 0 {
				clientToIngressMs = serverNowMs - clientTappedAtMs
			}
			log.Printf(
				"scene.req.received room=%s scene=%d requestId=%s clientTappedAtMs=%d serverNowMs=%d clientToIngressMs=%d",
				room, scene, requestId, clientTappedAtMs, serverNowMs, clientToIngressMs,
			)

			log.Printf("scene.req.before_initialize room=%s scene=%d requestId=%s skipped=true", room, scene, requestId)
			log.Printf(
				"scene.req.after_initialize room=%s scene=%d requestId=%s success=true durationMs=0 skipped=true",
				room, scene, requestId,
			)

			callStart := time.Now()
			log.Printf("scene.req.before_call room=%s scene=%d requestId=%s", room, scene, requestId)
			resp := rcu.CallLightingScene(scene, requestId)
			if resp == nil {
				log.Printf(
					"scene.req.after_call room=%s scene=%d requestId=%s success=false callDurationMs=%d totalDurationMs=%d",
					room,
					scene,
					requestId,
					time.Since(callStart).Milliseconds(),
					time.Since(receivedAt).Milliseconds(),
				)
				sendText(w, http.StatusBadGateway, "Failed to trigger scene")
				return
			}
			queueAttempts := intFrom(resp["queueAttempts"])
			attemptsMade := intFrom(resp["attemptsMade"])
			refreshDeferred, _ := resp["refreshDeferred"].(bool)
			lockWaitMs, _ := int64FromAny(resp["lockWaitMs"])
			status := strings.ToLower(strings.TrimSpace(stringFromAny(resp["status"])))
			if status == "" {
				status = "accepted"
			}
			success := status == "confirmed" || status == "accepted"
			errText := strings.TrimSpace(stringFromAny(resp["error"]))
			log.Printf(
				"scene.req.after_call room=%s scene=%d requestId=%s success=%t status=%s attemptsMade=%d callDurationMs=%d totalDurationMs=%d queueAttempts=%d refreshDeferred=%t lockWaitMs=%d error=%q",
				room,
				scene,
				requestId,
				success,
				status,
				attemptsMade,
				time.Since(callStart).Milliseconds(),
				time.Since(receivedAt).Milliseconds(),
				queueAttempts,
				refreshDeferred,
				lockWaitMs,
				errText,
			)
			if !success {
				w.Header().Set("Content-Type", "application/json")
				if status == "superseded" {
					w.WriteHeader(http.StatusConflict)
				} else {
					w.WriteHeader(http.StatusBadGateway)
				}
				writeJSON(w, resp)
				return
			}
			writeJSON(w, resp)
			s.broadcastRoomSnapshot(room)
			return
		}
		addrVal, okA := body["address"].(float64)
		levelVal, okL := body["level"].(float64)
		if !okA || !okL {
			sendText(w, http.StatusBadRequest, "Request must include numeric address and level")
			return
		}
		address := int(addrVal)
		level := int(levelVal)
		if level < 0 || level > 100 {
			sendText(w, http.StatusBadRequest, "Level must be between 0 and 100")
			return
		}
		requestID := strings.TrimSpace(stringFromAny(body["clientRequestId"]))
		if requestID == "" {
			requestID = fmt.Sprintf("lighting-%d-%d", time.Now().UnixMilli(), address)
		}
		updated := rcu.UpdateLightingLevel(address, level, requestID)
		if updated == nil {
			sendText(w, http.StatusBadGateway, "Failed to set target level")
			return
		}
		writeJSON(w, updated)
		s.broadcastRoomSnapshot(room)
		return
	}

	sendText(w, http.StatusMethodNotAllowed, "Method Not Allowed")
}

func (s *TestCommServer) handleHvac(w http.ResponseWriter, r *http.Request, room string) {
	rcu := s.getOrCreateRcu(room)
	if rcu == nil {
		sendText(w, http.StatusNotFound, "Unknown room")
		return
	}
	if r.Method == http.MethodGet {
		if !rcu.InitializeAndUpdate() {
			sendText(w, http.StatusBadGateway, "Failed to initialize RCU")
			return
		}
		payload := rcu.HvacSnapshot()
		writeJSON(w, payload)
		return
	}

	if r.Method == http.MethodPut {
		var updates map[string]interface{}
		if err := json.NewDecoder(r.Body).Decode(&updates); err != nil || len(updates) == 0 {
			sendText(w, http.StatusBadRequest, "Request body required")
			return
		}
		if !rcu.InitializeAndUpdate() {
			sendText(w, http.StatusBadGateway, "Failed to initialize RCU")
			return
		}
		payload := rcu.UpdateHvac(updates)
		if payload == nil {
			sendText(w, http.StatusBadGateway, "Failed to update HVAC data")
			return
		}
		writeJSON(w, payload)
		s.broadcastRoomSnapshot(room)
		return
	}

	sendText(w, http.StatusMethodNotAllowed, "Method Not Allowed")
}

func (s *TestCommServer) handleRawCommand(w http.ResponseWriter, r *http.Request, room string) {
	rcu := s.getOrCreateRcu(room)
	if rcu == nil {
		sendText(w, http.StatusNotFound, "Unknown room")
		return
	}
	if r.Method != http.MethodPost {
		sendText(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}

	var body map[string]interface{}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		sendText(w, http.StatusBadRequest, "Invalid JSON")
		return
	}

	hexFrame := strings.TrimSpace(stringFromAny(body["hex"]))
	if hexFrame == "" {
		sendText(w, http.StatusBadRequest, "Request must include hex command")
		return
	}

	frame, err := decodeHexCommand(hexFrame)
	if err != nil {
		sendText(w, http.StatusBadRequest, fmt.Sprintf("Invalid hex command: %v", err))
		return
	}

	requestID := strings.TrimSpace(stringFromAny(body["clientRequestId"]))
	payload := rcu.ExecuteRawCommand(frame, requestID)
	if payload == nil {
		sendText(w, http.StatusBadGateway, "Failed to send raw command")
		return
	}
	writeJSON(w, payload)
	s.broadcastRoomSnapshot(room)
}

// handleMenu implements /testcomm/rooms/{room}/menu with a simplified behavior
// compatible with the Java RcuMenuService/RcuMenuResponse contract.
func (s *TestCommServer) handleMenu(w http.ResponseWriter, r *http.Request, room string) {
	addCORSHeaders(w, r)
	if handleOptions(w, r) {
		return
	}

	state := s.getMenuState(room)

	switch r.Method {
	case http.MethodGet:
		// Return the current menu based on the last screen.
		if state.LastMenu == MenuScreenControl {
			resp := buildControlMenuResponse(state, "")
			writeJSON(w, resp)
		} else {
			resp := buildMainMenuResponse(state, "")
			writeJSON(w, resp)
		}
	case http.MethodPost:
		body, err := ioReadAll(r.Body)
		if err != nil {
			sendText(w, http.StatusBadRequest, "Invalid JSON")
			return
		}
		var payload map[string]interface{}
		if err := json.Unmarshal(body, &payload); err != nil {
			sendText(w, http.StatusBadRequest, "Invalid JSON")
			return
		}
		rawChoice, ok := payload["choice"]
		if !ok {
			sendText(w, http.StatusBadRequest, "Request must include numeric 'choice'")
			return
		}
		choice, ok := rawChoice.(float64)
		if !ok {
			sendText(w, http.StatusBadRequest, "Request must include numeric 'choice'")
			return
		}
		// parameters are optional; when present they should be a JSON object.
		params := map[string]string{}
		if pRaw, exists := payload["parameters"]; exists {
			if obj, ok := pRaw.(map[string]interface{}); ok {
				for k, v := range obj {
					if str, ok := v.(string); ok {
						params[k] = str
					} else {
						// coerce non-string values via JSON to string, to stay robust.
						b, _ := json.Marshal(v)
						params[k] = string(b)
					}
				}
			}
		}

		// For now we implement a minimal subset of menu behavior:
		// - 0: exit/back navigation
		// - 6 (main): toggle debug mode
		// - 7 (main): switch to control menu
		// All other choices just emit a message indicating not implemented.
		var output string
		switch state.LastMenu {
		case MenuScreenControl:
			switch int(choice) {
			case 0:
				state.LastMenu = MenuScreenMain
				state.LastControlSubmenu = "none"
				output = ""
			default:
				output = "Control menu actions are not yet implemented in Go backend."
			}
			resp := buildControlMenuResponse(state, output)
			writeJSON(w, resp)
		default: // MAIN
			switch int(choice) {
			case 0:
				output = "Exiting..."
			case 6:
				state.DebugMode = !state.DebugMode
				output = "Debug mode " + map[bool]string{true: "enabled", false: "disabled"}[state.DebugMode]
			case 7:
				state.LastMenu = MenuScreenControl
				state.LastControlSubmenu = "control"
				output = ""
				resp := buildControlMenuResponse(state, output)
				writeJSON(w, resp)
				return
			default:
				output = "This menu action is not yet implemented in Go backend."
			}
			resp := buildMainMenuResponse(state, output)
			writeJSON(w, resp)
		}
	default:
		sendText(w, http.StatusMethodNotAllowed, "Method Not Allowed")
	}
}

func (s *TestCommServer) handleLogs(w http.ResponseWriter, r *http.Request) {
	addCORSHeaders(w, r)
	if handleOptions(w, r) {
		return
	}
	if r.Method != http.MethodPost {
		sendText(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}
	data, err := os.ReadFile("/dev/stdin")
	if err != nil || len(data) == 0 {
		// fall back to reading from body directly
		body, _ := ioReadAll(r.Body)
		if len(body) == 0 {
			sendText(w, http.StatusBadRequest, "Empty request body")
			return
		}
		log.Printf("%s", string(body))
		sendText(w, http.StatusOK, "OK")
		return
	}
	log.Printf("%s", string(data))
	sendText(w, http.StatusOK, "OK")
}

func (s *TestCommServer) handleCoordinates(w http.ResponseWriter, r *http.Request) {
	addCORSHeaders(w, r)
	if handleOptions(w, r) {
		return
	}

	path := r.URL.Path
	if path == "/testcomm/coordinates" || path == "/testcomm/coordinates/" {
		if r.Method != http.MethodGet {
			sendText(w, http.StatusMethodNotAllowed, "Method Not Allowed")
			return
		}
		payload := s.coordinatesStore.BuildPayload()
		writeJSON(w, payload)
		return
	}

	if path == "/testcomm/coordinates/stream" {
		if r.Method != http.MethodGet {
			sendText(w, http.StatusMethodNotAllowed, "Method Not Allowed")
			return
		}
		s.handleCoordinatesStream(w, r)
		return
	}

	if path == "/testcomm/coordinates/zones" {
		s.handleCoordinatesUpdate(w, r, s.coordinatesStore.SaveZonesJSON, "Zones updated")
		return
	}

	if path == "/testcomm/coordinates/lighting-devices" {
		s.handleCoordinatesUpdate(w, r, s.coordinatesStore.SaveLightingDevicesJSON, "Lighting devices updated")
		return
	}

	if path == "/testcomm/coordinates/service-icons" {
		s.handleCoordinatesUpdate(w, r, s.coordinatesStore.SaveServiceIconsJSON, "Service icons updated")
		return
	}

	sendText(w, http.StatusNotFound, "Not Found")
}

func (s *TestCommServer) handleCoordinatesUpdate(
	w http.ResponseWriter,
	r *http.Request,
	save func(string) error,
	message string,
) {
	if r.Method != http.MethodPut {
		sendText(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}
	if !isAdminRequest(r) {
		sendText(w, http.StatusForbidden, "Admin access required")
		return
	}
	body, _ := ioReadAll(r.Body)
	if len(strings.TrimSpace(string(body))) == 0 {
		sendText(w, http.StatusBadRequest, "Request body required")
		return
	}
	if err := save(string(body)); err != nil {
		log.Printf("failed to save coordinates: %v", err)
		sendText(w, http.StatusInternalServerError, "Failed to save config")
		return
	}
	s.broadcastCoordinatesUpdate()
	sendText(w, http.StatusOK, message)
}

func (s *TestCommServer) handleDemoRcuSettings(w http.ResponseWriter, r *http.Request) {
	addCORSHeaders(w, r)
	if handleOptions(w, r) {
		return
	}

	switch r.Method {
	case http.MethodGet:
		writeJSON(w, map[string]interface{}{
			"room": "Demo 101",
			"host": s.roomConfigs["Demo 101"].Host,
			"port": s.roomConfigs["Demo 101"].Port,
		})
	case http.MethodPut:
		if !isAdminRequest(r) {
			sendText(w, http.StatusForbidden, "Admin access required")
			return
		}

		var payload struct {
			Host string `json:"host"`
			Port int    `json:"port"`
		}
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			sendText(w, http.StatusBadRequest, "Invalid JSON")
			return
		}

		cfg, err := normalizeDemoRcuConfig(payload.Host, payload.Port)
		if err != nil {
			sendText(w, http.StatusBadRequest, err.Error())
			return
		}
		if err := s.demoRcuStore.Save(cfg); err != nil {
			log.Printf("demo_rcu.save failed host=%s port=%d error=%v", cfg.Host, cfg.Port, err)
			sendText(w, http.StatusInternalServerError, "Failed to save demo RCU settings")
			return
		}

		s.updateRoomConfig("Demo 101", cfg)
		s.snapshotCacheMu.Lock()
		delete(s.snapshotCache, "Demo 101")
		s.snapshotCacheMu.Unlock()
		s.broadcastRoomSnapshot("Demo 101")
		writeJSON(w, map[string]interface{}{
			"room":    "Demo 101",
			"host":    cfg.Host,
			"port":    cfg.Port,
			"message": "Demo RCU settings updated",
		})
	default:
		sendText(w, http.StatusMethodNotAllowed, "Method Not Allowed")
	}
}

var wsUpgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

func (s *TestCommServer) handleCoordinatesStream(w http.ResponseWriter, r *http.Request) {
	conn, err := wsUpgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("websocket upgrade failed: %v", err)
		return
	}

	s.coordSocketsMu.Lock()
	s.coordSockets[conn] = struct{}{}
	s.coordSocketsMu.Unlock()

	// send initial
	_ = conn.WriteJSON(s.coordinatesStore.BuildUpdateMessage())

	go func() {
		defer func() {
			s.coordSocketsMu.Lock()
			delete(s.coordSockets, conn)
			s.coordSocketsMu.Unlock()
			conn.Close()
		}()
		for {
			if _, _, err := conn.ReadMessage(); err != nil {
				return
			}
		}
	}()
}

func (s *TestCommServer) handleServiceEvents(w http.ResponseWriter, r *http.Request) {
	addCORSHeaders(w, r)
	if handleOptions(w, r) {
		return
	}

	if r.URL.Path == "/testcomm/service-events/stream" {
		if r.Method != http.MethodGet {
			sendText(w, http.StatusMethodNotAllowed, "Method Not Allowed")
			return
		}
		s.handleServiceEventsStream(w, r)
		return
	}

	if r.Method != http.MethodGet {
		sendText(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}

	q := r.URL.Query()
	room := q.Get("roomNumber")
	serviceType := q.Get("serviceType")
	limit, _ := strconv.Atoi(q.Get("limit"))
	if limit <= 0 {
		limit = 100
	}

	events := s.serviceStore.Query(room, serviceType, limit)
	writeJSON(w, events)
}

func (s *TestCommServer) handleServiceEventsStream(w http.ResponseWriter, r *http.Request) {
	h := w.Header()
	h.Set("Content-Type", "text/event-stream")
	h.Set("Cache-Control", "no-cache")
	h.Set("Connection", "keep-alive")

	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "Streaming unsupported", http.StatusInternalServerError)
		return
	}

	lastID := s.serviceStore.LastIndexBefore(time.Now().Add(-60 * time.Second))

	send := func(rec ServiceEventRecord) error {
		w.Write([]byte("event: service-event\n"))
		data, _ := json.Marshal(rec.ToJSON())
		w.Write([]byte("data: "))
		w.Write(data)
		w.Write([]byte("\n\n"))
		flusher.Flush()
		return nil
	}

	ticker := time.NewTicker(1 * time.Second)
	defer ticker.Stop()
	notify := r.Context().Done()

	for {
		select {
		case <-ticker.C:
			for _, ev := range s.serviceStore.EventsSince(lastID) {
				if err := send(ev); err != nil {
					return
				}
				lastID = int(ev.ID)
			}
		case <-notify:
			return
		}
	}
}

// ========== Broadcast helpers ==========

func (s *TestCommServer) broadcastRoomSnapshot(room string) {
	s.roomStreamsMu.RLock()
	clients := append([]*sseClient(nil), s.roomStreams[room]...)
	s.roomStreamsMu.RUnlock()
	if len(clients) == 0 {
		return
	}
	rcu := s.getOrCreateRcu(room)
	snapshot, ok := s.buildSnapshotWithFallback(room, rcu)
	if !ok {
		return
	}
	for _, c := range clients {
		if err := c.SendEvent("snapshot", snapshot); err != nil {
			s.removeRoomClient(room, c)
		}
	}
}

func (s *TestCommServer) buildSnapshotWithFallback(room string, rcu RcuClient) (map[string]interface{}, bool) {
	if rcu == nil {
		return nil, false
	}

	if rcu.InitializeAndUpdate() {
		snapshot := rcu.Snapshot(s.serviceStore.EventsForRoom(room))
		withMeta := cloneMap(snapshot)
		withMeta["_meta"] = map[string]interface{}{
			"source":    "live",
			"stale":     false,
			"updatedAt": time.Now().UTC().Format(time.RFC3339),
		}
		s.cacheSnapshot(room, withMeta)
		return withMeta, true
	}

	if cached, ok := s.getCachedSnapshot(room); ok {
		fallback := cloneMap(cached)
		meta := map[string]interface{}{
			"source":    "cache",
			"stale":     true,
			"updatedAt": time.Now().UTC().Format(time.RFC3339),
		}
		if cachedMeta, okMeta := cached["_meta"].(map[string]interface{}); okMeta {
			if v, exists := cachedMeta["updatedAt"]; exists {
				meta["lastLiveAt"] = v
			}
		}
		fallback["_meta"] = meta
		log.Printf("snapshot.fallback.cache room=%s", room)
		return fallback, true
	}
	return nil, false
}

func (s *TestCommServer) cacheSnapshot(room string, payload map[string]interface{}) {
	s.snapshotCacheMu.Lock()
	defer s.snapshotCacheMu.Unlock()
	s.snapshotCache[room] = cachedRoomSnapshot{
		payload:   cloneMap(payload),
		updatedAt: time.Now().UTC(),
	}
}

func (s *TestCommServer) getCachedSnapshot(room string) (map[string]interface{}, bool) {
	s.snapshotCacheMu.RLock()
	defer s.snapshotCacheMu.RUnlock()
	entry, ok := s.snapshotCache[room]
	if !ok {
		return nil, false
	}
	_ = entry.updatedAt
	return cloneMap(entry.payload), true
}

func (s *TestCommServer) broadcastCoordinatesUpdate() {
	s.coordSocketsMu.RLock()
	sockets := make([]*websocket.Conn, 0, len(s.coordSockets))
	for c := range s.coordSockets {
		sockets = append(sockets, c)
	}
	s.coordSocketsMu.RUnlock()
	if len(sockets) == 0 {
		return
	}
	msg := s.coordinatesStore.BuildUpdateMessage()
	for _, c := range sockets {
		if err := c.WriteJSON(msg); err != nil {
			s.coordSocketsMu.Lock()
			delete(s.coordSockets, c)
			s.coordSocketsMu.Unlock()
			c.Close()
		}
	}
}

// ========== Stores and models ==========

type RoomStore struct {
	mu    sync.RWMutex
	rooms map[string]*RoomState
}

func NewRoomStore() *RoomStore {
	rs := &RoomStore{
		rooms: make(map[string]*RoomState),
	}
	rs.rooms["Demo 101"] = DemoRoom()
	return rs
}

func (rs *RoomStore) HasRoom(room string) bool {
	rs.mu.RLock()
	defer rs.mu.RUnlock()
	_, ok := rs.rooms[room]
	return ok
}

func (rs *RoomStore) Snapshot(room string, serviceEvents []map[string]interface{}) map[string]interface{} {
	rs.mu.RLock()
	defer rs.mu.RUnlock()
	state := rs.rooms[room]
	occupied, rented := simulatedOccupancyState(state.Status)
	return map[string]interface{}{
		"number":        room,
		"hvac":          mapSimHvacState(state.HVAC),
		"hvacDetail":    buildSimHvacDetail(state.HVAC),
		"lighting":      state.Lighting,
		"appState":      "RUN_STATE",
		"appStateValue": 1,
		"dnd":           state.DND,
		"mur":           state.MUR,
		"laundry":       state.Laundry,
		"occupancy": map[string]interface{}{
			"occupied":     occupied,
			"rented":       rented,
			"doorOpen":     false,
			"hasDoorAlarm": false,
		},
		"status":          state.Status,
		"hasAlarm":        state.HasAlarm,
		"lightingDevices": state.LightingDevices,
		"serviceEvents":   serviceEvents,
	}
}

func simulatedOccupancyState(status string) (occupied bool, rented bool) {
	switch strings.TrimSpace(strings.ToLower(status)) {
	case "rented occupied":
		return true, true
	case "rented hk", "rented vacant":
		return false, true
	case "unrented hk", "unrented vacant":
		return false, false
	default:
		return false, true
	}
}

func (rs *RoomStore) HvacSnapshot(room string) map[string]interface{} {
	rs.mu.RLock()
	defer rs.mu.RUnlock()
	return buildSimHvacDetail(rs.rooms[room].HVAC)
}

func (rs *RoomStore) UpdateHvac(room string, updates map[string]interface{}) map[string]interface{} {
	rs.mu.Lock()
	defer rs.mu.Unlock()
	state := rs.rooms[room]
	coerceFloat := func(v interface{}) (float64, bool) {
		switch t := v.(type) {
		case float64:
			return t, true
		case float32:
			return float64(t), true
		case int:
			return float64(t), true
		case int64:
			return float64(t), true
		case json.Number:
			f, err := t.Float64()
			if err != nil {
				return 0, false
			}
			return f, true
		default:
			return 0, false
		}
	}

	for k, v := range updates {
		switch k {
		case "onOff":
			if i, ok := intFromAny(v); ok {
				if i != 0 {
					i = 1
				}
				state.HVAC.OnOff = i
			}
		case "mode":
			if i, ok := intFromAny(v); ok {
				state.HVAC.Mode = i
			}
		case "fanMode":
			if i, ok := intFromAny(v); ok {
				state.HVAC.FanMode = i
			}
		case "setPoint":
			if f, ok := coerceFloat(v); ok {
				state.HVAC.SetPoint = f
			}
		case "roomTemperature":
			if f, ok := coerceFloat(v); ok {
				state.HVAC.RoomTemperature = f
			}
		case "runningStatus":
			if i, ok := intFromAny(v); ok {
				state.HVAC.RunningStatus = i
			}
		}
	}

	return buildSimHvacDetail(state.HVAC)
}

func (rs *RoomStore) UpdateLightingLevel(room string, address, level int) map[string]interface{} {
	rs.mu.Lock()
	defer rs.mu.Unlock()
	state := rs.rooms[room]
	for _, dev := range state.LightingDevices {
		if intFrom(dev["address"]) == address {
			dev["targetLevel"] = level
			dev["actualLevel"] = level
			return cloneMap(dev)
		}
	}
	return nil
}

func (rs *RoomStore) CallLightingScene(room string, scene int) map[string]interface{} {
	rs.mu.RLock()
	defer rs.mu.RUnlock()
	if _, ok := rs.rooms[room]; !ok {
		return nil
	}
	return map[string]interface{}{
		"scene":     scene,
		"group":     sceneGroupByte,
		"triggered": true,
		"source":    "simulation",
	}
}

func (rs *RoomStore) ExecuteRawCommand(room string, frame []byte) map[string]interface{} {
	rs.mu.RLock()
	defer rs.mu.RUnlock()
	if _, ok := rs.rooms[room]; !ok {
		return nil
	}
	return map[string]interface{}{
		"triggered": true,
		"source":    "simulation",
		"status":    "accepted",
		"frameHex":  fmt.Sprintf("% X", frame),
	}
}

func (rs *RoomStore) BuildLightingSummary(room string) map[string]interface{} {
	rs.mu.RLock()
	defer rs.mu.RUnlock()
	state := rs.rooms[room]
	onboard := []map[string]interface{}{}
	dali := []map[string]interface{}{}
	for _, dev := range state.LightingDevices {
		entry := map[string]interface{}{
			"address":     dev["address"],
			"name":        dev["name"],
			"actualLevel": dev["actualLevel"],
			"targetLevel": dev["targetLevel"],
			"status":      dev["status"],
			"type":        "dali",
		}
		if b, _ := dev["onboard"].(bool); b {
			entry["type"] = "onboard"
			onboard = append(onboard, entry)
		} else {
			dali = append(dali, entry)
		}
	}
	return map[string]interface{}{
		"onboardOutputs": onboard,
		"daliOutputs":    dali,
	}
}

func (rs *RoomStore) BuildLightingLegacy(room string) map[string]interface{} {
	rs.mu.RLock()
	defer rs.mu.RUnlock()
	state := rs.rooms[room]
	devs := make([]map[string]interface{}, len(state.LightingDevices))
	for i, d := range state.LightingDevices {
		devs[i] = cloneMap(d)
	}
	return map[string]interface{}{
		"lightingDevices": devs,
	}
}

func (rs *RoomStore) BuildOutputTargets(room string) map[string]interface{} {
	rs.mu.RLock()
	defer rs.mu.RUnlock()
	state := rs.rooms[room]
	outputs := make([]map[string]interface{}, 0, len(state.LightingDevices))
	for _, d := range state.LightingDevices {
		outputs = append(outputs, map[string]interface{}{
			"address":     d["address"],
			"name":        d["name"],
			"targetLevel": d["targetLevel"],
		})
	}
	return map[string]interface{}{
		"outputs": outputs,
	}
}

type RoomState struct {
	HVAC            SimHvacState
	Lighting        string
	DND             string
	MUR             string
	Laundry         string
	Status          string
	HasAlarm        bool
	LightingDevices []map[string]interface{}
}

type SimHvacState struct {
	OnOff           int
	RoomTemperature float64
	SetPoint        float64
	Mode            int
	FanMode         int
	RunningStatus   int
}

func mapSimHvacState(h SimHvacState) string {
	if h.OnOff == 0 {
		return "Off"
	}
	switch h.Mode {
	case 2:
		return "Cold"
	case 3:
		return "Hot"
	default:
		return "Active"
	}
}

func buildSimHvacDetail(h SimHvacState) map[string]interface{} {
	state := mapSimHvacState(h)
	return map[string]interface{}{
		"state":           state,
		"onOff":           h.OnOff,
		"roomTemperature": h.RoomTemperature,
		"setPoint":        h.SetPoint,
		"mode":            h.Mode,
		"fanMode":         h.FanMode,
		"runningStatus":   h.RunningStatus,
	}
}

func DemoRoom() *RoomState {
	return &RoomState{
		HVAC: SimHvacState{
			OnOff:           0,
			RoomTemperature: 22.5,
			SetPoint:        21.0,
			Mode:            0,
			FanMode:         4,
			RunningStatus:   0,
		},
		Lighting: "off",
		DND:      "",
		MUR:      "",
		Laundry:  "",
		Status:   "ok",
		HasAlarm: false,
		LightingDevices: []map[string]interface{}{
			{
				"address":     1,
				"name":        "Entry Light",
				"variety":     "dimmer",
				"type":        "lighting",
				"actualLevel": 0,
				"targetLevel": 0,
				"status":      "ok",
				"onboard":     true,
			},
			{
				"address":     2,
				"name":        "Bedside Lamp",
				"variety":     "dimmer",
				"type":        "lighting",
				"actualLevel": 0,
				"targetLevel": 0,
				"status":      "ok",
				"onboard":     false,
			},
		},
	}
}

type CoordinatesStore struct {
	configDir           string
	legacyConfigDir     string
	zonesFile           string
	legacyZonesFile     string
	lightingDevicesFile string
	legacyLightingFile  string
	serviceIconsFile    string
	legacyServiceIcons  string
}

func NewCoordinatesStore() *CoordinatesStore {
	paths := testcommconfig.ResolveFromCaller(1)
	testcommconfig.LogResolvedPaths("coordinates.resolver", paths)
	_ = os.MkdirAll(paths.ConfigDir, 0o755)
	return &CoordinatesStore{
		configDir:           paths.ConfigDir,
		legacyConfigDir:     paths.LegacyConfigDir,
		zonesFile:           paths.ZonesFile,
		legacyZonesFile:     filepath.Join(paths.LegacyConfigDir, "zones.json"),
		lightingDevicesFile: paths.LightingDevicesFile,
		legacyLightingFile:  filepath.Join(paths.LegacyConfigDir, "lighting-devices.json"),
		serviceIconsFile:    paths.ServiceIconsFile,
		legacyServiceIcons:  filepath.Join(paths.LegacyConfigDir, "service-icons.json"),
	}
}

const defaultZonesJSON = `{"homePageBlockButtons":[],"polyPointsData":[],"categoryNamesBlockFloorMap":{}}`
const defaultLightingJSON = `[]`
const defaultServiceIconsJSON = `[]`

func (cs *CoordinatesStore) LoadZonesJSON() string {
	return readJSONFileWithFallback(defaultZonesJSON, testcommconfig.LegacyCandidates(cs.zonesFile, cs.legacyZonesFile)...)
}

func (cs *CoordinatesStore) LoadLightingDevicesJSON() string {
	return readJSONFileWithFallback(defaultLightingJSON, testcommconfig.LegacyCandidates(cs.lightingDevicesFile, cs.legacyLightingFile)...)
}

func (cs *CoordinatesStore) LoadServiceIconsJSON() string {
	return readJSONFileWithFallback(defaultServiceIconsJSON, testcommconfig.LegacyCandidates(cs.serviceIconsFile, cs.legacyServiceIcons)...)
}

func (cs *CoordinatesStore) SaveZonesJSON(jsonStr string) error {
	return writeJSONFile(cs.zonesFile, jsonStr)
}

func (cs *CoordinatesStore) SaveLightingDevicesJSON(jsonStr string) error {
	return writeJSONFile(cs.lightingDevicesFile, jsonStr)
}

func (cs *CoordinatesStore) SaveServiceIconsJSON(jsonStr string) error {
	var serviceIcons interface{}
	if err := json.Unmarshal([]byte(jsonStr), &serviceIcons); err != nil {
		return err
	}
	if _, ok := serviceIcons.([]interface{}); !ok {
		return fmt.Errorf("serviceIcons must be a JSON array")
	}
	return writeJSONFile(cs.serviceIconsFile, jsonStr)
}

func (cs *CoordinatesStore) BuildPayload() map[string]interface{} {
	var zones interface{}
	_ = json.Unmarshal([]byte(cs.LoadZonesJSON()), &zones)
	lightingDevices, err := cs.parseLightingDevicesFile()
	if err != nil {
		lightingDevices = []interface{}{}
	}
	serviceIcons, err := cs.parseServiceIconsFile()
	if err != nil {
		serviceIcons = []interface{}{}
	}
	return map[string]interface{}{
		"zones":           zones,
		"lightingDevices": lightingDevices,
		"serviceIcons":    serviceIcons,
	}
}

func (cs *CoordinatesStore) BuildUpdateMessage() map[string]interface{} {
	return map[string]interface{}{
		"event":   "coordinates.updated",
		"payload": cs.BuildPayload(),
	}
}

func (cs *CoordinatesStore) parseLightingDevicesFile() (interface{}, error) {
	var root interface{}
	if err := json.Unmarshal([]byte(cs.LoadLightingDevicesJSON()), &root); err != nil {
		return nil, err
	}
	if typed, ok := root.([]interface{}); ok {
		return typed, nil
	}
	if typed, ok := root.(map[string]interface{}); ok {
		if lightingDevices, ok := typed["lightingDevices"].([]interface{}); ok {
			return lightingDevices, nil
		}
	}
	return []interface{}{}, nil
}

func (cs *CoordinatesStore) parseServiceIconsFile() (interface{}, error) {
	var root interface{}
	if err := json.Unmarshal([]byte(cs.LoadServiceIconsJSON()), &root); err == nil {
		if typed, ok := root.([]interface{}); ok {
			return typed, nil
		}
	}
	// Compatibility fallback: serviceIcons may be embedded in legacy lighting-devices.json map payload.
	var legacyRoot interface{}
	if err := json.Unmarshal([]byte(cs.LoadLightingDevicesJSON()), &legacyRoot); err != nil {
		return []interface{}{}, nil
	}
	if typed, ok := legacyRoot.(map[string]interface{}); ok {
		if serviceIcons, ok := typed["serviceIcons"].([]interface{}); ok {
			log.Printf("coordinates.migration using legacy serviceIcons from %s", cs.lightingDevicesFile)
			return serviceIcons, nil
		}
	}
	return []interface{}{}, nil
}

func readJSONFileWithFallback(fallback string, paths ...string) string {
	for _, p := range paths {
		if strings.TrimSpace(p) == "" {
			continue
		}
		if data, err := os.ReadFile(p); err == nil && len(data) > 0 {
			if p != paths[0] {
				log.Printf("coordinates.migration using legacy file path=%s", p)
			}
			return strings.TrimSpace(string(data))
		}
	}
	return fallback
}

func readJSONFile(path, fallback string) string {
	data, err := os.ReadFile(path)
	if err != nil || len(data) == 0 {
		_ = writeJSONFile(path, fallback)
		return fallback
	}
	str := strings.TrimSpace(string(data))
	if str == "" {
		return fallback
	}
	return str
}

func writeJSONFile(path, contents string) error {
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, []byte(contents), 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

func fileExists(path string) bool {
	info, err := os.Stat(path)
	if err != nil {
		return false
	}
	return !info.IsDir()
}

type ServiceEventRecord struct {
	ID          int64
	ServiceType string
	EventType   string
	Timestamp   int64
	RoomNumber  string
}

func (r ServiceEventRecord) ToJSON() map[string]interface{} {
	return map[string]interface{}{
		"serviceType": r.ServiceType,
		"eventType":   r.EventType,
		"timestamp":   r.Timestamp,
		"roomNumber":  r.RoomNumber,
	}
}

type ServiceEventStore struct {
	db     *sql.DB
	dbPath string
}

func NewServiceEventStore(dbPath string) *ServiceEventStore {
	resolved := resolveDbPath(dbPath)
	db, err := sql.Open("sqlite3", resolved)
	if err != nil {
		log.Fatalf("failed to open service events DB at %s: %v", resolved, err)
	}
	if err := initializeServiceEventsDB(db); err != nil {
		log.Fatalf("failed to initialize service events DB at %s: %v", resolved, err)
	}
	return &ServiceEventStore{
		db:     db,
		dbPath: resolved,
	}
}

func (s *ServiceEventStore) Query(roomNumber, serviceType string, limit int) []map[string]interface{} {
	if s.db == nil {
		return nil
	}
	var args []interface{}
	sb := strings.Builder{}
	sb.WriteString("SELECT room_number, service_type, event_type, timestamp FROM service_events WHERE 1=1")
	if roomNumber != "" {
		sb.WriteString(" AND room_number = ?")
		args = append(args, roomNumber)
	}
	if serviceType != "" {
		sb.WriteString(" AND service_type = ?")
		args = append(args, serviceType)
	}
	sb.WriteString(" ORDER BY timestamp DESC")
	if limit > 0 {
		sb.WriteString(" LIMIT ?")
		args = append(args, limit)
	}
	rows, err := s.db.Query(sb.String(), args...)
	if err != nil {
		log.Printf("error querying service events: %v", err)
		return nil
	}
	defer rows.Close()
	var out []map[string]interface{}
	for rows.Next() {
		var room, st, et string
		var ts int64
		if err := rows.Scan(&room, &st, &et, &ts); err != nil {
			log.Printf("error scanning service event row: %v", err)
			continue
		}
		out = append(out, map[string]interface{}{
			"roomNumber":  room,
			"serviceType": st,
			"eventType":   et,
			"timestamp":   ts,
		})
	}
	return out
}

func (s *ServiceEventStore) EventsForRoom(room string) []map[string]interface{} {
	// Reuse Query to honour ordering and filtering semantics.
	return s.Query(room, "", 100)
}

func (s *ServiceEventStore) LastIndexBefore(t time.Time) int {
	if s.db == nil {
		return 0
	}
	ts := t.Unix()
	row := s.db.QueryRow(`SELECT id FROM service_events WHERE timestamp <= ? ORDER BY id DESC LIMIT 1`, ts)
	var id int64
	if err := row.Scan(&id); err != nil {
		if err != sql.ErrNoRows {
			log.Printf("error querying LastIndexBefore: %v", err)
		}
		return 0
	}
	return int(id)
}

func (s *ServiceEventStore) EventsSince(lastID int) []ServiceEventRecord {
	if s.db == nil {
		return nil
	}
	rows, err := s.db.Query(`SELECT id, room_number, service_type, event_type, timestamp
                             FROM service_events
                             WHERE id > ?
                             ORDER BY id ASC`, lastID)
	if err != nil {
		log.Printf("error querying EventsSince: %v", err)
		return nil
	}
	defer rows.Close()
	var out []ServiceEventRecord
	for rows.Next() {
		var id, ts int64
		var room, st, et string
		if err := rows.Scan(&id, &room, &st, &et, &ts); err != nil {
			log.Printf("error scanning service_events row: %v", err)
			continue
		}
		out = append(out, ServiceEventRecord{
			ID:          id,
			ServiceType: st,
			EventType:   et,
			Timestamp:   ts,
			RoomNumber:  room,
		})
	}
	return out
}

// resolveDbPath mirrors Java's ServiceEventDAO.resolveDbPath behavior.
func resolveDbPath(dbPath string) string {
	resolved := strings.TrimSpace(dbPath)
	if resolved == "" {
		if env := os.Getenv("TESTCOMM_DB_PATH"); env != "" {
			resolved = strings.TrimSpace(env)
		}
	}
	if resolved == "" {
		resolved = "testcomm.db"
	}
	abs, err := filepath.Abs(resolved)
	if err != nil {
		return resolved
	}
	return abs
}

func initializeServiceEventsDB(db *sql.DB) error {
	schema := `
CREATE TABLE IF NOT EXISTS service_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    room_number TEXT NOT NULL,
    service_type TEXT NOT NULL,
    event_type TEXT NOT NULL,
    timestamp INTEGER NOT NULL,
    created_at INTEGER NOT NULL,
    UNIQUE(room_number, service_type, event_type, timestamp)
);
CREATE INDEX IF NOT EXISTS idx_room_service ON service_events(room_number, service_type);
CREATE INDEX IF NOT EXISTS idx_timestamp ON service_events(timestamp DESC);
`
	stmts := strings.Split(schema, ";")
	for _, stmt := range stmts {
		stmt = strings.TrimSpace(stmt)
		if stmt == "" {
			continue
		}
		if _, err := db.Exec(stmt); err != nil {
			return err
		}
	}
	return nil
}

// ========== SSE client ==========

type sseClient struct {
	w       http.ResponseWriter
	flusher http.Flusher
	mu      sync.Mutex
	closed  bool
}

type DemoRcuConfigStore struct {
	filePath       string
	legacyFilePath string
}

func NewDemoRcuConfigStore() *DemoRcuConfigStore {
	paths := testcommconfig.ResolveFromCaller(1)
	testcommconfig.LogResolvedPaths("demo_rcu.resolver", paths)
	_ = os.MkdirAll(paths.ConfigDir, 0o755)
	return &DemoRcuConfigStore{
		filePath:       paths.DemoRcuSettingsFile,
		legacyFilePath: filepath.Join(paths.LegacyConfigDir, "demo-rcu.json"),
	}
}

func (s *DemoRcuConfigStore) Load() RcuConfig {
	cfg := defaultDemoRcuConfigFromEnv()
	data, err := os.ReadFile(s.filePath)
	if err != nil || len(data) == 0 {
		if s.legacyFilePath != "" && s.legacyFilePath != s.filePath {
			if legacyData, legacyErr := os.ReadFile(s.legacyFilePath); legacyErr == nil && len(legacyData) > 0 {
				log.Printf("demo_rcu.migration using legacy file path=%s", s.legacyFilePath)
				data = legacyData
			} else {
				return cfg
			}
		} else {
			return cfg
		}
	}

	var payload struct {
		Host string `json:"host"`
		Port int    `json:"port"`
	}
	if err := json.Unmarshal(data, &payload); err != nil {
		log.Printf("demo_rcu.load invalid config path=%s error=%v", s.filePath, err)
		return cfg
	}

	loaded, err := normalizeDemoRcuConfig(payload.Host, payload.Port)
	if err != nil {
		log.Printf("demo_rcu.load invalid values path=%s error=%v", s.filePath, err)
		return cfg
	}
	return loaded
}

func (s *DemoRcuConfigStore) Save(cfg RcuConfig) error {
	payload := map[string]interface{}{
		"host": cfg.Host,
		"port": cfg.Port,
	}
	data, err := json.MarshalIndent(payload, "", "  ")
	if err != nil {
		return err
	}
	return writeJSONFile(s.filePath, string(data))
}

func defaultDemoRcuConfigFromEnv() RcuConfig {
	rcuHost := strings.TrimSpace(os.Getenv("TESTCOMM_DEMO_RCU_HOST"))
	if rcuHost == "" {
		rcuHost = "192.168.1.114"
	}
	rcuPort := 5556
	if p := strings.TrimSpace(os.Getenv("TESTCOMM_DEMO_RCU_PORT")); p != "" {
		if v, err := strconv.Atoi(p); err == nil {
			rcuPort = v
		}
	}
	cfg, err := normalizeDemoRcuConfig(rcuHost, rcuPort)
	if err != nil {
		return RcuConfig{Host: "192.168.1.114", Port: 5556}
	}
	return cfg
}

func normalizeDemoRcuConfig(host string, port int) (RcuConfig, error) {
	host = strings.TrimSpace(host)
	if host == "" {
		return RcuConfig{}, fmt.Errorf("Host is required")
	}
	if strings.ContainsAny(host, "/\\") {
		return RcuConfig{}, fmt.Errorf("Host must not contain slashes")
	}
	if port < 1 || port > 65535 {
		return RcuConfig{}, fmt.Errorf("Port must be between 1 and 65535")
	}
	return RcuConfig{Host: host, Port: port}, nil
}

func newSseClient(w http.ResponseWriter, flusher http.Flusher) *sseClient {
	return &sseClient{w: w, flusher: flusher}
}

func (c *sseClient) SendEvent(event string, data interface{}) (err error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.closed || c.w == nil || c.flusher == nil {
		return fmt.Errorf("sse client closed")
	}

	defer func() {
		if recovered := recover(); recovered != nil {
			c.closed = true
			err = fmt.Errorf("sse send event panic: %v", recovered)
		}
	}()

	if _, err := c.w.Write([]byte("event: " + event + "\n")); err != nil {
		c.closed = true
		return err
	}
	b, err := json.Marshal(data)
	if err != nil {
		return err
	}
	if _, err := c.w.Write([]byte("data: ")); err != nil {
		c.closed = true
		return err
	}
	if _, err := c.w.Write(b); err != nil {
		c.closed = true
		return err
	}
	if _, err := c.w.Write([]byte("\n\n")); err != nil {
		c.closed = true
		return err
	}
	c.flusher.Flush()
	if c.closed {
		return fmt.Errorf("sse client closed during flush")
	}
	return nil
}

func (c *sseClient) SendComment(comment string) (err error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.closed || c.w == nil || c.flusher == nil {
		return fmt.Errorf("sse client closed")
	}

	defer func() {
		if recovered := recover(); recovered != nil {
			c.closed = true
			err = fmt.Errorf("sse send comment panic: %v", recovered)
		}
	}()

	if _, err := c.w.Write([]byte(":" + comment + "\n\n")); err != nil {
		c.closed = true
		return err
	}
	c.flusher.Flush()
	if c.closed {
		return fmt.Errorf("sse client closed during flush")
	}
	return nil
}

func (c *sseClient) Close() {
	c.mu.Lock()
	c.closed = true
	c.mu.Unlock()
}

// ========== helpers ==========

func addCORSHeaders(w http.ResponseWriter, r *http.Request) {
	origin := r.Header.Get("Origin")
	if origin == "" {
		origin = "*"
	}
	h := w.Header()
	h.Set("Access-Control-Allow-Origin", origin)
	h.Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS, PUT, DELETE")
	h.Set("Access-Control-Allow-Headers", "Content-Type, Authorization, Accept, X-Requested-With, X-User-Role")
	h.Set("Access-Control-Allow-Credentials", "true")
	h.Set("Access-Control-Max-Age", "3600")
	h.Set("Access-Control-Allow-Private-Network", "true")
}

func handleOptions(w http.ResponseWriter, r *http.Request) bool {
	if strings.ToUpper(r.Method) != http.MethodOptions {
		return false
	}
	w.WriteHeader(http.StatusNoContent)
	return true
}

func isAdminRequest(r *http.Request) bool {
	role := r.Header.Get("X-User-Role")
	return strings.EqualFold(strings.TrimSpace(role), "admin")
}

func sendText(w http.ResponseWriter, status int, msg string) {
	w.Header().Set("Content-Type", "text/plain")
	w.WriteHeader(status)
	w.Write([]byte(msg))
}

func writeJSON(w http.ResponseWriter, payload interface{}) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(payload)
}

func trimSlashes(v string) string {
	for strings.HasPrefix(v, "/") {
		v = v[1:]
	}
	for strings.HasSuffix(v, "/") {
		v = v[:len(v)-1]
	}
	return v
}

func decodeHexCommand(raw string) ([]byte, error) {
	cleaned := strings.Map(func(r rune) rune {
		switch {
		case r >= '0' && r <= '9':
			return r
		case r >= 'a' && r <= 'f':
			return r
		case r >= 'A' && r <= 'F':
			return r
		default:
			return -1
		}
	}, raw)
	if cleaned == "" {
		return nil, fmt.Errorf("empty hex payload")
	}
	if len(cleaned)%2 != 0 {
		return nil, fmt.Errorf("hex payload must have even length")
	}
	out := make([]byte, len(cleaned)/2)
	for i := 0; i < len(cleaned); i += 2 {
		v, err := strconv.ParseUint(cleaned[i:i+2], 16, 8)
		if err != nil {
			return nil, err
		}
		out[i/2] = byte(v)
	}
	return out, nil
}

func urlDecode(s string) (string, error) {
	return url.QueryUnescape(s)
}

func ioReadAll(r io.Reader) ([]byte, error) {
	return io.ReadAll(r)
}

func intFrom(v interface{}) int {
	switch t := v.(type) {
	case int:
		return t
	case int32:
		return int(t)
	case int64:
		return int(t)
	case float64:
		return int(t)
	default:
		return 0
	}
}

func intFromAny(v interface{}) (int, bool) {
	switch t := v.(type) {
	case int:
		return t, true
	case int32:
		return int(t), true
	case int64:
		return int(t), true
	case float64:
		return int(t), true
	case float32:
		return int(t), true
	case json.Number:
		i, err := t.Int64()
		if err != nil {
			return 0, false
		}
		return int(i), true
	default:
		return 0, false
	}
}

func int64FromAny(v interface{}) (int64, bool) {
	switch t := v.(type) {
	case int:
		return int64(t), true
	case int32:
		return int64(t), true
	case int64:
		return t, true
	case float64:
		return int64(t), true
	case float32:
		return int64(t), true
	case json.Number:
		i, err := t.Int64()
		if err != nil {
			return 0, false
		}
		return i, true
	default:
		return 0, false
	}
}

func stringFromAny(v interface{}) string {
	if v == nil {
		return ""
	}
	if s, ok := v.(string); ok {
		return s
	}
	return ""
}

func cloneMap(m map[string]interface{}) map[string]interface{} {
	out := make(map[string]interface{}, len(m))
	for k, v := range m {
		out[k] = v
	}
	return out
}

func (s *TestCommServer) staticFileHandler(webRoot string) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Flutter web release artifacts use stable filenames like index.html and
		// main.dart.js. After rsync-based deploys, permissive browser caching can
		// keep serving an older bundle and produce mixed/stale UI states.
		w.Header().Set("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
		w.Header().Set("Pragma", "no-cache")
		w.Header().Set("Expires", "0")

		requestPath := r.URL.Path
		if strings.Contains(requestPath, "..") {
			sendText(w, http.StatusForbidden, "Forbidden")
			return
		}
		if requestPath == "/health" || requestPath == "/testcomm" || strings.HasPrefix(requestPath, "/testcomm/") {
			sendText(w, http.StatusNotFound, "Not Found")
			return
		}

		cleanPath := path.Clean("/" + requestPath)
		relPath := strings.TrimPrefix(cleanPath, "/")
		if relPath == "" || relPath == "." {
			relPath = "index.html"
		}

		candidatePath := filepath.Join(webRoot, filepath.FromSlash(relPath))
		if info, err := os.Stat(candidatePath); err == nil {
			if info.IsDir() {
				indexPath := filepath.Join(candidatePath, "index.html")
				if indexInfo, indexErr := os.Stat(indexPath); indexErr == nil && !indexInfo.IsDir() {
					http.ServeFile(w, r, indexPath)
					return
				}
			} else {
				http.ServeFile(w, r, candidatePath)
				return
			}
		}

		// SPA fallback: return index.html for deep-link routes.
		indexPath := filepath.Join(webRoot, "index.html")
		if info, err := os.Stat(indexPath); err == nil && !info.IsDir() {
			http.ServeFile(w, r, indexPath)
			return
		}

		sendText(w, http.StatusNotFound, "Not Found")
	})
}

func absOrOriginal(path string) string {
	abs, err := filepath.Abs(path)
	if err != nil {
		return path
	}
	return abs
}

func resolveLogFilePath() string {
	if configured := strings.TrimSpace(os.Getenv("TESTCOMM_LOG_FILE")); configured != "" {
		return absOrOriginal(configured)
	}
	return absOrOriginal(filepath.Join(".", "testcomm_go.log"))
}

func configureLogging() (io.Closer, string, error) {
	logPath := resolveLogFilePath()
	logDir := filepath.Dir(logPath)
	if err := os.MkdirAll(logDir, 0o755); err != nil {
		return nil, "", err
	}
	file, err := os.OpenFile(logPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
	if err != nil {
		return nil, "", err
	}
	log.SetOutput(io.MultiWriter(os.Stdout, file))
	return file, logPath, nil
}

func main() {
	log.SetFlags(log.Ldate | log.Ltime | log.Lmicroseconds)
	logCloser, logPath, logErr := configureLogging()
	if logErr != nil {
		log.Printf("logging.warning failed to initialize log file: %v", logErr)
	} else {
		defer logCloser.Close()
		log.Printf("startup.log_file path=%s mode=truncate_on_start", logPath)
	}

	port := 8082
	if p := os.Getenv("TESTCOMM_PORT"); p != "" {
		if v, err := strconv.Atoi(p); err == nil {
			port = v
		}
	}
	webRoot := os.Getenv("TESTCOMM_WEB_ROOT")
	server := NewTestCommServer(ServerConfig{
		Port:    port,
		WebRoot: webRoot,
	})
	if err := server.Start(); err != nil {
		log.Fatalf("server error: %v", err)
	}
}
