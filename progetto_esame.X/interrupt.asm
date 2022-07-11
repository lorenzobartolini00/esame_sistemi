		#include "p16f887.inc"
		#include "macro.inc"
		#include "costants.inc"			;definizione di costanti
		
		;label importate(variabili)
		extern	printBuff, uartCount, flags, portb_prev
		;label importate(funzioni)
		extern toggle_led, reload_tmr1, increment_cronometer, start_timer
	
		;variabili condivise
		udata_shr
w_temp          res    .1  ; salvataggio registri (context saving)
status_temp     res    .1  ;  "             "                "
pclath_temp	res    .1			; riserva un byte di memoria associato alla label pclath_temp
		
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
		
		;chiamo funzione che incrementa il conteggio del cronometro
		pagesel increment_cronometer
		call	increment_cronometer
		
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
		
		end