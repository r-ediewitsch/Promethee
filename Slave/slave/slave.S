#define __SFR_OFFSET 0x00
#include "avr/io.h" 

.equ smoke_rd, 0x05
.equ temp_rd, 0x06

; =========================================================================================

.global main
main:
  ; I/O Initialization
    CBI   DDRC, 0               ; set pin PC0 as input for ADC0

  ; SPI Slave Initialization
    LDI   R16, 1<<PB4           ; Set MISO (PB4) as an output
    OUT   DDRB, R16
    LDI   R16, 1<<SPE           ; Enable SPI in slave mode
    OUT   SPCR, R16

  ; ADC Initialization
    LDI   R17, 1<<REFS0 | 1<<ADLAR
    STS   ADMUX, R17            ; AVcc, left-justified data, ADC0
    LDI   R17, 0b10000111 
    STS   ADCSRA, R17           ; enable ADC, prescaler CLK/128

; -----------------------------------------------------------------------------------------

main_loop:
wait_for_receive:
    IN    R25, SPSR
    SBRS  R25, SPIF             ; check whether SPI transfer is complete
    RJMP  wait_for_receive      ; if not, wait until master sends data

    IN    R24, SPDR             ; read received byte into R24

    CPI   R24, smoke_rd         ; if master request smoke data
    BREQ  smoke_read            ; read smoke data

    CPI   R24, temp_rd          ; if master request temperature data
    BREQ  temp_read             ; read temperature data

  ; If master send another command, ignore
    RJMP  main_loop

; -----------------------------------------------------------------------------------------

smoke_read:
    CALL  read_smoke
    OUT   SPDR, R21             ; send smoke data to master
    RJMP  main_loop

temp_read:
    CALL  read_heat
    OUT   SPDR, R18             ; send temperature data to master
    RJMP  main_loop

; =========================================================================================

read_smoke:
    LDI   R17, 0xC7             ; Start ADC conversion (set ADSC)
    STS   ADCSRA, R17
wait_ADC:
    LDS   R17, ADCSRA           ; check ADIF flag in ADCSRA
    SBRS  R17, 4                ; skip jump when conversion is done
    RJMP  wait_ADC              ; loop until ADIF flag is set

    LDI   R17, 0xD7             ; set ADIF flag so that controller clears ADIF
    STS   ADCSRA, R17     

    LDS   R21, ADCH             ; get high-byte result from ADCH
    RET

; =========================================================================================

read_heat:
  ; Start signal DHT22 
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

  ; Read 5 byte from DHT22
    RCALL DHT22_read_byte       ; byte 1: humidity high byte
    MOV   R10, R18

    RCALL DHT22_read_byte       ; byte 2: humidity low byte
    MOV   R11, R18

    RCALL DHT22_read_byte       ; byte 3: temperature high byte
    MOV   R12, R18

    RCALL DHT22_read_byte       ; byte 4: temperature low byte
    MOV   R13, R18

    RCALL DHT22_read_byte       ; byte 5: checksum
    MOV   R14, R18

  ; Count checksum manually
    MOV   R16, R10              ; R16 = H_high
    ADD   R16, R11              ; + H_low
    ADD   R16, R12              ; + T_high
    ADD   R16, R13              ; + T_low

    CP    R16, R14              ; Compare with checksum
    BRNE  read_heat             ; If checksum doesn't add up, retake the data

  ; If data valid, process data
    MOV   R17, R12
    MOV   R16, R13              ; R17:R16 = Temp*10

    TST   R17                   ; Test whether temperature is negative 
    BRMI  is_negative           ; If yes, handle sign magnitude

    CALL  div_by_10             ; Divide result by 10
    RET

is_negative:
    ANDI  R17, 0x7F             ; Remove sign
    CALL  div_by_10             ; Divide result by 10
    ORI   R18, 0x80             ; Add sign at the MSB of result
    RET  

; -----------------------------------------------------------------------------------------

DHT22_read_byte:
    LDI   R17, 8                ; Load bit counter (8 bits per byte)
    CLR   R18                   ; Clear R18 to store the resulting byte

read_bit_loop:
    SBIS  PINB, 1               ; Wait for DHT22 to pull PB1 HIGH (start of bit)
    RJMP  read_bit_loop         ; Loop until PB1 is HIGH

    RCALL delay_timer_50us 

    SBIS  PINB, 1               ; Check if pin is still HIGH after 50 µs
    RJMP  read_bit_0            ; If LOW, it's a logic 0

    SEC                         ; If still HIGH, it's a logic 1
    ROL   R18                   ; Rotate in '1' into result byte (carry flag goes into bit 0)
    RJMP  wait_bit_end          ; Jump to wait for line to go LOW

read_bit_0:
    LSL   R18                   ; Logic 0: shift left (adds a 0 bit)

wait_bit_end:
    SBIC  PINB, 1               ; Wait for DHT22 to pull PB1 LOW again (end of bit)
    RJMP  wait_bit_end          ; Stay here until line is LOW

    DEC   R17                   ; Decrease bit counter
    BRNE  read_bit_loop         ; Repeat until all 8 bits are read

    RET

; =========================================================================================

div_by_10:
    CLR   R18                   ; clear low byte quotient
    CLR   R19                   ; clear high byte quotient
    CLR   R20                   ; clear remainder
    LDI   R21, 16               ; 16 bit loop counter

div10_loop:
  ; Shift left dividend and remainder
    LSL   R16
    ROL   R17
    ROL   R20

  ; Try subtracting remainder with 10
    MOV   R22, R20
    SUBI  R20, 10

    BRCS  div10_skip            ; Branch if subtraction failed (borrow occurred)

  ; Success: store 1 in quotient
    SEC
    ROL R18
    ROL R19
    RJMP div10_next

div10_skip:
  ; Failure: Restore remainder, store 0 in quotient
    MOV R20, R22
    CLC
    ROL R18
    ROL R19

div10_next:
    DEC R21                     ; Decrement loop counter
    BRNE div10_loop
    RET

; =========================================================================================

delay_20ms:                     ; ~20ms delay
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

; -----------------------------------------------------------------------------------------

delay_timer_50us:
    CLR   R20
    OUT   TCNT0, R20            ; Reset Timer0 counter to 0
    LDI   R20, 100              
    OUT   OCR0A, R20            ; Load compare value for ~50us delay
    LDI   R20, 0b00001010
    OUT   TCCR0B, R20           ; 1/8 prescaler, CTC mode
wait_timer_flag:
    IN    R20, TIFR0            ; Read Timer Interrupt Flag Register
    SBRS  R20, OCF0A
    RJMP  wait_timer_flag       ; Wait until timer reaches OCR0A
    CLR   R20
    OUT   TCCR0B, R20           ; Stop Timer0 by clearing prescaler bits (stops the clock)
    LDI   R20, 1<<OCF0A
    OUT   TIFR0, R20            ; Clear OCF0A flag
    RET

delay_timer_30us:
    CLR   R20
    OUT   TCNT0, R20            ; Reset Timer0 counter to 0
    LDI   R20, 60    
    OUT   OCR0A, R20            ; Load compare value for ~30us delay
    LDI   R20, 0b00001010
    OUT   TCCR0B, R20           ; 1/8 prescaler, CTC mode
wait_30us_flag:
    IN    R20, TIFR0            ; Read Timer Interrupt Flag Register
    SBRS  R20, OCF0A            
    RJMP  wait_30us_flag        ; Wait until timer reaches OCR0A
    CLR   R20
    OUT   TCCR0B, R20           ; Stop Timer0 by clearing prescaler bits (stops the clock)
    LDI   R20, 1<<OCF0A
    OUT   TIFR0, R20            ; Clear OCF0A flag
    RET