itsy32 (win32, linux, osx, dos, dpmi)
==========

ITSY Forth by John Metcalf

John Metcalf (http://www.retroprogramming.com/) implemented minimal forth system:
<ul>
<li>http://www.retroprogramming.com/2012/03/itsy-forth-1k-tiny-compiler.html
<li>http://www.retroprogramming.com/2012/04/itsy-forth-dictionary-and-inner.html
<li>http://www.retroprogramming.com/2012/04/itsy-forth-primitives.html
<li>http://www.retroprogramming.com/2012/06/itsy-forth-compiler.html
<li>http://www.retroprogramming.com/2012/09/itsy-documenting-bit-twiddling-voodoo.html
</ul>
Resulting binary has very impressive size (978 bytes) and can be used to bootstrap complete forth system.

Original itsy code is producing .com files and can be found in "msdos" directory of this repository.

kt97679 ported it to 32-bit linux code - "LINIX" directory.

DylanMc ported it to MacOS (also 32 bit) - "OSX" directory. Should move to any BSD pretty easily.

I am ported it to 32-bit DOS code ("DPMI" directory) and Win32 ("WIN32" directory).

Sample session:
<pre>
nasm itsy32.asm -f rdf
rlink dospe /s=256 /o=itsy32.exe itsy32.rdf
itsy32.exe

: say_hi 72 emit 105 emit 33 emit 10 emit ;
say_hi
Hi!
^C
</pre>

Dependency:
==========

Required linker RLINK from https://github.com/DosWorld/rtools/

License
==========

The license is a simplified CC BY ("use as you wish with attribution").
