//go:build !darwin

package main

import "strings"

func modelIdentifier() string { return "" }

func osPrettyName(platform, version string) string {
	if platform == "" {
		return version
	}
	return strings.ToUpper(platform[:1]) + platform[1:] + " " + version
}
