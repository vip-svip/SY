/* Convert supported sing-box JSON outbounds to canonical proxy URIs for vpnsub.sh.
 * Run with the bundled QuickJS-NG CLI: qjs --std vpn-singbox-json.js <json-file>.
 * Unsupported/local outbounds are intentionally ignored. */
function utf8Bytes(s) {
  var e = encodeURIComponent(String(s)), a = [], i = 0;
  while (i < e.length) {
    if (e.charAt(i) === '%') { a.push(parseInt(e.substr(i + 1, 2), 16)); i += 3; }
    else { a.push(e.charCodeAt(i)); i++; }
  }
  return a;
}
function b64(s) {
  var a = utf8Bytes(s), tab = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/', o = '', i, n;
  for (i = 0; i < a.length; i += 3) {
    n = (a[i] << 16) | ((a[i + 1] || 0) << 8) | (a[i + 2] || 0);
    o += tab[(n >> 18) & 63] + tab[(n >> 12) & 63] + (i + 1 < a.length ? tab[(n >> 6) & 63] : '=') + (i + 2 < a.length ? tab[n & 63] : '=');
  }
  return o;
}
function enc(v) { return encodeURIComponent(String(v == null ? '' : v)); }
function authority(host) {
  host = String(host || '');
  if (host.indexOf(':') >= 0 && host.charAt(0) !== '[') return '[' + host + ']';
  return host;
}
function vmessUri(o, name, tls, tr) {
  var j = {v:'2', ps:name, add:o.server, port:String(o.server_port), id:o.uuid || '', scy:o.security || o.method || 'auto', net:(tr.type || 'tcp'), path:tr.path || '/', host:((tr.headers || {}).Host || (tr.headers || {}).host || ''), tls:tls.enabled ? 'tls' : '', sni:(tls.server_name || o.server_name || '')};
  return 'vmess://' + b64(JSON.stringify(j));
}
function convert(o) {
  if (!o || typeof o !== 'object') return '';
  var t = String(o.type || '').toLowerCase(), name = String(o.tag || o.name || (o.server || 'proxy'));
  var host = String(o.server || ''), port = Number(o.server_port || 0), tls = o.tls || {}, tr = o.transport || {};
  if (!host || !(port > 0 && port <= 65535) || Math.floor(port) !== port) return '';
  var authHost = authority(host);
  var sni = tls.server_name || o.server_name || host, path = tr.path || '', headers = tr.headers || {}, wsHost = headers.Host || headers.host || '';
  if (t === 'shadowsocks') t = 'ss';
  if (t === 'socks' || t === 'socks4' || t === 'socks5') t = 'socks5';
  if (t === 'hy2') t = 'hysteria2';
  // URI conversion is intentionally fail-closed when the source transport cannot
  // be represented by the target URI dialect. Silently dropping gRPC, HTTPUpgrade,
  // HTTP/H2 or protocol-specific transport settings creates nodes that look valid
  // but connect differently from the imported sing-box profile.
  var transportType = String(tr.type || 'tcp').toLowerCase();
  if (transportType !== 'tcp' && transportType !== 'ws') return '';
  if (transportType === 'ws' && t !== 'vmess' && t !== 'vless') return '';
  // Do not emit syntactically plausible but unusable authenticated-protocol URIs.
  // sing-box outbound credentials are required for these URI forms; SOCKS remains
  // optionally authenticated. Trim only for validation, preserve original values.
  if (t === 'vmess' && !String(o.uuid || '').trim()) return '';
  if (t === 'vless' && !String(o.uuid || '').trim()) return '';
  if (t === 'trojan' && !String(o.password || '').trim()) return '';
  if (t === 'ss' && (!String(o.method || '').trim() || !String(o.password || '').trim())) return '';
  if (t === 'hysteria2' && !String(o.password || o.auth_str || '').trim()) return '';
  if (t === 'tuic' && (!String(o.uuid || '').trim() || !String(o.password || '').trim())) return '';
  if (t === 'anytls' && !String(o.password || '').trim()) return '';
  if (t === 'vmess') return vmessUri(o, name, tls, tr);
  if (t === 'vless') {
    var reality = tls.reality || null;
    // Reality is only valid with TLS enabled and a public key. A short_id alone
    // is not enough to construct a working Reality client URI; fail closed
    // rather than silently emitting a URI that cannot establish the intended link.
    if (reality && (reality.public_key || reality.short_id) && (!tls.enabled || !reality.public_key)) return '';
    var security = (reality && reality.public_key) ? 'reality' : (tls.enabled ? 'tls' : 'none');
    return 'vless://' + enc(o.uuid || '') + '@' + authHost + ':' + port + '?security=' + security + '&sni=' + enc(sni) + (tls.utls && tls.utls.fingerprint ? '&fp=' + enc(tls.utls.fingerprint) : '') + (reality && reality.public_key ? '&pbk=' + enc(reality.public_key) : '') + (reality && reality.short_id ? '&sid=' + enc(reality.short_id) : '') + (tr.type === 'ws' ? '&type=ws&path=' + enc(path || '/') : '') + (wsHost ? '&host=' + enc(wsHost) : '') + '#' + enc(name);
  }
  if (t === 'trojan') return 'trojan://' + enc(o.password || '') + '@' + authHost + ':' + port + '?sni=' + enc(sni) + '#' + enc(name);
  if (t === 'ss') return 'ss://' + b64(String(o.method || 'aes-256-gcm') + ':' + String(o.password || '')) + '@' + authHost + ':' + port + '#' + enc(name);
  if (t === 'hysteria2') return 'hysteria2://' + enc(o.password || o.auth_str || '') + '@' + authHost + ':' + port + '?sni=' + enc(sni) + '#' + enc(name);
  if (t === 'tuic') return 'tuic://' + enc(o.uuid || '') + ':' + enc(o.password || '') + '@' + authHost + ':' + port + '?sni=' + enc(sni) + '#' + enc(name);
  if (t === 'anytls') return 'anytls://' + enc(o.password || '') + '@' + authHost + ':' + port + '?sni=' + enc(sni) + '#' + enc(name);
  if (t === 'socks5') return 'socks5://' + (o.username ? enc(o.username) + (o.password ? ':' + enc(o.password) : '') + '@' : '') + authHost + ':' + port + '#' + enc(name);
  return '';
}
try {
  var file = (typeof scriptArgs !== 'undefined' && scriptArgs.length) ? scriptArgs[0] : '';
  if (!file || typeof std === 'undefined' || typeof std.loadFile !== 'function') std.exit(64);
  var source = std.loadFile(file);
  if (!source) std.exit(65);
  var root = JSON.parse(source), outs = root && root.outbounds;
  if (!Array.isArray(outs)) std.exit(0);
  var count = 0;
  outs.forEach(function (o) { var u = convert(o); if (u) { std.out.puts(u + '\n'); count++; } });
  std.exit(count ? 0 : 0);
} catch (e) {
  if (typeof std !== 'undefined' && std.err) std.err.puts('vpn-singbox-json: ' + String(e) + '\n');
  if (typeof std !== 'undefined') std.exit(1);
}
