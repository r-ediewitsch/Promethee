#define __SFR_OFFSET 0x00
#include "avr/io.h" 

.equ smoke_rd, 0x05
.equ temp_rd, 0x06

.global main

main:
  ; I/O Initialization
    SBI   DDRC, 0            ; set pin PC0 as input for ADC0
    SBI   DDRB, 5            
    SBI   DDRB, 4            
    
    LDI   R17, 0xFF
    OUT   DDRD, R17

  ; SPI Slave Initialization
    LDI   R16, 1<<PB4       ; Set MISO (PB4) as an output
    OUT   DDRB, R16
    LDI   R16, 1<<SPE       ; Enable SPI in slave mode
    OUT   SPCR, R16

  ; ADC Initialization
    LDI   R17, 1<<REFS0 | 1<<ADLAR
    STS   ADMUX, R17      ; AVcc, left-justified data, ADC0
    LDI   R17, 0b10000111 
    STS   ADCSRA, R17     ; enable ADC, prescaler CLK/128

main_loop:
    wait_for_receive:
    IN    R25, SPSR
    SBRS  R25, SPIF
    RJMP  wait_for_receive

    ; 2. Read the received byte from the data register
    IN    R24, SPDR

    ; 3. Check if the received byte is the command we are waiting for
    CPI   R24, smoke_rd
    BREQ  smoke_read

    CPI   R24, temp_rd
    BREQ  temp_read

    RJMP  main_loop
  
smoke_read:
    CALL  read_smoke
    OUT   SPDR, R21
    RJMP  main_loop

temp_read:
    CALL  read_heat
    OUT   SPDR, R18
    RJMP  main_loop

read_smoke:
    LDI   R17, 0xC7         ; Start ADC conversion (set ADSC)
    STS   ADCSRA, R17

wait_ADC:
    LDS   R17, ADCSRA     ; check ADIF flag in ADCSRA
    SBRS  R17, 4          ; skip jump when conversion is done
    RJMP  wait_ADC        ; loop until ADIF flag is set

    LDI   R17, 0xD7       ; set ADIF flag so that controller clears ADIF
    STS   ADCSRA, R17     

    LDS   R21, ADCH       ; get high-byte result from ADCH
    RET

read_heat:
  ; Start signal DHT11 
    SBI   DDRB, 1
    CBI   PORTB, 1
    RCALL delay_2ms
    SBI   PORTB, 1

  ; Wait for response
    ;CALL  delay_timer_30us
    CBI   DDRB, 1
wait_response_1:
    SBIC  PINB, 1
    RJMP  wait_response_1
wait_response_2:
    SBIS  PINB, 1
    RJMP  wait_response_2
wait_response_3:
    SBIC  PINB, 1
    RJMP  wait_response_3

  ; Read 5 byte from DHT11
    RCALL DHT11_read_byte        ; byte 1: humidity high byte
    MOV   R10, R18

    RCALL DHT11_read_byte        ; byte 2: humidity low byte
    MOV   R11, R18

    RCALL DHT11_read_byte        ; byte 3: temperature high byte
    MOV   R12, R18

    RCALL DHT11_read_byte        ; byte 4: temperature low byte
    MOV   R13, R18

    RCALL DHT11_read_byte        ; byte 5: checksum
    MOV   R14, R18

  ; Count checksum manually
    MOV   R16, R10             ; R16 = H_int
    ADD   R16, R11             ; + H_dec
    ADD   R16, R12             ; + T_int
    ADD   R16, R13             ; + T_dec

    CP    R16, R14             ; Compare with checksum
    BRNE  read_heat            ; If checksum doesn't add up, retake the data

    ;=== DATA VALID - proses suhu ===

    MOV   R17, R12
    MOV   R16, R13

    TST   R17
    BRMI  is_negative

    CALL  div_by_10
    OUT   PORTD, R18
    RET

is_negative:
    ANDI  R17, 0x7F
    CALL  div_by_10
    ORI   R18, 0x80
    OUT   PORTD, R18
    RET  

DHT11_read_byte:
    LDI   R17, 8
    CLR   R18
read_bit_loop:
    SBIS  PINB, 1
    RJMP  read_bit_loop
    RCALL delay_timer_50us
    SBIS  PINB, 1
    RJMP  read_bit_0
    SEC
    ROL   R18
    RJMP  wait_bit_end
read_bit_0:
    LSL   R18
wait_bit_end:
    SBIC  PINB, 1
    RJMP  wait_bit_end
    DEC   R17
    BRNE  read_bit_loop
    RET

div_by_10:
    CLR R18        ; Quotient low
    CLR R19        ; Quotient high
    CLR R20        ; Remainder
    LDI R21, 16    ; 16 bits to process

div10_loop:
    ; Shift left dividend and remainder
    LSL R16
    ROL R17
    ROL R20

    ; Try subtracting 10
    MOV R22, R20
    SUBI R20, 10
    BRCS div10_skip

    ; Success: store 1 in quotient
    SEC
    ROL R18
    ROL R19
    RJMP div10_next

div10_skip:
    ; Restore remainder, store 0 in quotient
    MOV R20, R22
    CLC
    ROL R18
    ROL R19

div10_next:
    DEC R21
    BRNE div10_loop
    RET

delay_2ms:
    LDI   R21, 255
delay_20ms_loop_1:
    LDI   R22, 210
delay_20ms_loop_2:
    LDI   R23, 2
delay_20ms_loop_3:
    DEC   R23
    BRNE  delay_20ms_loop_3
    DEC   R22
    BRNE  delay_20ms_loop_2
    DEC   R21
    BRNE  delay_20ms_loop_1
    RET

delay_2s:
    LDI   R21, 255
delay_2s_loop_1:
    LDI   R22, 255
delay_2s_loop_2:
    LDI   R23, 164
delay_2s_loop_3:
    DEC   R23
    BRNE  delay_2s_loop_3
    DEC   R22
    BRNE  delay_2s_loop_2
    DEC   R21
    BRNE  delay_2s_loop_1
    RET

delay_timer_50us:
    CLR   R20
    OUT   TCNT0, R20
    LDI   R20, 100
    OUT   OCR0A, R20
    LDI   R20, 0b00001010
    OUT   TCCR0B, R20
wait_timer_flag:
    IN    R20, TIFR0
    SBRS  R20, OCF0A
    RJMP  wait_timer_flag
    CLR   R20
    OUT   TCCR0B, R20
    LDI   R20, (1<<OCF0A)
    OUT   TIFR0, R20
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