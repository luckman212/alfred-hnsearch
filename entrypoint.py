#!/usr/bin/env python3

import os
import sys
import json
import hnlib

items = []

def output(respect_order=True):
  json.dump({
    "skipknowledge": respect_order,
    "items": items
  }, sys.stdout)
  exit()

def noarg():
  HNS_CLI_FQPN = os.path.join(os.getenv('HNS_TOOL_PATH'), os.getenv('HNS_KW_TRIGGER').split('|')[0])
  items.append({
    "title": "Search Hacker News",
    "subtitle": f"Enter a search term (add |n to override default min points {os.getenv('HNS_POINTS',1)})",
    "mods": { "ctrl": { "subtitle": "" }, "alt": { "subtitle": "" }},
    "valid": False
  })
  try:
    items.extend(hnlib.hist_get())
  except:
    hnlib.hist_clear()
    pass
  if not os.path.exists(HNS_CLI_FQPN):
    items.append({
      "title": f"Install commandline tool",
      "subtitle": HNS_CLI_FQPN,
      "mods": { "ctrl": { "subtitle": "" }, "alt": { "subtitle": "" }},
      "variables": {
        "HNS_ACTION": "install_cli",
        "HNS_CLI_FQPN": HNS_CLI_FQPN
      },
      "icon": { "path": "icons/cli.png" }
    })
  items.append({
    "title": "Clear Workflow Cache and History",
    "subtitle": hnlib.WF_CACHE_DIR,
    "arg": "_",
    "mods": { "ctrl": { "subtitle": "" }, "alt": { "subtitle": "" }},
    "action": { "auto": hnlib.WF_CACHE_DIR },
    "variables": { "HNS_ACTION": "clear_cache" },
    "icon": { "path": "icons/trash.png" }
  })
  output(respect_order=True)

try:
  q = sys.argv[1].split("|")
  arg = q[0].strip()
  assert len(arg)
except:
  noarg()

try:
  HNS_POINTS = int(q[1])
except:
  HNS_POINTS = os.getenv('HNS_POINTS', 1)

items.extend([
  {
    "uid": "hns_date",
    "title": "Search by date",
    "mods": { "ctrl": { "subtitle": "" }, "alt": { "subtitle": "" }},
    "icon": { "path": "icons/bydate.png" },
    "variables": {
      "HNS_ACTION": "init",
      "VERB": "search_by_date",
      "search": arg,
      "search_desc": f"{arg} (date)",
      "HNS_POINTS": HNS_POINTS,
      "search_hash": f"search_by_date|{arg}||{HNS_POINTS}"
    }
  },
  {
    "uid": "hns_popularity",
    "title": "Search by popularity",
    "mods": { "ctrl": { "subtitle": "" }, "alt": { "subtitle": "" }},
    "icon": { "path": "icons/bypoints.png" },
    "variables": {
      "HNS_ACTION": "init",
      "VERB": "search",
      "search": arg,
      "search_desc": f"{arg} (points)",
      "HNS_POINTS": HNS_POINTS,
      "search_hash": f"search|{arg}||{HNS_POINTS}"
    }
  },
  {
    "uid": "hns_author",
    "title": "Search by username (aka author)",
    "mods": { "ctrl": { "subtitle": "" }, "alt": { "subtitle": "" }},
    "arg": "",
    "icon": { "path": "icons/byauthor.png" },
    "variables": {
      "HNS_ACTION": "init",
      "VERB": "search",
      "AUTHOR": arg,
      "search": "",
      "search_desc": f"author: {arg}",
      "HNS_POINTS": HNS_POINTS,
      "search_hash": f"search||{arg}|{HNS_POINTS}"
    }
  }])
output(respect_order=False)
