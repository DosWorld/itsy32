; Itsy Forth
;    Written by John Metcalf
;    Commentary by John Metcalf and Mike Adams
;    Translated to Win32 by github user DosWorld
;    Translated to DOS-DPMI by github user DosWorld
;    Translated to Linux by github user kt97679
;    Translated to MacOS X by Dylan McNamee
;
; nasm ITSY-WIN.ASM -f win32 -o ITSY-WIN.OBJ
; i686-w64-mingw32-ld ITSY-WIN.OBJ -lkernel32 -o ITSY-WIN.EXE -e _main
; strip ITSY-WIN.EXE

        BITS     32
        use32

        global   _main
        extern   _GetStdHandle@4
        extern   _ExitProcess@4

        extern   _ReadConsoleA@20
        extern   _WriteConsoleA@20
        extern   _FlushConsoleInputBuffer@4

        NULL     EQU 0
        STD_INPUT_HANDLE EQU -10
        STD_OUTPUT_HANDLE        EQU -11

%define link 0
%define immediate 080h

%macro head 4
%%link dd link
%define link %%link
%strlen %%count %1
        db       %3 + %%count, %1
        xt_      %+ %2 dd %4
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

%define MEMSIZE 1024*1024*2
%define TIBSIZE 1024
%define STACKSIZE 32*1024
%define TIBPTR endmem - TIBSIZE
%define SP0 TIBPTR - 4
%define RP0 SP0 - STACKSIZE

        segment  .text USE32

; esp - data stack pointer
; ebp - return stack pointer
; esi - Forth instruction pointer
; ebx - TOS (top of data stack)

_main:
        cld
        push     ebp
        mov      eax, esp
        mov      dword[savesp],eax

        push     dword STD_INPUT_HANDLE
        call     _GetStdHandle@4
        mov      dword[stdin_handle],eax

        push     dword STD_OUTPUT_HANDLE
        call     _GetStdHandle@4
        mov      dword[stdout_handle],eax

        push     dword[stdin_handle]
        call     _FlushConsoleInputBuffer@4

        jmp      _abort

_halt:
        mov      eax, dword[savesp]
        mov      esp, eax
        pop      ebp
        push     NULL
        call     _ExitProcess@4

outchar:
        push     ebx
        push     esi
        push     ecx
        push     edi
        push     edx

        mov      byte[iobuf],al
        push     dword NULL
        push     dword Written
        push     dword 1
        push     dword iobuf
        push     dword[stdout_handle]
        call     _WriteConsoleA@20

        pop      edx
        pop      edi
        pop      ecx
        pop      esi
        pop      ebx
        ret

getchar:
        push     ebx
        push     esi
        push     ecx
        push     edi
        push     edx

        push     dword NULL
        push     dword Written
        push     dword 1
        push     dword iobuf
        push     dword[stdin_handle]
        call     _ReadConsoleA@20
        mov      al, byte[iobuf]
        and      eax, 0xff

        pop      edx
        pop      edi
        pop      ecx
        pop      esi
        pop      ebx
        ret

        primitive        'execute', execute
; ebx is TOS, so it contains address we will jump to
        mov      eax, ebx        ; eax is important here, it is used by docolon and dovar
        pop      ebx             ; we used TOS so we need to pop new value from the data stack
        jmp      dword[eax]      ; now we jump to the address that is stored in the eax

        primitive        'abort', abort
_abort:
        mov      eax, dword[val_number_t_i_b]
        mov      dword[val_to_in],eax
        xor      ebp, ebp
        mov      dword[val_state],ebp
        mov      eax, dword[savesp]
        mov      esp, eax
;        mov esp, SP0
        mov      ebp, RP0
        mov      esi, xt_interpret + 4
        jmp      next

        primitive        ',', comma
        xchg     eax, ebx
        mov      ebx, val_dp
        mov      edi,[ebx]
        stosd
        mov      [ ebx],edi
        pop      ebx
        jmp      next

        primitive        'lit', lit
        push     ebx
        lodsd
        xchg     eax, ebx
        jmp      next

        primitive        'rot', rote
        pop      edx
        pop      eax
        push     edx
        push     ebx
        xchg     eax, ebx
        jmp      next

        primitive        'drop', drop
        pop      ebx
        jmp      next

        primitive        'dup', dupe
        push     ebx
        jmp      next

        primitive        'swap', swap
        xchg     ebx,[esp]
        jmp      next

        primitive        '+', plus
        pop      eax
        add      ebx, eax
        jmp      next

        primitive        'exit', exit
        xchg     ebp, esp
        pop      esi
        xchg     ebp, esp
