;Progetto di esame Bartolini
;-----------------------------------------------------------------------------------------------
	
;Si realizzi un firmware che implementi un cronometro con risoluzione di un secondo
;e visualizzi il tempo tramite porta seriale (EUSART) nel formato "mm:ss". Un
;pulsante permetta di arrestare e riattivare il cronometro, mentre un LED sia acceso
;quando il cronometro è attivo.

;-----------------------------------------------------------------------------------------------
    
	#include	"p16f887.inc"	
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
flags		res    .1
w_temp          res    .1  ; salvataggio registri (context saving)
status_temp     res    .1  ;  "             "                "
pclath_temp	res    .1			; riserva un byte di memoria associato alla label status_temp
portb_prev	res    .1
		    
    ; variabili in RAM(memoria NON condivisa)
		udata
printBuff	res    .6	;Riservo 6 byte, anche se serviranno soltanto 3 byte
uartCount       res    .1  ; numero di byte rimasti da stampare

	 ;definizioni costanti
	 
    ;Timer0 viene utilizzato per il debouncing. L'oscillatore interno ha una frequenza di 8MHz e la frequenza scelta come sorgente per il timer è Fosc/4.
    ;Avendo scelto un PS di 256, il periodo Ttick è pari a 256/(8MHz/4) = 128us.
    ;Siccome il tempo di debouncing è di 10ms e x:10ms = 1:128us, allora x = 10ms/256us = 78 tick. 
    ;Pertanto la costante da caricare sul timer0 sarà (.256-.39)
tmr_10ms    EQU	   (.256-.78)
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
		
		;leggo PORTB per annullare mismatch
		banksel	PORTB
		movf	PORTB, w	; legge PORTB eliminando condizione di mismatch
		bcf INTCON, RBIF
		bsf INTCON, RBIE
		
		;abilito interrupt da timer 1
		banksel PIE1
		bsf PIE1, TMR1IE
		
		;inizializzo portb_prev
		movlw	0x01    ; Pulsante non premuto -> switch aperto -> Vdd -> Logic 1
		movwf	portb_prev
		
		;accendo il led di debug e il led di sleep
		banksel PORTD
		movlw	B'00000101'
		movwf	PORTD
		
		;ricarico il timer
		pagesel reload_tmr1
		call	reload_tmr1
		
		;faccio partire il cronometro
		banksel T1CON
		bsf	T1CON, TMR1ON
		
		;Abilito interrupt per timer1
		banksel PIE1
		bsf     PIE1, TMR1IE
		
		;abilito gloabal interrupt enable
		bsf INTCON, GIE
		bsf INTCON, PEIE
main_loop
		
wait_sleep
		;disabilito il global interrupt enable: la cpu non può andare in interrupt nella fase che precede lo sleep
		bcf INTCON, GIE
		
		;la cpu non va in sleep se can_sleep = 0
		btfsc flags, CAN_SLEEP
		goto go_sleep
		
		;TRMT = 1 -> Shift Register empty
		;TRMT = 0 -> Shift Register full
		;banksel TXSTA
		;la cpu non va in sleep se TRMT = 0, perchè la trasmissione non è terminata
		;btfsc TXSTA, TRMT
		;goto go_sleep
		
		;riabilito il global interrupt enable
		bsf INTCON, GIE
		
		goto wait_sleep
go_sleep
		;spengo il led di sleep
		banksel PORTD
		bcf PORTD, LED_D3
		
		sleep
wake_up		
		;accendo il led di sleep
		banksel PORTD
		bsf PORTD, LED_D3
		
		;una volta risvegliato dall'interrupt, riabilito il GIE per entrare nella ISR
		bsf INTCON, GIE
		
		goto main_loop
;-----------------------------------------------------------------------------------------------
;interrupt service routine
irq		code	0x0004
		;salvataggio del contesto
		movwf	w_temp		
		swapf	STATUS,w		
		movwf	status_temp		
		movf	PCLATH,w		
		movwf	pclath_temp
test_timer0
		;controllo se l'interrupt è stato generato dallo scadere del timer0, utilizzato per il debouncing
		btfss INTCON, T0IE
		goto test_button
		btfss INTCON, T0IF
		goto test_button
		
		;resetto l'interrupt flag e disabilito interrupt da timer 0
		bcf INTCON, T0IF
		bcf INTCON, T0IE
		
		;riabilito l'interrupt dei pulsanti.
		bsf INTCON, RBIE
		
		;setto can_sleep
		bsf flags, CAN_SLEEP
		
		goto irq_end
