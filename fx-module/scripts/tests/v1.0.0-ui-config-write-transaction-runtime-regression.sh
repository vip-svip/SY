#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HTML="$ROOT/webroot/index.html"
command -v node >/dev/null 2>&1 || { echo 'SKIP: node unavailable for runtime config transaction test'; exit 0; }
node - "$HTML" <<'NODE'
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const vm = require('vm');
const cp = require('child_process');
const html = fs.readFileSync(process.argv[2], 'utf8');
const start = html.indexOf('function pgWriteConf(text){');
const end = html.indexOf('function pgPersistNow(){', start);
if (start < 0 || end <= start) throw new Error('pgWriteConf body not found');
const source = html.slice(start, end) + '\nthis.__pgWriteConf = pgWriteConf;';
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fx-pg-conf-txn-'));
const conf = path.join(dir, 'settings.conf');
const tmp = conf + '.tmp';
const bak = conf + '.bak';
const txn = conf + '.txn';
let injection = '';
function sh(cmd, allowFailure = false) {
  try { cp.execFileSync('/bin/sh', ['-c', cmd], {stdio: 'ignore'}); return true; }
  catch (e) { if (!allowFailure) throw e; return false; }
}
function pgExec(cmd) {
  if (injection === 'preflight' && cmd.startsWith('test -f ' + tmp + ' && test ')) {
    injection = '';
    return Promise.resolve({ok: false});
  }
  if (injection === 'post-rename' && cmd.startsWith('if ! mv -f ' + tmp + ' ' + conf + '; then exit 1; fi;')) {
    injection = '';
    sh('mv -f ' + tmp + ' ' + conf + '; exit 17', true);
    return Promise.resolve({ok: false});
  }
  return Promise.resolve({ok: sh(cmd, true)});
}
function buildWriter() {
  const context = {
    CONFP: conf,
    PG_WRITE_SLICE: 87376,
    pgB64: value => Buffer.from(value, 'utf8').toString('base64'),
    pgExec,
    toast: () => {},
    lt: value => value,
  };
  vm.createContext(context);
  vm.runInContext(source, context, {timeout: 2000});
  return context.__pgWriteConf;
}
function assert(ok, message) { if (!ok) throw new Error(message); }
function readConf() { return fs.existsSync(conf) ? fs.readFileSync(conf, 'utf8') : null; }
async function main() {
  const write = buildWriter();

  // Normal write: UTF-8 byte count, commit and cleanup must all succeed.
  fs.writeFileSync(conf, 'old-existing-config\n');
  assert(await write('new config 中文\n'), 'normal write returned failure');
  assert(readConf() === 'new config 中文\n', 'normal write content mismatch');
  assert(!fs.existsSync(txn) && !fs.existsSync(bak) && !fs.existsSync(tmp), 'normal write left transaction artifacts');

  // Fail before backup/commit: the existing config must stay untouched.
  fs.writeFileSync(conf, 'preserve-before-preflight-failure\n');
  injection = 'preflight';
  assert((await write('should-not-commit\n')) === false, 'preflight failure was reported as success');
  assert(readConf() === 'preserve-before-preflight-failure\n', 'preflight failure damaged existing config');
  assert(!fs.existsSync(txn) && !fs.existsSync(bak) && !fs.existsSync(tmp), 'preflight failure left transaction artifacts');

  // A failure after rename but before finalization must roll back to the verified backup.
  fs.writeFileSync(conf, 'preserve-after-commit-failure\n');
  injection = 'post-rename';
  assert((await write('new but not finalized\n')) === false, 'post-rename injected failure was reported as success');
  assert(readConf() === 'preserve-after-commit-failure\n', 'post-rename failure did not roll back');
  assert(!fs.existsSync(txn) && !fs.existsSync(bak) && !fs.existsSync(tmp), 'post-rename recovery left transaction artifacts');

  // Simulate a process interrupted after replacing the file but before removing the marker.
  fs.writeFileSync(bak, 'recover-this-known-good-config\n');
  fs.writeFileSync(txn, 'had-old');
  fs.writeFileSync(conf, 'interrupted-unverified-config\n');
  assert(await write('next-write-after-recovery\n'), 'next write could not recover interrupted transaction');
  assert(readConf() === 'next-write-after-recovery\n', 'next write did not proceed after recovery');
  assert(!fs.existsSync(txn) && !fs.existsSync(bak) && !fs.existsSync(tmp), 'interrupted transaction artifacts remain');

  console.log('PASS: UI config transaction runtime simulation (normal write, preflight failure, post-rename rollback, interrupted recovery)');
}
main().catch(e => { console.error(e.stack || e); process.exitCode = 1; }).finally(() => {
  try { fs.rmSync(dir, {recursive:true, force:true}); } catch (_) {}
});
NODE
