;definizioni costanti

;-------------------------------------------------------------------------------------------

;Timer0 viene utilizzato per il debouncing. L'oscillatore interno ha una frequenza di 8MHz e la frequenza scelta come sorgente per il timer è Fosc/4.
;Avendo scelto un PS di 256, il periodo Ttick è pari a 256/(8MHz/4) = 128us.
;Siccome il tempo di debouncing è di 10ms e x:10ms = 1:128us, allora x = 10ms/256us = 78 tick. 
;Pertanto la costante da caricare sul timer0 sarà (.256-.39)

tmr_10ms    equ	   (.256-.78)

;Timer1 è utilizzato per il cronometro, che ha una risoluzione di 1 secondo.
;Avendo scelto come sorgente per il timer1 quella dell'oscillatore esterno, che ha una frequenza di 36768KHz, e avendo impostato il PS a 1, 
;il Ttick è pari a 1/36768KHz
;Il tempo massimo che può raggiungere il timer1 con queste impostazioni è pari a Tmax = Ttick*65536 = 2s.
;Pertanto il numero di incrementi che corrisponde ad 1s è pari alla metà degli incrementi massimi, ovvero 65536/2.

tmr_1s	    equ    (.65536-.32768)

;la variabile flags è un vettore che contiene 2 bit di flag:
CAN_SLEEP   equ .0
TX_ON	    equ .1

;nomi led
LED_D1	    equ .0
LED_D2	    equ .1
LED_D3	    equ .2
LED_D4	    equ .3