;================================================================
; Game Quiz Math 
; Target: PIC16F877, Fosc = 20MHz (HS)
;================================================================

    LIST P=16F877
    #include <p16f877.inc>

    __CONFIG _CP_OFF & _WDT_OFF & _BODEN_OFF & _PWRTE_OFF & _HS_OSC & _WRT_ENABLE_ON & _LVP_OFF & _DEBUG_OFF & _CPD_OFF

;----------------------------------------------------------------
; Bank Select Macros
;----------------------------------------------------------------
BANK0   MACRO
        bcf STATUS,RP0
        bcf STATUS,RP1
        ENDM

BANK1   MACRO
        bsf STATUS,RP0
        bcf STATUS,RP1
        ENDM

;----------------------------------------------------------------
; Variables (Bank 0)
;----------------------------------------------------------------
        CBLOCK 0x20
        SCORE           ; Accumulated score
        STATE           ; Game state machine
        OPCODE          ; 0=+, 1=-, 2=*, 3=/
        NUM1            ; First operand
        NUM2            ; Second operand
        RESULTV         ; Correct answer
        ANSWER          ; User answer
        DIGCNT          ; Entered digits counter (0, 1, 2)
        DIG1            ; First digit
        TICKCNT         ; 100ms interrupt counter (0 to 9)
        SECCNT          ; Countdown seconds counter (5 to 0)
        FLAGS           ; bit0 = Timeout, bit1 = Update LCD
        TEMP
        TEMP2
        KEYV            ; Keypad scan code
        BCDH            ; Tens digit in ASCII
        BCDL            ; Units digit in ASCII
        DELAY_LOOP
        ENDC

        ; Interrupt Context Save (Common RAM 0x70-0x7F)
        CBLOCK 0x70
        W_TEMP
        STATUS_TEMP
        ENDC

FLG_TIMEOUT     EQU 0
FLG_UPDSEC      EQU 1

ST_SELECT       EQU .0
ST_SHOW         EQU .1
ST_INPUT        EQU .2
ST_RESULT       EQU .3

; Timer1 reload value for 100ms at 20MHz with 1:8 Prescaler
; 65536 - 62500 = 3036 = 0x0BDC
T1_PRELOAD_H    EQU 0x0B
T1_PRELOAD_L    EQU 0xDC

; T1CON: 1:8 Prescaler (bits 5-4 = 11), Timer ON (bit 0 = 1) -> 0x31
T1_ON_1_8       EQU 0x31

;================================================================
; Reset & Interrupt Vectors
;================================================================
        ORG 0x0000
        goto MAIN

        ORG 0x0004
        goto ISR

;================================================================
; INTERRUPT SERVICE ROUTINE - Timer1 (100ms)
;================================================================
ISR:
        movwf   W_TEMP
        swapf   STATUS,w
        movwf   STATUS_TEMP
        BANK0

        btfss   PIR1,TMR1IF
        goto    ISR_DONE

        bcf     PIR1,TMR1IF             ; Clear interrupt flag

        ; Reload Timer1 for 100ms
        bcf     T1CON,TMR1ON
        movlw   T1_PRELOAD_H
        movwf   TMR1H
        movlw   T1_PRELOAD_L
        movwf   TMR1L
        movlw   T1_ON_1_8
        movwf   T1CON

        ; Toggle RC7 monitor pin every 100ms
        movlw   0x80
        xorwf   PORTC,f

        ; Count time only during input state
        movf    STATE,w
        xorlw   ST_INPUT
        btfss   STATUS,Z
        goto    ISR_DONE

        ; Count 10 ticks of 100ms = 1 second
        incf    TICKCNT,f
        movlw   .10
        subwf   TICKCNT,w
        btfss   STATUS,Z
        goto    ISR_DONE

        ; 1 second elapsed
        clrf    TICKCNT
        bsf     FLAGS,FLG_UPDSEC

        movf    SECCNT,f
        btfsc   STATUS,Z
        goto    ISR_TIMEOUT_TRIG

        decf    SECCNT,f
        goto    ISR_DONE

ISR_TIMEOUT_TRIG:
        bsf     FLAGS,FLG_TIMEOUT       ; 5 seconds elapsed
        clrf    T1CON