test_button
		btfss	INTCON, RBIF
		goto	test_timer1
		btfss	INTCON, RBIE
		goto	test_timer1
		
		;leggo la porta per eliminare la condizione di mismatch
		banksel	PORTB
		movf	PORTB, w	; legge PORTB eliminando condizione di mismatch
		bcf	INTCON, RBIF
		
		;controllo se c'è stato un cambiamento dello stato della porta
		xorwf	portb_prev, w	
		andlw	0x01	       
		btfsc	STATUS,Z        
		goto	button_end	
		
		;il pulsante 1 è stato premuto o rilasciato, iniziare il conteggio di debouncing
		
		;disabilito interrupt
		bcf INTCON, RBIE
		
		;resetto can_sleep. Il micro non può andare in sleep durante il debouncing
		bcf flags, CAN_SLEEP
		
		;faccio partire il timer 0 per il debouncing
		movlw	tmr_10ms
		pagesel start_timer
		call    start_timer
	
		;se il bit 0 di portb_prev è a zero significa che il pulsante è stato premuto
		btfss	portb_prev, 0
		goto	button_end 
		
		;toggle led di debug
		movlw   0x01        ;Corrisponde alla costante 00000001
		pagesel toggle_led
		call toggle_led
		
		;faccio il toggle del cronometro
		;banksel T1CON
		;movlw	0x01
		;xorwf   T1CON, f
		
button_end
		; salva nuovo stato di PORTB su portb_prev
		banksel PORTB
		movf	PORTB, w
		movwf	portb_prev

		goto	irq_end	
		
test_timer1
		;controllo se il timer 1 è scaduto
		banksel	PIE1
		btfss	PIE1, TMR1IE
		goto irq_end
		banksel	PIR1
		btfss	PIR1, TMR1IF
		goto irq_end
		
		;ricarico il timer
		pagesel reload_tmr1
		call	reload_tmr1
		
		;toggle led timer
		movlw   0x02        ;Corrisponde alla costante 00000010
		pagesel toggle_led
		call toggle_led
		
		goto irq_end
		
test_usart
		
		
irq_end
		;ripristino del contesto
		movf	pclath_temp,w
		movwf	PCLATH			
		swapf	status_temp,w				
		movwf	STATUS		
		swapf	w_temp,f		
		swapf	w_temp,w
		
		retfie
;-----------------------------------------------------------------------------------------------
		
start_timer
		banksel TMR0
		movwf TMR0
		
		bcf INTCON, T0IF
		bsf INTCON, T0IE
		
		return
toggle_led
		
		banksel PORTD
		xorwf	PORTD, f
		
		return
		
reload_tmr1
    
	;Carico la costante sul registro a 16 bit
	banksel	TMR1L
	movlw	low  tmr_1s
	movwf	TMR1L
	movlw	high tmr_1s
	movwf	TMR1H

	;Azzero il bit di flag
	banksel	    PIR1
	bcf	    PIR1, TMR1IF

	;Faccio partire il timer
	banksel T1CON
	bsf     T1CON, TMR1ON

	return
		
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
	movlw	0xFF
	movwf	TRISA
	movwf	TRISC
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
	setRegK	OPTION_REG, B'01000111'
	
;Inizializzazione timer1
	
	;T1GINV = 0 -> non rilevante, siccome il gate è disabilitato
	;TMR1GE = 0 -> gate disabilitato
	;T1CKPS<1:0> = 00 -> prescaler a 1:1
	;T1OSCEN = 1 -> oscillatore LP abilitato
	;#T1SYNC = 1 -> sincronizzazione disabilitata(il timer deve lavorare anche in sleep)
	;TMR1CS = 1 -> seleziono sorgente esterna, oscillatore LP, dato che quando il micro è in sleep il timer deve continuare a contare
	;TMR1ON = 0 -> timer è disattivato, verrà attivato al momento opportuno
	setRegK T1CON, B'00001110'
	
	
;Configuro modulo EUSART
	
	;CSRC = 0 -> don't care in Async mode
	;TX9 = 0 -> trasmissione nono bit disabilitato
	;TXEN = 1 -> trasmissione abilitata
	;SYNC = 0 -> Asynchrnous mode
	;SENDB = 0 -> Sync Break transmission completed
	;BRGH = 1 -> sabilito modalità High speed per la generazione del bode rate
	;TMRT read only
	;TX9D = 0 -> nono bit a zero
	setRegK TXSTA, B'00100100'
	
	;SPEN = 1 -> porta seriale abilitata
	;RX9 = 0 -> ricezione nono bit disabilitato
	;SREN = 0 -> ricezione continua(non utilizzata)
	;CREN = 0 -> disabilita ricezione(non utilizzata)
	;ADDEN = 0 -> don't care
	;FERR read only
	;OERR read only
	;RX9D = 0 -> nono bit a zero
	setRegK RCSTA, B'10000000'
	
	;BRG16 = 0 -> Baud Rate generator ad 8 bit
	setReg0 BAUDCTL
	
	;imposto il bode rate.
	;bode_rate = 19.2kHz
	;SYNC = 0
	;BRGH = 1
	;BRG16 = 0
	setRegK SPBRG, .25
	
    end