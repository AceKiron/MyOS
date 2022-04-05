org 0x7C00; Tells assembler the code is expected to be loaded at address 0x7C00. The assembler uses this information to calculate label addresses.
bits 16; Tells assembler to emit 16/32/64-bit code. In this case 16-bit code.

; 0x0D = byte code for \r which sets cursor x to 0, 0x0A = byte code for \n which increments cursor y by 1.
%define ENDL 0x0D, 0x0A;

;
; FAT12 header
;
jmp short start
nop

bdb_oem:                    db 'MSWIN4.1'   ; OEM identifier. Recommended to be "MSWIN4.1".
                                            ; 8 bytes.
bdb_bytes_per_sector:       dw 512          ; Number of bytes per sector (remember, all numbers are in the little-endian format.)
bdb_sectors_per_cluster:    db 1            ; Number of sectors per cluster.
bdb_reserved_sectors:       dw 1            ; Number of reserved sectors. The boot record sectors are included in this value.
bdb_fat_count:              db 2            ; Number of FATs on the storage media. Often this value is 2.
bdb_dir_entries_count:      dw 0E0h         ; Number of directory entries (must be set so that the root directory occupies entire sectors.)
bdb_total_sectors:          dw 2880         ; The total sectors in the logical volume. If this value is 0, it means there are more than 65535 sectors in the volume, and the actual count is stored in the Large Sector Count entry at 0x20.
                                            ; 2880 * 512 = 1.44MB.
bdb_media_descriptor_type:  db 0F0h         ; This byte indicates the media descriptor type.
                                            ; F0 = 3.5" floppy disk.
bdb_sectors_pet_fat:        dw 9            ; Number of sectors per FAT. FAT12/FAT16 only.
bdb_sectors_per_track:      dw 18           ; Number of sectors per track.
bdb_heads:                  dw 2            ; Number of heads or sides on the storage media.
bdb_hidden_sectors:         dd 0            ; Number of hidden sectors (i.e. the LBA of the beginning of the partition.)
bdb_large_sector_count:     dd 0            ; Large sector count. This field is set if there are more than 65535 sectors in the volume, resulting in a value which does not fit in the Number of Sectors entry at 0x13.

;
; Extended boot record
;
ebr_drive_number:           db 0                    ; Drive number. The value here should be identical to the value returned by BIOS interrupt 0x13, or passed in the DL register.
                                                    ; 0x00 = floppy, 0x80 = HDD.
                            db 0                    ; Reserved.
ebr_signature:              db 29h                  ; Signature (must be 0x28 or 0x29.)
ebr_volume_id:              db 12h, 34h, 56h, 78h   ; VolumeID 'Serial' number. Used for tracking volumes between computers. You can ignore this if you want.
                                                    ; Volume label string. This field is padded with spaces.
ebr_volume_label:           db 'NANOBYTE OS'        ; 11 bytes. Padded with spaces.
ebr_system_id:              db 'FAT12   '           ; 8 bytes. This field is a string representation of the FAT file system type. It is padded with spaces. The spec says never to trust the contents of this string for any use.



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
    mov ax, 0           ; Can't write to DS/ES directly.
    mov ds, ax
    mov es, ax

    ; Setup stack.
    mov ss, ax
    mov sp, 0x7C00      ; Stack grows downwards from where we are loaded in memory.

    ; Read something from floppy disk.
    ; BIOS should set DL to drive number.
    mov [ebr_drive_number], dl

    mov ax, 1           ; LBA=1, second sector from disk
    mov cl, 1           ; 1 sector to read
    mov bx, 0x7E00      ; Data should be after the bootloader
    call disk_read

    ; Print message
    mov si, msg_hello
    call puts

    cli         ; Disables interrupts, this way the CPU can't get out of "halt" state.
    hlt         ; Stops CPU from executing (it can be resumed by an interrupt.)

;
; Error handlers
;

floppy_error:
    mov si, msg_read_failed
    call puts
    jmp wait_key_and_reboot

wait_key_and_reboot:
    mov ah, 0
    int 16h                 ; Wait for keypress.
    jmp 0FFFFh:0            ; Jump to beginning of BIOS, should reboot.

.halt:
    cli                     ; Disables interrupts, this way the CPU can't get out of "halt" state.
    hlt



;
; Disk routines
;


;
; Converts an LBA address to a CHS address
; Params:
;   - ax: LBA address
; Returns:
;   - cx [bites 0-5]: sector number
;   - cx [bites 6-15]: cylinder
;   - dh: head
;
lba_to_chs:
    ; Divide the logical block address by the number of sectors per track.
    
    push ax
    push dx

    xor dx, dx                          ; Sets dx to 0 as dx will always equal to itself.
    div word [bdb_sectors_per_track]    ; ax = LBA / SectorsPerTrack
                                        ; dx = LBA % SectorsPerTrack
    inc dx                              ; dx = LBA % SectorsPerTrack + 1 = sector

    mov cx, dx                          ; cx = sector
    
    xor dx, dx
    div word [bdb_heads]                ; ax = (LBA / SectorsPerTrack) / Heads = cylinder
                                        ; dx = (LBA / SectorsPerTrack) % Heads = head
    mov dh, dl                          ; dl = head
    mov ch, al                          ; ch = cylinder (lower 8 bits)
    shl ah, 6
    or cl, ah                           ; Puts the upper 2 bits of cylinder in CL.

    pop ax
    mov dl, al                          ; Restores DL.
    pop ax
    ret

;
; Reads sectors from a disk
; Params:
;   - ax: LBA address
;   - cl: number of sectors to read (up to 128)
;   - dl: drive number
;   - es:bx: memory address where to store read data
;
disk_read:
    push ax                 ; Save registers we will modify.
    push bx
    push cx
    push dx
    push di

    push cx                 ; Temporarily saves CL (number of sectors to read.)
    call lba_to_chs         ; Compute CHS
    pop ax                  ; AL = number of sectors to read

    mov ah, 02h
    mov di, 3               ; Retry count

.retry:
    pusha                   ; Save all registers, we don't know what BIOS modifies.
    stc                     ; Set carry flag, some BIOS'es don't set it.
    int 13h                 ; Carry flag cleared = success
    jnc .done               ; Jump if carry not set

    ; Read failed.
    popa
    call disk_reset
    dec di
    test di, di
    jnz .retry

.fail:
    ; All attempts are exhausted.
    jmp floppy_error

.done:
    popa

    pop di
    pop dx
    pop cx
    pop bx
    pop ax                 ; Restore registers modified

    ret

;
; Resets disk controller
; Params:
;   - dl: drive number
;
disk_reset:
    pusha
    mov ah, 0
    stc
    int 13h
    jc floppy_error
    popa
    ret


msg_hello:              db 'Hello World!', ENDL, 0
msg_read_failed:        db 'Read from disk failed!', ENDL, 0



times 510-($-$$) db 0; Repeats the instruction 510 times.
                     ; $ = Special symbol which is equal to the memory offset of the current line.
                     ; $$ = Special symbol which is equal to the memory offset of the beginning of the current section.
                     ; $-$$ = Gives the size of our program so far (in bytes.)

dw 0AA55h; Stands for "define word(s)". Writes given word(s) (2 byte value, encoded in little endian) to the assembled binary file.
