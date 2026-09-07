# Makefile
CRYSTAL         ?= crystal
PYTHON          ?= python3
UNICODE_VERSION ?= 17.0.0

SOURCES := $(wildcard src/grapheme_cell_width.cr src/grapheme_cell_width/*.cr)

.PHONY: all setup spec spec-debug bench bench-width bench-grapheme verify \
        gen-tables docs format format-check clean clean-full

all: gen-tables verify

gen-tables:
	@echo -e "\n==> Generating width and grapheme tables for Unicode $(UNICODE_VERSION)..."
	@$(CRYSTAL) run tools/gen_tables.cr -- --version $(UNICODE_VERSION)
	@echo -e "\n==> Generating grapheme break tests..."
	@$(CRYSTAL) run tools/gen_grapheme_tests.cr -- --version $(UNICODE_VERSION)

spec:
	@echo -e "\n==> Running specs..."
	@$(CRYSTAL) spec

spec-debug:
	@echo -e "\n==> Running specs (with debug)..."
	@$(CRYSTAL) spec -Dgrapheme_cell_width_debug

bench: bench-width bench-grapheme

bench-width:
	@echo -e "\n==> Running width benchmarks..."
	@$(CRYSTAL) run --release bench/bench.cr

bench-grapheme:
	@echo -e "\n==> Running grapheme benchmarks..."
	@$(CRYSTAL) run --release bench/grapheme_bench.cr

widths.tsv: $(SOURCES) tools/dump_widths.cr
	@echo -e "\n==> Dumping widths to widths.tsv..."
	@$(CRYSTAL) run tools/dump_widths.cr -- $@

verify: widths.tsv
	@echo -e "\n==> Verifying against Python unicodedata..."
	@echo "    (Note: unicodedata2 is needed; install via 'pip install unicodedata2')"
	@$(PYTHON) tools/verify.py widths.tsv $(UNICODE_VERSION)

clean:
	@echo -e "\n==> Cleaning build artifacts..."
	@rm -f widths.tsv
	@rm -rf docs

clean-full: clean
	@echo -e "\n==> Cleaning all artifacts..."
	@rm -rf lib bin .shards
	@rm -f shard.lock
	@rm -f src/grapheme_cell_width/grapheme_tables.cr src/grapheme_cell_width/tables.cr spec/fixtures/GraphemeBreakTest.txt