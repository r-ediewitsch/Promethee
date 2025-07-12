#define __SFR_OFFSET 0x00
#include "avr/io.h"
#include "avr/interrupt.h"

.equ smoke_rd, 0x05
.equ temp_rd, 0x06
.equ wait_rd, 0x00

.global INT0_vect
INT0_vect:
  ; Ngko sek
    RETI

.global main

main:
  ; I/O Initialization
    LDI  R16, 0xFF
    OUT  DDRD, R16
    OUT  DDRC, R16
    SBI  DDRB, 0

  ; SPI Master Initialization
    LDI  R16, (1<<PB5) | (1<<PB3) | (1<<PB2)
    OUT  DDRB, R16         ; Set MOSI (PB3), SCK (PB5), and SS (PB2) as outputs
    LDI  R16, (1<<SPE) | (1<<MSTR) | (1<<SPR0)
    OUT  SPCR, R16         ; Enable SPI, Master, set clock rate fck/16

    CLR  R18
    CLR  R19

  ; Serial Initialization
    CLR   R16
    STS   UCSR0A, R16         ; clear UCSR0A register
    STS   UBRR0H, R16         ; clear UBRR0H register
    LDI   R16, 51             ; set baud rate 19200
    STS   UBRR0L, R16   
    LDI   R16, 1<<RXEN0 | 1<<TXEN0
    STS   UCSR0B, R16         ; enable RXB and TXB
    LDI   R16, 1<<USBS0 | 3<<UCSZ00
    STS   UCSR0C, R16         ; asynchronous, no parity, 2 stop, 8 bits

  ; External Interrupt Configuration
    LDI   R16, 1<<ISC11 | 1<<ISC10 | 1<<ISC01
    STS   EICRA, R16          ; INT1 on rising edge, INT0 on falling edge
    LDI   R16, 1<<INT1 | 1<<INT0
    OUT   EIMSK, R16          ; Enable both INT0 and INT1

    SEI                       ; Enable global interrupts

main_loop:
    CALL smoke_spi_read
    MOV R8, R16
    CALL print_smoke
    
    CALL temp_spi_read
    MOV R9, R16
    CALL print_temp
    ;OUT PORTD, R19

    CALL delay_one_sec
    CALL handle_alarm
    RJMP main_loop

handle_alarm:
    CPI  R18, 100
    BRSH tc
    RJMP ret
tc: ANDI  R19, 0x7F
    CPI  R19, 60
    BRLO ret
    SBI  PORTB, 0
ret:RET
    

turnOff:
    CBI  PORTB, 0
    RJMP main_loop

turnOn:
    SBI  PORTB, 0
    RJMP main_loop


smoke_spi_read:
    CBI  PORTB, 2  ; Pull CS LOW

    LDI  R16, smoke_rd ; --- Send the SMOKE command ---
    CALL spi_transmit

    CALL delay_one_sec

    LDI  R16, wait_rd     ; --- Send dummy byte to get the data ---
    CALL spi_transmit
    ; Smoke data is now in R16

    SBI  PORTB, 2            ; Pull CS HIGH
    RET

temp_spi_read:
    CBI  PORTB, 2  ; Pull CS LOW

    LDI  R16, temp_rd ; --- Send the SMOKE command ---
    CALL spi_transmit

    CALL delay_one_sec

    LDI  R16, wait_rd     ; --- Send dummy byte to get the data ---
    CALL spi_transmit
    ; Smoke data is now in R16

    SBI  PORTB, 2            ; Pull CS HIGH
    RET

spi_transmit:
    OUT  SPDR, R16 ; Load data into SPI Data Register to start
wait_loop:
    IN   R17, SPSR ; Check for transfer complete flag
    SBRS R17, SPIF
    RJMP wait_loop
    IN   R16, SPDR ; Read SPDR to clear flag and get received byte
    RET

div_16bit:
    CLR   R21         ; clear high byte quotient
    CLR   R20         ; clear low byte quotient
    CLR   R23         ; clear high byte remainder
    CLR   R22         ; clear low byte remainder
    LDI   R26, 16     ; 16 bit loop counter

div_16bit_loop:
    ; Shift left dividend (R17:R16)
    LSL   R16
    ROL   R17

    ; Shift left remainder (R23:R22), bringing in bit from dividend
    ROL   R22
    ROL   R23

    ; Save current remainder before subtraction
    MOV   R24, R23
    MOV   R25, R22

    ; Try subtracting remainder with divisor (R19:R18)
    SUB   R22, R18
    SBC   R23, R19

    BRCS  div_16bit_skip  ; Branch if subtraction failed (borrow occurred)

    ; Success: store 1 in quotient
    LSL R20
    ROL R21
    INC R20
    RJMP  div_16bit_next

div_16bit_skip:
    ; Failure: Restore remainder and store 0 in quotient
    MOV   R23, R24
    MOV   R22, R25
    LSL   R20
    ROL   R21

div_16bit_next:
    DEC   R26         ; Decrement loop counter
    BRNE  div_16bit_loop
    RET

print_char:
  LDS R17, UCSR0A
  SBRS R17, UDRE0    ; wait for UDR0
  RJMP print_char
  STS UDR0, R16      ; send char to serial
  RET

