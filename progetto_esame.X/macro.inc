; definizione di macro utili per ottenere un codice piu' compatto
;
; se si include questo file in MPLAB X, selezionare "exclude from build"
;  dalle proprieta' del file (tasto destro sul file nella finestra
;  del progetto)


; macro per settare il valore di un registro (movlw + banksel + movwf)
setRegK			macro Reg, Const
		movlw Const
		banksel Reg
		movwf Reg
				endm


; macro per azzerare un registro (banksel + clrf)
setReg0	macro Reg
		    banksel Reg
		    clrf Reg
	    endm

