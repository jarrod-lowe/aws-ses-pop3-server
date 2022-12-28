test: out/pop3-server-amd64
	go test -race -v ./...

out/pop3-server-amd64: go.mod pkg/*/*.go
	CGO_ENABLED=0 GOARCH=amd64 GOOS=linux go build -o $@

out/pop3-server-arm64: go.mod pkg/*/*.go
	CGO_ENABLED=0 GOARCH=arm64 GOOS=linux go build -o $@
