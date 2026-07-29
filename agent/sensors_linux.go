//go:build linux

package main

func collectSensors() Sensors {
	return readHwmon("/sys/class/hwmon")
}
