#define __SFR_OFFSET 0x00
#include "avr/io.h" 

.global main

main:
  ; I/O Initialization
    SBI   DDRC, 0            ; set pin PC0 as input for ADC0
    SBI   DDRB, 5            
    SBI   DDRB, 4            
    
  ; ADC Initialization
    LDI   R17, 1<<REFS0 | 1<<ADLAR
    STS   ADMUX, R17      ; AVcc, left-justified data, ADC0
    LDI   R17, 0b10000111 
    STS   ADCSRA, R17     ; enable ADC, prescaler CLK/128

main_loop:
    CALL  read_smoke
    CALL  read_heat
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

    CPI   R21, 100        ; compare high byte with 100 (400 ppm)
    BRSH  turnOn          ; jump to c2 if the high 2-bit = 0
    JMP   turnOff         ; turn off the LED if the high 2-bit > 0 

turnOn:
    SBI PORTB, 5          ; set PORTB5 to turn on the LED
    RET

turnOff:
    CBI PORTB, 5          ; clear PORTB5 to turn off the LED
    RET

read_heat:
    RCALL delay_2s

  ; Start signal DHT11 
    SBI   DDRB, 1
    CBI   PORTB, 1
    RCALL delay_20ms
    SBI   PORTB, 1

  ; Wait for response
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
    RCALL DHT11_read_byte        ; byte 1: humidity integer
    MOV   R10, R18

    RCALL DHT11_read_byte        ; byte 2: humidity decimal
    MOV   R11, R18

    RCALL DHT11_read_byte        ; byte 3: temperature integer
    MOV   R12, R18

    RCALL DHT11_read_byte        ; byte 4: temperature decimal
    MOV   R13, R18

    RCALL DHT11_read_byte        ; byte 5: checksum
    MOV   R14, R18

  ; Count checksum manually
    MOV   R16, R10             ; R16 = H_int
    ADD   R16, R11             ; + H_dec
    ADD   R16, R12             ; + T_int
    ADD   R16, R13             ; + T_dec

    CP    R16, R14             ; Compare with checksum
    BRNE  read_heat         ; If checksum doesn't add up, retake the data

    ; === DATA VALID - proses suhu ===
    ; OUT   PORTD, R12

    LDI   R21, 30
    CP    R12, R21
    BRLT  turnOffh

turnOnh:
    SBI PORTB, 4          ; set PORTB5 to turn on the LED
    RET

turnOffh:
    CBI PORTB, 4          ; set PORTB5 to turn on the LED
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

delay_20ms:
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