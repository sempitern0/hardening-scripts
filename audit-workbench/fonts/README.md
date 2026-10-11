# Tipografía opcional Atkinson Hyperlegible

Los archivos WOFF2 no están incluidos. Si dispones legítimamente de los cuatro ficheros que muestras en la captura, cópialos a esta carpeta conservando sus nombres exactos:

```
fonts/
  AtkinsonHyperlegible-Regular.woff2
  AtkinsonHyperlegible-Bold.woff2
  AtkinsonHyperlegible-Italic.woff2
  AtkinsonHyperlegible-BoldItalic.woff2
  atkinson.css
```

Luego, en `index.html`, añade **después** de `styles.css`:

```html
<link rel="stylesheet" href="fonts/atkinson.css">
```

El CSS contiene las cuatro reglas `@font-face`; el navegador utilizará la fuente sin Internet. No actives ese enlace antes de copiar los WOFF2 para evitar errores 404. Tras activar las fuentes en una PWA, incluye `./fonts/atkinson.css` y los cuatro WOFF2 en `CORE` de `sw.js`, actualiza `CACHE_NAME` y prueba de nuevo el modo avión. Para preservar la autoría/licencia, incluye los términos de distribución (normalmente SIL Open Font License; revisa la versión concreta de los archivos que descargues).

Si no los añades, la aplicación funciona con las fuentes instaladas del sistema.
