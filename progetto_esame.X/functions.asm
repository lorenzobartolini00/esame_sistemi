		#include "p16f887.inc"
		#include "macro.inc"
		#include "costants.inc"			;definizione di costanti
		
		;label importate
		extern	curr_sec, curr_min, printBuff, byte_count, flags
		
		;funzioni esportate
		global	start_timer, toggle_led, reload_tmr1, increment_cronometer, format_data, prepare_transmission
		
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

format_data
	
	;questa funzione copia il contenuto di curr_sec, curr_min in printBuff.
	
	;in totale printBuff è composto da 5 byte
	;il primo e il secondo sono per le unità e le decine dei secondi
	;il terzo è per il carattere ":", mentre gli ultimi due sono per le decine e le unità dei minuti
	
	banksel	printBuff
	
	movlw	'm'
	movwf	(printBuff+0)
	movlw	'm'
	movwf	(printBuff+1)
	movlw	.58	;corrisponde al carattere ":" nella codifica ASCII
	movwf	(printBuff+2)
	movlw	's'
	movwf	(printBuff+3)
	movlw	's'
	movwf	(printBuff+4)
	
	movlw .10         ; carattere invio
	movwf (printBuff+5)
	
	
	return
	
prepare_transmission
	
	;printBuff: contiene i byte da trasmettere
	;W: numero di byte da trasmettere
	
	;questa funzione inizializza la trasmissione
	
	;salvo w nella variabile byte_count che conta quanti byte sono rimasti da trasmettere
	banksel	byte_count
	movwf	byte_count
	
	banksel	printBuff
	;copio l'indirizzo di printBuff nel registro FSR per l'indirizzamento indiretto
	movlw	printBuff
	movwf	FSR
	
	;setto il flag di trasmissione in corso, in modo da evitare che il micro vada in sleep
	bsf flags, TX_ON
	
	;abilito l'interrupt TXIE. L'IF viene settato quando la trasmissione seriale è abilitata e il buffer non contiene nessun byte pendente.
	;Siccome la trasmissione seriale è stata abilitata nella configurazione hwd, il flag a questo punto è già settato
	;Una volta che abilito l'IE, verrà richiamata la interrupt service routine.
	banksel	PIE1
	bsf PIE1, TXIE
	
	return
	
	end