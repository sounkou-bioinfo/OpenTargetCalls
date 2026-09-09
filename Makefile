CARGO ?= cargo
LAKE ?= lake
PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin
INSTALL ?= install
BIN ?= target/release/opentargetcalls

.PHONY: all fmt test lint proof release smoke install clean

all: test proof

fmt:
	$(CARGO) fmt --check

test:
	$(CARGO) test --all-targets

lint:
	$(CARGO) clippy --all-targets -- -D warnings

proof:
	$(LAKE) build

release:
	$(CARGO) build --release

smoke: release
	$(BIN) targets --assay wes --validated-enrichment
	@set -eu; work=$$(mktemp -d); trap 'rm -rf "$$work"' 0; \
	$(BIN) hba \
		--assay wgs \
		--evidence examples/hba/evidence.synthetic.tsv \
		--hypotheses examples/hba/hypotheses.synthetic.tsv \
		--min-margin 10 \
		--certificate "$$work/hba.cert"; \
	grep -qx 'schema=opentargetcalls-certificate-v1' "$$work/hba.cert"; \
	$(BIN) verify --certificate "$$work/hba.cert"

install: release
	$(INSTALL) -d $(BINDIR)
	$(INSTALL) -m 0755 $(BIN) $(BINDIR)/opentargetcalls

clean:
	$(CARGO) clean
	$(LAKE) clean
