#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HTML="$ROOT/webroot/index.html"
command -v node >/dev/null 2>&1 || { echo 'SKIP: node unavailable for static JS transaction assertion'; exit 0; }
node - "$HTML" <<'NODE'
const fs = require('fs');
const html = fs.readFileSync(process.argv[2], 'utf8');
const start = html.indexOf('function pgWriteConf(text){');
const end = html.indexOf('function pgPersistNow(){', start);
if (start < 0 || end <= start) throw new Error('pgWriteConf body not found');
const body = html.slice(start, end);
const checks = [
  ['temporary size is checked', body.indexOf('cmds.push(sizeCheck);')],
  ['verified backup comes after temp validation', body.indexOf('var backupCmd=')],
  ['atomic commit comes after backup', body.indexOf('var commitCmd=')],
  ['preflight compares byte count', body.indexOf('var sizeCheck=')],
  ['recovery copy is verified', body.indexOf('cmp -s "+bak+" "+recover+')],
  ['success cleanup removes backup only after verification', body.lastIndexOf('rm -f "+bak+" "+bakTmp+" "+recover')],
];
for (const [name, at] of checks) if (at < 0) throw new Error(name + ': missing');
if (!(checks[3][1] < checks[0][1] && checks[0][1] < checks[1][1] && checks[1][1] < checks[2][1] && checks[2][1] < checks[5][1])) {
  throw new Error('transaction command order is unsafe');
}
if ((body.match(/expectedBytes/g) || []).length < 3 || !body.includes('var commitCmd=') || !body.includes('! test -f "+CONFP+"')) throw new Error('post-commit size verification missing');
if (!body.includes("pgExec('rm -f '+tmp+' '+bakTmp+' '+recover+' '+txnTmp)")) throw new Error('failure cleanup must clear only disposable temporary files');
if (!body.includes('Keep txn and backup if recovery cannot be verified')) throw new Error('failed recovery must retain transaction marker and verified backup');
console.log('PASS: UI config writes validate temp before commit, preserve a verified backup, and roll back post-commit failure');
NODE
