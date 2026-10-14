#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SmartPick_iC - Generatore CSV variabili per importazione diretta in iCube Engineer
=================================================================================

Formato CSV identico all'export/import della Variable Table di iCube Engineer
(riferimento: testVar.csv):

    Group;Name;DataType;Usage;IsTranslate;Comment;InitValue;AccessSpecifier;IsRetain;IsConstant;IsOpc;Address

Uso (dalla root del repository):

    python3 Variables/gen_var_csv.py

Output:

    Variables/<modulo>/<target>.csv     CSV "import-ready" (12 colonne esatte),
                                        uno per ogni tabella variabili di iCube:
                                        GVL, interfaccia FB, ogni METHOD,
                                        PROGRAM, FUNCTION, TYPE (riferimento)
    Variables/ByWorksheet/<foglio>.csv  un CSV per foglio .st (tutte le variabili
                                        del foglio, utile come documento)
    Variables/Vars_MASTER.csv           registro riassuntivo di TUTTE le variabili

Mapping ST -> CSV:

    VAR           -> Group=VAR           Usage=Local  (Global se dentro GVL)
    VAR_INPUT     -> Group=VAR_INPUT     Usage=Input
    VAR_OUTPUT    -> Group=VAR_OUTPUT    Usage=Output
    VAR_IN_OUT    -> Group=VAR_IN_OUT    Usage=InOut
    VAR CONSTANT  -> Group=VAR CONSTANT  IsConstant=True
    VAR RETAIN    -> Group=VAR RETAIN    IsRetain=True
    campi STRUCT  -> Group=STRUCT        (solo riferimento: i DUT si creano nel
                                          DUT editor di iCube, non via CSV)
    literal ENUM  -> Group=ENUM          (solo riferimento)
