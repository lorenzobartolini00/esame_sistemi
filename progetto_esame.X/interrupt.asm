		#include "p16f887.inc"
		#include "macro.inc"
		#include "costants.inc"			;definizione di costanti
		
		;label importate(variabili)
		extern	printBuff, flags, portb_prev, byte_count
		;label importate(funzioni)
		extern toggle_led, reload_tmr1, increment_chronometer, start_timer, format_data, prepare_transmission
	
		;variabili condivise
		udata_shr
w_temp          res    .1  ; salvataggio registri (context saving)
status_temp     res    .1  ;  "             "                "
pclath_temp	res    .1			; riserva un byte di memoria associato alla label pclath_temp
	
		;direttiva che attiva i led di debug
		;#define	DEBUG
		
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
		
		;toggle led del cronometro
		movlw   0x01        ;Corrisponde alla costante 00000001
		pagesel toggle_led
		call toggle_led
		
		
		;faccio il toggle del cronometro
		banksel T1CON
		movlw	0x01
		xorwf   T1CON, f
		
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
		goto test_usart
		banksel	PIR1
		btfss	PIR1, TMR1IF
		goto test_usart
		
		;ricarico il timer
		pagesel reload_tmr1
		call	reload_tmr1
		
		#ifdef	DEBUG
		    ;toggle led debug
		    movlw   0x02        ;Corrisponde alla costante 00000010
		    pagesel toggle_led
		    call toggle_led
		#endif
		
		;chiamo funzione che incrementa il conteggio del cronometro
		pagesel increment_chronometer
		call	increment_chronometer
		
		;chiamo funzione che scrive il valore del cronometro su printBuff
		pagesel	format_data
		call format_data
		
		;copio la costante 6 in w, siccome dovrò trasmettere 6 byte -> 'm' + 'm' + ':' + 's' + 's' + 'invio'
		movlw	.6
		
		;chiamo funzione che prepara la trasmissione dei dati
		pagesel	prepare_transmission
		call	prepare_transmission
		
		goto irq_end
		
test_usart
		;controllo se il buffer si è svuotato, cioè se la trasmissione precedente è terminata
		banksel PIE1
		btfss PIE1, TXIE
		goto irq_end
		banksel PIR1
		btfss PIR1, TXIF
		goto irq_end
		
		;in questo caso siamo pronti ad iniziare una nuova trasmissione
		
		;controllo che ci siano ancora byte da trasmettere
		banksel byte_count
		movf	byte_count, w
		
		;se il bit Z del registro status è settato, significa che byte_count è a zero e non ci sono più byte da trasmettere
		btfsc	STATUS, Z
		goto	uart_tx_end
		
		;se ho ancora byte da trasmettere, li recupero dal buffer, andando a leggere il registro INDF: indirizzamento indiretto di printBuff
		movf	INDF, w
		
		;ora copio il byte contenuto in printBuff nel registro TXREG, causando l'inizio della trasmissione
		banksel	TXREG
		movwf	TXREG
		
		;incremento il registro FSR, in modo da andare a puntare al byte successivo di printBuff
		incf	FSR, f
		
		;decremento il contatore
		banksel	byte_count
		decf	byte_count, f
		
		goto irq_end

uart_tx_end    
		;resetto ilbit di flag. In questo modo il micro può tornare in sleep
		bcf	flags, TX_ON
		
		;disabilito l'interrupt enable, siccome i byte da trasmettere sono terminati
		banksel	PIE1
		bcf	PIE1, TXIE
		
irq_end
		;ripristino del contesto
		movf	pclath_temp,w
		movwf	PCLATH			
		swapf	status_temp,w				
		movwf	STATUS		
		swapf	w_temp,f		
		swapf	w_temp,w
		
		retfie
		
		end