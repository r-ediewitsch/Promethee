#define __SFR_OFFSET 0x00
#include "avr/io.h"
#include "avr/interrupt.h"

.equ smoke_rd, 0x05
.equ temp_rd, 0x06
.equ wait_rd, 0x00

; ========================================================================================

.global INT0_vect
  ; Emergency button interrupt
INT0_vect:
    SBI   PORTB, 0              ; Turn on the alarm
    MOV   R4, R3                ; Set alarm flag
    CALL  print_emergency_alert
    RETI

.global INT1_vect
  ; Flame sensor interrupt
INT1_vect:
    SBI   PORTB, 0              ; Turn on the alarm     
    MOV   R4, R3                ; Set alarm flag
    CALL  print_flame_alert
    RETI

; =========================================================================================

.global main
main:
  ; Stack Pointer Initialization
    LDI R16, hi8(RAMEND)
    OUT SPH, R16
    LDI R16, lo8(RAMEND)
    OUT SPL, R16

  ; I/O Initialization
    LDI  R16, 0xFF
    OUT  DDRC, R16              ; Set PCx as output

    LDI  R16, 0x1C
    OUT  DDRD, R16              ; Set PD2-4 as input
    LDI  R16, 0x14
    OUT  PORTD, R16             ; Set button pull-up for PD2 and PD4

    SBI  DDRB, 0                ; Set PB0 as output for alarm

  ; SPI Master Initialization
    LDI  R16, (1<<PB5) | (1<<PB3) | (1<<PB2)
    OUT  DDRB, R16              ; Set MOSI (PB3), SCK (PB5), and SS (PB2) as outputs
    LDI  R16, (1<<SPE) | (1<<MSTR) | (1<<SPR0)
    OUT  SPCR, R16              ; Enable SPI, Master, set clock rate fck/16

    CLR  R18
    CLR  R19

  ; Serial Initialization
    CLR   R16
    STS   UCSR0A, R16           ; clear UCSR0A register
    STS   UBRR0H, R16           ; clear UBRR0H register
    LDI   R16, 51               ; set baud rate 19200
    STS   UBRR0L, R16   
    LDI   R16, 1<<RXEN0 | 1<<TXEN0
    STS   UCSR0B, R16           ; enable RXB and TXB
    LDI   R16, 1<<USBS0 | 3<<UCSZ00
    STS   UCSR0C, R16           ; asynchronous, no parity, 2 stop, 8 bits

  ; External Interrupt Configuration
    LDI   R16, 1<<ISC11 | 1<<ISC10 | 1<<ISC01
    STS   EICRA, R16            ; INT1 on rising edge, INT0 on falling edge
    LDI   R16, 1<<INT1 | 1<<INT0
    OUT   EIMSK, R16            ; Enable both INT0 and INT1

    SEI                         ; Enable global interrupts

  ; I2C Initialization
    LDI   R16, 0
    STS   TWSR, R28             ; Prescaler = 1
    LDI   R16, 72             
    STS   TWBR, R28             ; SCL ≈ 100 kHz

  ; LCD Display Initialization
    RCALL I2C_start             ; Start I2C transmission
    LDI   R29, 0x7C             ; LCD address = 0x7C
    RCALL I2C_write

    CLR   R21
    CLR   R22
    LDI   R27, 0x80             ; RS = 0
    LDI   R16, 0x28             ; Command for LCD 2 lines, 5x7 matrix
    RCALL cmd_write             ; Send command
    LDI   R16, 0x0C             ; Command for display ON, cursor OFF
    RCALL cmd_write             ; Send command
    LDI   R16, 0x01             ; Command to clear LCD
    RCALL cmd_write             ; Send command
    CLR   R27
    LDI   R16, 0x06             ; Command to shift cursor right
    RCALL cmd_write             ; Send command
    RCALL I2C_stop              ; Stop I2C transmission

  ; Flag Comparator
    LDI   R16, 0x01           
    MOV   R3, R16               ; Store flag comparator to R3

; -----------------------------------------------------------------------------------------