ISR_DONE:
        swapf   STATUS_TEMP,w
        movwf   STATUS
        swapf   W_TEMP,f
        swapf   W_TEMP,w
        retfie

;================================================================
; MAIN
;================================================================
MAIN:
        BANK0
        clrf    PORTD
        clrf    PORTE
        clrf    PORTC
        clrf    PORTB

        BANK1
        movlw   0x06
        movwf   ADCON1                  ; Digital I/O on PORTA and PORTE

        movlw   0x20
        movwf   TRISA                   ; RA5 input for reset button
        movlw   0x0F
        movwf   TRISB                   ; RB0-RB3 inputs, RB4-RB7 outputs
        clrf    TRISC                   ; RC7 output for monitor
        clrf    TRISD                   ; PORTD output for LCD data
        clrf    TRISE                   ; RE0=EN, RE1=RS

        bcf     OPTION_REG,7            ; Enable PORTB pull-ups
        bcf     OPTION_REG,5            ; Timer0 internal clock

        clrf    T1CON
        bsf     PIE1,TMR1IE             ; Enable Timer1 interrupt
        BANK0

        clrf    SCORE
        clrf    FLAGS
        clrf    STATE

        ; Initialize LCD display
        call    LCD_Init

        ; Enable global and peripheral interrupts
        bsf     INTCON,PEIE
        bsf     INTCON,GIE

;----------------------------------------------------------------
; State 1: Selection screen
;----------------------------------------------------------------
STATE_SELECT:
        clrf    T1CON
        clrf    FLAGS
        movlw   ST_SELECT
        movwf   STATE

        call    LCD_Clear
        movlw   0x80
        call    send_c
        call    Print_SelectLine        ; "Select: + - * /"
        call    Show_ScoreLine          ; Display current score

SEL_LOOP:
        ; Check reset button on RA5 (Active Low)
        btfsc   PORTA,5
        goto    SEL_POLL_KEY
        clrf    SCORE                   ; Reset score
        call    Show_ScoreLine
        call    del_15m
SEL_WAIT_REL:
        btfss   PORTA,5
        goto    SEL_WAIT_REL

SEL_POLL_KEY:
        call    Keypad_Scan
        movf    KEYV,w
        xorlw   0xFF
        btfsc   STATUS,Z
        goto    SEL_LOOP

        movf    KEYV,w
        xorlw   0x0A                    ; Key A = Addition
        btfsc   STATUS,Z
        goto    GOT_ADD

        movf    KEYV,w
        xorlw   0x0B                    ; Key B = Subtraction
        btfsc   STATUS,Z
        goto    GOT_SUB

        movf    KEYV,w
        xorlw   0x0C                    ; Key C = Multiplication
        btfsc   STATUS,Z
        goto    GOT_MUL

        movf    KEYV,w
        xorlw   0x0D                    ; Key D = Division
        btfsc   STATUS,Z
        goto    GOT_DIV

        goto    SEL_LOOP

GOT_ADD:
        clrf    OPCODE
        goto    STEP2_GEN
GOT_SUB:
        movlw   .1
        movwf   OPCODE
        goto    STEP2_GEN
GOT_MUL:
        movlw   .2
        movwf   OPCODE
        goto    STEP2_GEN
GOT_DIV:
        movlw   .3
        movwf   OPCODE

;----------------------------------------------------------------
; State 2: Generate random numbers from Timer0
;----------------------------------------------------------------
STEP2_GEN:
        movf    TMR0,w
        movwf   TEMP

        ; High nibble -> NUM1 (0-9)
        swapf   TEMP,w
        andlw   0x0F
        movwf   NUM1
        movlw   .10
        subwf   NUM1,w
        btfsc   STATUS,C
        movwf   NUM1

        ; Low nibble -> NUM2 (0-9)
        movf    TEMP,w
        andlw   0x0F
        movwf   NUM2
        movlw   .10
        subwf   NUM2,w
        btfsc   STATUS,C
        movwf   NUM2

        movf    OPCODE,w
        xorlw   .0
        btfsc   STATUS,Z
        goto    GEN_ADD

        movf    OPCODE,w
        xorlw   .1
        btfsc   STATUS,Z
        goto    GEN_SUB

        movf    OPCODE,w
        xorlw   .2
        btfsc   STATUS,Z
        goto    GEN_MUL
        goto    GEN_DIV

