#!/usr/bin/env python3
"""Move the legacy Ad page content into the single Hosts/Rules page."""
from html.parser import HTMLParser
from pathlib import Path
import re
import sys

source = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module/webroot/index.html")
html = source.read_text(encoding="utf-8")
marker = "<!-- FX: merged pageAd into pageHosts -->"
if marker in html:
    print("Ad/Hosts content already merged")
    raise SystemExit(0)

class PageLocator(HTMLParser):
    def __init__(self, text):
        super().__init__(convert_charrefs=False)
        self.text = text
        self.lines = [0]
        for match in re.finditer("\n", text):
            self.lines.append(match.end())
        self.stack = []
        self.pages = {}

    def offset(self):
        line, col = self.getpos()
        return self.lines[line - 1] + col

    def handle_starttag(self, tag, attrs):
        start = self.offset()
        raw = self.get_starttag_text()
        attr = dict(attrs)
        page_id = attr.get("id") if attr.get("id") in ("pageAd", "pageHosts") else None
        if page_id:
            if page_id in self.pages:
                raise ValueError("duplicate " + page_id)
            self.pages[page_id] = {"start": start, "content_start": start + len(raw), "end": None}
        if tag.lower() not in {"area","base","br","col","embed","hr","img","input","link","meta","param","source","track","wbr"}:
            self.stack.append((tag.lower(), page_id))

    def handle_startendtag(self, tag, attrs):
        pass

    def handle_endtag(self, tag):
        tag = tag.lower()
        if not self.stack:
            return
        match_index = None
        for index in range(len(self.stack) - 1, -1, -1):
            if self.stack[index][0] == tag:
                match_index = index
                break
        if match_index is None:
            return
        closing = self.stack[match_index:]
        del self.stack[match_index:]
        target = next((item[1] for item in reversed(closing) if item[1]), None)
        if target and self.pages[target]["end"] is None:
            start = self.offset()
            close = re.match(r"</\s*" + re.escape(tag) + r"\s*>", self.text[start:], re.I)
            if close:
                self.pages[target]["end"] = start
                self.pages[target]["close_end"] = start + close.end()

locator = PageLocator(html)
locator.feed(html)
for page_id in ("pageAd", "pageHosts"):
    if page_id not in locator.pages or locator.pages[page_id]["end"] is None:
        raise SystemExit("cannot safely locate complete " + page_id + " container")
ad = locator.pages["pageAd"]
hosts = locator.pages["pageHosts"]
if ad["content_start"] > ad["end"] or hosts["content_start"] > hosts["end"]:
    raise SystemExit("invalid page boundaries")
ad_content = html[ad["content_start"]:ad["end"]]
if not ad_content.strip():
    raise SystemExit("legacy Ad page is empty; refusing an unverified merge")
# Append the former Ad cards after the existing rule/Hosts cards, preserving
# all original IDs and event handlers used by the existing WebUI JavaScript.
host_content = html[hosts["content_start"]:hosts["end"]]
if "mitmTrafficEnable" in host_content or "rootCertCard" in host_content:
    raise SystemExit("Ad cards already appear in Hosts page without merge marker")
edits = [
    (hosts["end"], hosts["end"], "\n" + marker + "\n" + ad_content),
    (ad["content_start"], ad["end"], "\n<!-- FX: legacy Ad content moved to Hosts page -->\n"),
]
for start, end, replacement in sorted(edits, reverse=True):
    html = html[:start] + replacement + html[end:]
source.write_text(html, encoding="utf-8")
print("Merged legacy Ad content into pageHosts; retained stable element IDs")