main_loop:
    SBIS  PIND, 4               ; Check whether reset button is pressed
    CALL handle_reset           ; If yes, call handler

    CALL smoke_spi_read
    MOV R8, R16                 ; Read smoke sensor from slave
    CALL temp_spi_read
    MOV R9, R16                 ; Read temperature sensor from slave

    CALL print_smoke            ; Print smoke reading to serial monitor
    CALL print_temp             ; Print temp reading to serial monitor
    
    SBRC R4, 0
    CALL delay_one_sec          ; Delay if alarm is on

    CALL handle_alarm           ; Check threshold for the alarm
    RJMP main_loop

; =========================================================================================

handle_reset:
    SBRS  R4, 0                 ; If alarm is off, skip
    RJMP  reset_done
    SBIC  PIND, 3               ; If flame still detected, skip
    RJMP  reset_done

    MOV   R18, R8
    MOV   R19, R9               ; Copy smoke (R8) and temp (R9) into upper registers

    CPI   R18, 100
    BRSH  reset_done            ; If smoke >= 400, skip

    ANDI  R19, 0x7F             ; Remove temp sign
    CPI   R19, 60
    BRSH  reset_done            ; If temp >= 60, skip

    CALL  print_reset_message
    CBI   PORTB, 0              ; Turn off the alarm
    CLR   R4                    ; Clear alarm flag

reset_done:
    RET

; =========================================================================================

handle_alarm:
    CP    R4, R3
    BREQ  alarm_done            ; If alarm is on, skip

    MOV   R18, R8
    MOV   R19, R9               ; Copy smoke (R8) and temp (R9) into upper registers

    CPI   R18, 100              ; Check if smoke >= 100
    BRLO  check_temp_only       ; If lower, check temp only

    ANDI  R19, 0x7F             ; Remove sign bit from temp
    CPI   R19, 60               ; Check if temp >= 60
    BRLO  smoke_only_msg        ; If lower, print "SMOKE HIGH"

    SBI   PORTB, 0              ; Smoke high + Temp high
    MOV   R4, R3                ; Turn on alarm and set flag
    CALL  print_fire_alert      ; print "SMOKE+TEMP HIGH"
    RJMP  alarm_done

check_temp_only:
    ANDI  R19, 0x7F             ; Remove sign bit from temp
    CPI   R19, 60               ; Check if temp >= 60
    BRLO  print_safe_msg        ; If lower, print "SAFE CONDITION"

    CALL  print_temp_notice     ; If not, print "TEMP HIGH"
    RJMP  alarm_done

smoke_only_msg:
    CALL  print_smoke_notice 
    RJMP  alarm_done

print_safe_msg:
    CALL  print_safe_message

alarm_done:
    RET

; =========================================================================================

print_smoke_notice:
    CALL lcd_clear              ; Clear LCD screen 
    LDI  R30, lo8(smoke_notice)
    LDI  R31, hi8(smoke_notice) ; Store message to R30:R31
    CALL disp_msg               ; Display message to LCD screen
    CALL delay_one_sec
    RET

print_temp_notice:
    CALL lcd_clear
    LDI  R30, lo8(temp_notice)
    LDI  R31, hi8(temp_notice)
    CALL disp_msg
    CALL delay_one_sec
    RET

print_fire_alert:
    CALL lcd_clear
    LDI  R30, lo8(fire_alert)
    LDI  R31, hi8(fire_alert)
    CALL disp_msg
    CALL delay_one_sec
    RET

print_flame_alert:
    CALL lcd_clear
    LDI  R30, lo8(flame_warning)
    LDI  R31, hi8(flame_warning)
    CALL disp_msg
    CALL delay_one_sec
    RET

print_emergency_alert:
    CALL lcd_clear
    LDI  R30, lo8(emergency_warning)
    LDI  R31, hi8(emergency_warning)
    CALL disp_msg
    CALL delay_one_sec
    RET

print_safe_message:
    CALL lcd_clear
    LDI  R30, lo8(safe)
    LDI  R31, hi8(safe)
    CALL disp_msg
    CALL delay_one_sec
    RET

print_reset_message:
    CALL lcd_clear
    LDI  R30, lo8(reset_msg)
    LDI  R31, hi8(reset_msg)
    CALL disp_msg
    CALL delay_one_sec
    RET

; =========================================================================================

