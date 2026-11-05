'use strict';
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const source = fs.readFileSync(process.argv[2], 'utf8');
const marker = '\ntry {\n  var file = (typeof scriptArgs';
const cut = source.indexOf(marker);
assert(cut > 0, 'CLI entrypoint marker found');
const context = {};
vm.runInNewContext(source.slice(0, cut) + '\nthis.convertForTest = convert;\n', context);
const convert = context.convertForTest;
const base = {server:'edge.example', server_port:443, tag:'test'};
const cases = [
  [{...base, type:'vless'}, 'VLESS UUID required'],
  [{...base, type:'vmess'}, 'VMess UUID required'],
  [{...base, type:'trojan'}, 'Trojan password required'],
  [{...base, type:'shadowsocks', method:'aes-256-gcm'}, 'Shadowsocks password required'],
  [{...base, type:'shadowsocks', password:'secret'}, 'Shadowsocks method required'],
  [{...base, type:'hysteria2'}, 'Hysteria2 auth required'],
  [{...base, type:'tuic', uuid:'user'}, 'TUIC password required'],
  [{...base, type:'tuic', password:'secret'}, 'TUIC UUID required'],
  [{...base, type:'anytls'}, 'AnyTLS password required']
];
for (const [input, message] of cases) assert.strictEqual(convert(input), '', message);
assert(convert({...base, type:'vless', uuid:'id'}).startsWith('vless://id@'), 'valid VLESS still converts');
assert(convert({...base, type:'vmess', uuid:'id'}).startsWith('vmess://'), 'valid VMess still converts');
assert(convert({...base, type:'trojan', password:'secret'}).startsWith('trojan://'), 'valid Trojan still converts');
assert(convert({...base, type:'shadowsocks', method:'aes-256-gcm', password:'secret'}).startsWith('ss://'), 'valid Shadowsocks still converts');
assert(convert({...base, type:'hysteria2', password:'secret'}).startsWith('hysteria2://'), 'valid Hysteria2 still converts');
assert(convert({...base, type:'tuic', uuid:'id', password:'secret'}).startsWith('tuic://'), 'valid TUIC still converts');
assert(convert({...base, type:'anytls', password:'secret'}).startsWith('anytls://'), 'valid AnyTLS still converts');
assert(convert({...base, type:'socks5'}).startsWith('socks5://'), 'SOCKS remains optionally authenticated');
assert(convert({...base, type:'hysteria2', auth_str:'legacy-auth'}).startsWith('hysteria2://legacy-auth@'), 'Hysteria2 auth_str accepted');
console.log('PASS: sing-box URI conversion rejects missing required credentials');
