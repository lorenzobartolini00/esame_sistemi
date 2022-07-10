;Progetto di esame Bartolini
;-----------------------------------------------------------------------------------------------
	
;Si realizzi un firmware che implementi un cronometro con risoluzione di un secondo
;e visualizzi il tempo tramite porta seriale (EUSART) nel formato "mm:ss". Un
;pulsante permetta di arrestare e riattivare il cronometro, mentre un LED sia acceso
;quando il cronometro è attivo.

;-----------------------------------------------------------------------------------------------
    
	list		p=16f887		; direttiva che definisce il tipo di processore
	#include	<p16f887.inc>	
	#include "macro.inc"			; definizione di macro utili
	
	; configuration bits
	__CONFIG _CONFIG1, _INTRC_OSC_NOCLKOUT & _CP_OFF & _WDT_OFF & _BOR_OFF & _PWRTE_OFF & _LVP_OFF & _DEBUG_OFF & _CPD_OFF
	__CONFIG _CONFIG2, _BOR21V

;-----------------------------------------------------------------------------------------------
	
; variabili in RAM (shared RAM)
		udata_shr
current_sec         res    .1
current_min         res    .1
	 ;flags contiene due bit: CRONO_ON e CAN_SLEEP, che vengono utilizzati per controllare se il cronometro 
	 ;è attivo e se la cpu può andare in sleep. La cpu non può andare in sleep fintanto che si sta facendo il debouncing
flags		    res	   .1
		    
    ; variabili in RAM(memoria NON condivisa)
		udata
printBuff	res	.6	;Riservo 6 byte, anche se serviranno soltanto 3 byte
w_temp          res    .1  ; salvataggio registri (context saving)
status_temp     res    .1  ;  "             "                "
uartCount       res    .1  ; numero di byte rimasti da stampare

	 ;definizioni costanti
	 
    ;Timer0 viene utilizzato per il debouncing. L'oscillatore interno ha una frequenza di 4MHz e la frequenza scelta come sorgente per il timer è Fosc/4.
    ;Avendo scelto un PS di 256, il periodo Ttick è pari a 256/(4MHz/4) = 256us.
    ;Siccome il tempo di debouncing è di 10ms e x:10ms = 1:256us, allora x = 10ms/256us = 39 tick. 
    ;Pertanto la costante da caricare sul timer0 sarà (.256-.39)
tmr_10ms    EQU	   (.256-.39)
    ;Timer1 è utilizzato per il cronometro, che ha una risoluzione di 1 secondo.
    ;Avendo scelto come sorgente per il timer1 quella dell'oscillatore esterno, che ha una frequenza di 36768KHz, e avendo impostato il PS a 1, 
    ;il Ttick è pari a 1/36768KHz
    ;Il tempo massimo che può raggiungere il timer1 con queste impostazioni è pari a Tmax = Ttick*65536 = 2s.
    ;Pertanto il numero di incrementi che corrisponde ad 1s è pari alla metà degli incrementi massimi, ovvero 65536/2.
tmr_1s	    EQU    (.65536-.32768)
max_sec	    EQU   .60	

;-----------------------------------------------------------------------------------------------

		; reset vector
rst_vector		code	0x0000
		pagesel start
		goto start


		; programma principale
		code
start  
		;chiamo inizializzazione hardware
		pagesel initHw
		call initHw
		
		;inizialmente la cpu può andare in sleep
		bsf flags, CAN_SLEEP
		
		;il cronometro ancora non è partito
		bcf flags, CRN_RUN
		
		bsf INTCON, GIE
main_loop
		
wait_sleep
		;disabilito il global interrupt enable: la cpu non può andare in interrupt nella fase che precede lo sleep
		bcf INTCON, GIE
		
		;la cpu non va in sleep se can_sleep = 0
		btfsc flags, CAN_SLEEP
		goto go_sleep
		
		;TRMT = 1 -> Shift Register empty
		;TRMT = 0 -> Shift Register full
		banksel TXSTA
		;la cpu non va in sleep se TRMT = 0, perchè la trasmissione non è terminata
		btfsc TXSTA, TRMT
		goto go_sleep
		
		;riabilito il global interrupt enable
		bsf INTCON, GIE
		
		goto wait_sleep
go_sleep
		sleep
		
		;una volta risvegliato dall'interrupt, riabilito il GIE per entrare nella ISR
		bsf INTCON, GIE
		
		goto main_loop
;-----------------------------------------------------------------------------------------------
;interrupt service routine
irq		code	0x0004
		;salvataggio del contesto
		movwf w_temp
		swapf STATUS, w
		movwf status_temp
test_timer0
		
test_button
		
test_timer1
		
test_usart
		
irq_end
		;ripristino del contesto
		swapf status_temp, w
		movwf STATUS
		swapf w_temp, f
		swapf w_temp, w
		
		retfie
		
;-----------------------------------------------------------------------------------------------
		
initHw
; Scelgo la frequenza del clock di sistema
		
	setRegK OSCCON, B'01110001' ; 8 MHz internal oscillator
	
;Interrupt
	clrf	INTCON	;tutti gli interrupt sono disabilitati
	
;Inizializzazione pulsanti PORTB
		
	;setto i pin di PORTB come output(tutti e quattro i pulsanti). 
	;0 -> output
	;1 -> input
	
	;1 -> pulsante rilasciato
	;0 -> pulsante premuto
	;il pulsante che vogliamo utilizzare è RB0
	setRegK	TRISB, 0xFF
	;setto come input anche PORTA e PORTE
	movwf	TRISA
	movwf	TRISE
	
	;disattivo input analogico su tutti i pin di PORTB
	setReg0	ANSELH
	
	;abilito l'interrupt on change sul pulsante RB0 di PORTB
	setRegK	IOCB, 0x01
	
;Inizializzazione LED
	
	;setto i pin da 3 a 0 di PORTD come output
	setRegK	TRISD, 0xF0
	
;Inizializzazione timer0
	 
	;#RBPU = 0 -> pull up di portb attivi
	;INTEDG = 0 -> interrupt sul falling edge
	;T0CS = 0 -> sorgente di clock interna Fosc/4
	;T0SE = 0 -> incremento sul fronte di salita(irrilevante, siccome utilizzo sorgente interna)
	;PSA = 0 -> prescaler assegnato al timer0
	;PS<2:0> = 111 -> prescaler a 256
	setRegK	OPTION_REG, '00000111'
	
;Inizializzazione timer1
	
	;T1GINV = 0 -> non rilevante, siccome il gate è disabilitato
	;TMR1GE = 0 -> gate disabilitato
	;T1CKPS<1:0> = 00 -> prescaler a 1:1
	;T1OSCEN = 1 -> oscillatore LP abilitato
	;#T1SYNC = 0 -> sincronizzazione disabilitata(il timer deve lavorare anche in sleep)
	;TMR1CS = 1 -> seleziono sorgente esterna, oscillatore LP, dato che quando il micro è in sleep il timer deve continuare a contare
	;TMR1ON = 0 -> timer è disattivato, verrà attivato al momento opportuno
	setRegK T1CON, '00001010'
	
	
;Configuro modulo EUSART
	
	;CSRC = 0 -> don't care in Async mode
	;TX9 = 0 -> trasmissione nono bit disabilitato
	;TXEN = 1 -> trasmissione abilitata
	;SYNC = 0 -> Asynchrnous mode
	;SENDB = 0 -> Sync Break transmission completed
	;BRGH = 1 -> sabilito modalità High speed per la generazione del bode rate
	;TMRT read only
	;TX9D = 0 -> nono bit a zero
	setRegK TXSTA, '00100100'
	
	;SPEN = 1 -> porta seriale abilitata
	;RX9 = 0 -> ricezione nono bit disabilitato
	;SREN = 0 -> ricezione continua(non utilizzata)
	;CREN = 0 -> disabilita ricezione(non utilizzata)
	;ADDEN = 0 -> don't care
	;FERR read only
	;OERR read only
	;RX9D = 0 -> nono bit a zero
	setRegK RCSTA, '10000000'
	
	;BRG16 = 0 -> Baud Rate generator ad 8 bit
	setReg0 BAUDCTL
	
	;imposto il bode rate.
	;bode_rate = 19.2kHz
	;SYNC = 0
	;BRGH = 1
	;BRG16 = 0
	
	setRegK SPBRG, .25
	
    end