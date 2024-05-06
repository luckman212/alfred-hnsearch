#!/usr/bin/env python3

import argparse
import os
import sys
import json
import time

WF_CACHE_DIR = os.getenv('alfred_workflow_cache', '.')
HNS_HIST_FILE = os.path.join(WF_CACHE_DIR, 'history.json')
HNS_HIST_SIZE = int(os.getenv('HNS_HIST_SIZE', 3))
HNS_DEFAULT_POINTS = int(os.getenv('HNS_POINTS', 10))

class HNSearch:
  def __init__(self, s):
    self.date = None
    for attr in vars(s):
      setattr(self, attr, getattr(s, attr))
    if not self.date:
      self.date = int(time.time())

  @classmethod
  def from_json(h, json_data):
    instance = h.__new__(h)
    for key, value in json_data.items():
      setattr(instance, key, value)
    return instance

def hist_clear():
  hitems = []
  with open(HNS_HIST_FILE, 'w') as h:
    json.dump(hitems, h, indent=2)

def hist_add(s):
  if not (s and s.search_desc):
    return
  hitems = []
  if HNS_HIST_SIZE > 0:
    if os.path.exists(HNS_HIST_FILE):
      with open(HNS_HIST_FILE, 'r') as h:
        hitems = json.load(h)
    hitems = [i for i in hitems if i['search_hash'] != s.search_hash]
    s_dict = vars(s)
    hitems.append(s_dict)
    hitems = hitems[-HNS_HIST_SIZE:]
  with open(HNS_HIST_FILE, 'w') as h:
    json.dump(hitems, h, indent=2)

def hist_get():
  hitems = []
  if HNS_HIST_SIZE <= 0 or not os.path.exists(HNS_HIST_FILE):
    return hitems
  with open(HNS_HIST_FILE, 'r') as h:
    hist_items = json.load(h)
  hist_items = hist_items[-HNS_HIST_SIZE:]
  rev_hist_items = hist_items[::-1]
  for i in rev_hist_items:
    s = HNSearch.from_json(i)
    t = s.search_desc
    qs = s.search
    if s.points != HNS_DEFAULT_POINTS:
      t += f' ↑{str(s.points)}'
      qs += f'|{s.points}'
    hitems.append({
      "title": t,
      "subtitle": time.strftime('%a %b %-d %Y, %-I:%M %p', time.localtime(s.date)),
      "mods": { "ctrl": { "subtitle": "" }, "alt": { "subtitle": "" }},
      "icon": { "path": "icons/gray.png" },
      "mods": {
        "alt": {
          "subtitle": "queue for searching again",
          "variables": {
            "HNS_ACTION": "requeue",
            "HNS_QSEARCH": qs
          }
        }
      },
      "variables": {
        "HNS_ACTION": "init",
        "VERB": s.verb,
        "AUTHOR": s.author,
        "search": s.search,
        "search_desc": s.search_desc,
        "HNS_POINTS": s.points,
        "search_hash": s.search_hash
      }
    })
  return hitems

def main(args):
  parser = argparse.ArgumentParser(description=None, epilog=None, add_help=False)
  parser.add_argument('--action',
    type=str,
    choices=[ 'add', 'get', 'clear' ],
    required=True)
  parser.add_argument('--search_desc', type=str, help=argparse.SUPPRESS)
  parser.add_argument('--verb', type=str, help=argparse.SUPPRESS)
  parser.add_argument('--search', type=str, help=argparse.SUPPRESS)
  parser.add_argument('--author', type=str, help=argparse.SUPPRESS)
  parser.add_argument('--points', type=int, help=argparse.SUPPRESS)
  parser.add_argument('--search_hash', type=str, help=argparse.SUPPRESS)
  try:
    parsed = parser.parse_args()
  except argparse.ArgumentError:
    print(f'error', file=sys.stderr)
    exit(1)
  #print(parsed, file=sys.stderr)
  if parsed.action == 'add':
    s = HNSearch(parsed)
    delattr(s, 'action')
    hist_add(s)
  if parsed.action == 'get':
    print(hist_get())
  if parsed.action == 'clear':
    hist_clear()

if __name__ == '__main__':
  sys.exit(main(sys.argv[1:]))
