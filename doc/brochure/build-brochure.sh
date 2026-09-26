#!/usr/bin/env bash
# Regenera el brochure de Consilio:
#   1. baja las cifras vivas de /data/summary (o usa un JSON local con SUMMARY_JSON=...)
#   2. reescribe en el HTML cada elemento con data-k / data-bar
#   3. imprime el PDF con Chrome headless
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
HTML="$DIR/consilio-brochure.html"
PDF="$DIR/consilio-brochure.pdf"
URL="${SUMMARY_URL:-https://consilio.medicinainteligente.ai/data/summary}"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
JSON="${SUMMARY_JSON:-}"

if [[ -z "$JSON" ]]; then
  JSON="$(mktemp -t consilio-summary).json"
  echo "→ bajando cifras de $URL"
  curl -fsS -m 30 "$URL" -o "$JSON"
fi

echo "→ inyectando cifras en el HTML"
python3 - "$HTML" "$JSON" <<'PY'
import json, re, sys, datetime
html_path, json_path = sys.argv[1], sys.argv[2]
data = json.load(open(json_path))
data["_fetched"] = datetime.datetime.now().astimezone().isoformat()  # hora local: en UTC de noche salía el día siguiente

def get(path):
    cur = data
    for k in path.split("."):
        if not isinstance(cur, dict) or k not in cur:
            sys.exit(f"ERROR: la clave '{path}' no está en el JSON; no se inventa el número")
        cur = cur[k]
    return cur

def fmt(v, f):
    if f == "date":
        return datetime.datetime.fromisoformat(str(v).replace("Z", "+00:00")).strftime("%d/%m/%Y")
    if f == "pct":
        return f"{float(v):.1f}".replace(".", ",")
    return f"{int(v):,}".replace(",", ".")

s = open(html_path, encoding="utf-8").read()
n = 0

# <tag ... data-k="a.b" [data-f="x"] ...>VALOR</tag>   (VALOR sin etiquetas anidadas)
def rep_k(m):
    global n
    attrs = m.group(2)
    key = re.search(r'data-k="([^"]+)"', attrs).group(1)
    f = re.search(r'data-f="([^"]+)"', attrs)
    n += 1
    return f"<{m.group(1)}{attrs}>{fmt(get(key), f.group(1) if f else 'int')}</{m.group(1)}>"
s = re.sub(r'<(\w+)(\s[^>]*data-k="[^"]+"[^>]*)>([^<]*)</\1>', rep_k, s)

# barras: <i ... data-bar="x" data-of="y" style="width:NN%">
def rep_bar(m):
    global n
    tag = m.group(0)
    part = get(re.search(r'data-bar="([^"]+)"', tag).group(1))
    tot = get(re.search(r'data-of="([^"]+)"', tag).group(1))
    n += 1
    return re.sub(r'style="width:[^"]*"', f'style="width:{100*part/tot:.2f}%"', tag)
s = re.sub(r'<i\s[^>]*data-bar="[^"]+"[^>]*>', rep_bar, s)

open(html_path, "w", encoding="utf-8").write(s)
print(f"   {n} cifras actualizadas (build {data.get('sources',{}).get('build',{}).get('sha','?')})")
PY

echo "→ imprimiendo PDF"
"$CHROME" --headless=new --disable-gpu --no-pdf-header-footer \
  --virtual-time-budget=10000 --run-all-compositor-stages-before-draw \
  --print-to-pdf="$PDF" "file://$HTML" 2>/dev/null

echo "✓ $PDF ($(mdls -raw -name kMDItemNumberOfPages "$PDF" 2>/dev/null || echo '?') páginas)"
