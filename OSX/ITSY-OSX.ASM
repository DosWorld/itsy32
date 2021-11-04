; Itsy Forth
;    Written by John Metcalf
;    Commentary by John Metcalf and Mike Adams
;    Translated to DOS-DPMI by github user DosWorld
;    Translated to Linux by github user kt97679
;    Translated to MacOS X by Dylan McNamee
;
; nasm -g -f macho itsy-osx.asm && ld -macosx_version_min 10.5.0 -o itsy itsy-osx.o
;
; simple session:
; ./itsy
; : hi 72 emit 101 emit 108 emit 108 emit 111 emit 10 emit ;
; hi
; Hello
; ^C
; TODOs:
;   fix seg fault on Ctrl-D
;   fix that 72 101 108 108 111 emit emit emit emit emit doesn't work.
;   build up Forth control structures - if then else, do while, etc.
;   implement string functions num->string, string literals, ., ."
;   hard-code the mach-o header (as with Linux version) so ld doesn't add 8K of header.
;--------------------------------------------------------------------------
; Implementation notes:
;
; Register Usage:
;    sp - data stack pointer.
;    bp - return stack pointer.
;    si - Forth instruction pointer.
;    di - pointer to current XT (CFA of word currently being executed).
;    bx - TOS (top of data stack). The top value on the data stack is not
;         actually kept on the CPU's data stack. It's kept in the BX register.
;         Having it in a register like this speeds up the operation of
;         the primitive words. They don't have to take the time to pull a
;         value off of the stack; it's already in a register where it can
;         be used right away!
;    ax, cd, dx - Can all be freely used for processing data. The other
;         registers can still be used also, but only with caution. Their
;         contents must be pushed to the stack and then restored before
;         exiting from the word or calling any other Forth words. LOTS of
;         potential for program crashes if you don't do this correctly.
;         The notable exception is the DI register, which can (and is, below)
;         used pretty freely in assembly code, since the concept of a pointer
;         to the current CFA is rather irrelevant in assembly.
;
;
; Structure of an Itsy word definition:
;     # of
;    Bytes:   Description:
;    ------   ---------------------------------------------------------
;      2      Link Field. Contains the address of the link field of the
;                definition preceding this one in the dictionary. The link
;                field of the first def in the dictionary contains 0.
;    Varies   Name Field. The first byte of the name field contains the length
;                of the name; succeeding bytes contain the ASCII characters of
;                the name itself. If the high bit of the length is set, the
;                definition is tagged as being an "immediate" word.
;      2      Code Field. Contains the address of the executable code for
;                the word. For primitives, this will likely be the address
;                of the word's own data field. Note that the header creation
;                macros automatically generate labels for the code field
;                addresses of the words they're used to define, though the
;                CFA labels aren't visible in the code shown below. The
;                assembler macros create labels, known as "execution tags"
;                or XTs, for the code field of each word.
;    Varies   Data Field. Contains either a list of the code field addresses
;                of the words that make up this definition, or assembly-
;                language code for primitives, or numeric data for variables
;                 and constants and such.

%define link 0
%define immediate 080h

%macro head 4
%%link dd link
%define link %%link
%strlen %%count %1
        db       %3 + %%count, %1
        xt_      %+ %2 dd %4
        yt_      %+ %2:
%endmacro

%macro primitive 2-3 0
        head     %1, %2, %3, $ + 4
%endmacro

%macro colon 2-3 0
        head     %1, %2, %3, docolon
%endmacro

%macro variable 3
        head     %1, %2, 0, dovar
        val_     %+ %2 dd %3
%endmacro

%define MEMSIZE 1048576
%define TIBSIZE 80
%define STACKSIZE 4096
%define TIBPTR fstack + MEMSIZE - TIBSIZE ; fheap ;TEXTORG + MEMSIZE - TIBSIZE
%define SP0 TIBPTR - 4
%define RP0 SP0 - STACKSIZE
%define DSTACK RP0 - STACKSIZE

        BITS     32

        section  .data

; -------------------
; System Variables
; -------------------

; state - ( -- addr ) true = compiling, false = interpreting
        variable 'state', state, 0

; >in - ( -- addr ) next character in input buffer
        variable '>in', to_in, 0

; #tib - ( -- addr ) number of characters in the input buffer
        variable '#tib', number_t_i_b, 0

