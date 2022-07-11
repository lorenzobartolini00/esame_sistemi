		#include "p16f887.inc"
		#include "macro.inc"
		#include "costants.inc"			;definizione di costanti
		
		;label importate
		extern	curr_sec, curr_min
		
		;funzioni esportate
		global	start_timer, toggle_led, reload_tmr1, increment_cronometer
		
;-----------------------------------------------------------------------------------------------
;utility functions utilizzate a supporto del programma principale
		code
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

increment_cronometer
	;incremento i secondi
	incf	curr_sec
	
	;se i secondi sono arrivati a 60, allora incrementa i minuti, altrimenti return
	movlw	.60
	subwf	curr_sec, w

	;se il bit Z di status è a 1 significa che i secondi sono arrivati a 60
	banksel	STATUS
	btfss	STATUS, Z
	goto	end_increment
	
	;azzero i secondi
	clrf	curr_sec
	
	;toggle led di conteggio
	pagesel	toggle_led
	movlw	0x08
	call	toggle_led
	
	;incremento i minuti
	incf	curr_min, w
	
	;se i minuti sono arrivati a 60, allora azzerali e return
	movlw	.60
	subwf	curr_min, w

	;se il bit Z di status è a 1 significa che i secondi sono arrivati a 60
	banksel	STATUS
	btfss	STATUS, Z
	goto	end_increment
	
	;azzero i secondi
	clrf	curr_min
		
end_increment
	return
	
	end