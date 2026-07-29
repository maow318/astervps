//go:build windows

package main

import (
	"strconv"
	"strings"
)

// Windows exposes ACPI thermal zones through WMI; consumer boards frequently
// report nothing (or access denied), which degrades to an empty section.
// Fan telemetry needs a kernel driver, so it is intentionally out of scope.
func collectSensors() Sensors {
	sensors := emptySensors()
	output, err := runCommand(execTimeout, "powershell",
		"-NoProfile", "-NonInteractive", "-Command",
		"Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature | ForEach-Object { \"$($_.InstanceName)`t$($_.CurrentTemperature)\" }")
	if err != nil {
		return sensors
	}
	sensors.Temps = parseThermalZones(output)
	sortSensors(&sensors)
	sensors.Available = len(sensors.Temps) > 0
	return sensors
}

func parseThermalZones(output string) []TempReading {
	temps := make([]TempReading, 0)
	for _, line := range strings.Split(output, "\n") {
		parts := strings.Split(strings.TrimSpace(line), "\t")
		if len(parts) != 2 {
			continue
		}
		raw, err := strconv.ParseFloat(strings.TrimSpace(parts[1]), 64)
		if err != nil {
			continue
		}
		celsius := kelvinTenthsToCelsius(raw)
		if celsius <= 0 || celsius > 150 {
			continue
		}
		label := strings.TrimSpace(parts[0])
		if label == "" {
			label = "Thermal zone"
		}
		temps = append(temps, TempReading{Label: label, Celsius: celsius})
	}
	return temps
}