GEN_ADD:
        movf    NUM1,w
        addwf   NUM2,w
        movwf   RESULTV
        goto    STEP3_SHOW

GEN_SUB:
        ; Prevent negative results by swapping
        movf    NUM2,w
        subwf   NUM1,w
        btfsc   STATUS,C
        goto    GEN_SUB_OK
        movf    NUM1,w
        movwf   TEMP2
        movf    NUM2,w
        movwf   NUM1
        movf    TEMP2,w
        movwf   NUM2
GEN_SUB_OK:
        movf    NUM2,w
        subwf   NUM1,w
        movwf   RESULTV
        goto    STEP3_SHOW

GEN_MUL:
        ; Clamp NUM1 to max 5
        movlw   .6
        subwf   NUM1,w
        btfss   STATUS,C
        goto    GEN_MUL_CALC
        movlw   .6
        subwf   NUM1,f
GEN_MUL_CALC:
        clrf    RESULTV
        movf    NUM2,w
        movwf   TEMP
        movf    TEMP,f
        btfsc   STATUS,Z
        goto    STEP3_SHOW
GEN_MUL_LOOP:
        movf    NUM1,w
        addwf   RESULTV,f
        decfsz  TEMP,f
        goto    GEN_MUL_LOOP
        goto    STEP3_SHOW

GEN_DIV:
        ; Prevent division by zero
        movf    NUM2,f
        btfsc   STATUS,Z
        incf    NUM2,f
        clrf    RESULTV
        movf    NUM1,w
        movwf   TEMP
GEN_DIV_LOOP:
        movf    NUM2,w
        subwf   TEMP,w
        btfss   STATUS,C
        goto    STEP3_SHOW
        movf    NUM2,w
        subwf   TEMP,f
        incf    RESULTV,f
        goto    GEN_DIV_LOOP

;----------------------------------------------------------------
; State 3: Display question and prepare input
;----------------------------------------------------------------
STEP3_SHOW:
        clrf    T1CON
        movlw   ST_SHOW
        movwf   STATE

        clrf    ANSWER
        clrf    DIGCNT
        movlw   .5
        movwf   SECCNT
        clrf    TICKCNT
        clrf    FLAGS

        call    LCD_Clear
        movlw   0x80
        call    send_c

        ; Display question: NUM1 op NUM2 = _ _
        movf    NUM1,w
        call    Print_Digit
        call    Print_OpChar
        movf    NUM2,w
        call    Print_Digit

        movlw   ' '
        call    send_d
        movlw   '='
        call    send_d
        movlw   ' '
        call    send_d
        movlw   '_'
        call    send_d
        movlw   ' '
        call    send_d
        movlw   '_'
        call    send_d

        call    Show_ScoreAndTimer

        ; Reload and start Timer1
        bcf     PIR1,TMR1IF
        movlw   T1_PRELOAD_H
        movwf   TMR1H
        movlw   T1_PRELOAD_L
        movwf   TMR1L

        movlw   ST_INPUT
        movwf   STATE
        movlw   T1_ON_1_8
        movwf   T1CON

;----------------------------------------------------------------
; State 4: Input 2 digits within 5 seconds
;----------------------------------------------------------------
STATE_INPUT:
        btfss   FLAGS,FLG_UPDSEC
        goto    CHK_TIMEOUT
        bcf     FLAGS,FLG_UPDSEC
        call    Refresh_Timer_Digit

CHK_TIMEOUT:
        btfsc   FLAGS,FLG_TIMEOUT
        goto    INPUT_TIMEOUT

        call    Keypad_Scan
        movf    KEYV,w
        xorlw   0xFF
        btfsc   STATUS,Z
        goto    STATE_INPUT

        ; Filter non-digits
        movlw   .10
        subwf   KEYV,w
        btfsc   STATUS,C
        goto    STATE_INPUT

        movf    DIGCNT,f
        btfsc   STATUS,Z
        goto    INPUT_FIRST_DIGIT

        ; Second digit entered
        movf    DIG1,w
        movwf   TEMP2
        clrf    ANSWER
