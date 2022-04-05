org 0x0; Tells assembler the code is expected to be loaded at address 0x0. The assembler uses this information to calculate label addresses.
bits 16; Tells assembler to emit 16/32/64-bit code. In this case 16-bit code.

; 0x0D = byte code for \r which sets cursor x to 0, 0x0A = byte code for \n which increments cursor y by 1.
%define ENDL 0x0D, 0x0A;

start:
    ; Print hello world message
    mov si, msg_hello
    call puts

.halt:
    cli
    hlt

;
; Prints a string to the screen
; Params:
;   - ds:si points to string
;
puts:
    ; Save registers we will modify
    push si
    push ax
    ; push bx

.loop:
    lodsb       ; Loads next character in al.
    or al, al   ; Verify if next character is null?
    jz .done    ; Jumps to .done if zero flag is set.

    ; Prints a character to the screen in TTY mode.
    mov ah, 0x0e    ; Call BIOS interrupt.
    ; mov bh, 0       ; Set page number to 0.
    int 0x10

    jmp .loop

.done:
    ; pop bx
    pop ax
    pop si
    ret

msg_hello: db 'Hello World from KERNEL!', ENDL, 0