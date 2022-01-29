all: itsy32.exe

itsy32.exe: itsy32.rdf
	rlink dospe /s=256 /o=itsy32.exe itsy32.rdf

itsy32.rdf: itsy32.asm
        nasm itsy32.asm -f rdf
clean:
        del itsy32.rdf
        del itsy32.exe
