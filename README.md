# Gastronova Impresión: componente local

El programa que se instala en la PC de un local para que [Gastronova](https://gastronova.com.ar) imprima comandas y
tickets en sus impresoras térmicas. La extensión
[Gastronova Impresion](https://chromewebstore.google.com/detail/hjhbknickakeacelnjfldbbhnobdibjc) le pasa cada trabajo
por *native messaging* de Chrome y él lo manda, sin filtrar, a la cola de impresión del sistema (el spooler de
Windows, CUPS en Linux y macOS).

No se conecta a internet ni guarda nada: sólo lee los mensajes de la extensión, lista las impresoras y les manda
bytes. Chrome únicamente lo deja hablar con la extensión publicada (`allowed_origins` del manifiesto que registra el
instalador).

Cómo dejarlo andando en un local:
[Cómo conectar una impresora térmica a Gastronova](https://gastronova.com.ar/blog/como-conectar-impresora-termica-gastronova).
Los instaladores salen de las [releases](https://github.com/mati-caliz/gastronova-print-agent/releases).

## Cómo se instala en Windows

Sin firma digital, un `.exe` bajado con el navegador hace que Chrome frene la descarga y que Windows lo muestre como
de un editor desconocido. SignPath Foundation rechazó la firma gratuita (pide un proyecto con adopción pública) y un
certificado propio es pago, así que el camino principal no pasa por el navegador:

- **PowerShell**: `irm https://gastronova.com.ar/impresion | iex`, o lo mismo con Windows + R como
  `powershell -c "irm https://gastronova.com.ar/impresion | iex"`. `gastronova-impresion.ps1` baja el `.exe` de su
  misma release, lo compara contra el SHA256 que trae adentro y lo corre con `/S`. Lo que baja PowerShell no lleva la
  marca de internet, así que no aparece SmartScreen.
- **winget**: `winget install Gastronova.Impresion`. Con cada release, `scripts/winget-manifests.sh` arma los
  manifiestos para el PR a `microsoft/winget-pkgs`.

El `.exe` sigue en la release para quien prefiera el instalador con ventanas. El repo es público para que cualquiera
pueda ver qué instala.