; dp - ( -- addr ) first free cell in the dictionary
        variable 'dp', dp, DSTACK

; base - ( -- addr ) number base
        variable 'base', base, 10

; last - ( -- addr ) the last word to be defined
; NOTE: The label "final:" must be placed immediately before
; the last word defined in this file. If new words are added,
; make sure they're either added before the "final:" label
; or the "final:" label is moved to the position immediately
; before the last word added.
        variable 'last', last, final

; tib - ( -- addr ) address of the input buffer
        variable 'tib', t_i_b, TIBPTR

        section  .text
        global   start
start:
        jmp      xt_abort+4

; this is a separate routine to fix up the stack before the syscall
_mysyscall:
        int      80h
        ret

; execute - ( xt -- ) call the word at xt
        primitive        'execute', execute
        mov      eax, ebx        ; eax is important here, it is used by docolon and dovar
        pop      ebx
        jmp      dword[eax]

; -------------------
; Initialisation
; -------------------

; abort - ( -- ) initialise Itsy then jump to interpret
        primitive        'abort', abort
        mov      eax, dword[val_number_t_i_b]
        mov      dword[val_to_in],eax
        xor      ebp, ebp
        mov      dword[val_state],ebp
        mov      esp, SP0
        mov      ebp, RP0
        mov      esi, xt_interpret + 4
        jmp      next

; -------------------
; Compilation
; -------------------

; , - ( x -- ) compile x to the current definition.
;    Stores the number on the stack to the memory location currently
;    pointed to by dp.
        primitive        ',', comma
        xchg     eax, ebx
        mov      ebx, val_dp
        mov      edi,[ebx]
        stosd
        mov      [ ebx],edi
        pop      ebx
        jmp      next

; lit - ( -- ) push the value in the cell straight after lit.
;   lit is the word that is compiled into a definition when you put a
;   "literal" number in a Forth definition. When your word is compiled,
;   the CFA of lit gets stored in the definition followed immediately
;   by the value of the number you put into the code. At run time, lit
;   pushes the value of your number onto the stack.
        primitive        'lit', lit
        push     ebx
        lodsd
        xchg     eax, ebx
        jmp      next

; -------------------
; Stack
; -------------------

; rot - ( x y z -- y z x ) rotate x, y and z.
;   Standard Forth word that extracts number 3rd from the top of the stack
;   and puts it on the top, effectively rotating the top 3 values.
        primitive        'rot', rote
        pop      edx
        pop      eax
        push     edx
        push     ebx
        xchg     eax, ebx
        jmp      next

; drop - ( x -- ) remove x from the stack.
        primitive        'drop', drop
        pop      ebx
        jmp      next

; dup - ( x -- x x ) add a copy of x to the stack
        primitive        'dup', dupe
        push     ebx
        jmp      next

; # swap - ( x y -- y x ) exchange x and y
        primitive        'swap', swap
        xchg     ebx,[esp]
        jmp      next

; -------------------
; Maths / Logic
; -------------------

; + - ( x y -- z) calculate z=x+y then return z
        primitive        '+', plus
        pop      eax
        add      ebx, eax
        jmp      next

        primitive        '=', equals
        pop      eax
        sub      ebx, eax
        sub      ebx, 1
        sbb      ebx, ebx
        jmp      next

        primitive        '@', fetch
        mov      ebx, dword[ebx]
        jmp      next

        primitive        '!', store
        pop      dword[ebx]
        pop      ebx
        jmp      next

; break ( -- ) trigger a breakpoint for debugging
        primitive        'break', break
        int      3
        jmp      next

; ----------------------
; The inner interpteter (buried in here):
; ----------------------
        primitive        'exit', exit
        xchg     ebp, esp
        pop      esi
        xchg     ebp, esp
next:
        lodsd    ; funny that the key part of the inner interpreter is buried here
        jmp      dword[eax]      ; eax is later used by docolon and dovar

; -------------------
; Flow Control
; -------------------

; 0branch - ( x -- ) jump if x is zero
; This is the primitive word that's compiled as the runtime code in
; an IF...THEN statement. The number compiled into the word's definition
; immediately after 0branch is the address of the word in the definition
; that we're branching to. That address gets loaded into the instruction
; pointer. In essence, this word sees a false flag (i.e. a zero) and
; then jumps over the words that comprise the "do this if true" clause
; of an IF...ELSE...THEN statement.

        primitive        '0branch', zero_branch
        lodsd
        test     ebx, ebx
        jne      zerob_z
        xchg     eax, esi
