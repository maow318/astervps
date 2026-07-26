VERSION ?= dev
OUT := dist
LDFLAGS := -s -w

build-all:
	mkdir -p $(OUT)
	GOOS=linux GOARCH=amd64 go build -ldflags "$(LDFLAGS)" -o $(OUT)/aster-agent-linux-amd64 .
	GOOS=linux GOARCH=arm64 go build -ldflags "$(LDFLAGS)" -o $(OUT)/aster-agent-linux-arm64 .
	GOOS=darwin GOARCH=arm64 go build -ldflags "$(LDFLAGS)" -o $(OUT)/aster-agent-darwin-arm64 .