"""

import glob
import os
import re

# ---------------------------------------------------------------------------
# Configurazione (modificabile senza toccare la logica)
# ---------------------------------------------------------------------------
GVL_USAGE = 'Global'          # Usage delle variabili dichiarate dentro i GVL
ACCESS_SPECIFIER = 'None'
IS_TRANSLATE = 'False'
IS_OPC = 'False'
ADDRESS = ''

HEADER = ['Group', 'Name', 'DataType', 'Usage', 'IsTranslate', 'Comment',
          'InitValue', 'AccessSpecifier', 'IsRetain', 'IsConstant', 'IsOpc', 'Address']

SECTION_USAGE = {
    'VAR': 'Local',
    'VAR_INPUT': 'Input',
    'VAR_OUTPUT': 'Output',
    'VAR_IN_OUT': 'InOut',
    'VAR CONSTANT': 'Local',
    'VAR RETAIN': 'Local',
}

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


# ---------------------------------------------------------------------------
# Scanner commenti/letterali (mantiene gli offset del testo originale)
# ---------------------------------------------------------------------------
def strip_comments_keep_map(txt):
    """Ritorna (code, comments).
    code = testo senza commenti (sostituiti da spazi, offset invariati).
    comments = [(start, end, testo)] con offset su txt."""
    out = []
    comments = []
    i, n = 0, len(txt)
    in_str = False
    while i < n:
        c = txt[i]
        if in_str:
            out.append(c)
            if c == "'":
                if i + 1 < n and txt[i + 1] == "'":
                    out.append("'")
                    i += 2
                    continue
                in_str = False
            i += 1
            continue
        if c == "'":
            in_str = True
            out.append(c)
            i += 1
            continue
        if c == '(' and i + 1 < n and txt[i + 1] == '*':
            j = txt.find('*)', i + 2)
            j = n - 2 if j < 0 else j
            comments.append((i, j + 2, txt[i + 2:j]))
            out.append(' ' * (j + 2 - i))
            i = j + 2
            continue
        out.append(c)
        i += 1
    return ''.join(out), comments


def clean_comment(c):
    return re.sub(r'\s+', ' ', c).strip()


def find_stmt_end(code, start):
    """Posizione del ';' terminante la dichiarazione che inizia a start
    (rispetta letterali e parentesi)."""
    depth = 0
    in_str = False
    i = start
    n = len(code)
    while i < n:
        c = code[i]
        if in_str:
            if c == "'":
                if i + 1 < n and code[i + 1] == "'":
                    i += 2
                    continue
                in_str = False
        else:
            if c == "'":
                in_str = True
            elif c in '([':
                depth += 1
            elif c in ')]':
                depth -= 1
            elif c == ';' and depth == 0:
                return i
        i += 1
    return n - 1


def comment_for(code, comments, decl_start, decl_end):
    """Commento inline (stessa riga della fine dichiarazione) oppure il
    commento immediatamente precedente (solo spazi fra commento e dichiarazione)."""
    line_end = code.find('\n', decl_end)
    line_end = len(code) if line_end < 0 else line_end
    for (s, e, t) in comments:
        if decl_end <= s < line_end and code[decl_end:s].strip() == '':
            return clean_comment(t)
    cand = None
    for (s, e, t) in comments:
        if e <= decl_start and code[e:decl_start].strip() == '':
            if cand is None or s > cand[0]:
                cand = (s, e, t)
    if cand is not None:
        return clean_comment(cand[2])
    return ''


# ---------------------------------------------------------------------------
# Parsing dichiarazioni
# ---------------------------------------------------------------------------
def split_type_init(rest):
    """Separa 'TYPE [:= INIT]' al primo ':=' a profondita 0."""
    depth = 0
    in_str = False
    i = 0
    while i < len(rest):
        c = rest[i]
        if in_str:
            if c == "'":
                if i + 1 < len(rest) and rest[i + 1] == "'":
                    i += 2
                    continue
                in_str = False
        else:
            if c == "'":
                in_str = True
            elif c in '([':
                depth += 1
            elif c in ')]':
                depth -= 1
            elif c == ':' and i + 1 < len(rest) and rest[i + 1] == '=' and depth == 0:
                return rest[:i].strip(), rest[i + 2:].strip()
        i += 1
    return rest.strip(), ''


def parse_decls(abs_start, abs_end, code, comments):
    """Estrae le dichiarazioni dal segmento code[abs_start:abs_end]."""
    rows = []
    pos = abs_start
    while pos < abs_end:
        # salta spazi e righe vuote
        while pos < abs_end and code[pos] in ' \t\r\n':
            pos += 1
        if pos >= abs_end:
            break
        decl_start = pos
        semi = find_stmt_end(code, decl_start)
        if semi >= abs_end:
            break
        decl = code[decl_start:semi].strip()
        decl = re.sub(r'\s+', ' ', decl)
        pos = semi + 1
        m = re.match(r'^([A-Za-z0-9_,\s]+?)\s*:\s*(.*)$', decl, flags=re.S)
        if not m:
            continue
        names = [x.strip() for x in m.group(1).split(',') if x.strip()]
        vtype, vinit = split_type_init(m.group(2))
        vtype = re.sub(r'\s+', ' ', vtype).strip()
        vinit = re.sub(r'\s+', ' ', vinit).strip()
        cmt = comment_for(code, comments, decl_start, semi + 1)
        for nm in names:
            rows.append({'name': nm, 'type': vtype, 'init': vinit, 'comment': cmt})
    return rows


VARSEC_RE = re.compile(
    r'\b(VAR_INPUT|VAR_OUTPUT|VAR_IN_OUT|VAR\s+CONSTANT|VAR\s+RETAIN|VAR)\b(.*?)\bEND_VAR\b',
    flags=re.S)


def parse_var_sections(abs_start, abs_end, code, comments):
    """Sezioni VAR* dentro il segmento indicato -> righe con kind."""
    rows = []
    seg = code[abs_start:abs_end]
    for m in VARSEC_RE.finditer(seg):
        kind = re.sub(r'\s+', ' ', m.group(1).strip())
        s = abs_start + m.start(2)
        e = abs_start + m.end(2)
        for r in parse_decls(s, e, code, comments):
            r['kind'] = kind
            rows.append(r)
    return rows


# ---------------------------------------------------------------------------
# Parsing tipi (STRUCT / ENUM)
# ---------------------------------------------------------------------------
def parse_types(code, comments):
    types = []
    for tm in re.finditer(r'\bTYPE\s+([A-Za-z0-9_]+)\s*:\s*(.*?)\bEND_TYPE\b',
                          code, flags=re.S):
        tname = tm.group(1)
        tbody = tm.group(2)
        t_abs = tm.start(2)
        if re.search(r'\bSTRUCT\b', tbody):
            fm = re.search(r'\bSTRUCT\b(.*?)\bEND_STRUCT\b', tbody, flags=re.S)
            fields = []
            if fm:
                fs = t_abs + fm.start(1)
                fe = t_abs + fm.end(1)
                for r in parse_decls(fs, fe, code, comments):
                    r['kind'] = 'STRUCT'
                    fields.append(r)
            types.append({'name': tname, 'kind': 'STRUCT', 'items': fields})
        else:
            lits = []
            depth = 0
            lstart = None
            inner = None
            for i, c in enumerate(tbody):
                if c == '(':
                    depth += 1
                    if depth == 1:
                        lstart = i
                elif c == ')':
                    depth -= 1
                    if depth == 0 and lstart is not None:
                        inner = tbody[lstart + 1:i]
                        break
            if inner is None:
                inner = tbody
            cnt = 0
            for part in inner.split(','):
                part = part.strip()
                if not part:
                    continue
                if ':=' in part:
                    nm, val = part.split(':=', 1)
                    nm, val = nm.strip(), val.strip()
                    try:
                        cnt = int(val) + 1
                    except ValueError:
                        pass
                else:
                    nm, val = part, str(cnt)
                    cnt += 1
                lits.append({'name': nm, 'value': val, 'comment': ''})
            types.append({'name': tname, 'kind': 'ENUM', 'items': lits})
    return types


# ---------------------------------------------------------------------------
# Emissione CSV
# ---------------------------------------------------------------------------
def csv_field(s):
    s = s or ''
    if any(ch in s for ch in ';"\r\n'):
        return '"' + s.replace('"', '""') + '"'
    return s


def make_row(vr, usage=None, group=None):
    """Riga CSV dalle 12 colonne a partire da una dichiarazione."""
    kind = vr.get('kind', 'VAR')
    grp = group if group is not None else kind
    usg = usage if usage is not None else SECTION_USAGE.get(kind, 'Local')
    is_const = 'True' if kind == 'VAR CONSTANT' else 'False'
    is_ret = 'True' if kind == 'VAR RETAIN' else 'False'
    return [grp, vr['name'], vr['type'], usg, IS_TRANSLATE, vr['comment'],
            vr['init'], ACCESS_SPECIFIER, is_ret, is_const, IS_OPC, ADDRESS]


def write_csv(path, rows):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='\r\n') as f:
        f.write(';'.join(HEADER) + '\n')
        for r in rows:
            f.write(';'.join(csv_field(x) for x in r) + '\n')
    return len(rows)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    os.chdir(ROOT)
    files = sorted(glob.glob('[0-9][0-9]_*/**/*.st', recursive=True) + glob.glob('00_*.st'))
    master = []
    out_files = []
    stats = {'GVL': 0, 'FB': 0, 'METHOD': 0, 'PROGRAM': 0, 'FUNCTION': 0,
             'STRUCT': 0, 'ENUM': 0, 'TYPE_WS_VAR': 0}

    for path in files:
        base = os.path.splitext(os.path.basename(path))[0]
        mod = os.path.dirname(path) or '.'
        txt = open(path, encoding='utf-8').read()
        code, comments = strip_comments_keep_map(txt)

        ws_rows = []   # righe per il CSV "per foglio"

        # ---- TYPE (riferimento DUT) --------------------------------------
        for tp in parse_types(code, comments):
            rows = []
            if tp['kind'] == 'STRUCT':
                for fld in tp['items']:
                    rows.append(make_row(fld, usage='Local', group='STRUCT'))
                    stats['STRUCT'] += 1
            else:
                for lit in tp['items']:
                    rows.append(['ENUM', lit['name'], tp['name'], 'Local',
                                 IS_TRANSLATE, '', lit['value'], ACCESS_SPECIFIER,
                                 'False', 'False', IS_OPC, ADDRESS])
                    stats['ENUM'] += 1
            if rows:
                tag = 'S' if tp['kind'] == 'STRUCT' else 'E'
                out = os.path.join('Variables', 'DUT_Reference', mod, f'{base}.{tag}.{tp["name"]}.csv')
                n = write_csv(out, rows)
                out_files.append((out, n))
                ws_rows.extend(rows)
                for r in rows:
                    master.append([path, tp['kind'], tp['name']] + r)

        # ---- GVL --------------------------------------------------------
        is_gvl = base.startswith('GVL_')
        if is_gvl:
            rows = []
            for vr in parse_var_sections(0, len(code), code, comments):
                usage = GVL_USAGE
                rows.append(make_row(vr, usage=usage))
                stats['GVL'] += 1
            if rows:
                out = os.path.join('Variables', mod, f'{base}.csv')
                n = write_csv(out, rows)
                out_files.append((out, n))
                ws_rows.extend(rows)
                for r in rows:
                    master.append([path, 'GVL', base] + r)

        # ---- FUNCTION ----------------------------------------------------
        done_ranges = []
        for fm in re.finditer(r'^\s*FUNCTION\s+([A-Za-z0-9_]+)\s*:', code, flags=re.M):
            fname = fm.group(1)
            fblk = re.search(r'\bFUNCTION\s+' + re.escape(fname) + r'\s*:.*?\bEND_FUNCTION\b',
                             code, flags=re.S)
            if not fblk:
                continue
            done_ranges.append((fblk.start(), fblk.end()))
            rows = []
            for vr in parse_var_sections(fblk.start(), fblk.end(), code, comments):
                rows.append(make_row(vr))
                stats['FUNCTION'] += 1
            if rows:
                out = os.path.join('Variables', mod, f'{fname}.csv')
                n = write_csv(out, rows)
                out_files.append((out, n))
                ws_rows.extend(rows)
                for r in rows:
                    master.append([path, 'FUNCTION', fname] + r)

        # ---- FUNCTION_BLOCK ----------------------------------------------
        fb_names = []
        for fbm in re.finditer(r'^\s*FUNCTION_BLOCK\s+([A-Za-z0-9_]+)', code, flags=re.M):
            fbname = fbm.group(1)
            fb_names.append(fbname)
            fblk = re.search(r'\bFUNCTION_BLOCK\s+' + re.escape(fbname) + r'\b.*?\bEND_FUNCTION_BLOCK\b',
                             code, flags=re.S)
            if not fblk:
                continue
            done_ranges.append((fblk.start(), fblk.end()))
            rows = []
            for vr in parse_var_sections(fblk.start(), fblk.end(), code, comments):
                rows.append(make_row(vr))
                stats['FB'] += 1
            if rows:
                out = os.path.join('Variables', mod, f'{base}.csv')
                n = write_csv(out, rows)
                out_files.append((out, n))
                ws_rows.extend(rows)
                for r in rows:
                    master.append([path, 'FB', fbname] + r)

        # ---- METHOD (blocchi fratelli, dopo END_FUNCTION_BLOCK) -----------
        for mm in re.finditer(r'^\s*METHOD\s+([A-Za-z0-9_]+)\s*:', code, flags=re.M):
            mname = mm.group(1)
            mblk = re.search(r'\bMETHOD\s+' + re.escape(mname) + r'\s*:.*?\bEND_METHOD\b',
                             code, flags=re.S)
            if not mblk:
                continue
            done_ranges.append((mblk.start(), mblk.end()))
            rows = []
            for vr in parse_var_sections(mblk.start(), mblk.end(), code, comments):
                rows.append(make_row(vr))
                stats['METHOD'] += 1
            if rows:
                owner = fb_names[0] if fb_names else base
                out = os.path.join('Variables', mod, f'{base}.M.{mname}.csv')
                n = write_csv(out, rows)
                out_files.append((out, n))
                ws_rows.extend(rows)
                for r in rows:
                    master.append([path, 'METHOD', f'{owner}.{mname}'] + r)

        # ---- PROGRAM ------------------------------------------------------
        for pm in re.finditer(r'^\s*PROGRAM\s+([A-Za-z0-9_]+)', code, flags=re.M):
            pname = pm.group(1)
            pblk = re.search(r'\bPROGRAM\s+' + re.escape(pname) + r'\b.*?\bEND_PROGRAM\b',
                             code, flags=re.S)
            if not pblk:
                continue
            done_ranges.append((pblk.start(), pblk.end()))
            rows = []
            for vr in parse_var_sections(pblk.start(), pblk.end(), code, comments):
                rows.append(make_row(vr))
                stats['PROGRAM'] += 1
            if rows:
                out = os.path.join('Variables', mod, f'{base}.csv')
                n = write_csv(out, rows)
                out_files.append((out, n))
                ws_rows.extend(rows)
                for r in rows:
                    master.append([path, 'PROGRAM', pname] + r)

        # ---- VAR residue a livello foglio (es. costanti nei DUT) ---------
        if not is_gvl and not fb_names and not any(
                re.match(r'^\s*(FUNCTION|PROGRAM)\s+', code.splitlines()[i])
                for i in range(min(3, len(code.splitlines())))):
            covered = [any(s <= m.start() < e for (s, e) in done_ranges)
                       for m in VARSEC_RE.finditer(code)]
            rows = []
            for m in VARSEC_RE.finditer(code):
                if any(s <= m.start() < e for (s, e) in done_ranges):
                    continue
                kind = re.sub(r'\s+', ' ', m.group(1).strip())
                s, e = m.start(2), m.end(2)
                for vr in parse_decls(s, e, code, comments):
                    vr['kind'] = kind
                    rows.append(make_row(vr))
                    stats['TYPE_WS_VAR'] += 1
            if rows:
                out = os.path.join('Variables', mod, f'{base}.WS_VARS.csv')
                n = write_csv(out, rows)
                out_files.append((out, n))
                ws_rows.extend(rows)
                for r in rows:
                    master.append([path, 'WS_VAR', base] + r)

        # ---- CSV per foglio (ByWorksheet) --------------------------------
        if ws_rows:
            out = os.path.join('Variables', 'ByWorksheet', f'{base}.csv')
            n = write_csv(out, ws_rows)
            out_files.append((out, n))

    # ---- MASTER ----------------------------------------------------------
    os.makedirs('Variables', exist_ok=True)
    master_path = os.path.join('Variables', 'Vars_MASTER.csv')
    with open(master_path, 'w', encoding='utf-8', newline='\r\n') as f:
        f.write(';'.join(['Worksheet', 'ScopeKind', 'ScopeName'] + HEADER) + '\n')
        for r in master:
            f.write(';'.join(csv_field(x) for x in r) + '\n')

    total = sum(stats.values())
    print(f'CSV generati : {len(out_files)} file + 1 master')
    print(f'Variabili    : {total}')
    for k, v in stats.items():
        print(f'   {k:12s}: {v}')
    print(f'Master       : {master_path} ({len(master)} righe)')


if __name__ == '__main__':
    main()
