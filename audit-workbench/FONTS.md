# Tipografía accesible (sin solicitudes externas)

**Recomendación:** [Atkinson Hyperlegible Next](https://github.com/googlefonts/atkinson-hyperlegible-next). Diseñada para distinguir letras y números similares; licencia [SIL Open Font License 1.1](https://github.com/googlefonts/atkinson-hyperlegible-next/blob/main/OFL.txt). Alternativa más neutra: [Inter](https://github.com/rsms/inter), también OFL.

La aplicación utiliza `Atkinson Hyperlegible Next` si está instalada en el dispositivo, y fuentes de sistema en otro caso. En una futura integración local:

1. Descarga voluntariamente la fuente WOFF2 desde su proyecto oficial y revisa su licencia (no la incluyas desde CDN).
2. Copia el WOFF2 a `fonts/` y conserva el fichero de licencia original.
3. Añade al principio de `styles.css` la regla:

```css
@font-face {
  font-family: "Atkinson Hyperlegible Next";
  src: url("./fonts/AtkinsonHyperlegibleNext-Regular.woff2") format("woff2");
  font-style: normal;
  font-weight: 400;
  font-display: swap;
}
```

4. Ajusta el nombre del archivo y los pesos a los que hayas descargado. Incluye esos archivos en la caché de `sw.js` para uso offline. El PDF imprimirá con la fuente cuando el navegador la tenga cargada; la ausencia de la fuente no bloquea la aplicación.

La interfaz usa `16px` como tamaño de base, controles de al menos 44px táctiles, estados visibles de foco y respeto por `prefers-reduced-motion`.
