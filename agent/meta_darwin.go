//go:build darwin

package main

import "syscall"

func modelIdentifier() string {
	value, err := syscall.Sysctl("hw.model")
	if err != nil {
		return ""
	}
	return value
}

func osPrettyName(platform, version string) string {
	return "macOS " + version
}
