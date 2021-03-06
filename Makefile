SELF_DIR := $(dir $(lastword $(MAKEFILE_LIST)))
include $(SELF_DIR)/.ci/common.mk

SHELL=/bin/bash -o pipefail

html_report          := coverage.html
test                 := .ci/test-cover.sh
test_ci_integration  := .ci/test-integration.sh
convert-test-data    := .ci/convert-test-data.sh
coverfile            := cover.out
coverage_xml         := coverage.xml
junit_xml            := junit.xml
test_log             := test.log
metalint_check       := .ci/metalint.sh
metalint_config      := .metalinter.json
metalint_exclude     := .excludemetalint
m3collector_package  := github.com/m3db/m3collector
gopath_prefix        := $(GOPATH)/src
vendor_prefix        := vendor
mockgen_package      := github.com/golang/mock/mockgen
mocks_output_dir     := generated/mocks/mocks
mocks_rules_dir      := generated/mocks
auto_gen             := .ci/auto-gen.sh
license_dir          := .ci/uber-licence
license_node_modules := $(license_dir)/node_modules
package_root         := github.com/m3db/m3collector


BUILD           := $(abspath ./bin)
LINUX_AMD64_ENV := GOOS=linux GOARCH=amd64 CGO_ENABLED=0

.PHONY: setup
setup:
	@echo "+ $@"
	mkdir -p $(BUILD)

.PHONY: metalint
metalint: install-metalinter install-linter-badtime
	@echo "+ $@"
	@($(metalint_check) $(metalint_config) $(metalint_exclude) && echo "metalinted successfully!") || (echo "metalinter failed" && exit 1)

.PHONY: install-licence-bin
install-license-bin: install-vendor
	@echo "+ $@ : Installing node modules"
	git submodule update --init --recursive
	[ -d $(license_node_modules) ] || (cd $(license_dir) && npm install)

.PHONY: install-mockgen
install-mockgen: install-vendor
	@echo "+ $@"
	glide install

.PHONY: mock-gen
mock-gen: install-mockgen install-license-bin install-util-mockclean
	@echo Generating mocks
	PACKAGE=$(package_root) $(auto_gen) $(mocks_output_dir) $(mocks_rules_dir)

.PHONY: mock-gen-no-deps
mock-gen-no-deps:
	@echo "+ $@ : Generating mocks"
	PACKAGE=$(package_root) $(auto_gen) $(mocks_output_dir) $(mocks_rules_dir)

.PHONY: test-internal
test-internal:
	@echo "+ $@"
	@which go-junit-report > /dev/null || go get -u github.com/sectioneight/go-junit-report
	$(test) $(coverfile) | tee $(test_log)

.PHONY: test-integration
test-integration:
	@echo "+ $@"
	go test -v -tags=integration ./integration

.PHONY: test-xml
test-xml: test-internal
	@echo "+ $@"
	go-junit-report < $(test_log) > $(junit_xml)
	gocov convert $(coverfile) | gocov-xml > $(coverage_xml)
	@$(convert-test-data) $(coverage_xml)
	@rm $(coverfile) &> /dev/null

.PHONY: test
test: test-internal
	@echo "+ $@"
	gocov convert $(coverfile) | gocov report

.PHONY: testhtml
testhtml: test-internal
	@echo "+ $@"
	gocov convert $(coverfile) | gocov-html > $(html_report) && open $(html_report)
	@rm -f $(test_log) &> /dev/null

.PHONY: test-ci-unit
test-ci-unit: test-internal
	@echo "+ $@"
	@which goveralls > /dev/null || go get -u -f github.com/mattn/goveralls
	goveralls -coverprofile=$(coverfile) -service=travis-ci || echo -e "\x1b[31mCoveralls failed\x1b[m"

.PHONY: test-ci-integration
test-ci-integration:
	@echo "+ $@"
	$(test_ci_integration)

.PHONY: clean
clean:
	@echo "+ $@"
	rm -f *.html *.xml *.out *.test
	go clean .

.PHONY: all
all: clean metalint test-ci-unit test-ci-integration
	@echo Made all successfully

.DEFAULT_GOAL := all