zerob_z:
        pop      ebx
        jmp      next

; branch - ( addr -- ) unconditional jump
; This is one of the pieces of runtime code that's compiled by
; BEGIN/WHILE/REPEAT, BEGIN/AGAIN, and BEGIN/UNTIL loops. As with 0branch,
; the number compiled into the dictionary immediately after the branch is
; the address of the word in the definition that we're branching to.
        primitive        'branch', branch
        mov      esi, dword[esi]
        jmp      next

; -----------------------
; Terminal Input / Output
; -----------------------

; accept - ( addr len -- len2 ) read a string from the terminal
; accept reads a string of characters from the terminal. The string
; is stored at addr and can be up to len characters long.
; accept returns the actual length of the string.

; converted Linux syscall to MacOS syscall
; see: https://filippo.io/making-system-calls-from-assembly-in-mac-os-x/
; main difference is Linux passes syscall params in registers, MacOS / BSD does it on the stack
; ( addr len -- len_read )
        primitive        'accept', accept
; ebx has the # bytes to read
; stdin is handle 0
; top of stack has the buffer address
        pop      ecx             ; save buffer
        push     ebx             ; count
        push     ecx             ; buffer
        push     0               ; stdin
        mov      eax, 0x3        ; sys_read
        call     _mysyscall
        add      esp, 12         ; discard args
        xchg     ebx, eax        ; MacOS / BSD - eax after sys_read contains number of bytes read (negative number means error), let's move it to TOS
        dec      ebx             ; last char is CR
        push     ebx
        jmp      next

; ( char -- ) emit a character to the terminal
        primitive        'emit', emit
; char to print is in ebx
        push     ebx             ; needs to be in memory - why not stack?
        mov      ebx, esp        ; save stack pointer (pointing at our char)
        push     1               ; count
        push     ebx             ; buffer (into the stack)
        push     1               ; stdout
        mov      eax, 0x4        ; sys_write
        call     _mysyscall
aftemt:
        add      esp, 16         ; reset stack
        pop      ebx             ; TOS goes in ebx
        jmp      next

; -------------------
; String
; -------------------

; count - ( addr -- addr2 len )
; count is given the address of a "counted string" (like the name field of a
; word definition in Forth, with the first byte being the number of
; characters in the string and immediately followed by the characters
; themselves). It returns the length of the string and a pointer to the
; first actual character in the string.
        primitive        'count', count
        movzx    eax, byte[ebx]
        inc      ebx
        push     ebx
        mov      ebx, eax
        jmp      next

        primitive        '>number', to_number
        pop      edi
        pop      ecx
        pop      eax
to_numl:
        test     ebx, ebx
        je       to_numz
        push     eax
        movzx    eax, byte[edi]
        cmp      al, 'a'
        jc       to_nums
        sub      al, 32
to_nums:
        cmp      al, '9' + 1
        jc       to_numg
        cmp      al, 'A'
        jc       to_numh
        sub      al, 7
to_numg:
        sub      al, 48
        cmp      al, byte[val_base]
        jnc      to_numh
        xchg     eax, edx
        pop      eax
        push     edx
        xchg     eax, ecx
        mul      dword[val_base]
        xchg     eax, ecx
        mul      dword[val_base]
        add      ecx, edx
        pop      edx
        add      eax, edx
        dec      ebx
        inc      edi
        jmp      to_numl
to_numz:
        push     eax
to_numh:
        push     ecx
        push     edi
        jmp      next

; word - ( char -- addr ) parse the next word in the input buffer
; word scans the "terminal input buffer" (whose address is given by the
; system constant tib) for words to execute, starting at the current
; address stored in the input buffer pointer >in. The character on the
; stack when word is called is the one that the code will look for as
; the separator between words. 999 times out of 1000,; this is going to
; be a space.
        primitive        'word', word
        mov      edi, dword[val_dp]
        push     edi
        mov      edx, ebx
        mov      ebx, dword[val_t_i_b]
        mov      ecx, ebx
        add      ebx, dword[val_to_in]
        add      ecx, dword[val_number_t_i_b]
