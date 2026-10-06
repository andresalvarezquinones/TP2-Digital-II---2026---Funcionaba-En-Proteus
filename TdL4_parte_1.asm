;========================================================
; TdL4 - Cronómetro SS:CC con TMR0
; PIC16F887 - FOSC = 4 MHz (cristal XT)
;
; PINES
;   RD0-RD6 -> segmentos a,b,c,d,e,f,g (bus compartido)
;   RD7     -> punto decimal dp (opcional, solo en el display 2)
;   RB1     -> display 1: decenas de segundos
;   RB2     -> display 2: unidades de segundos (con punto decimal)
;   RB3     -> display 3: decenas de centésimas
;   RB4     -> display 4: unidades de centésimas
;   RA0     -> pulsador (a GND, pull-up externo de 10 kOhm)
;
; SUPUESTOS DE NIVELES (cambiar si el circuito es distinto)
;   Displays de cátodo común  -> segmento activo en alto
;   Selectores activos en alto (transistor NPN a GND)
;   Pulsador activo en bajo
;
; BASE DE TIEMPO
;   TMR0 con reloj interno FOSC/4, prescaler 1:32, precarga 178
;   T0 = (256-178) x 32 x 1 us = 2,496 ms
;   4 interrupciones = 1 centésima (4 x T0 = 9,98 ms)
;   Cada selector se activa cada 4 x T0 = ~10 ms (refresco ~100 Hz)
;   Antirrebote: 8 muestras = 8 x T0 = ~20 ms (presión y liberación)
;   Pulsación larga: 400 muestras = 400 x T0 = ~1 s desde la
;   validación de la presión
;========================================================

        LIST    P=16F887
        #include <P16F887.INC>
        ERRORLEVEL -302         ; silenciar avisos de banco

        __CONFIG _CONFIG1, _FOSC_XT & _WDTE_OFF & _PWRTE_ON & _MCLRE_ON & _CP_OFF & _CPD_OFF & _BOREN_OFF & _IESO_OFF & _FCMEN_OFF & _LVP_OFF
        __CONFIG _CONFIG2, _WRT_OFF & _BOR40V

;--------------------------------------------------------
; MODO DEPURACIÓN
; Descomentar la línea siguiente para que "iniciar"
; arranque desde DEBUG_SEG:DEBUG_CENT en vez de 00:00.
; Ejemplos: 9 y 95 (prueba 09:99 -> 10:00)
;           59 y 95 (prueba 59:99 -> 00:00)
; DEJARLO COMENTADO EN EL PROGRAMA DEFINITIVO.
;--------------------------------------------------------
;#define DEBUG
DEBUG_SEG   EQU     .9
DEBUG_CENT  EQU     .95

;--------------------------------------------------------
; CONSTANTES
;--------------------------------------------------------
PRECARGA    EQU     .178        ; precarga de TMR0
TICKS_CENT  EQU     .4          ; interrupciones por centésima
DEB_N       EQU     .8          ; muestras de antirrebote (~20 ms)
LARGA_L     EQU     0x90        ; 400 = 0x0190 (parte baja)
LARGA_H     EQU     0x01        ; 400 = 0x0190 (parte alta)
MASC_SEL    EQU     b'11100001' ; PORTB: bits que NO son selectores (RB1..RB4 = 0)

;--------------------------------------------------------
; VARIABLES (banco 0)
;--------------------------------------------------------
        CBLOCK  0x20
        TICK                    ; interrupciones dentro de la centésima
        DIGITO                  ; dígito que se muestra (0..3)
        CENTESIMAS              ; 0..99
        SEGUNDOS                ; 0..59
        ESTADO                  ; 0=detenido, 1=contando, 2=pausado
        BTN_ESTADO              ; 0=liberado estable, 1=presionado estable
        DEB                     ; contador de antirrebote
        DUR_L                   ; duración de la pulsación (16 bits)
        DUR_H
        LARGA_HECHA             ; 1 si la larga ya se disparó
        EV_CORTO                ; evento pulsación corta (lo pone la ISR)
        EV_LARGO                ; evento pulsación larga (lo pone la ISR)
        D0                      ; buffer de display: decenas de segundos
        D1                      ; unidades de segundos
        D2                      ; decenas de centésimas
        D3                      ; unidades de centésimas (D0..D3 contiguos)
        TMP                     ; auxiliar del multiplexado
        C_COPIA                 ; copias para la conversión (main)
        S_COPIA
        DEC_C
        DEC_S
        ENDC

; Variables de contexto en zona común a todos los bancos (0x70-0x7F)
        CBLOCK  0x70
        W_TEMP
        STATUS_TEMP
        PCLATH_TEMP
        FSR_TEMP
        ENDC

;--------------------------------------------------------
; VECTORES
;--------------------------------------------------------
        ORG     0x0000
        GOTO    INICIO

        ORG     0x0004
        GOTO    ISR

;--------------------------------------------------------
; TABLAS (quedan en los primeros 256 words: el ADDWF PCL
; no cruza un límite de página de 256)
;--------------------------------------------------------
; Segmentos, cátodo común. bit0=a ... bit6=g, bit7=dp
TABLA_7SEG:
        ADDWF   PCL,F
        RETLW   b'00111111'     ; 0
        RETLW   b'00000110'     ; 1
        RETLW   b'01011011'     ; 2
        RETLW   b'01001111'     ; 3
        RETLW   b'01100110'     ; 4
        RETLW   b'01101101'     ; 5
        RETLW   b'01111101'     ; 6
        RETLW   b'00000111'     ; 7
        RETLW   b'01111111'     ; 8
        RETLW   b'01101111'     ; 9

; Máscara del selector de cada dígito en PORTB (activo en alto)
TABLA_SEL:
        ADDWF   PCL,F
        RETLW   b'00000010'     ; RB1 (display 1)
        RETLW   b'00000100'     ; RB2 (display 2)
        RETLW   b'00001000'     ; RB3 (display 3)
        RETLW   b'00010000'     ; RB4 (display 4)

