#define __SFR_OFFSET 0x00
#include "avr/io.h"
#include "avr/interrupt.h"

.equ smoke_rd, 0x05
.equ temp_rd, 0x06
.equ wait_rd, 0x00

.global main

main:
  ; I/O Initialization
    LDI  R16, 0xFF
    OUT  DDRD, R16
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

main_loop:
    CALL smoke_spi_read
    MOV R18, R16
    
    CALL temp_spi_read
    MOV R19, R16
    OUT PORTD, R19

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