smoke_spi_read:
    CBI  PORTB, 2               ; Pull CS LOW

    LDI  R16, smoke_rd          ; Send command to request smoke data
    CALL spi_transmit           ; Transmit to slave

    CALL delay_timer_1ms

    LDI  R16, wait_rd           ; Send dummy byte to get the data
    CALL spi_transmit           ; Transmit to slave
    
  ; Smoke data is now in R16
    SBI  PORTB, 2               ; Pull CS HIGH
    RET

temp_spi_read:
    CBI  PORTB, 2               ; Pull CS LOW

    LDI  R16, temp_rd           ; Send command to request temp data
    CALL spi_transmit           ; Transmit to slave

    CALL delay_50ms

    LDI  R16, wait_rd           ; Send dummy byte to get the data
    CALL spi_transmit           ; Transmit to slave
    
  ; Temp data is now in R16
    SBI  PORTB, 2               ; Pull CS HIGH
    RET

; -----------------------------------------------------------------------------------------

spi_transmit:
    OUT  SPDR, R16              ; Load data into SPI Data Register to start
wait_loop:
    IN   R17, SPSR              ; Check for transfer complete flag
    SBRS R17, SPIF              ; Wait until the flag is set
    RJMP wait_loop
    IN   R16, SPDR              ; Read SPDR to clear flag and get received byte
    RET

; =========================================================================================

I2C_start:
    LDI   R28, 1<<TWINT | 1<<TWSTA | 1<<TWEN
    STS   TWCR, R28             ; transmit START condition
wt1:LDS   R28, TWCR
    SBRS  R28, TWINT            ; Check for TWI interrupt flag
    RJMP  wt1                   ; If not set, wait for end of transmission
    RET

I2C_write:
    STS   TWDR, R29             ; Copy SLA+W into data register
    LDI   R28, 1<<TWINT | 1<<TWEN
    STS   TWCR, R28             ; Transmit SLA+W
wt2:LDS   R28, TWCR
    SBRS  R28, TWINT
    RJMP  wt2                   ; wait for end of transmission
    RET

I2C_stop:
    LDI   R28, 1<<TWINT | 1<<TWSTO | 1<<TWEN
    STS   TWCR, R28             ; transmit STOP condition
    RET

; =========================================================================================

cmd_write:                      ; different label for better readibility
data_write:
    MOV   R29, R27
    RCALL I2C_write             ; send control byte to LCD
    RCALL delay_timer_50us      ; 50 microsecond delay
    MOV   R29, R16
    RCALL I2C_write             ; send data byte to LCD
    RCALL delay_timer_50us      ; 50 microsecond delay
    RET

; -----------------------------------------------------------------------------------------

disp_msg:
    RCALL I2C_start             ; Start I2C transmission
    LDI R29, 0x7C               ; LCD address = 0x7C
    RCALL I2C_write
agl:LPM   R16, Z+               ; Load char of string onto R16
    CPI   R16, 13               ; If char = newline, handle
    BREQ  nl
    CPI   R16, 0                ; If char = end of string, exit
    BREQ  exl                    
  
    RCALL delay_timer_1ms 
    LDI   R27, 0xC0   
    RCALL data_write            ; Send char to LCD display
  
    RJMP  agl                   ; loop to get the next char
  
exl:RCALL I2C_stop              ; Stop I2C transmission
    RET

nl: LDI   R27, 0x80   
    LDI   R16, 0xC0             ; Move cursor to the second row
    RCALL cmd_write             ; Send command to LCD display
    RJMP agl                    ; loop to get the next char

; -----------------------------------------------------------------------------------------

lcd_clear:
    CALL  I2C_start             ; Start I2C transmission
    LDI   R29, 0x7C             ; LCD address = 0x7C
    CALL  I2C_write
    CLR   R27
    LDI   R16, 0x01             ; Clear display command
    CALL  cmd_write             ; Send command to LCD display
    CALL  delay_timer_5ms       
    CALL  I2C_stop              ; Stop I2C transmission
    RET

; =========================================================================================

div_16bit:
    CLR   R21                   ; clear high byte quotient
    CLR   R20                   ; clear low byte quotient
    CLR   R23                   ; clear high byte remainder
    CLR   R22                   ; clear low byte remainder
    LDI   R26, 16               ; 16 bit loop counter

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

    BRCS  div_16bit_skip        ; Branch if subtraction failed (borrow occurred)

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
    DEC   R26                   ; Decrement loop counter
    BRNE  div_16bit_loop
    RET

