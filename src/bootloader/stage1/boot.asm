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
    ; Setup data segments.
    mov ax, 0           ; Can't write to DS/ES directly.
    mov ds, ax
    mov es, ax

    ; Setup stack.
    mov ss, ax
    mov sp, 0x7C00      ; Stack grows downwards from where we are loaded in memory.

    ; Some BIOS'es might start us at 07C0:0000 instead of 0000:7C00. Make sure we're in the expected location.
    push es
    push word .after
    retf

.after:
    ; Read something from floppy disk.
    ; BIOS should set DL to drive number.
    mov [ebr_drive_number], dl

    ; Show loading message.
    mov si, msg_loading
    call puts

    ; Read drive parameters (sectors per track and head count) instead of relying on data on formatted disk.
    push es
    mov ah, 08h
    int 13h
    jc floppy_error
    pop es

    and cl, 0x3F                    ; Removes top 2 bits.
    xor ch, ch                      ; Sets ch to 0, as ch will always equal itself.
    mov [bdb_sectors_per_track], cx ; Sector count.
    
    inc dh
    mov [bdb_heads], dh             ; Head count.

    ; Compute LBA of root directory = reserved + fats * sectors_per_fat.
    ; NOTE: This section can be hardcoded.
    mov ax, [bdb_sectors_pet_fat]
    mov bl, [bdb_fat_count]
    xor bh, bh
    mul bx                          ; ax = (fats * sectors_per_fat)
    add ax, [bdb_reserved_sectors]  ; ax = LBA of root directory
    push ax

    ; Compute size of root directory = (32 * number_of_entries) / bytes_per_sector;
    mov ax, [bdb_dir_entries_count]
    shl ax, 5                       ; ax *= 32
    xor dx, dx                      ; dx = 0
    div word [bdb_bytes_per_sector] ; number of sectors we need to read

    test dx, dx                 ; if dx != 0, add 1
    jz .root_dir_after
    inc ax                      ; Division remainder != 0, add 1
                                ; This means we have a sector only partially filled with entries

.root_dir_after:
    ; Read root directory
    mov cl, al                  ; cl = number of sectors to read = size of root directory
    pop ax                      ; ax = LBA of root directory
    mov dl, [ebr_drive_number]  ; dl = drive number (we saved it previously!)
    mov bx, buffer              ; es:bx = buffer
    call disk_read

    ; Search for kernel.bin
    xor bx, bx
    mov di, buffer

.search_kernel:
    mov si, file_kernel_bin
    mov cx, 11                      ; Compare up to 11 characters
    push di
    repe cmpsb
    pop di
    je .found_kernel

    add di, 32
    inc bx
    cmp bx, [bdb_dir_entries_count]
    jl .search_kernel

    ; Kernel not found
    jmp kernel_not_found_error

.found_kernel:
    mov ax, [di + 26]           ; First logical cluster field (offset 26)
    mov [kernel_cluster], ax

    ; Load FAT from disk into memory
    mov ax, [bdb_reserved_sectors]
    mov bx, buffer
    mov cl, [bdb_sectors_pet_fat]
    mov dl, [ebr_drive_number]
    call disk_read

    ; Read kernel and process FAT chain
    mov bx, KERNEL_LOAD_SEGMENT
    mov es, bx
    mov bx, KERNEL_LOAD_OFFSET

.load_kernel_loop:
    ; Read next cluster
    mov ax, [kernel_cluster]

    ; HISS! Hardcoded value!
    add ax, 31                      ; first cluster = (cluster number - 2) * sectors_per_cluster + kernel_cluster
                                    ; start sector = reserved + fats + root directory size = 1 + 18 + 14 = 33
    mov cl, 1
    mov dl, [ebr_drive_number]
    call disk_read

    add bx, [bdb_bytes_per_sector]

    ; Compute location of next cluster
    mov ax, [kernel_cluster]
    mov cx, 3
    mul cx
    mov cx, 2
    div cx                          ; ax = index of entry in FA, dx = cluter % 2

    mov si, buffer
    add si, ax
    mov ax, [ds:si]                 ; Read entry from FAT table at index ax

    or dx, dx
    jz .even

.odd:
    shr ax, 4
    jmp .next_cluster_after

.even:
    and ax, 0x0FFF

.next_cluster_after:
    cmp ax, 0x0FF8                  ; End of chain
    jae .read_finish

    mov [kernel_cluster], ax
    jmp .load_kernel_loop

.read_finish:
    ; Jump to our kernel
    mov dl, [ebr_drive_number]      ; Boot device in dl

    mov ax, KERNEL_LOAD_SEGMENT     ; Set segment registers
    mov ds, ax
    mov es, ax

    jmp KERNEL_LOAD_SEGMENT:KERNEL_LOAD_OFFSET

    jmp wait_key_and_reboot ; You should never get to this, but just in case.
    cli                     ; Disables interrupts, this way the CPU can't get out of "halt" state.
    hlt                     ; Stops CPU from executing (it can be resumed by an interrupt.)

;
; Error handlers
;

floppy_error:
    mov si, msg_read_failed
    call puts
    jmp wait_key_and_reboot

kernel_not_found_error:
    mov si, msg_kernel_not_found
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


file_kernel_bin:        db 'STAGE2  BIN'

msg_loading:            db 'Loading...', ENDL, 0
msg_read_failed:        db 'Read from disk failed!', ENDL, 0
msg_kernel_not_found:   db 'STAGE2.BIN file not found!', ENDL, 0

kernel_cluster:         dw 0

KERNEL_LOAD_SEGMENT     equ 0x2000
KERNEL_LOAD_OFFSET      equ 0



times 510-($-$$) db 0; Repeats the instruction 510 times.
                     ; $ = Special symbol which is equal to the memory offset of the current line.
                     ; $$ = Special symbol which is equal to the memory offset of the beginning of the current section.
                     ; $-$$ = Gives the size of our program so far (in bytes.)

dw 0AA55h; Stands for "define word(s)". Writes given word(s) (2 byte value, encoded in little endian) to the assembled binary file.

buffer: