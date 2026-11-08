Yulong Ad Plugin 7.0.1 bundled rule attribution
===============================================

Source APK: Yulong Ad Plugin 7.0.1
Source files: assets/builtin_adguard_dns.trie, builtin_adguard_mobile.trie,
builtin_yoyo_adservers.trie, builtin_cn_domestic.trie and
assets/README-builtin-rules.txt.

AdGuard DNS filter and AdGuard Mobile Ads filter
  (c) AdGuard Team - https://github.com/AdguardTeam/AdguardFilters
  GNU General Public License v3.0.

Peter Lowe's Ad and tracking server list
  (c) Peter Lowe - https://pgl.yoyo.org/adservers/
  CC BY-NC-SA 4.0.

anti-AD
  (c) privacy-protection-tools - https://github.com/privacy-protection-tools/anti-AD
  GNU General Public License v3.0.

EasyList China
  (c) EasyList authors - https://github.com/easylist/easylistchina
  CC BY-SA 3.0 / GNU GPL v3.0.

ADgk
  (c) banbendalao - https://github.com/banbendalao/ADgk
  GNU General Public License v3.0.

AdGuard Chinese filter
  (c) AdGuard Team - https://github.com/AdguardTeam/AdguardFilters
  GNU General Public License v3.0.

FX stores validated domain-only Hosts/DNS entries in Yulong_AdBlock.txt.
ABP cosmetic selectors and exceptions are retained separately in
Yulong_AdBlock_Cosmetic.txt, and are not applied by the DNS/Hosts pipeline.


Decoder output contract:
- `Yulong_AdBlock.txt`: DNS-safe host rules. Complete host terminals written
  as `domain^` or `||domain^` are recovered to the exact hostname. This is a
  deliberate migration repair for ABP separator syntax left in the precompiled
  Trie; the original Go Trie matcher compares raw labels and does not strip `^`.
  Prefix-only `||domain` forms are not converted because they lack a proven
  DNS end-boundary.
- `Yulong_AdBlock_Cosmetic.txt`: preserved cosmetic selectors/exceptions;
  not activated by the DNS-only import path.
- `Yulong_AdBlock_Review.jsonl`: exact unsupported terminals paired with their
  source trie. URL-start anchors, paths, wildcard expressions, IP literals and
  malformed tokens remain review-only and are never widened into DNS blocks.