print_char:
    LDS R17, UCSR0A
    SBRS R17, UDRE0             ; test data buffer if data can be sent
    RJMP print_char             ; if not, back to print_char
    STS UDR0, R16               ; send char to serial monitor
    RET

; =========================================================================================

print_decimal_3digit:
    PUSH  R16
    PUSH  R17
    PUSH  R18
    PUSH  R19
    PUSH  R20
    PUSH  R21
    PUSH  R22
    PUSH  R23
    PUSH  R24
    PUSH  R25                   ; save value of the register used onto stack

    CLT                         ; clear leading zero flag 

  ; Initialize dividend R17:R16 with 16-bit input value from R23:R22
    MOV   R17, R23
    MOV   R16, R22

  ; Thousands Digit: Input / 1000
    LDI   R19, hi8(1000)
    LDI   R18, lo8(1000)
    RCALL div_16bit             ; Quotient -> R21:R20, Remainder -> R23:R22
    
  ; Logic to suppress leading zeros
    CPI   R20, 0                ; Check if the 16-bit quotient is zero
    BREQ  sth                   ; If it is, don't print it
    
    MOV   R16, R20              ; Quotient (0-9) fits in one byte
    SUBI  R16, -48              ; Convert to ASCII
    RCALL print_char
    SET                         ; set leading zero flag

sth:MOV   R17, R23
    MOV   R16, R22              ; move remainder to R17:R16 as the next dividend

  ; Hundreds Digit: Remainder / 100
    LDI   R19, 0
    LDI   R18, 100
    RCALL div_16bit             ; Quotient -> R21:R20, Remainder -> R23:R22

    BRTS  ph                    ; if there is digit printed, skip the leading zero check
    CPI   R20, 0
    BREQ  sh1
    
ph: MOV   R16, R20              ; Quotient (0-9) fits in one byte
    SUBI  R16, -48              ; Convert to ASCII
    RCALL print_char
    SET                         ; set leading zero flag

sh1:MOV   R17, R23
    MOV   R16, R22

  ; Tens Digit: Remainder / 10
    LDI   R19, 0
    LDI   R18, 10
    RCALL div_16bit             ; Quotient -> R21:R20, Remainder -> R23:R22

    BRTS  pt                    ; if there is digit printed, skip the leading zero check
    CPI   R20, 0
    BREQ  st1

pt: MOV   R16, R20              ; Quotient (0-9) fits in one byte
    SUBI  R16, -48              ; Convert to ASCII
    RCALL print_char
    SET                         ; set leading zero flag

  ; Units Digit: The final remainder
st1:MOV   R16, R22              ; Take remainder directly
    SUBI  R16, -48              ; Convert to ASCII
    RCALL print_char

  ; Print Newline
    LDI   R16, '\r'
    RCALL print_char
    LDI   R16, '\n'
    RCALL print_char

    CLT                         ; clear leading zero flag

    POP   R25
    POP   R24
    POP   R23
    POP   R22
    POP   R21
    POP   R20
    POP   R19
    POP   R18
    POP   R17
    POP   R16                   ; restore register value from stack
    RET

; -----------------------------------------------------------------------------------------

print_decimal_2digit:
    PUSH  R16
    PUSH  R17
    PUSH  R18
    PUSH  R19
    PUSH  R20
    PUSH  R21
    PUSH  R22
    PUSH  R23
    PUSH  R24
    PUSH  R25                   ; save value of the register used onto stack

    SBRS  R22, 7                ; check if temp is negative
    RJMP  pos                   ; if not, jump to pos
    ANDI  R22, 0x7F             
    
    LDI   R16, '-'              ; if yes, remove the sign and print '-'
    RCALL print_char

  ; Initialize dividend R17:R16 with 8-bit input value from R22
pos:CLR   R17
    MOV   R16, R22

  ; Tens digit: |Input| / 10
    LDI   R19, 0
    LDI   R18, 10
    RCALL div_16bit             ; Quotient -> R21:R20, Remainder -> R23:R22  

    CPI   R20, 0                ; Check if the 16-bit quotient is zero
    BREQ  st2                   ; If it is, don't print it

    MOV   R16, R20              ; Quotient (0-9) fits in one byte
    SUBI  R16, -48              ; Convert to ASCII
    RCALL print_char

  ; Units digit: The remainder of the division