IF2_MUL:
        movf    TEMP2,f
        btfsc   STATUS,Z
        goto    IF2_ADD2
        movlw   .10
        addwf   ANSWER,f
        decf    TEMP2,f
        goto    IF2_MUL
IF2_ADD2:
        movf    KEYV,w
        addwf   ANSWER,f

        movlw   0x80 + .11
        call    send_c
        movf    KEYV,w
        addlw   '0'
        call    send_d

        clrf    T1CON
        goto    STEP5_RESULT

INPUT_FIRST_DIGIT:
        movf    KEYV,w
        movwf   DIG1
        incf    DIGCNT,f

        movlw   0x80 + .9
        call    send_c
        movf    KEYV,w
        addlw   '0'
        call    send_d
        goto    STATE_INPUT

INPUT_TIMEOUT:
        clrf    T1CON

;----------------------------------------------------------------
; State 5: Check result and update score
;----------------------------------------------------------------
STEP5_RESULT:
        clrf    T1CON
        movlw   ST_RESULT
        movwf   STATE

        call    LCD_Clear
        movlw   0x80
        call    send_c

        btfsc   FLAGS,FLG_TIMEOUT
        goto    RES_TIMEOUT

        movf    ANSWER,w
        subwf   RESULTV,w
        btfsc   STATUS,Z
        goto    RES_CORRECT
        goto    RES_WRONG

RES_TIMEOUT:
        call    Print_TimeoutMsg        ; "Timeout! -3"
        movlw   .3
        call    Score_Sub
        goto    RES_DONE

RES_CORRECT:
        call    Print_CorrectMsg        ; "Correct! +10"
        movlw   .10
        addwf   SCORE,f
        goto    RES_DONE

RES_WRONG:
        call    Print_WrongMsg          ; "Wrong! -5"
        movlw   .5
        call    Score_Sub

RES_DONE:
        call    Show_ScoreLine

        ; Display result delay (about 2 seconds)
        movlw   .140
        movwf   DELAY_LOOP
DLY_RES:
        call    del_15m
        decfsz  DELAY_LOOP,f
        goto    DLY_RES

        goto    STATE_SELECT

;================================================================
; Helper Functions
;================================================================
; Subtract score clamped at 0
Score_Sub:
        movwf   TEMP
        movf    TEMP,w
        subwf   SCORE,w
        btfss   STATUS,C
        goto    SCORE_CLAMP
        movf    TEMP,w
        subwf   SCORE,f
        return
SCORE_CLAMP:
        clrf    SCORE
        return

Refresh_Timer_Digit:
        movlw   0xC0 + .13
        call    send_c
        movf    SECCNT,w
        addlw   '0'
        call    send_d
        return

Show_ScoreLine:
        movlw   0xC0
        call    send_c
        call    Print_ScoreLabel
        movf    SCORE,w
        call    Bin2BCD_2digit
        movf    BCDH,w
        call    send_d
        movf    BCDL,w
        call    send_d
        return

Show_ScoreAndTimer:
        movlw   0xC0
        call    send_c
        call    Print_ScoreLabel
        movf    SCORE,w
        call    Bin2BCD_2digit
        movf    BCDH,w
        call    send_d
        movf    BCDL,w
        call    send_d
        movlw   ' '
        call    send_d
        movlw   'T'
        call    send_d
        movlw   ':'
        call    send_d
        movlw   ' '
        call    send_d
        movf    SECCNT,w
        addlw   '0'
        call    send_d
        return

Bin2BCD_2digit:
        movwf   TEMP
        clrf    BCDH
BCD_LOOP:
        movlw   .10
        subwf   TEMP,w
        btfss   STATUS,C
        goto    BCD_DONE
        movwf   TEMP
        incf    BCDH,f
        goto    BCD_LOOP
BCD_DONE:
        movf    TEMP,w
        movwf   BCDL
        movlw   '0'
        addwf   BCDH,f
        movlw   '0'
        addwf   BCDL,f
        return

Print_Digit:
        addlw   '0'
        call    send_d
        return

