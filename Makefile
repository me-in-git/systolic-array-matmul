# Simulation with Icarus Verilog 12+.
#   make test         - build and run every testbench (fails on any FAIL/ERROR)
#   make run-<tb>     - run a single testbench, e.g. make run-tb_systolic
#   make clean

TESTS ?= tb_systolic
SRC   := $(wildcard rtl/*.sv)
BUILD := build

.PHONY: test clean

test: $(addprefix run-,$(TESTS))

run-%: $(BUILD)/%.vvp
	@echo "==> $*"
	@vvp -n $< | tee $(BUILD)/$*.log
	@! grep -qE "FAIL|ERROR:" $(BUILD)/$*.log
	@grep -qE "ALL PASS|: 0 error\(s\)" $(BUILD)/$*.log

$(BUILD)/%.vvp: $(SRC) tb/%.sv | $(BUILD)
	iverilog -g2012 -s $* -o $@ $(SRC) tb/$*.sv

$(BUILD):
	mkdir -p $@

clean:
	rm -rf $(BUILD)

# Re-run the testbench at several array sizes (checks results and 3N latency)
SWEEP_N ?= 2 3 4 5 6 8

.PHONY: sweep
sweep: | $(BUILD)
	@set -e; for n in $(SWEEP_N); do \
	  iverilog -g2012 -s tb_systolic -Ptb_systolic.N=$$n -o $(BUILD)/sweep.vvp $(SRC) tb/tb_systolic.sv; \
	  vvp -n $(BUILD)/sweep.vvp > $(BUILD)/sweep_$$n.log; \
	  ! grep -qE "FAIL|ERROR:" $(BUILD)/sweep_$$n.log; \
	  grep -qE "ALL PASS" $(BUILD)/sweep_$$n.log; \
	  echo "N=$$n: $$(grep -m1 -o '[0-9]* cycles from start' $(BUILD)/sweep_$$n.log), $$(grep -o '[0-9]* checks' $(BUILD)/sweep_$$n.log)"; \
	done
