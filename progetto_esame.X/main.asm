;Progetto di esame Bartolini
;-----------------------------------------------------------------------------------------------
	
;Si realizzi un firmware che implementi un cronometro con risoluzione di un secondo
;e visualizzi il tempo tramite porta seriale (EUSART) nel formato "mm:ss". Un
;pulsante permetta di arrestare e riattivare il cronometro, mentre un LED sia acceso
;quando il cronometro è attivo.

;-----------------------------------------------------------------------------------------------
    
	#include	"p16f887.inc"	
	#include "macro.inc"			; definizione di macro utili
	#include "costants.inc"			;definizione di costanti
	
	; configuration bits
	__CONFIG _CONFIG1, _INTRC_OSC_NOCLKOUT & _CP_OFF & _WDT_OFF & _BOR_OFF & _PWRTE_OFF & _LVP_OFF & _DEBUG_OFF & _CPD_OFF
	__CONFIG _CONFIG2, _BOR21V
	
	;label definite esternamente
	extern	start_timer, toggle_led, reload_tmr1, increment_chronometer, format_data, prepare_transmission  ;definite nel file functions.asm
	
	;variabili esportate
	global printBuff, flags, portb_prev, curr_sec, curr_min, byte_count
	
	;direttiva che attiva i led di debug
	;#define	DEBUG

;-----------------------------------------------------------------------------------------------
	
; variabili in RAM (shared RAM)
		udata_shr
	 ;flags contiene due bit: TX_ON e CAN_SLEEP, che vengono utilizzati per controllare se la trasmissione è in corso
	 ;e se la cpu può andare in sleep. La cpu non può andare in sleep fintanto che si sta facendo il debouncing
flags		res    .1
portb_prev	res    .1
		    
    ; variabili in RAM(memoria NON condivisa)
		udata
printBuff	 res    .6	;Riservo 6 byte al buffer
byte_count       res    .1	;Numero di byte rimasti da trasmettere
curr_sec       res    .1	;secondi
curr_min       res    .1	;minuti
       
    

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
		
;inizializzo i bit di flag e i contatori
		
		;inizialmente la cpu può andare in sleep
		bsf flags, CAN_SLEEP
		
		;la trasmissione non è in corso
		bcf flags, TX_ON
		
		;azzero i contatori dei minuti e dei secondi
		banksel curr_sec
		clrf	curr_sec
		banksel curr_min
		clrf	curr_min
		
;inizializzo portb
		
		;leggo PORTB per annullare mismatch
		banksel	PORTB
		movf	PORTB, w	; legge PORTB eliminando condizione di mismatch
		bcf INTCON, RBIF	;resetto interrupt flag
		bsf INTCON, RBIE	;abilito interrupt portb
		
		;inizializzo portb_prev
		movlw	0x01    ; Pulsante non premuto -> switch aperto -> Vdd -> Logic 1
		movwf	portb_prev
		
;inizializzo i led
		
		;accendo il led di debug e il led di sleep
		banksel PORTD
		movlw	B'00000001'
		movwf	PORTD

;inizializzo timer 1
		
		;ricarico il timer
		pagesel reload_tmr1
		call	reload_tmr1
		
		;faccio partire il cronometro
		banksel T1CON
		bsf	T1CON, TMR1ON
		
		;Abilito interrupt per timer1
		banksel PIE1
		bsf     PIE1, TMR1IE
		
		;abilito periferical interrupt enable
		bsf INTCON, PEIE
		
		;abilito global interrupt enable
		bsf INTCON, GIE


;trasmetto il valore 00:00
		
		;chiamo funzione che scrive il valore del cronometro su printBuff
		pagesel	format_data
		call format_data
		
		;copio la costante 6 in w, siccome dovrò trasmettere 6 byte -> 'm' + 'm' + ':' + 's' + 's' + 'invio'
		movlw	.6
		
		;chiamo funzione che prepara la trasmissione dei dati
		pagesel	prepare_transmission
		call	prepare_transmission
main_loop
		
wait_sleep
		;disabilito  global interrupt enable
		bcf INTCON, GIE
			
		;la cpu non può andare in sleep se can_sleep = 0
		btfsc flags, CAN_SLEEP
		goto test_tx
		
		goto no_sleep
test_tx		
		;la cpu non può andare in sleep se la trasmissione non è terminata(TX_ON = 1 -> trasmissione in corso)
		btfss	flags, TX_ON
		goto	test_sr
		
		goto no_sleep
test_sr		
		;siccome il flag TX_ON viene resettato prima che la trasmissione sia realmente terminata, occorre controllare se lo shift register è realmente vuoto
		
		;il bit TRMT indica lo stato dello shift register. Se lo shift register è vuoto, il bit è settato
		banksel	    TXSTA
		btfsc	    TXSTA, TRMT
		goto go_sleep

no_sleep
		;abilito global interrupt enable
		bsf INTCON, GIE
		
		goto	wait_sleep
go_sleep
		#ifdef DEBUG
		    ;spengo il led di sleep
		    banksel PORTD
		    bcf PORTD, 0x02
		#endif
		
		
		sleep
wake_up		
		#ifdef DEBUG
		    ;accendo il led di sleep
		    banksel PORTD
		    bsf PORTD, 0x02
		#endif
		
		
		;una volta risvegliato dall'interrupt, riabilito il GIE per entrare nella ISR
		bsf INTCON, GIE
		
		goto main_loop	
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
	setRegK WPUB, B'00001111'
	;setto come input anche PORTA e PORTE
	movlw	0xFF
	movwf	TRISA
	movwf	TRISE
	
	
	setReg0 PORTC
	setRegK TRISC, B'10111111'
	
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
	;BRGH = 1 -> abilito modalità High speed per la generazione del bode rate
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
	
	return
	
    end