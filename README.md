itsy32
==========

Dos32 backport of itsy forth by John Metcalf

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

I ported it to 32-bit DOS code. Sample session:

<pre>
nasm itsy32.asm -frdf
rdx itsy32.rdf

: say_hi 72 emit 105 emit 33 emit 10 emit ;
say_hi
Hi!
^C
</pre>
