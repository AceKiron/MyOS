bits 16; Tells assembler we're writing 16-bits code

section _ENTRY class=CODE

extern _cstart_
global entry

entry:
    ; Set up a stack
    cli
    mov ax, ds
    mov ss, ax
    mov sp, 0
    mov bp, sp
    sti

    ; Expect boot drive in dl, send it as argument to cstart function
    xor dh, dh
    push dx
    call _cstart_

    cli
    hlt