Print_OpChar:
        movf    OPCODE,w
        xorlw   .0
        btfsc   STATUS,Z
        goto    PO_ADD
        movf    OPCODE,w
        xorlw   .1
        btfsc   STATUS,Z
        goto    PO_SUB
        movf    OPCODE,w
        xorlw   .2
        btfsc   STATUS,Z
        goto    PO_MUL
        goto    PO_DIV

PO_ADD:
        movlw   '+'
        call    send_d
        return
PO_SUB:
        movlw   '-'
        call    send_d
        return
PO_MUL:
        movlw   '*'
        call    send_d
        return
PO_DIV:
        movlw   '/'
        call    send_d
        return

;================================================================
; LCD Strings
;================================================================
Print_SelectLine:
        movlw   'S'
        call    send_d
        movlw   'e'
        call    send_d
        movlw   'l'
        call    send_d
        movlw   'e'
        call    send_d
        movlw   'c'
        call    send_d
        movlw   't'
        call    send_d
        movlw   ':'
        call    send_d
        movlw   ' '
        call    send_d
        movlw   '+'
        call    send_d
        movlw   ' '
        call    send_d
        movlw   '-'
        call    send_d
        movlw   ' '
        call    send_d
        movlw   '*'
        call    send_d
        movlw   ' '
        call    send_d
        movlw   '/'
        call    send_d
        return

Print_ScoreLabel:
        movlw   'S'
        call    send_d
        movlw   'c'
        call    send_d
        movlw   'o'
        call    send_d
        movlw   'r'
        call    send_d
        movlw   'e'
        call    send_d
        movlw   ':'
        call    send_d
        movlw   ' '
        call    send_d
        return

Print_CorrectMsg:
        movlw   'C'
        call    send_d
        movlw   'o'
        call    send_d
        movlw   'r'
        call    send_d
        movlw   'r'
        call    send_d
        movlw   'e'
        call    send_d
        movlw   'c'
        call    send_d
        movlw   't'
        call    send_d
        movlw   '!'
        call    send_d
        movlw   ' '
        call    send_d
        movlw   '+'
        call    send_d
        movlw   '1'
        call    send_d
        movlw   '0'
        call    send_d
        return

Print_WrongMsg:
        movlw   'W'
        call    send_d
        movlw   'r'
        call    send_d
        movlw   'o'
        call    send_d
        movlw   'n'
        call    send_d
        movlw   'g'
        call    send_d
        movlw   '!'
        call    send_d
        movlw   ' '
        call    send_d
        movlw   '-'
        call    send_d
        movlw   '5'
        call    send_d
        return

Print_TimeoutMsg:
        movlw   'T'
        call    send_d
        movlw   'i'
        call    send_d
        movlw   'm'
        call    send_d
        movlw   'e'
        call    send_d
        movlw   'o'
        call    send_d
        movlw   'u'
        call    send_d
        movlw   't'
        call    send_d
        movlw   '!'
        call    send_d
        movlw   ' '
        call    send_d
        movlw   '-'
        call    send_d
        movlw   '3'
        call    send_d
        return

;================================================================
; 4x4 Keypad Scan
;================================================================
Keypad_Scan:
        movlw   0xFF
        movwf   KEYV

        ; Row 1 (RB4 = 0)
        bcf     PORTB,4
        bsf     PORTB,5
        bsf     PORTB,6
        bsf     PORTB,7
        call    del_100u
        btfss   PORTB,0
        goto    KS_K1
        btfss   PORTB,1
        goto    KS_K2
        btfss   PORTB,2
        goto    KS_K3
        btfss   PORTB,3
        goto    KS_KA

        ; Row 2 (RB5 = 0)
        bsf     PORTB,4
        bcf     PORTB,5
        call    del_100u
        btfss   PORTB,0
        goto    KS_K4
        btfss   PORTB,1
        goto    KS_K5
        btfss   PORTB,2
        goto    KS_K6
        btfss   PORTB,3
        goto    KS_KB

        ; Row 3 (RB6 = 0)
        bsf     PORTB,5
        bcf     PORTB,6
        call    del_100u
        btfss   PORTB,0
        goto    KS_K7
        btfss   PORTB,1
        goto    KS_K8
        btfss   PORTB,2
        goto    KS_K9
        btfss   PORTB,3
        goto    KS_KC

        ; Row 4 (RB7 = 0)
        bsf     PORTB,6
        bcf     PORTB,7
        call    del_100u
        btfss   PORTB,1
        goto    KS_K0
        btfss   PORTB,3
        goto    KS_KD

        goto    KS_EXIT

