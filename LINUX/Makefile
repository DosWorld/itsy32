all: itsy-lin

itsy-lin: itsy-lin.asm
	nasm itsy-lin.asm -fbin -l itsy-lin.lst -o itsy-lin
	chmod +x itsy-lin
clean:
	rm itsy-lin.lst itsy-lin
