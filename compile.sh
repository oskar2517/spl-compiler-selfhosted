#!/bin/sh

gcc -E -P -x c src/spl_compiler.spl -o spl_compiler_processed.spl
java -jar shadow-1.0-SNAPSHOT-all.jar spl_compiler_processed.spl --target x86 --headless -o spl_compiler.nasm
nasm -f elf64 spl_compiler.nasm -o spl_compiler.o
gcc spl_compiler.o stdlib.o -o spl_compiler -lSDL2 -no-pie
chmod +x spl_compiler
ulimit -s 32768
cat input.spl | ./spl_compiler