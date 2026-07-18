org 100h

section .text

start:
    mov     ax, 13h
    int     10h
    mov     word [unk_01], 0
    mov     word [unk_02], 32h    ; 32h = 50 em decimal
    mov     word [unk_03], 3

loc_01:
    mov     ax, [unk_01]
    mov     bx, [unk_02]
    cmp     ax, bx
    jg      loc_03
    call    sub_01
    inc     word [unk_01]
    mov     ax, [unk_03]
    cmp     ax, 0
    jl      loc_02
    dec     word [unk_02]
    mov     bx, [unk_01]
    sub     bx, [unk_02]
    shl     bx, 2
    add     bx, 0Ah
    add     [unk_03], bx
    jmp     loc_01

loc_02:
    mov     bx, [unk_01]
    shl     bx, 2
    add     bx, 6
    add     [unk_03], bx
    jmp     loc_01

loc_03:
    mov     ah, 0
    int     16h
    mov     ax, 3
    int     10h
    mov     ax, 4C00h
    int     21h

sub_01:
    pusha
    mov     cx, 0A0h              ; 0A0h = 160 em decimal
    add     cx, [unk_01]
    mov     dx, 64h               ; 64h = 100 em decimal
    add     dx, [unk_02]
    call    sub_02
    mov     cx, 0A0h
    sub     cx, [unk_01]
    mov     dx, 64h
    add     dx, [unk_02]
    call    sub_02
    mov     cx, 0A0h
    add     cx, [unk_01]
    mov     dx, 64h
    sub     dx, [unk_02]
    call    sub_02
    mov     cx, 0A0h
    sub     cx, [unk_01]
    mov     dx, 64h
    sub     dx, [unk_02]
    call    sub_02
    mov     cx, 0A0h
    add     cx, [unk_02]
    mov     dx, 64h
    add     dx, [unk_01]
    call    sub_02
    mov     cx, 0A0h
    sub     cx, [unk_02]
    mov     dx, 64h
    add     dx, [unk_01]
    call    sub_02
    mov     cx, 0A0h
    add     cx, [unk_02]
    mov     dx, 64h
    sub     dx, [unk_01]
    call    sub_02
    mov     cx, 0A0h
    sub     cx, [unk_02]
    mov     dx, 64h
    sub     dx, [unk_01]
    call    sub_02
    popa
    ret

sub_02:
    mov     ah, 0Ch
    mov     al, 4
    mov     bh, 0
    int     10h
    ret

section .data
    unk_01 dw 0
    unk_02 dw 0
    unk_03 dw 0
