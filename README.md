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

## Por qué es público

Para que los instaladores salgan firmados: un ejecutable sin firma hace que Chrome bloquee la descarga y que Windows
lo muestre como de un editor desconocido. La firma la da SignPath Foundation, gratis para proyectos de código abierto.

## Política de firma de código

Firma de código gratuita provista por [SignPath.io](https://about.signpath.io), certificado de
[SignPath Foundation](https://signpath.org).

- Se firman sólo los instaladores que arma el workflow `release.yml` de este repositorio a partir de un tag `v*`,
  en los runners de GitHub; nada que se arme fuera de ese workflow.
- Autor, revisión y aprobación de cada release: [mati-caliz](https://github.com/mati-caliz).
- Privacidad: el componente no transmite información a ningún sistema en red, salvo lo que el usuario le pide a la
  extensión imprimir en sus propias impresoras.
