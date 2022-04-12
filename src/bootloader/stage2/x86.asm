bits 16; Tells assembler we're writing 16-bits code

section _TEXT class=CODE

global _x86_VideoWriteCharTeletype; Exports the _x86_VideoWriteCharTeletype function
_x86_VideoWriteCharTeletype:
    ; Make new call frame
    push bp; Save old call frame
    mov bp, sp; Initialize new call frame
    
    push bx; Save bx

    ; [bp + 0] - Old call frame
    ; [bp + 2] - Return address (small memory model => 2 bytes)
    ; [bp + 4] - First argument (character)
    ; [bp + 6] - Second argument (page)
    mov ah, 0Eh
    mov al, [bp + 4]
    mov bh, [bp + 6]

    int 10h

    pop bx; Restore bx

    ; Restore old call frame
    mov sp, bp
    pop bp
    ret