# Flash a prebuilt release .elf onto the target with a Black Magic Probe.
# Self-contained: does not need the firmware source tree or ARM toolchain,
# only `arm-none-eabi-gdb` (or `gdb-multiarch`) on PATH.
#
# Usage:
#   make flash                        # flash the ELF named in target.json
#   make flash ELF=other_build.elf    # flash a specific ELF in this dir
#   make flash ELF=/path/to/other.elf # or anywhere else
#   make list                         # show available .elf files here
#   make verify                       # check ELF sha256 against target.json
#   make scan / scan-reset            # probe the SWD bus without flashing
#   make flash-reset                  # flash while holding the target in reset
#   make bmp-info                     # print Black Magic Probe firmware info
#
#   make flash BMP_PORT=/dev/ttyACM1        # override the probe's serial port
#   make flash BMP_PORT=\\.\COM31           # Windows COM10+ ports need \\.\COMx
#   make flash BMP_TARGET_POWER=0           # target has its own power supply
ifeq ($(OS),Windows_NT)
detected_OS := WIN
else
detected_OS := $(shell uname)
endif

# arm-none-eabi-gdb must be on PATH, or point GDB at a full path.
GDB		?= arm-none-eabi-gdb
SHA256SUM	?= sha256sum

ifeq ($(detected_OS),WIN)
BMP_PORT	?= \\.\COM30
else
BMP_PORT	?= /dev/ttyACM0
endif
BMP_SCAN		?= swdp_scan
BMP_TARGET		?= 1
# Lower SWD speed helps with low target voltage or longer wires.
BMP_FREQUENCY		?= 1000000
BMP_CONNECT_UNDER_RESET	?= 1
# 0 = externally powered target, 1 = enable target power from probe.
BMP_TARGET_POWER	?= 1

TARGET_JSON	?= target.json

# Pull version/part number out of target.json so the default ELF stays
# correct as new releases are dropped in, without editing this file.
PRODUCT_ID	:= $(shell sed -n 's/.*"product_id": *"\([^"]*\)".*/\1/p' $(TARGET_JSON))
VERSION		:= $(shell sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' $(TARGET_JSON))
PART_NUMBER	:= $(shell sed -n 's/.*"part_number": *"\([^"]*\)".*/\1/p' $(TARGET_JSON))
EXPECTED_SHA	:= $(shell sed -n 's/.*"elf_sha256": *"\([^"]*\)".*/\1/p' $(TARGET_JSON))

ELF	?= $(PRODUCT_ID)_v$(VERSION)_$(PART_NUMBER).elf

BMP_POWER_CMD	= $(if $(filter 1 y yes true on,$(BMP_TARGET_POWER)),-ex "monitor tpwr enable",)
BMP_FREQ_CMD	= $(if $(strip $(BMP_FREQUENCY)),-ex "monitor frequency $(BMP_FREQUENCY)",)
BMP_RESET_CMD	= $(if $(filter 1 y yes true on,$(BMP_CONNECT_UNDER_RESET)),-ex "monitor connect_rst enable",)

.DEFAULT_GOAL := flash
.PHONY: flash flash-reset scan scan-reset bmp-info verify list

list:
ifeq ($(detected_OS),WIN)
	@dir /b *.elf
else
	@ls -1 *.elf
endif

verify:
	@test -f "$(ELF)" || { echo "ELF not found: $(ELF)"; exit 1; }
	@test -n "$(EXPECTED_SHA)" || { echo "No elf_sha256 in $(TARGET_JSON)"; exit 1; }
	@echo "$(EXPECTED_SHA)  $(ELF)" | $(SHA256SUM) -c -

scan:
	@echo "BMP SCAN   $(BMP_PORT)"
	"$(GDB)" -nx --batch -ex "target extended-remote $(BMP_PORT)" $(BMP_POWER_CMD) $(BMP_FREQ_CMD) $(BMP_RESET_CMD) -ex "monitor $(BMP_SCAN)" -ex "quit"

scan-reset:
	@echo "BMP SCAN RESET   $(BMP_PORT)"
	"$(GDB)" -nx --batch -ex "target extended-remote $(BMP_PORT)" $(BMP_POWER_CMD) $(BMP_FREQ_CMD) -ex "monitor connect_rst enable" -ex "monitor $(BMP_SCAN)" -ex "quit"

bmp-info:
	@echo "BMP INFO   $(BMP_PORT)"
	"$(GDB)" -nx --batch -ex "target extended-remote $(BMP_PORT)" -ex "monitor" -ex "quit"

flash:
	@test -f "$(ELF)" || { echo "ELF not found: $(ELF) (set ELF=path/to/file.elf)"; exit 1; }
	@echo "BMP   $(BMP_PORT) $(ELF)"
	"$(GDB)" -nx --batch -ex "target extended-remote $(BMP_PORT)" $(BMP_POWER_CMD) $(BMP_FREQ_CMD) $(BMP_RESET_CMD) -ex "monitor $(BMP_SCAN)" -ex "attach $(BMP_TARGET)" -ex "load" -ex "compare-sections" -ex "kill" "$(ELF)"

flash-reset:
	$(MAKE) flash BMP_CONNECT_UNDER_RESET=1
