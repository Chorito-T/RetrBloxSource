section .data
    msg db "nothing: ", 0
    msg_len equ $ - msg
    nothing dd 48
    newline db 10

section .bss
    buffer resb 4

section .text
    global _start

_start:
    mov eax, 4
    mov ebx, 1
    mov ecx, msg
    mov edx, msg_len
    int 0x80
    mov eax, [nothing]
    mov [buffer], al
    mov eax, 4
    mov ebx, 1
    mov ecx, buffer
    mov edx, 1
    int 0x80
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    mov eax, 4
    mov ebx, 1
    mov ecx, newline
    mov edx, 1
    int 0x80
    mov eax, 1
    mov ebx, 0
    int 0x80