print_decimal_3digit:
    ; --- Save registers ---
    PUSH R16
    PUSH R17
    PUSH R18
    PUSH R19
    PUSH R20
    PUSH R21
    PUSH R22
    PUSH R23
    PUSH R24
    PUSH R25

    ; --- Initialize dividend R17:R16 with 16-bit input value from R23:R22 ---
    MOV   R17, R23
    MOV   R16, R22

    ; --- Thousands Digit: (Input) / 1000 ---
    LDI   R19, hi8(1000)
    LDI   R18, lo8(1000)
    RCALL div_16bit         ; Quotient -> R21:R20, Remainder -> R23:R22
    
    ; Logic to suppress leading zeros
    CPI   R20, 0            ; Check if the 16-bit quotient is zero
    BREQ  sth               ; If it is, don't print it
    
    MOV   R16, R20          ; Quotient (0-9) fits in one byte
    SUBI  R16, -48          ; Convert to ASCII
    RCALL print_char

sth:MOV   R17, R23
    MOV   R16, R22

    ; --- Hundreds Digit: (Remainder) / 100 ---
    LDI   R19, 0
    LDI   R18, 100
    RCALL div_16bit         ; Quotient -> R21:R20, Remainder -> R23:R22
    
    MOV   R16, R20          ; Quotient (0-9) fits in one byte
    SUBI   R16, -48
    RCALL print_char

    MOV   R17, R23
    MOV   R16, R22

    ; --- Tens Digit: (Remainder) / 10 ---
    LDI   R19, 0
    LDI   R18, 10
    RCALL div_16bit         ; Quotient -> R21:R20, Remainder -> R23:R22

    MOV   R16, R20
    SUBI   R16, -48
    RCALL print_char

    ; --- Units Digit: The final remainder ---
    MOV   R16, R22
    SUBI   R16, -48
    RCALL print_char

    LDI   R16, '\r'
    RCALL print_char
    LDI   R16, '\n'
    RCALL print_char

    ; --- Restore registers ---
    POP   R25
    POP   R24
    POP   R23
    POP   R22
    POP   R21
    POP   R20
    POP   R19
    POP   R18
    POP   R17
    POP   R16
    RET

print_decimal_2digit:
    ; --- Save registers that will be used ---
    PUSH R16
    PUSH R17
    PUSH R18
    PUSH R19
    PUSH R20
    PUSH R21
    PUSH R22
    PUSH R23
    PUSH R24
    PUSH R25

    ; --- Prepare for division ---
    SBRS  R22, 7
    RJMP  pos
    ANDI  R22, 0x7F
    
    LDI   R16, '-'
    RCALL print_char

pos:CLR   R17
    MOV   R16, R22

    ; --- Tens digit: (R17:R16) / 10 ---
    LDI   R19, 0
    LDI   R18, 10
    RCALL div_16bit         ; Call your 16-bit division routine
    
    ; The quotient (tens digit) is now in R18
    MOV   R16, R20
    OUT   PORTC, R20

    CPI   R20, 0            ; Check if the 16-bit quotient is zero
    BREQ  stt 

    SUBI  R16, -48         ; Convert digit to ASCII (standard way)
    RCALL print_char

    ; --- Units digit: The remainder of the division ---
stt:MOV   R16, R22
    SUBI  R16, -48          ; Convert digit to ASCII
    RCALL print_char

    ; --- Send a newline for clean formatting ---
    LDI   R16, '\r'
    RCALL print_char
    LDI   R16, '\n'
    RCALL print_char

    ; --- Restore registers ---
    POP   R25
    POP   R24
    POP   R23
    POP   R22
    POP   R21
    POP   R20
    POP   R19
    POP   R18
    POP   R17
    POP   R16
    RET

 print_smoke:
    LDI   R30, lo8(smoke_msg)   ; Z points to the warning message 
    LDI   R31, hi8(smoke_msg)
    CALL  print_message

    CLR   R23
    MOV   R22, R8
    LSL   R22
    ROL   R23
    LSL   R22
    ROL   R23
    CALL print_decimal_3digit
    
    RET

print_temp:
    LDI   R30, lo8(temp_msg)   ; Z points to the warning message 
    LDI   R31, hi8(temp_msg)
    CALL  print_message

    MOV   R22, R9
   
    ;OUT   PORTC, R9
    CALL  print_decimal_2digit

    RET

print_message:
agn:LPM   R18, Z+             ; load char of string onto R18
    CPI   R18, 0              ; check if R18 = 0 (end of string)
    BREQ  ext    
l1: LDS   R17, UCSR0A         
    SBRS  R17, UDRE0          ; test data buffer if data can be sent
    RJMP  l1                  ; if not, back to l1
    STS   UDR0, R18           ; send char in R18 to the serial monitor
    RJMP  agn                 ; loop for the next char
ext:RET


delay_one_sec:
    LDI  R21, 100
delay_loop_inner:
    LDI  R22, 255
    LDI  R23, 255
delay_inner:
    DEC  R23
    BRNE delay_inner
    DEC  R22
    BRNE delay_inner
    DEC  R21
    BRNE delay_loop_inner
    RET

delay_timer_30us:
    CLR   R20
    OUT   TCNT0, R20
    LDI   R20, 60         ; 30us for 1MHz
    OUT   OCR0A, R20
    LDI   R20, 0b00001010
    OUT   TCCR0B, R20
wait_30us_flag:
    IN    R20, TIFR0
    SBRS  R20, OCF0A
    RJMP  wait_30us_flag
    CLR   R20
    OUT   TCCR0B, R20
    LDI   R20, (1<<OCF0A)
    OUT   TIFR0, R20
    RET

temp_msg:
    .ascii "Temperature: "
    .byte 10,0

smoke_msg:
    .ascii "Smoke (ppm): "
    .byte 10,0