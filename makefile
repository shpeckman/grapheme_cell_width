# Makefile
CRYSTAL         ?= crystal
PYTHON          ?= python3
UNICODE_VERSION ?= 17.0.0

SOURCES := $(wildcard src/grapheme_cell_width.cr src/grapheme_cell_width/*.cr)

.PHONY: all setup spec spec-debug bench bench-width bench-grapheme verify \
        gen-tables gen-tests docs format format-check clean clean-full

all: setup

setup: gen-tables gen-tests spec

spec:
	$(CRYSTAL) spec

spec-debug:
	$(CRYSTAL) spec -Dgrapheme_cell_width_debug

bench: bench-width bench-grapheme

bench-width:
	$(CRYSTAL) run --release bench/bench.cr

bench-grapheme:
	$(CRYSTAL) run --release bench/grapheme_bench.cr

widths.tsv: $(SOURCES) tools/dump_widths.cr
	$(CRYSTAL) run tools/dump_widths.cr -- $@

verify: widths.tsv
	$(PYTHON) tools/verify.py widths.tsv

gen-tables:
	$(CRYSTAL) run tools/gen_tables.cr -- --version $(UNICODE_VERSION)

gen-tests:
	$(CRYSTAL) run tools/gen_grapheme_tests.cr -- --version $(UNICODE_VERSION)

docs:
	$(CRYSTAL) docs

format:
	$(CRYSTAL) tool format src spec bench tools

format-check:
	$(CRYSTAL) tool format --check src spec bench tools

clean:
	rm -f widths.tsv
	rm -rf docs

clean-full: clean
	rm -rf lib bin .shards
	rm -f shard.lock
	rm -f src/grapheme_cell_width/grapheme_tables.cr src/grapheme_cell_width/tables.cr spec/fixtures/GraphemeBreakTest.txt