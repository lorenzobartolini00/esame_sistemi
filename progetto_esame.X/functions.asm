		#include "p16f887.inc"
		#include "macro.inc"
		#include "costants.inc"			;definizione di costanti
		
		;label importate
		extern	curr_sec, curr_min, printBuff, byte_count, flags
		
		;funzioni esportate
		global	start_timer, toggle_led, reload_tmr1, increment_chronometer, format_data, prepare_transmission
		
		;variabili nella memoria di banco
		    udata_shr
tmp         res    .1
tmp2         res    .1
		
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

increment_chronometer
		;incremento i secondi
		banksel	curr_sec
		incf	curr_sec

		;se i secondi sono arrivati a 60, allora incrementa i minuti, altrimenti return
		movlw	.60
		subwf	curr_sec, w

		;se il bit Z di status è a 1 significa che i secondi sono arrivati a 60
		btfss	STATUS, Z
		goto	end_increment

		;azzero i secondi
		clrf	curr_sec

		;incremento i minuti
		banksel	curr_min
		incf	curr_min

		;se i minuti sono arrivati a 60, allora azzerali e return
		movlw	.60
		subwf	curr_min, w

		;se il bit Z di status è a 1 significa che i secondi sono arrivati a 60
		btfss	STATUS, Z
		goto	end_increment

		;azzero i secondi
		clrf	curr_min
		
end_increment
		return

format_data
	
		;questa funzione copia il contenuto di curr_sec, curr_min in printBuff.

		;in totale printBuff è composto da 6 byte
		;il primo e il secondo sono per le unità e le decine dei secondi
		;il terzo è per il carattere ":", il quarto e il quinto sono per le decine e le unità dei minuti e l'ultimo è per il carattere invio
		
;formatto i minuti
		
		;copio su W la variabile che contiene i minuti totalizzati dal cronometro
		banksel	    curr_min
		movf	    curr_min, w
		
		;chiamo una funzione che salva su W e tmp rispettivamente le decine e le unità del valore presente su W
		pagesel	    split_number
		call	    split_number
		
		;su W sono salvate le decine dei minuti
		banksel	printBuff
		;copio le decine di minuti sul primo registro di printBuff
		movwf	(printBuff+0)
		
		;su tmp sono salvate le unità dei minuti
		movf	tmp, w
		;copio le unità di minuti sul secondo registro di printBuff
		movwf	(printBuff+1)
		
;inserisco i due punti
		
		movlw	.58	;corrisponde al carattere ":" nella codifica ASCII
		movwf	(printBuff+2)
		
;formatto i secondi
		
		;copio su W la variabile che contiene i secondi totalizzati dal cronometro
		banksel	    curr_sec
		movf	    curr_sec, w
		
		;chiamo una funzione che salva su W e tmp rispettivamente le decine e le unità del valore presente su W
		pagesel	    split_number
		call	    split_number
		
		;su W sono salvate le decine dei secondi
		banksel	printBuff
		;copio le decine di secondi sul terzo registro di printBuff
		movwf	(printBuff+3)
		
		;su tmp sono salvate le unità dei secondi
		movf	tmp, w
		;copio le unità di secondi sul quarto registro di printBuff
		movwf	(printBuff+4)
		
;inserisco carattere invio

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

		bankisel	printBuff	;siccome sto usando l'indirizzamento indiretto, devo utilizzare la direttiva bankisel che setta il bit IRP del registro STATUS
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
		
split_number
		;W: numero decimale da suddividere in decine e unità.
		;le decine dovranno essere salvate su W, mentre le unità sul registro tmp
		;bisogna anche convertire le due cifre in codice ASCII
		
		;Esempio: numero 25 deve essere suddiviso in 2 e 5 e poi il 2 -> 2+48 = 50, che in ASCII corrisponde al carattere '2' e
		;5 -> 5+48 = 53, che in ASCII corrisponde al carattere '5'
		
		;per fare ciò occorre realizzare una divisione attraverso la tecnica delle sottrazioni ripetute.
		
		;utilizzo tmp2 come contatore. Alla fine del loop conterrà il quoziente della divisione tra il numero da convertire e 10, ovvero le decine del numero stesso,
		;mentre tmp conterrà il resto della divisione, che corrisponde alle unità del numero stesso.
		
		;Esempio: 25/10 = 2 con resto di 5, dove 2 sono le decine e 5 sono le unità
		
		;azzero tmp2
		clrf	tmp2

loop_div_10
		
		;salvo il contenuto di W su tmp
		movwf	tmp	;la prima volta che si entra nel loop, su W c'è il numero da formattare, mentre le volte successive ci sarà il risultato della sottrazione del loop precedente
		
		;sottraggo dal numero da formattare 10(number - 10)
		movlw	.10
		subwf	tmp, w	    ;lo salvo in w, in modo da non modificare il contenuto di tmp, nel caso in cui il risultato dell'operazione sia negativo
		
		;controllo che il risultato sia maggiore di 0, andando a verificare il bit di carry(prestito). 
		;Se C=0, allora il risultato è minore di zero, pertanto bisogna smettere di sottrarre.
		btfss	STATUS, C
		goto end_div
		
		;incremento il contatore
		incf	tmp2
		
		goto	loop_div_10
end_div		
		;A questo punto si ha:
		;tmp	-> unità
		;tmp2	-> decine
		
		;converto i numeri da decimale a formato ASCII. Basterà sommare al valore contenuto in tmp e tmp2 il numero 48
		;0  -> .48
		;1  -> .49
		;2  -> .50
		;3  -> .51
		;4  -> .52
		;5  -> .53
		;6  -> .54
		;7  -> .55
		;8  -> .56
		;9  -> .57
		movlw	.48
		
		;salvo il risultato della conversione delle unità in tmp
		addwf	tmp, f
		;salvo il risultato della conversione delle decine in W
		addwf	tmp2, w
		
		return
	end