st2:MOV   R16, R22              ; Take remainder directly
    SUBI  R16, -48              ; Convert digit to ASCII
    RCALL print_char

  ; Print Newline
    LDI   R16, '\r'
    RCALL print_char
    LDI   R16, '\n'
    RCALL print_char

    POP   R25
    POP   R24
    POP   R23
    POP   R22
    POP   R21
    POP   R20
    POP   R19
    POP   R18
    POP   R17
    POP   R16                   ; restore register value from stack
    RET

; =========================================================================================

 print_smoke:
    LDI   R30, lo8(smoke_msg)   ; Z points to the smoke message 
    LDI   R31, hi8(smoke_msg)
    CALL  print_message

    CLR   R23
    MOV   R22, R8               ; Move smoke data to R23:R22
    LSL   R22
    ROL   R23
    LSL   R22
    ROL   R23                   ; Shift left 2 times (multiply by 4)
    CALL print_decimal_3digit
    
    RET

print_temp:
    LDI   R30, lo8(temp_msg)    ; Z points to the temperature message 
    LDI   R31, hi8(temp_msg)
    CALL  print_message

    MOV   R22, R9               ; Move temp data to R22
    CALL  print_decimal_2digit

    RET

; -----------------------------------------------------------------------------------------

print_message:
agn:LPM   R18, Z+               ; load char of string onto R18
    CPI   R18, 0                ; check if R18 = 0 (end of string)
    BREQ  ext    
l1: LDS   R17, UCSR0A         
    SBRS  R17, UDRE0            ; test data buffer if data can be sent
    RJMP  l1                    ; if not, back to l1
    STS   UDR0, R18             ; send char in R18 to the serial monitor
    RJMP  agn                   ; loop for the next char
ext:RET

; =========================================================================================

delay_50ms:
    LDI   R21, 5                ; 5*10ms = 50ms delay
    JMP   delay_loop_inner
delay_one_sec:
    LDI   R21, 100              ; 100*10ms = 1s delay
delay_loop_inner:               ; generate 10ms delay
    LDI   R22, 255
    LDI   R23, 255
delay_inner:
    DEC   R23
    BRNE  delay_inner
    DEC   R22
    BRNE  delay_inner
    DEC   R21
    BRNE  delay_loop_inner
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

delay_timer_5ms:
    LDI   R24, 50               ; Set loop counter to 10 for 50*100us = 000us
    RJMP   delay_1ms_loop
delay_timer_1ms:
    LDI   R24, 10               ; Set loop counter to 10 for 10*100us = 1000us
delay_1ms_loop:
    CLR   R20
    OUT   TCNT0, R20
    LDI   R20, 200
    OUT   OCR0A, R20            ; Load compare value for ~100us delay
    LDI   R20, 0b00000010
    OUT   TCCR0B, R20
wait_100us_flag:
    IN    R20, TIFR0
    SBRS  R20, OCF0A
    RJMP  wait_100us_flag
    LDI   R20, 1<<OCF0A
    OUT   TIFR0, R20
    CLR   R20
    OUT   TCCR0B, R20

    DEC   R24
    BRNE  delay_1ms_loop
    RET

; =========================================================================================

temp_msg:
    .ascii "Temperature: "
    .byte 10,0

smoke_msg:
    .ascii "Smoke (ppm): "
    .byte 10,0

; -----------------------------------------------------------------------------------------

flame_warning:
    .ascii "WARNING!"
    .byte 13
    .ascii "FLAME DETECTED"
    .byte 0

emergency_warning:
    .ascii "WARNING!"
    .byte 13
    .ascii "EMERGENCY BUTTON"
    .byte 0

fire_alert:
    .ascii "ALERT!"
    .byte 13
    .ascii "FIRE+SMOKE HIGH"
    .byte 0

smoke_notice:
    .ascii "NOTICE!"
    .byte 13
    .ascii "HIGH SMOKE"
    .byte 0

temp_notice:
    .ascii "NOTICE!"
    .byte 13
    .ascii "HIGH TEMP"
    .byte 0

reset_msg:
    .ascii "SAFE CONDITION"
    .byte 13
    .ascii "RESETTING..."
    .byte 0

safe:
    .ascii "SAFE CONDITION"
    .byte 13,0