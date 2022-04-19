bits 16; Tells assembler we're writing 16-bits code

section _TEXT class=CODE

;
; void _cdecl x86_div64_32(uint64_t dividend, uint32_t divisor, uint32_t* quotientOut, uint64_t* remainderOut)
;
global _x86_div64_32; Exports the _x86_div64_32 function
_x86_div64_32:
    ; Make new call frame
    push bp; Save old call frame
    mov bp, sp; Initialize new call frame
    
    push bx; Save bx

    ; Divide upper 32 bits
    mov eax, [bp + 4]; eax <- upper 32 bits of dividend
    mov ecx, [bp + 12]; ecx <- divisor
    xor edx, edx
    div ecx; eax - quot, edx - remainder

    ; Store upper 32 bits of quotient
    mov bx, [bp + 16]
    mov [bx + 4], eax

    ; Divide lower 32 bits
    mov eax, [bp + 4]; eax <- lower 32 bits of dividend
                     ; edx <- old remainder
    div ecx

    ; Store results
    mov [bx], eax
    mov bx, [bp + 18]
    mov [bx], edx

    pop bx; Restore bx

    ; Restore old call frame
    mov sp, bp
    pop bp
    ret

;
; void _cdecl x86_VideoWriteCharTeletype(char c, uint8_t page);
;
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
