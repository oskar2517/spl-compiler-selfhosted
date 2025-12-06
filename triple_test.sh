#!/usr/bin/env bash
set -euo pipefail

### CONFIG #####################################################################

SRC_FILE="src/spl_compiler.spl"
PROCESSED_FILE="spl_compiler_processed.spl"
JAR_FILE="shadow-1.0-SNAPSHOT-all.jar"
STDLIB_OBJ="stdlib.o"

### PRETTY LOGGING #############################################################

if [ -t 1 ]; then
    COLOR_BLUE="\033[34m"
    COLOR_GREEN="\033[32m"
    COLOR_RED="\033[31m"
    COLOR_YELLOW="\033[33m"
    COLOR_BOLD="\033[1m"
    COLOR_RESET="\033[0m"
else
    COLOR_BLUE=""
    COLOR_GREEN=""
    COLOR_RED=""
    COLOR_YELLOW=""
    COLOR_BOLD=""
    COLOR_RESET=""
fi

log_step()   { printf "%b\n" "${COLOR_BLUE}${COLOR_BOLD}==> $*${COLOR_RESET}"; }
log_info()   { printf "%b\n" "${COLOR_YELLOW}[*] $*${COLOR_RESET}"; }
log_ok()     { printf "%b\n" "${COLOR_GREEN}[OK] $*${COLOR_RESET}"; }
log_error()  { printf "%b\n" "${COLOR_RED}[ERR] $*${COLOR_RESET}" >&2; }

trap 'log_error "Script failed (line $LINENO)."' ERR

### BUILD PIPELINE #############################################################

log_step "Preprocess source (${SRC_FILE})"
gcc -E -P -x c "${SRC_FILE}" -o "${PROCESSED_FILE}"
log_ok "Preprocessed source -> ${PROCESSED_FILE}"

log_step "Compile Stage 0 (Java -> NASM -> ELF)"
java -jar "${JAR_FILE}" "${PROCESSED_FILE}" --target x86 --headless -o stage0.nasm
nasm -f elf64 stage0.nasm -o stage0.o
gcc stage0.o "${STDLIB_OBJ}" -o stage0 -lSDL2 -no-pie
chmod +x stage0
log_ok "Built stage0 compiler (./stage0)"

log_step "Append NUL byte to processed source"
printf "\x00" >> "${PROCESSED_FILE}"
log_ok "Appended NUL byte to ${PROCESSED_FILE}"

log_step "Compile Stage 1 (stage0 -> NASM -> ELF)"
ulimit -s 32768
./stage0 < "${PROCESSED_FILE}" > stage1.nasm
nasm -f elf64 stage1.nasm -o stage1.o
gcc stage1.o "${STDLIB_OBJ}" -o stage1 -lSDL2 -no-pie
chmod +x stage1
log_ok "Built stage1 compiler (./stage1)"

log_step "Compile Stage 2 (stage1 -> NASM -> ELF)"
ulimit -s 32768
./stage1 < "${PROCESSED_FILE}" > stage2.nasm

### HASH CHECK (SHA-1) #########################################################

log_step "Compare stage1 and stage2 assembly (sha1)"

hash_stage1=$(sha1sum stage1.nasm | awk '{print $1}')
hash_stage2=$(sha1sum stage2.nasm | awk '{print $1}')

log_info "stage1: ${hash_stage1}"
log_info "stage2: ${hash_stage2}"

if [ "${hash_stage1}" = "${hash_stage2}" ]; then
    log_ok "Bootstrap check passed: stage1 and stage2 are identical."
    exit 0
else
    log_error "Bootstrap check FAILED: stage1 and stage2 differ."
    exit 1
fi
