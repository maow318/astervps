package main

// Thermal sensors: fans and temperatures, collected per platform (hwmon on
// Linux, AppleSMC on macOS, WMI thermal zones on Windows). Virtual machines
// simply have none — the section stays empty and clients hide it.

import (
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

type FanReading struct {
	Label string  `json:"label"`
	RPM   float64 `json:"rpm"`
}

type TempReading struct {
	Label   string  `json:"label"`
	Celsius float64 `json:"celsius"`
}

type Sensors struct {
	Available bool          `json:"available"`
	Fans      []FanReading  `json:"fans"`
	Temps     []TempReading `json:"temps"`
}

func emptySensors() Sensors {
	return Sensors{Available: false, Fans: []FanReading{}, Temps: []TempReading{}}
}

// readHwmon walks a hwmon-style directory tree. Split from the Linux entry
// point so the parser is unit-testable on any platform.
func readHwmon(root string) Sensors {
	sensors := emptySensors()
	chips, err := os.ReadDir(root)
	if err != nil {
		return sensors
	}
	for _, chip := range chips {
		chipDir := filepath.Join(root, chip.Name())
		chipName := strings.TrimSpace(readSmallFile(filepath.Join(chipDir, "name")))
		entries, err := os.ReadDir(chipDir)
		if err != nil {
			continue
		}
		for _, entry := range entries {
			name := entry.Name()
			switch {
			case strings.HasPrefix(name, "temp") && strings.HasSuffix(name, "_input"):
				raw := readSmallFile(filepath.Join(chipDir, name))
				milli, err := strconv.ParseFloat(strings.TrimSpace(raw), 64)
				if err != nil {
					continue
				}
				celsius := milli / 1000
				if celsius <= 0 || celsius > 150 {
					continue
				}
				label := strings.TrimSpace(
					readSmallFile(filepath.Join(chipDir, strings.TrimSuffix(name, "_input")+"_label")))
				if label == "" {
					label = chipName + " " + strings.TrimSuffix(name, "_input")
				}
				sensors.Temps = append(sensors.Temps, TempReading{Label: label, Celsius: celsius})
			case strings.HasPrefix(name, "fan") && strings.HasSuffix(name, "_input"):
				raw := readSmallFile(filepath.Join(chipDir, name))
				rpm, err := strconv.ParseFloat(strings.TrimSpace(raw), 64)
				if err != nil || rpm <= 0 {
					continue
				}
				label := strings.TrimSpace(
					readSmallFile(filepath.Join(chipDir, strings.TrimSuffix(name, "_input")+"_label")))
				if label == "" {
					label = chipName + " " + strings.TrimSuffix(name, "_input")
				}
				sensors.Fans = append(sensors.Fans, FanReading{Label: label, RPM: rpm})
			}
		}
	}
	sortSensors(&sensors)
	sensors.Available = len(sensors.Temps) > 0 || len(sensors.Fans) > 0
	return sensors
}

func sortSensors(sensors *Sensors) {
	sort.Slice(sensors.Temps, func(i, j int) bool {
		return sensors.Temps[i].Label < sensors.Temps[j].Label
	})
	sort.Slice(sensors.Fans, func(i, j int) bool {
		return sensors.Fans[i].Label < sensors.Fans[j].Label
	})
}

func readSmallFile(path string) string {
	data, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return string(data)
}

// kelvinTenthsToCelsius converts WMI MSAcpi_ThermalZoneTemperature units.
func kelvinTenthsToCelsius(value float64) float64 {
	return value/10 - 273.15
}
