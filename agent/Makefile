VERSION ?= dev
OUT := dist

build-all:
	mkdir -p $(OUT)
	GOOS=linux GOARCH=amd64 go build -o $(OUT)/aster-agent-linux-amd64 .
	GOOS=linux GOARCH=arm64 go build -o $(OUT)/aster-agent-linux-arm64 .
	GOOS=darwin GOARCH=arm64 go build -o $(OUT)/aster-agent-darwin-arm64 .