next:
        lodsd
        jmp      dword[eax]      ; eax is later used by docolon and dovar

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

        primitive        '0branch', zero_branch
        lodsd
        test     ebx, ebx
        jne      zerob_z
        xchg     eax, esi
zerob_z:
        pop      ebx
        jmp      next

        primitive        'branch', branch
        mov      esi, dword[esi]
        jmp      next

        primitive        'count', count
        movzx    eax, byte[ebx]
        inc      ebx
        push     ebx
        mov      ebx, eax
        jmp      next

        primitive        'accept', accept
        pop      edi             ; Pop the address of the string buffer into DI.
        xor      ecx, ecx        ; Clear the CX register.
acceptl:
        call     getchar         ; Do the DOS call to get a chr from the keyboard.
        cmp      al, 3
        je       _halt
        cmp      al, 8           ; See if it's a backspace (ASCII character 08h).
        jne      acceptn         ; If not, jump for more testing.
        jecxz    acceptb         ; "Jump if CX=0". If the user typed a backspace but
; there isn't anything in the buffer to erase, jump
; to the code that'll beep at him to let him know.
; User typed a backspace. Go ahead and output it.
        mov      al, ' '         ; Then output a space to wipe out the character that
        call     outchar         ; the user had just typed.
        mov      al, 8           ; Then output another backspace to put the cursor
        call     outchar         ; back into position to read another character.
        dec      ecx             ; We just deleted a character. Now we need to decrement
        dec      edi             ; both the counter and the buffer pointer.
        jmp      acceptl         ; Then go back for another character.
acceptn:
        cmp      al, 13          ; See if the input chr is a carriage return.
        je       acceptz         ; If so, we're done. jump to the end of the routine.
        cmp      ecx, ebx        ; Compare current string length to the maximum allowed.
        jne      accepts         ; If the string's not too long, jump.
acceptb:
        mov      al, 7           ; User's input is unusable in some way. Send the
        call     outchar         ; BEL chr to make a beep sound to let him know.
        jmp      acceptl         ; Then go back and let him try again.
accepts:
        cld
        stosb    ; Save the input character into the buffer. Note that
; this opcode automatically increments the pointer
; in the DI register.
        inc      ecx             ; But we have to increment the length counter manually.
        jmp      acceptl         ; Go back for another character.
acceptz:
        jecxz    acceptb         ; If the buffer is empty, beep at the user and go
; back for more input.
        mov      al, 10          ; Send a carriage return to the display...
        call     outchar         ;
        mov      al, 13          ; ...followed by a linefeed.
        call     outchar         ;
        mov      ebx, ecx        ; Move the count to the top of the stack.
        jmp      next

        primitive        'emit', emit
        xchg     eax, ebx        ; Move our output character to the AX register.
        call     outchar         ; Send it to the display.
        pop      ebx             ; Pop the argument off the stack.
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
        cmp      al, 9
        je       wordf
        cmp      al, 10
        je       wordf
        cmp      al, 13
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
        test     al, immediate
        jne      findi
        neg      ebx
findi:
        and      eax, 31
        add      edi, eax
        inc      edi
        push     edi
        jmp      next

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

        colon    ';', semicolon, immediate
        dd       xt_lit, xt_exit
        dd       xt_comma
        dd       xt_lit, 0
        dd       xt_state
        dd       xt_store
        dd       xt_exit

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


        segment  .data USE32

savesp:
        dd       0
stdin_handle:
        dd       0
stdout_handle:
        dd       0
iobuf:
        db       0

        variable 'state', state, 0
        variable '>in', to_in, 0
        variable '#tib', number_t_i_b, 0
        variable 'dp', dp, freemem
        variable 'base', base, 10
        variable 'last', last, final
        variable 'tib', t_i_b, TIBPTR

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
        dd       xt_lit, TIBSIZE - 2
        dd       xt_accept
        dd       xt_number_t_i_b
        dd       xt_store
        dd       xt_lit, 0
        dd       xt_to_in
        dd       xt_store
intpar:
        dd       xt_lit, 32
        dd       xt_word
        dd       xt_find
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
        dd       xt_execute
        dd       xt_branch
        dd       intdone
intnf:
        dd       xt_dupe
        dd       xt_rote
        dd       xt_count
        dd       xt_to_number
        dd       xt_zero_branch
        dd       intskip
        dd       xt_state
        dd       xt_fetch
        dd       xt_zero_branch
        dd       intnc
        dd       xt_last
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

        segment  .bss USE32
Written:
        resd     1
freemem:
        resb     MEMSIZE
endmem:

