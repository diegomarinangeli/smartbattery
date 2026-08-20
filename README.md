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

## Se la carica sembra fermarsi sotto la soglia impostata

Verificato end-to-end (non solo scrittura/lettura del registro, ma carica reale) sul Cyborg 15 A12VE il 2026-08-20: scritto 82 nell'EC, lasciato caricare fino allo stop, Windows ha mostrato 82%. Cioè il valore scritto nel registro EC e la percentuale che Windows mostra al momento dello stop **coincidono 1:1** — non c'è un offset fisso da compensare. Un precedente episodio ("impostato 80, fermato a 78") non si è ripetuto in questo test: potrebbe essere stato letto in un momento diverso rispetto al rilassamento della tensione post-carica, o provenire da un meccanismo diverso (es. MSI Center invece di questo script).

Per questo il parametro `-Offset` esiste solo come scappatoia manuale (default `0`, nessuna compensazione applicata automaticamente): se osservi *tu stesso*, in modo ripetibile, un gap tra `-Percent` e dove la carica si ferma davvero sul tuo laptop, puoi correggerlo con `-Offset`. Non impostarlo "a intuito": una soglia troppo alta fa caricare la batteria oltre il limite voluto, il che è peggio (per la durata della batteria) di un occasionale, non confermato, arresto leggermente sotto.

## La carica non riparte finché la batteria non scende parecchio sotto la soglia (comportamento voluto, non un bug)

Con la soglia impostata a 80%, se scolleghi e ricolleghi l'alimentatore (o se il laptop consuma più di quanto l'AC fornisce) mentre la batteria è, ad esempio, al 75%, la carica **non riparte subito**. Questo è normale: senza un'isteresi, il laptop farebbe continui micro-cicli di carica/scarica appena sotto l'80%, il che usura la batteria più di un limite netto. L'EC ha quindi una soglia di ripresa più bassa di quella di stop (nell'implementazione standard MSI, circa 10 punti sotto — quindi la carica riparte solo sotto ~70% con soglia 80%). Tra le due soglie il sistema resta semplicemente alimentato via AC senza toccare la batteria: non è "bloccato", sta facendo esattamente il suo lavoro.

Per verificare lo stato reale (invece di fidarti solo della percentuale mostrata) usa:
```powershell
Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus | Select-Object Charging, Discharging, PowerOnline
```
`PowerOnline: True` + `Charging: False` + `Discharging: False` = alimentato da AC, batteria in pausa dentro la finestra di isteresi. È lo stato atteso, non un errore.

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

Correggi manualmente se osservi tu stesso un gap ripetibile tra `-Percent` e dove la carica si ferma davvero (vedi sezione sopra):
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
