all: ITSY-WIN.EXE

ITSY-WIN.EXE: ITSY-WIN.ASM
	nasm ITSY-WIN.ASM -f win32 -o ITSY-WIN.OBJ
	i686-w64-mingw32-ld ITSY-WIN.OBJ -lkernel32 -o ITSY-WIN.EXE -e _main
	strip ITSY-WIN.EXE
clean:
	del ITSY-WIN.OBJ
