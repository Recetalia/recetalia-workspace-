# Brochure de Consilio

- `consilio-brochure.html`: fuente única, 6 páginas A4. Los SVG van inline y las fuentes vienen de Google Fonts.
- `build-brochure.sh`: regenera el PDF.
- `consilio-brochure.pdf`: el resultado.

## Regenerar

```bash
./build-brochure.sh                                   # baja las cifras vivas e imprime el PDF
SUMMARY_JSON=/tmp/consilio-summary.json ./build-brochure.sh   # sin red, con un JSON local
```

El script hace tres cosas:

1. Baja `https://consilio.medicinainteligente.ai/data/summary`.
2. Reescribe en el HTML cada elemento marcado con `data-k="ruta.del.json"`. Con `data-f` se elige el formato: `int`, `pct` o `date`. Las barras de gravedad usan `data-bar` y `data-of`.
3. Imprime con Chrome headless (`--virtual-time-budget=10000`, para que carguen las fuentes).

Si falta una clave en el JSON, el script corta con error: no deja un número viejo en silencio. Hace falta Chrome en `/Applications`, o la variable `CHROME=...`.

## De dónde sale cada cifra

Todo número marcado con `data-k` sale de `/data/summary`, y la portada muestra la fecha de la bajada. Hay dos excepciones, que son mediciones citadas y están escritas a mano:

- **14 categorías ATC de DDInter**: `consilio/docs/2026-09-25-castellano-y-colores.md`, en § DDInter.
- **12/12 casos de duplicidad**: `scripts/eval_duplicidad.py`, en `consilio/docs/2026-09-24-duplicidad-terapeutica-design.md`, § Despliegue.

Los ejemplos clínicos están verificados en producción: warfarina + ibuprofeno, los tres pares graves, paracetamol + paracetamol/codeína, diazepam + lorazepam, enalapril + amlodipino + HCTZ, hidrocortisona + fludrocortisona y N18.5 → N18.

Del brochure v1 **no** se usa el 59,5 % de cobertura del DNMA ni los 381/275 pares con desacuerdo de gravedad, porque se midieron antes de ampliar DDInter.