wordf:
        cmp      ecx, ebx
        je       wordz
        mov      al, byte[ebx]
        inc      ebx
        cmp      al, dl
        je       wordf
wordc:
        inc      edi
        mov      byte[edi],al
        cmp      ecx, ebx
        je       wordz
        mov      al, byte[ebx]
        inc      ebx
        cmp      al, dl
        jne      wordc
wordz:
        mov      byte[edi + 1],32
        mov      eax, dword[val_dp]
        xchg     eax, edi
        sub      eax, edi
        mov      byte[edi],al
        sub      ebx, dword[val_t_i_b]
        mov      dword[val_to_in],ebx
        pop      ebx
        jmp      next

; -----------------------
; Dictionary Search
; -----------------------

; find - ( addr -- addr2 flag ) look up word in the dictionary
; find looks in the Forth dictionary for a word with the name given in the
; counted string at addr. One of the following will be returned:
;   flag =  0, addr2 = counted string --> word was not found
;   flag =  1, addr2 = call address   --> word is immediate
;   flag = -1, addr2 = call address   --> word is not immediate
        primitive        'find', find
        mov      edi, val_last
findl:
        push     edi
        push     ebx
        movzx    ecx, byte[ebx]
        inc      ecx
findc:
        mov      al, byte[edi + 4]
        and      al, 07Fh
        cmp      al, byte[ebx]
        je       findm
        pop      ebx
        pop      edi
        mov      edi, dword[edi]
        test     edi, edi
        jne      findl
findnf:
        push     ebx
        xor      ebx, ebx
        jmp      next
findm:
        inc      edi
        inc      ebx
        loop     findc
        pop      ebx
        pop      edi
        xor      ebx, ebx
        inc      ebx
        lea      edi,[edi + 4]
        mov      al, byte[edi]
        test     al, 080h
        jne      findi
        neg      ebx
findi:
        and      eax, 31
        add      edi, eax
        inc      edi
        push     edi
        jmp      next

; -----------------------
; Colon Definition
; -----------------------

; : - ( -- ) define a new Forth word, taking the name from the input buffer.
; Ah! We've finally found a word that's actually defined as a Forth colon
; definition rather than an assembly language routine! Partly, anyway; the
; first part is Forth code, but the end is the assembly language run-time
; routine that, incidentally, executes Forth colon definitions. Notice that
; the first part is not a sequence of opcodes, but rather is a list of
; code field addresses for the words used in the definition. In each code
; field of each defined word is an "execution tag", or "xt", a pointer to
; the runtime code that executes the word. In a Forth colon definition, this
; is going to be a pointer to the docolon routine we see in the second part
; of the definition of colon itself below.
        colon    ':', colon
        dd       xt_lit, -1
        dd       xt_state
        dd       xt_store
        dd       xt_create
        dd       xt_do_semi_code

docolon:
        xchg     ebp, esp
        push     esi
        xchg     ebp, esp
        lea      esi,[eax + 4]   ; eax value is set by next
        jmp      next

; ; - ( -- ) complete the Forth word being compiled
        colon    ';', semicolon, immediate
        dd       xt_lit, xt_exit
        dd       xt_comma
        dd       xt_lit, 0
        dd       xt_state
        dd       xt_store
        dd       xt_exit

; -----------------------
; Headers
; -----------------------

; create - ( -- ) build a header for a new word in the dictionary, taking
; the name from the input buffer - a runtime version of 'primitive'
        colon    'create', create
        dd       xt_dp, xt_fetch
        dd       xt_last, xt_fetch
        dd       xt_comma
        dd       xt_last, xt_store
        dd       xt_lit, 32
        dd       xt_word
        dd       xt_count
        dd       xt_plus
        dd       xt_dp, xt_store
        dd       xt_lit, 0
        dd       xt_comma
        dd       xt_do_semi_code

dovar:
        push     ebx
        lea      ebx,[eax + 4]   ; eax value is set by next
        jmp      next

