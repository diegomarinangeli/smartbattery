# SmartBattery

## Descrizione

Script PowerShell che imposta un limite di carica della batteria (default 80%) su laptop MSI, scrivendo direttamente al controller EC (Embedded Controller) tramite l'interfaccia WMI `MSI_ACPI` (`root\wmi`, GUID `ABBC0F6E-8EA1-11D1-00A0-C90629100000`) — la stessa interfaccia usata internamente da MSI Center.

**Non serve MSI Center installato.** Il limite viene scritto direttamente nel firmware dell'EC: una volta impostato, il controller ferma la carica al valore configurato **in autonomia hardware**, senza bisogno di nessun processo/servizio in background e sopravvive ai riavvii.

Testato e verificato su un **MSI Cyborg 15 A12VE** il 2026-08-18 con un round-trip scrittura/lettura (scritto 80 → riletto correttamente 80).

## Come funziona

Il registro EC all'indirizzo `0xd7` contiene la soglia di carica. Il bit 7 del byte marca la scrittura come valida; i 7 bit bassi sono la percentuale (0-100):

- Scrittura: `byte = percentuale | 0x80`
- Lettura: `percentuale = byte & 0x7F`

Un byte letto come `0x80` (percentuale 0 con bit 7 settato) indica "nessun limite impostato" — comportamento di default su un laptop mai configurato, carica normalmente al 100%.

Questo meccanismo è stato identificato incrociando: (1) una patch del kernel Linux per il driver `msi-wmi-platform` (`platform/x86: msi-wmi-platform: Add charge_threshold support`, non ancora mergiata al momento della scrittura) che descrive indirizzo e formato, e (2) verifica empirica diretta sull'hardware reale tramite chiamate WMI in PowerShell.

## Perché la carica si ferma sotto la soglia impostata (es. 78% invece di 80%)

L'EC decide quando fermare la carica confrontando la soglia con il **proprio** contatore interno di carica (fuel gauge), che è un valore diverso dalla percentuale che Windows mostra in tray (calcolata da Windows a partire dai valori ACPI di capacità, con un refresh proprio e non sincronizzato con quello dell'EC). In pratica l'EC può raggiungere la soglia e fermare la carica prima che il numero mostrato da Windows si aggiorni di conseguenza — quindi impostando 80 si può vedere la carica fermarsi visibilmente all'78% circa. Non è un bug nella scrittura/lettura del registro (il round-trip scrittura→lettura è sempre fedele a quanto scritto): sono due contatori indipendenti che divergono leggermente.

Lo script compensa questo con il parametro `-Offset` (default `2`, tarato sul gap osservato su questa macchina: richiesti 80, fermata visibile a 78): scrive nell'EC `Percent + Offset`, in modo che il punto di stop *visibile in Windows* combaci con `-Percent`. Se sul tuo laptop il gap è diverso, ricalibra: imposta un limite, lascia caricare fino allo stop, guarda a che percentuale si è davvero fermato in Windows, e regola `-Offset` di conseguenza al prossimo utilizzo. Il gap può anche spostarsi leggermente nel tempo con l'usura della batteria (degrado della full-charge-capacity), quindi vale la pena ricontrollarlo ogni tanto.

## Requisiti

- Windows 10/11
- Laptop MSI con interfaccia WMI `MSI_ACPI` esposta (verifica con `Get-CimClass -Namespace root\wmi -ClassName MSI_ACPI` — se la classe non esiste, questo script non funziona sul tuo modello)
- Privilegi di amministratore (lo script si auto-eleva con un prompt UAC se lanciato senza)

## Utilizzo

Imposta il limite all'80% (default):
```powershell
.\Set-BatteryLimit.ps1
```

Imposta una percentuale diversa:
```powershell
.\Set-BatteryLimit.ps1 -Percent 60
```

Ricalibra l'offset di compensazione (vedi sezione sopra) se sul tuo laptop il gap osservato è diverso da 2 punti:
```powershell
.\Set-BatteryLimit.ps1 -Percent 80 -Offset 3
```

Legge il limite attualmente impostato:
```powershell
.\Set-BatteryLimit.ps1 -Get
```

Rimuove il limite (torna a caricare normalmente al 100%):
```powershell
.\Set-BatteryLimit.ps1 -Percent 100
```

Lo script verifica sempre il valore rileggendolo dopo la scrittura — se la rilettura non corrisponde a quanto scritto, si ferma con un errore invece di dare per scontato che sia andata a buon fine.

## Se il tuo modello MSI non ha la classe WMI `MSI_ACPI`

Alcuni modelli/generazioni MSI potrebbero non esporre questa interfaccia, o usare un indirizzo EC diverso da `0xd7`. In quel caso l'alternativa sicura è usare **MSI Center** (Microsoft Store) → Battery Master → modalità "Balanced" (carica sotto il 70%, ferma all'80%).

## Licenza

MIT.
