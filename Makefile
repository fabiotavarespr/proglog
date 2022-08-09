PWD = $(shell pwd -L)
GOCMD=go
GOTEST=$(GOCMD) test
BIN_DIR = bin
PROTO_DIR = proto
SERVER_DIR = server
CLIENT_DIR = client
CONFIG_PATH=${PWD}/.proglog/

ifeq ($(OS), Windows_NT)
	SHELL := powershell.exe
	.SHELLFLAGS := -NoProfile -Command
	SHELL_VERSION = $(shell (Get-Host | Select-Object Version | Format-Table -HideTableHeaders | Out-String).Trim())
	OS = $(shell "{0} {1}" -f "windows", (Get-ComputerInfo -Property OsVersion, OsArchitecture | Format-Table -HideTableHeaders | Out-String).Trim())
	PACKAGE = $(shell (Get-Content go.mod -head 1).Split(" ")[1])
	CHECK_DIR_CMD = if (!(Test-Path $@)) { $$e = [char]27; Write-Error "$$e[31mDirectory $@ doesn't exist$${e}[0m" }
	HELP_CMD = Select-String "^[a-zA-Z_-]+:.*?\#\# .*$$" "./Makefile" | Foreach-Object { $$_data = $$_.matches -split ":.*?\#\# "; $$obj = New-Object PSCustomObject; Add-Member -InputObject $$obj -NotePropertyName ('Command') -NotePropertyValue $$_data[0]; Add-Member -InputObject $$obj -NotePropertyName ('Description') -NotePropertyValue $$_data[1]; $$obj } | Format-Table -HideTableHeaders @{Expression={ $$e = [char]27; "$$e[36m$$($$_.Command)$${e}[0m" }}, Description
	RM_F_CMD = Remove-Item -erroraction silentlycontinue -Force
	RM_RF_CMD = ${RM_F_CMD} -Recurse
	SERVER_BIN = ${SERVER_DIR}.exe
	CLIENT_BIN = ${CLIENT_DIR}.exe
else
	SHELL := bash
	SHELL_VERSION = $(shell echo $$BASH_VERSION)
	UNAME := $(shell uname -s)
	VERSION_AND_ARCH = $(shell uname -rm)
	ifeq ($(UNAME),Darwin)
		OS = macos ${VERSION_AND_ARCH}
	else ifeq ($(UNAME),Linux)
		OS = linux ${VERSION_AND_ARCH}
	else
    $(error OS not supported by this Makefile)
	endif
	PACKAGE = $(shell head -1 go.mod | awk '{print $$2}')
	CHECK_DIR_CMD = test -d $@ || (echo "\033[31mDirectory $@ doesn't exist\033[0m" && false)
	HELP_CMD = grep -E '^[a-zA-Z_-]+:.*?\#\# .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?\#\# "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
	RM_F_CMD = rm -f
	RM_RF_CMD = ${RM_F_CMD} -r
	SERVER_BIN = ${SERVER_DIR}
	CLIENT_BIN = ${CLIENT_DIR}
endif

.DEFAULT_GOAL := help
.PHONY: help
help: ## Show this help
	@${HELP_CMD}

about: ## Display info related to the build
	@echo "OS: ${OS}"
	@echo "Shell: ${SHELL} ${SHELL_VERSION}"
	@echo "Protoc version: $(shell protoc --version)"
	@echo "Go version: $(shell go version)"
	@echo "Go package: ${PACKAGE}"
	@echo "Openssl version: $(shell openssl version)"

grpc-install-mac: ## Install GRPC dependencies
	@brew install protobuf protoc-gen-go protoc-gen-go-grpc cfssl

grpc-check: ## Check if grpc has installed
	@protoc --version

tidy: ## Downloads go dependencies
	@$(GOCMD) mod tidy

fmt: tidy ## Run go fmt
	@$(GOCMD) fmt ./...

run-api: fmt ## Run api
	@$(GOCMD) run ./cmd/server/main.go

.PHONY: compile
compile: fmt ## Compile protobuf files
	protoc api/v1/*.proto \
		--go_out=. \
		--go_opt=paths=source_relative \
		--go-grpc_out=. \
		--go-grpc_opt=paths=source_relative \
		--proto_path=.

.PHONY: test
test: fmt clean-cache ## Launch tests
	@$(GOTEST) -race ./...

clean-cache: ## Clean cache
	@$(GOCMD) clean -testcache

.PHONY: init
init:  ## Config inital path
	mkdir -p ${CONFIG_PATH}

.PHONY: gencert
gencert:  ## auto-generate cert
	cfssl gencert \
		-initca scripts/test/ca-csr.json | cfssljson -bare ca

	cfssl gencert \
		-ca=ca.pem \
		-ca-key=ca-key.pem \
		-config=scripts/test/ca-config.json \
		-profile=server \
		scripts/test/server-csr.json | cfssljson -bare server

.PHONY: delcert
delcert: ## Remove auto-generate cert
	rm -rf ca-key.pem ca.csr ca.pem server-key.pem server.pem server.csr