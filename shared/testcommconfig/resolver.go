package testcommconfig

import (
	"log"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

type Paths struct {
	ConfigDir                string
	LegacyConfigDir          string
	ZonesFile                string
	LightingDevicesFile      string
	ServiceIconsFile         string
	DemoRcuSettingsFile      string
	RoomRegistrySettingsFile string
}

func ResolveFromCaller(callerSkip int) Paths {
	if configured := strings.TrimSpace(os.Getenv("TESTCOMM_CONFIG_DIR")); configured != "" {
		resolved := absOrOriginal(configured)
		return build(resolved, legacyConfigDir())
	}
	if _, srcFile, _, ok := runtime.Caller(callerSkip); ok && strings.TrimSpace(srcFile) != "" {
		resolved := absOrOriginal(filepath.Join(filepath.Dir(srcFile), "config"))
		return build(resolved, legacyConfigDir())
	}
	legacy := legacyConfigDir()
	return build(legacy, legacy)
}

func LogResolvedPaths(prefix string, paths Paths) {
	log.Printf("%s config_dir=%s legacy_config_dir=%s zones=%s lighting_devices=%s service_icons=%s demo_rcu=%s rooms=%s",
		prefix,
		paths.ConfigDir,
		paths.LegacyConfigDir,
		paths.ZonesFile,
		paths.LightingDevicesFile,
		paths.ServiceIconsFile,
		paths.DemoRcuSettingsFile,
		paths.RoomRegistrySettingsFile,
	)
}

func LegacyCandidates(primary, legacy string) []string {
	out := []string{primary}
	if legacy != "" && legacy != primary {
		out = append(out, legacy)
	}
	return out
}

func build(configDir, legacyDir string) Paths {
	return Paths{
		ConfigDir:                configDir,
		LegacyConfigDir:          legacyDir,
		ZonesFile:                filepath.Join(configDir, "zones.json"),
		LightingDevicesFile:      filepath.Join(configDir, "lighting-devices.json"),
		ServiceIconsFile:         filepath.Join(configDir, "service-icons.json"),
		DemoRcuSettingsFile:      filepath.Join(configDir, "demo-rcu.json"),
		RoomRegistrySettingsFile: filepath.Join(configDir, "testcomm_rooms.json"),
	}
}

func legacyConfigDir() string {
	base, _ := os.Getwd()
	return absOrOriginal(filepath.Join(base, "config"))
}

func absOrOriginal(path string) string {
	abs, err := filepath.Abs(path)
	if err != nil {
		return path
	}
	return abs
}
