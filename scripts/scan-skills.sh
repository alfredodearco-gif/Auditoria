#!/usr/bin/env bash
# Escanea con SkillSpector cada skill instalada; solo re-escanea las nuevas o modificadas (cache por hash).
# Uso: scan-skills.sh [--all] [--quiet]
set -uo pipefail

ROOTS=(
  "$HOME/.claude/skills"
  "$HOME/.claude/plugins"
  "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/skills"
  "/home/claude/.claude/skills"
  "/mnt/skills/public"
)
STATE="${SKILLSPECTOR_STATE:-$HOME/.cache/skillspector-scan}"
mkdir -p "$STATE/reports"
CACHE="$STATE/hashes.tsv"; touch "$CACHE"
FORCE=0; QUIET=0
for a in "$@"; do case $a in --all) FORCE=1;; --quiet) QUIET=1;; esac; done

if ! command -v skillspector >/dev/null 2>&1; then
  export PATH="$HOME/.local/bin:$PATH"
  command -v skillspector >/dev/null 2>&1 || \
    uv tool install -q git+https://github.com/NVIDIA/skillspector.git >/dev/null 2>&1 || \
    { echo "skillspector no disponible"; exit 0; }
fi

mapfile -t DIRS < <(for r in "${ROOTS[@]}"; do [ -d "$r" ] && find -L "$r" -name SKILL.md -not -path '*/node_modules/*' 2>/dev/null; done | xargs -r -n1 dirname | sort -u)

NEW=(); ALERTS=()
for d in "${DIRS[@]}"; do
  h=$(find -L "$d" -type f -not -path '*/.git/*' -print0 2>/dev/null | sort -z | xargs -0 sha256sum 2>/dev/null | sha256sum | cut -c1-16)
  if [ $FORCE -eq 0 ] && grep -qxF "$h	$d" "$CACHE"; then continue; fi
  id=$(printf '%s' "$d" | sha256sum | cut -c1-12)
  out="$STATE/reports/$id.json"
  skillspector scan "$d" --no-llm --format json --output "$out" >/dev/null 2>&1
  res=$(python3 -I - "$out" <<'PY'
import json,sys
try:
    d=json.load(open(sys.argv[1])); r=d["risk_assessment"]
    print(f'{r["score"]}\t{r["severity"]}\t{r["recommendation"]}\t{len(d.get("issues",[]))}')
except Exception: print("?\tERROR\tSCAN_FAILED\t0")
PY
)
  grep -vF "	$d" "$CACHE" > "$CACHE.tmp"; echo "$h	$d" >> "$CACHE.tmp"; mv "$CACHE.tmp" "$CACHE"
  line="$res	$(basename "$d")	$d"
  printf '%s\n' "$line" >> "$STATE/results.tsv"
  NEW+=("$line")
  case "$(cut -f2 <<<"$res")" in HIGH|CRITICAL|ERROR) ALERTS+=("$line");; esac
done

[ $QUIET -eq 1 ] && [ ${#ALERTS[@]} -eq 0 ] && exit 0
if [ ${#NEW[@]} -gt 0 ]; then
  echo "SkillSpector: ${#NEW[@]} skill(s) nuevas o modificadas escaneadas."
  if [ ${#ALERTS[@]} -gt 0 ]; then
    echo "ALERTA: skills con riesgo HIGH/CRITICAL o escaneo fallido (score severidad recomendación hallazgos nombre ruta):"
    printf '  %s\n' "${ALERTS[@]}"
    echo "Revisarlas con la skill skill-inspector antes de usarlas. Reportes JSON en $STATE/reports/"
  fi
fi
