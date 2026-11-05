#!/usr/bin/env python3
"""Guard the Unbound stop path against signalling a PID after ownership changes."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "fx-module/scripts/unbound.sh"
source = SOURCE.read_text(encoding="utf-8")
start = source.index("_stop() {")
end = source.index("\n}\n_ensure() {", start) + 2
stop = source[start:end]

term = stop.index('kill -TERM "$_p"')
term_recheck = stop.rfind('_same=$(_owned_pid 2>/dev/null) || _same=\'\'', 0, term)
assert term_recheck >= 0, "TERM must be preceded by a fresh ownership check"
term_guard = stop[term_recheck:term]
assert 'if [ "$_same" != "$_p" ]; then' in term_guard, "TERM ownership mismatch must abort"
assert "return 1" in term_guard, "TERM ownership mismatch must preserve state and abort"

kill = stop.index('kill -KILL "$_p"')
kill_recheck = stop.rfind('_same=$(_owned_pid 2>/dev/null) || _same=\'\'', 0, kill)
assert kill_recheck >= 0, "KILL must be preceded by a fresh ownership check"
kill_guard = stop[kill_recheck:kill]
assert 'if [ "$_same" = "$_p" ]' in kill_guard, "KILL must remain conditional on confirmed ownership"

assert stop.index('if [ -z "$_p" ]; then') < term_recheck < term < kill_recheck < kill
print("PASS: Unbound rechecks /proc command-line ownership immediately before TERM and KILL")