KS_K1:  movlw   .1
        goto    KS_SAVE
KS_K2:  movlw   .2
        goto    KS_SAVE
KS_K3:  movlw   .3
        goto    KS_SAVE
KS_KA:  movlw   0x0A
        goto    KS_SAVE

KS_K4:  movlw   .4
        goto    KS_SAVE
KS_K5:  movlw   .5
        goto    KS_SAVE
KS_K6:  movlw   .6
        goto    KS_SAVE
KS_KB:  movlw   0x0B
        goto    KS_SAVE

KS_K7:  movlw   .7
        goto    KS_SAVE
KS_K8:  movlw   .8
        goto    KS_SAVE
KS_K9:  movlw   .9
        goto    KS_SAVE
KS_KC:  movlw   0x0C
        goto    KS_SAVE

KS_K0:  movlw   .0
        goto    KS_SAVE
KS_KD:  movlw   0x0D
        goto    KS_SAVE

KS_SAVE:
        movwf   KEYV
        ; Wait for key release
KS_REL:
        bcf     PORTB,4
        bcf     PORTB,5
        bcf     PORTB,6
        bcf     PORTB,7
        call    del_100u
        movf    PORTB,w
        andlw   0x0F
        xorlw   0x0F
        btfss   STATUS,Z
        goto    KS_REL

KS_EXIT:
        bsf     PORTB,4
        bsf     PORTB,5
        bsf     PORTB,6
        bsf     PORTB,7
        return

;================================================================
; LCD Routines
;================================================================
LCD_Init:
        call    del_15m
        call    del_15m

        movlw   0x30
        call    send_c
        call    del_4m

        movlw   0x30
        call    send_c
        call    del_100u

        movlw   0x30
        call    send_c
        call    del_100u

        movlw   0x38                    ; 8-bit, 2 lines, 5x8
        call    send_c
        call    del_100u

        movlw   0x0C                    ; Display ON, cursor OFF
        call    send_c
        call    del_100u

        movlw   0x06                    ; Increment, no shift
        call    send_c
        call    del_100u

        call    LCD_Clear
        return

LCD_Clear:
        movlw   0x01
        call    send_c
        call    del_1_5m
        call    del_1_5m
        return

send_c:
        movwf   PORTD
        bcf     PORTE,1                 ; RS = 0
        nop
        bsf     PORTE,0                 ; E = 1
        call    del_50u
        bcf     PORTE,0                 ; E = 0
        call    del_50u
        return

send_d:
        movwf   PORTD
        bsf     PORTE,1                 ; RS = 1
        nop
        bsf     PORTE,0                 ; E = 1
        call    del_50u
        bcf     PORTE,0                 ; E = 0
        call    del_50u
        bcf     PORTE,1
        return

;================================================================
; Delay Routines (Dedicated memory at 0x6A and 0x6B)
;================================================================
del_50u:
        movlw   d'85'
        movwf   0x6A
lulaa1: decfsz  0x6A,f
        goto    lulaa1
        return

del_100u:
        movlw   d'200'
        movwf   0x6A
lulaa2: decfsz  0x6A,f
        goto    lulaa2
        return

del_1_5m:
        movlw   d'90'
        movwf   0x6B
lulaa3: movlw   d'27'
        movwf   0x6A
lulaa4: decfsz  0x6A,f
        goto    lulaa4
        decfsz  0x6B,f
        goto    lulaa3
        return

del_4m:
        movlw   d'205'
        movwf   0x6B
lulaa5: movlw   d'35'
        movwf   0x6A
lulaa6: decfsz  0x6A,f
        goto    lulaa6
        decfsz  0x6B,f
        goto    lulaa5
        return

del_15m:
        movlw   d'125'
        movwf   0x6B
lulaa7: movlw   d'190'
        movwf   0x6A
lulaa8: decfsz  0x6A,f
        goto    lulaa8
        decfsz  0x6B,f
        goto    lulaa7
        return

        END