; # (;code) - ( -- ) replace the xt of the word being defined with a pointer
; to the code immediately following (;code)
; The idea behind this compiler word is that you may have a word that does
; various compiling/accounting tasks that are defined in terms of Forth code
; when its being used to compile another word, but afterward, when the new
; word is executed in interpreter mode, you want your compiling word to do
; something else that needs to be coded in assembly. (;code) is the word that
; says, "Okay, that's what you do when you're compiling, but THIS is what
; you're going to do while executing, so look sharp, it's in assembly!"
; Somewhat like the word DOES>, which is used in a similar manner to define
; run-time code in terms of Forth words.
        primitive        '(;code)', do_semi_code
        mov      edi, dword[val_last]
        mov      al, byte[edi + 4]
        and      eax, 31
        add      edi, eax
        mov      dword[edi + 5],esi
        xchg     ebp, esp
        pop      esi
        xchg     esp, ebp
        jmp      next

; -----------------------
; Constants
; -----------------------

; constant - ( x -- ) create a new constant with the value x, taking the name
; from the input buffer
        colon    'constant', constant
        dw       xt_create       ; Create the constant's header.
        dw       xt_comma        ; Store the constant's value into the word's
; data field.
        dw       xt_do_semi_code ; Write, into the code field of the header we just
; created, the address that immediately follows
; this statement: the address of the doconst
; routine, which is the code that's responsible
; for pushing onto the stack the value that's
; contained in the data field of the word whose
; header we just created when that word is
; invoked.
doconst:
        push     bx              ; Push the stack down.
        mov      bx, word[di+2]  ; DI should be pointing to the constant's code
; field. Load into the top of the stack the
; value 2 bytes further down from the code field,
; i.e. the constant's actual value.
        jmp      next            ;

; -----------------------
; Outer Interpreter
; -----------------------

; -------------------------------------------------------
; NOTE! The following line with the final: label MUST be
; immediately before the final word definition!
; -------------------------------------------------------

final:

        colon    'interpret', interpret
interpt:
        dd       xt_number_t_i_b
        dd       xt_fetch
        dd       xt_to_in
        dd       xt_fetch
        dd       xt_equals
        dd       xt_zero_branch
        dd       intpar
        dd       xt_t_i_b
        dd       xt_fetch
        dd       xt_lit, 50
        dd       xt_accept
        dd       xt_number_t_i_b
        dd       xt_store
        dd       xt_lit, 0
        dd       xt_to_in
        dd       xt_store
intpar:
        dd       xt_lit, 32      ; find a " "
        dd       xt_word
        dd       xt_find         ; is it in the dictionary?
        dd       xt_dupe
        dd       xt_zero_branch
        dd       intnf
        dd       xt_state
        dd       xt_fetch
        dd       xt_equals
        dd       xt_zero_branch
        dd       intexc
        dd       xt_comma
        dd       xt_branch
        dd       intdone
intexc:
        dd       xt_execute      ; found immediate word - execute it, then loop
        dd       xt_branch
        dd       intdone
intnf:
        dd       xt_dupe         ; not a forth word - is it a number?
        dd       xt_rote
        dd       xt_count
        dd       xt_to_number
        dd       xt_zero_branch
        dd       intskip
        dd       xt_state        ; conversion error:
        dd       xt_fetch        ; branch on State (interpreting vs compiling)
        dd       xt_zero_branch  ; interpreting -> loop
        dd       intnc
        dd       xt_last         ; compiling -> orderly shutdown
        dd       xt_fetch
        dd       xt_dupe
        dd       xt_fetch
        dd       xt_last
        dd       xt_store
        dd       xt_dp
        dd       xt_store
intnc:
        dd       xt_abort
intskip:
        dd       xt_drop
        dd       xt_drop
        dd       xt_state
        dd       xt_fetch
        dd       xt_zero_branch
        dd       intdone
        dd       xt_lit
        dd       xt_lit
        dd       xt_comma
        dd       xt_comma
intdone:
        dd       xt_branch
        dd       interpt
        dd       xt_abort

        colon    'testitsymac', testitsymac
dotest:
        dd       xt_t_i_b
        dd       xt_fetch
        dd       xt_lit, 1
        dd       xt_accept
looper:
        dd       xt_lit, 50
        dd       xt_lit, 50
        dd       xt_emit
        dd       dotest
freemem:

        section  .bss
fstack:
        resb     16000 + MEMSIZE
; rstack: resb 2048
; fheap:  resb 2048
; astack:  resb 2048
; dstack:  resb 2048

        filesize equ $ - $$
