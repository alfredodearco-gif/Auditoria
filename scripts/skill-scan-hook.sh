#!/usr/bin/env bash
# Hook de Claude Code. start: lanza escaneo incremental en segundo plano. report: entrega alertas pendientes como contexto.
STATE="${SKILLSPECTOR_STATE:-$HOME/.cache/skillspector-scan}"
mkdir -p "$STATE"
DIR="$(cd "$(dirname "$0")" && pwd)"
case "${1:-}" in
  start)
    cat >/dev/null
    (
      flock -n 9 || exit 0
      out=$("$DIR/scan-skills.sh" --quiet 2>&1)
      [ -n "$out" ] && printf '%s\n' "$out" >> "$STATE/pending-alerts.txt"
    ) 9>"$STATE/scan.lock" >/dev/null 2>&1 &
    disown
    ;;
  report)
    cat >/dev/null
    f="$STATE/pending-alerts.txt"
    if [ -s "$f" ]; then
      mv "$f" "$f.sent"
      echo "[SkillSpector] Resultado del escaneo automático de skills:"
      cat "$f.sent"
      echo "Informa al usuario de estas alertas."
    fi
    ;;
esac
exit 0
