# :mortar_board: Esame Sistemi Elettronici, Luglio 2022
```
- Hardware: PIC16F887
- Ambiente di sviluppo: Microchip MPLAB X IDE](#segnalazione-bug-e-richieste-di-aiuto)
- Linguaggio: Assembly)
- Gestione eventi: microcontrollore in modalità sleep (se possibile) in assenza di eventi da processare
```
## :page_with_curl: Consegna:
Si realizzi un firmware che implementi un cronometro con risoluzione di un secondo e visualizzi il tempo tramite porta seriale (EUSART) nel formato "mm:ss". Un pulsante permetta di arrestare e riattivare il cronometro, mentre un LED sia acceso quando il cronometro è attivo.

## :computer: Inizializzazione hardware
Prima di tutto impostiamo la frequenza del clock a 8MHz, attraverso il registro OSCCON. Questa scelta influenzerà la scelta del bode rate (vedi più avanti).
Preliminarmente vengono disattivati tutti gli interrupt attraverso un clear di INTCON, siccome verranno attivati al momento opportuno.

Le periferiche necessarie sono le seguenti:

- [Timer 0: gestione debouncing](#timer-0)
- [Timer 1: conteggio cronometro](#timer-1)
- [EUSART: bode rate](#eusart)

Inoltre è necessario impostare i pin di I/O nel seguente modo:
```
- PORTB: tutti i pin settati come input digitali. Pertanto resetto tutti i bit del registro ANSELH per disabilitare l’input analogico. Verrà utilizzato solamente il pin RB0, ovvero quello a cui è connesso uno dei pulsanti di cui la board è dotata(SW1). Abilito anche la funzionalità interrupt-on-change per il pulsante RB0, settando il bit corrispondente del registro IOCB. Infine attivo per i 4 pulsanti anche le resistenze di pull-up, essenziali quando i pin sono settato come input. 
- PORTA e PORTE: input digitali. 
- PORTD: i 4 LSB settati come output digitali. Su questi pin sono connessi i 4 LED della board. Nel progetto ne viene utilizzato solo uno.
- PORTC: tutti i bit settati come input digitali, tranne il bit RC6, che, una volta abilitato il modulo EUSART, viene automaticamente settato come output digitale. Infatti il pin RC6 viene utilizzato come asynchronous serial output, ovvero per trasmettere in uscita i dati dalla porta seriale. 
```

### :hourglass: Timer 0
Questo timer viene utilizzato per gestire il debouncing, pertanto deve essere impostato per contare un tempo pari a 10ms. Seguono i calcoli per la scelta del valore da scrivere su TMR0.
```
F_OSC=8MHz; PS=256;
Ad ogni incremento di questo registro, trascorre un tempo pari a:
T_tick=1/(F_OSC/4×1/PS)=1/(8MHz/4×1/256)=128μs
Siccome 1:128μs=x:10ms , ho bisogno di un numero di incrementi pari a:
x=10ms/128μs=78 tick
Pertanto in TMR0 dovrò scrivere (256-78).
```
### :hourglass: Timer 1
Questo timer viene utilizzato per il conteggio del cronometro, che ha una risoluzione di 1s. Seguono i calcoli per la scelta del valore da scrivere in TMR1. 
Siccome il microprocessore deve poter andare in sleep mentre il cronometro continua a contare, devo scegliere come sorgente, il clock prodotto dall’oscillatore esterno LP(Low Power). 
```
F_LP=32,768kHz; PS=1;
Siccome il tempo massimo che il timer è in grado di contare(con queste impostazioni) è
T_max=1/(F_LP×1/PS)=1/32,768kHz=2s
e che il numero di incrementi massimo (essendo un timer a 16 bit) è pari a 2^16=65536, allora il numero di incrementi per avere 1 secondo è semplicemente pari alla metà di 65536, cioè 32768.
```
### :fax: EUSART
Per scegliere il bode rate è necessario impostare 3 bit: 
- SYNC bit di TXSTA, che permette di scegliere tra la modalità asincrona o quella sincrona;
- BRGH bit di TXSTA, che abilita la modalità High speed;
- BRG16 bit di BAUDCTL, che abilita la possibilità di utilizzare valori a 16 bit per il registro che determina il bode rate(SPBRG e SPBRGH).
Scelgo il bode rate standard di 19,2kHz. 
```
SYNC=0→Asynchronous mode
BRGH=1→High speed mode
BRG16=0→8 bit register
```
Una volta impostati questi tre bit, è necessario ricavare il valore da scrivere sul registro SPBRG(ed eventualmente SPBRGH se BRG = 1) per ottenere il bode rate desiderato. La formula che lega il contenuto di SPBRG al bode rate(per le scelte attuali) è la seguente:
```
Desired Bode Rate=  F_OSC/(16×([SPBRG]+1))

Invertendo si ricava:

[SPBRG]=(F_OSC/(Desired Bode Rate))/16-1

Sostituendo con i valori F_OSC=8Mhz,DBR=19.2kHz,si ha:
[SPBRG]=(8Mhz/19.2kHz)/16-1≈25
```

La scelta di questo valore è anche giustificata dalla bassa percentuale di errore(vedi data sheet).

## :zap: Interrupt
Quando viene richiamata la ISR, vi sono varie sorgenti di interrupt da testare:
- T0IF: significa che il debouncing è terminato. Dopo aver resettato l’IF, posso settare il flag di can_sleep(per permettere al micro di andare in sleep) e riabilitare l’interrupt del pulsante(RBIE), che era stato disabilitato alla pressione del pulsante.
- RBIF: significa che uno dei pin di PORTB ha cambiato stato. Siccome abbiamo abilitato l’IOC soltanto per RB0, sarà soltanto lui a poter far entrare il micro nella ISR. Dopo aver iniziato la sequenza di debouncing(da effettuare a prescindere se il pulsante è stato premuto o rilasciato), dobbiamo controllare se il pulsante è stato premuto. In quest’ultimo caso, come da specifiche, verrà messo in pausa il cronometro(oppure fatto ripartire), mentre un LED verrà spento (oppure acceso). Infine verrà fatto il clear del flag can_sleep, impedendo al micro di andare in sleep fino al termine del debouncing e disabilitato interrupt da pulsante.
- TMR1IF: significa che è passato un secondo, pertanto dovrò ricaricare il timer, incrementare il cronometro(cioè le due variabili che tengono traccia del conteggio per minuti e secondi) e trasmettere il nuovo valore attraverso la porta seriale. 
A questo punto preparo la trasmissione. 
  1. A partire dalle due variabili che ho incrementato(curr_min e curr_sec), ricavo quattro byte che rappresentano il conteggio(decine di minuti e secondi, unità di minuti e secondi).
  2. Copio questi 4 byte, insieme a quello che corrisponde al carattere ‘:’ e quello per il carattere ‘a capo’ in un array(printBuff).
  3. Abilito l’interrupt flag TXIE, dopo aver copiato l’indirizzo dell’array(printBuff) nel registro FSR.
- TXIF: significa che la trasmissione precedente è terminata, pertanto è possibile trasmettere un nuovo dato. I dati da trasmettere vengono prelevati tramite indirizzamento indiretto da printBuff(attraverso la lettura di INDF) e copiato nel registro TXREG, avviando la trasmissione. Nell’array sono salvati 6 byte, che verranno trasmessi uno di seguito all’altro. 
Quando i byte da inviare sono terminati, l’interrupt enable della porta seriale(TXIE) viene disabilitato. Mentre la trasmissione è in corso, viene settato un bit di flag che impedisce al micro di andare in sleep(TX_ON). 

Nota: siccome prima che venga trasmesso il primo byte il registro a scorrimento è vuoto, il bit TXIF è già settato, pertanto non appena si setta TXIE, verrà richiamata la ISR per la trasmissione del primo byte. TXIF è settato quando lo shift register è vuoto, ovvero quando la trasmissione è terminata.

## :loop: Main loop
Il main loop è molto semplice, siccome la maggior parte del programma è gestita nell’ISR. Il micro gestisce le fasi di entrata e uscita dallo sleep. Per la maggior parte del tempo, infatti, il micro può andare in sleep, siccome il conteggio del timer1 prosegue anche in questo caso. 
Il micro non può andare in sleep nei seguenti casi:
- Durante il debouncing: per questo viene controllato il flag can_sleep.
- Durante la trasmissione. Il bit di flag TX_ON viene settato non appena comincia la trasmissione(dopo il set di TXIE) e resettato non appena viene caricato l’ultimo byte da trasmettere sul registro a scorrimento del modulo EUSART. 
- Prima del termine della trasmissione: siccome TX_ON viene resettato prima che la trasmissione sia effettivamente conclusa, è necessario controllare il bit TMRT del registro TXSTA per assicurarsi che la trasmissione sia realmente terminata.
Prima di andare in sleep, disabilito il GIE, in modo da evitare che il micro salti nella ISR. Il GIE verrà riabilitato non appena il micro esce dallo sleep, per poter gestire l’interrupt.

Il micro si risveglia in due casi: 
- Overflow di timer 1;
- Pressione pulsante RB0.

