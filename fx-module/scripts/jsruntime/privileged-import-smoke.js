/* Harmless runtime probe; run only through scripts/jsruntime/runner.sh. */
const guarded = ['qjs:std', 'qjs:os', 'qjs:bjson', '/system/lib64/libc.so'];
const aliases = ['std', 'os', 'bjson'];
const checks = [
  ...guarded.map(name => import(name).then(
    () => ({name, blocked:false, reason:'import resolved unexpectedly'}),
    err => ({name, blocked:String(err).includes('disabled by FX'), error:String(err)})
  )),
  ...aliases.map(name => import(name).then(
    () => ({name, blocked:false, reason:'bare privileged alias resolved unexpectedly'}),
    err => ({name, blocked:String(err).includes('disabled by FX'), error:String(err)})
  ))
];
Promise.all(checks).then(results => {
  const safe = results.every(item => item.blocked);
  $done({sandbox:safe, probes:results});
}).catch(err => $done({sandbox:false, error:String(err)}));
