"""Validate the outstanding-row parser against REAL rows transcribed from
Qais's outstanding print (ALIF ELECTRONICS). Mirrors the logic in
lib/services/parsers.dart:parseOutstandingRow.

Run: python3 tool/validate_parser.py
"""
import re
import sys

CELL = re.compile(r'03\d{9}')
DATE = re.compile(r'\d{1,2}-[A-Za-z]{3}-\d{2,4}')
KNOWN_OFFICERS = ['Sajjad Ahmed', 'M Asad', 'Amjad Ali Rana',
                  'Yasir islam', 'Arslan Sulehri', 'Ahsan Mehmood']


def to_double(s):
    return float(s.replace(',', '').strip())


def parse_row(line):
    m = CELL.search(line)
    if not m:
        return None
    cell = m.group(0)
    left = line[:m.start()].strip()
    right = line[m.end():].strip()

    toks = left.split()
    if len(toks) < 4 or not toks[0].isdigit() or not re.fullmatch(r'\d{5,6}', toks[1]):
        return None
    ac_no = toks[1]
    acc_date, name_start = '', 2
    for i in range(2, len(toks)):
        if DATE.fullmatch(toks[i]):
            acc_date, name_start = toks[i], i + 1
            break
    tail = ' '.join(toks[name_start:])
    name, officer = tail, ''
    for known in KNOWN_OFFICERS:
        if tail.endswith(known):
            officer, name = known, tail[:-len(known)].strip()
            break

    dm = DATE.search(right)
    if not dm:
        return None
    last_date = dm.group(0)
    nums = right[:dm.start()].split()
    if len(nums) < 7:
        return None
    money = nums[-6:]
    if any(not re.fullmatch(r'[\d,]+', t) for t in money):
        return None
    item = ' '.join(nums[:-6])
    return dict(accountNo=ac_no, accDate=acc_date, name=name, officer=officer,
                cell=cell, item=item, price=to_double(money[0]),
                balance=to_double(money[1]), installment=to_double(money[2]),
                osAmount=to_double(money[3]), paid=to_double(money[4]),
                currentDue=to_double(money[5]), lastInstDate=last_date)


# Real rows from the print (names/numbers as printed).
ROWS = [
    # (raw OCR-ish line, expected dict subset to assert)
    ("1 003077 19-Jul-26 Naeem Akhtar Sajjad Ahmed 03216512528 SOLAR+FAN 285000 185000 46250 92500 0 92500 19-Jul-26",
     dict(accountNo='003077', name='Naeem Akhtar', officer='Sajjad Ahmed',
          cell='03216512528', item='SOLAR+FAN', price=285000.0,
          installment=46250.0, osAmount=92500.0, paid=0.0, currentDue=92500.0)),
    ("7 002910 16-Mar-26 Shahid nadeem Ahmed Sajjad Ahmed 03046856156 MOBILE 174000 87000 14500 14500 8000 6500 29-Sep-26",
     dict(accountNo='002910', name='Shahid nadeem Ahmed', item='MOBILE',
          balance=87000.0, paid=8000.0, currentDue=6500.0,
          lastInstDate='29-Sep-26')),
    ("14 002847 9-Feb-26 Adil Ali Sajjad Ahmed 03256266863 LED 48000 20000 4000 4000 3000 1000 12-Sep-26",
     dict(accountNo='002847', name='Adil Ali', item='LED', osAmount=4000.0,
          paid=3000.0, currentDue=1000.0)),
    ("22 002796 9-Jan-26 Ikram Sajjad Ahmed 03152444967 MOBILE 43800 14600 3650 3650 1850 1800 21-Sep-26",
     dict(accountNo='002796', name='Ikram', currentDue=1800.0, paid=1850.0)),
    ("42 002580 19-Oct-25 M Afzal Sajjad Ahmed 03015215248 BIKE 212000 27000 13500 13500 10000 3500 28-Sep-26",
     dict(accountNo='002580', name='M Afzal', item='BIKE', price=212000.0,
          installment=13500.0)),
]

fails = 0
for raw, expected in ROWS:
    got = parse_row(raw)
    if got is None:
        print(f"FAIL (no parse): {raw[:60]}...");
        fails += 1
        continue
    bad = {k: (expected[k], got[k]) for k in expected if got.get(k) != expected[k]}
    if bad:
        print(f"FAIL {raw[:40]}... mismatches: {bad}")
        fails += 1
    else:
        print(f"OK   A/C {got['accountNo']} | {got['name']} | due {got['currentDue']:,.0f}")

print()
if fails:
    print(f"{fails} row(s) FAILED")
    sys.exit(1)
print("All rows parsed correctly ✔")
