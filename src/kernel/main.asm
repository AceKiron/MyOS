org 0x7C00; Tells assembler the code is expected to be loaded at address 0x7C00. The assembler uses this information to calculate label addresses.
bits 16; Tells assembler to emit 16/32/64-bit code. In this case 16-bit code.

; 0x0D = byte code for \r which sets cursor x to 0, 0x0A = byte code for \n which increments cursor y by 1.
%define ENDL 0x0D, 0x0A;

start:
    jmp main

;
; Prints a string to the screen
; Params:
;   - ds:si points to string
;
puts:
    ; Save registers we will modify
    push si
    push ax

.loop:
    lodsb; Loads next character in al.
    or al, al; Verify if next character is null?
    jz .done; Jumps to .done if zero flag is set.

    ; Prints a character to the screen in TTY mode.
    mov ah, 0x0e
    int 0x10

    jmp .loop

.done:
    pop ax
    pop si
    ret

main:
    ; Setup data segments.
    mov ax, 0; Can't write to DS/ES directly.
    mov ds, ax
    mov es, ax

    ; Setup stack.
    mov ss, ax
    mov sp, 0x7C00; Stack grows downwards from where we are loaded in memory.

    ; Print message
    mov si, msg_hello
    call puts

    hlt; Stops CPU from executing (it can be resumed by an interrupt.)

.halt:
    jmp .halt; Jumps to given location, unconditionally (equivalent with goto instruction in C.)

msg_hello: db 'Hello World!', ENDL, 0



times 510-($-$$) db 0; Repeats the instruction 510 times.
                     ; $ = Special symbol which is equal to the memory offset of the current line.
                     ; $$ = Special symbol which is equal to the memory offset of the beginning of the current section.
                     ; $-$$ = Gives the size of our program so far (in bytes.)

dw 0AA55h; Stands for "define word(s)". Writes given word(s) (2 byte value, encoded in little endian) to the assembled binary file.
