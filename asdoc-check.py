#!/usr/bin/env python3
"""asdoc-check.py — validate doc blocks in AllSpeak (.as) source files.

Doc-block convention (see prompt-260509.md for design notes). A "section"
looks like this:

    !! prose line                 <- doc prose (zero or more lines)
    !!                            <- blank prose line (paragraph break)
    !! @hash <hex>                <- machine-managed: hash of the code below
    !! @verified <hex>            <- set when a reviewer signs off; stores the
                                     code hash at the time of verification
    <any non-"!!" lines>          <- the code (or labels, blanks, ! comments)
    !!!                           <- terminator (line containing only "!!!")

Line classification (trailing whitespace is ignored — the spec was
tightened so editors that strip it can't corrupt files):

  - Line equals "!!!"                             -> TERMINATOR
  - Line equals "!!"                              -> DOC PROSE (blank line)
  - Line matches "!![ \\t]<content>"               -> DOC PROSE (with content)
    (if <content> starts with "@", it's METADATA)
  - Anything else                                 -> CODE

Usage:
  asdoc-check.py [options] <path> [<path> ...]

  Each <path> is a file or a directory. Directories are walked for files
  matching --ext (default .as).

Options:
  --write       Insert/update "!! @hash" lines so they match the current
                code. Never touches @verified. Without this flag the tool
                is read-only.
  --json        Emit a JSON report on stdout instead of human-readable text.
  --ext .EXT    Extension to match when walking directories (default .as).
  --strict      Treat warnings as errors for exit-code purposes.
  --self-test   Run built-in fixtures and exit.

Exit codes:
  0  no errors (warnings allowed unless --strict)
  1  errors (or warnings under --strict)
  2  invalid invocation
"""

import argparse
import hashlib
import json
import os
import re
import sys


# ---------- line classification ----------

# A doc-block line: !! followed by exactly one space or tab, then content
# (which may be empty — that's the "blank prose line" form).
DOC_LINE_RE = re.compile(r'^!![ \t](.*)$')

# Inside a doc-prose line, a metadata key looks like "@word" optionally
# followed by whitespace and a value.
META_RE = re.compile(r'^@(\w+)(?:[ \t]+(.*))?$')


def classify(line):
    """Classify a single line. `line` should NOT include the trailing newline.

    Returns (kind, payload):
      ('TERM', None)
      ('DOC',  content_str)        <- empty string for the bare "!!" form
      ('META', (key, value))
      ('CODE', line)

    Trailing whitespace on terminator and blank-prose forms is tolerated:
    "!!!  " is the same as "!!!", "!!  " is the same as "!!".
    """
    s = line.rstrip()
    if s == '!!!':
        return ('TERM', None)
    if s == '!!':
        return ('DOC', '')
    m = DOC_LINE_RE.match(line)
    if m:
        content = m.group(1)
        meta = META_RE.match(content)
        if meta:
            return ('META', (meta.group(1), (meta.group(2) or '').rstrip()))
        return ('DOC', content)
    return ('CODE', line)


# ---------- section model ----------

class Section:
    __slots__ = ('start_line', 'end_line', 'doc', 'meta', 'code',
                 'code_line_numbers', 'meta_line_numbers')

    def __init__(self, start_line):
        self.start_line = start_line       # 1-based line of the opener
        self.end_line = None               # 1-based line of the terminator
        self.doc = []                      # list[str]      — prose, in order
        self.meta = {}                     # key -> value (last wins)
        self.meta_line_numbers = {}        # key -> lineno (for diagnostics)
        self.code = []                     # list[str]      — code lines, in order
        self.code_line_numbers = []        # parallel to self.code

    def code_hash(self):
        """SHA-1 of the code, first 8 hex chars.

        Normalization: each line's trailing whitespace is stripped, lines are
        joined with '\\n', and any trailing blank lines are removed. Leading
        whitespace and regular '!' comments are preserved (they're part of
        what the human wrote).
        """
        lines = [ln.rstrip() for ln in self.code]
        while lines and lines[-1] == '':
            lines.pop()
        if not lines:
            return None
        h = hashlib.sha256('\n'.join(lines).encode('utf-8')).hexdigest()
        return h[:8]


# ---------- parser ----------

def parse(text):
    """Parse source text. Returns (sections, issues, raw_lines).

    `issues` is a list of (lineno, severity, code, message) where severity
    is 'error' | 'warn' | 'info'.
    """
    sections = []
    issues = []
    raw_lines = text.splitlines()

    cur = None  # current Section, or None if outside any section
    saw_code_in_section = False  # to flag misplaced doc/meta lines

    for i, raw in enumerate(raw_lines, start=1):
        kind, payload = classify(raw)

        if cur is None:
            # Outside any section.
            if kind == 'TERM':
                issues.append((i, 'error', 'orphan-terminator',
                               'terminator "!!" with no open section'))
            elif kind in ('DOC', 'META'):
                cur = Section(i)
                saw_code_in_section = False
                if kind == 'DOC':
                    cur.doc.append(payload)
                else:
                    key, val = payload
                    if key in cur.meta:
                        issues.append((i, 'warn', 'duplicate-meta',
                                       'duplicate @%s in section' % key))
                    cur.meta[key] = val
                    cur.meta_line_numbers[key] = i
            else:
                # CODE outside a section — fine; not every file uses the
                # convention. No issue raised.
                pass
            continue

        # Inside a section.
        if kind == 'TERM':
            cur.end_line = i
            sections.append(cur)
            cur = None
            saw_code_in_section = False
        elif kind == 'DOC':
            if saw_code_in_section:
                issues.append((i, 'info', 'doc-after-code',
                               'doc prose line appears after code in section '
                               'opened at line %d' % cur.start_line))
            cur.doc.append(payload)
        elif kind == 'META':
            key, val = payload
            if key in cur.meta:
                issues.append((i, 'warn', 'duplicate-meta',
                               'duplicate @%s in section opened at line %d'
                               % (key, cur.start_line)))
            cur.meta[key] = val
            cur.meta_line_numbers[key] = i
        else:  # CODE
            cur.code.append(payload)
            cur.code_line_numbers.append(i)
            if payload.strip() != '':
                saw_code_in_section = True

    if cur is not None:
        issues.append((cur.start_line, 'error', 'unclosed-section',
                       'section opened at line %d has no terminator before EOF'
                       % cur.start_line))

    return sections, issues, raw_lines


# ---------- per-section status ----------

def section_status(section):
    """Return a dict describing hash/verification state for one section."""
    h = section.code_hash()
    stored_hash = section.meta.get('hash')
    verified_hash = section.meta.get('verified')

    status = {
        'start_line': section.start_line,
        'end_line': section.end_line,
        'has_code': h is not None,
        'current_hash': h,
        'stored_hash': stored_hash,
        'verified_hash': verified_hash,
        'doc_lines': len(section.doc),
        'code_lines': len(section.code),
    }

    if h is None:
        status['hash_state'] = 'no-code'
    elif stored_hash is None:
        status['hash_state'] = 'no-baseline'
    elif stored_hash == h:
        status['hash_state'] = 'fresh'
    else:
        status['hash_state'] = 'stale'

    if verified_hash is None:
        status['verify_state'] = 'unverified'
    elif h is None:
        status['verify_state'] = 'verified-no-code'
    elif verified_hash == h:
        status['verify_state'] = 'verified-fresh'
    else:
        status['verify_state'] = 'verified-stale'

    return status


def status_issues(section, status):
    """Issues derived from a section's status. Same shape as parse()'s."""
    out = []
    if status['hash_state'] == 'stale':
        out.append((section.meta_line_numbers.get('hash', section.start_line),
                    'warn', 'hash-stale',
                    'stored @hash %s does not match current code hash %s'
                    % (status['stored_hash'], status['current_hash'])))
    elif status['hash_state'] == 'no-baseline' and status['has_code']:
        out.append((section.start_line, 'info', 'hash-missing',
                    'section has no @hash line — drift cannot be detected'))
    if status['verify_state'] == 'verified-stale':
        out.append((section.meta_line_numbers.get('verified',
                                                  section.start_line),
                    'warn', 'verify-stale',
                    'verified hash %s does not match current code hash %s'
                    % (status['verified_hash'], status['current_hash'])))
    return out


# ---------- write mode (rewrite @hash) ----------

def rewrite_hashes(sections, raw_lines):
    """Return new list of lines with @hash lines updated/inserted.

    Strategy: for each section that has code,
      - if a @hash line already exists, replace its value in place;
      - otherwise, insert a new "!! @hash <hex>" line immediately before the
        terminator.
    """
    # Build a list of edits as (lineno, action, payload) where lineno is
    # 1-based. Actions: 'replace' (replace this line) or 'insert-before'
    # (insert a line before this line).
    edits = []
    for s in sections:
        h = s.code_hash()
        if h is None:
            continue
        new_line = '!! @hash %s' % h
        if 'hash' in s.meta_line_numbers:
            ln = s.meta_line_numbers['hash']
            if raw_lines[ln - 1] != new_line:
                edits.append((ln, 'replace', new_line))
        else:
            edits.append((s.end_line, 'insert-before', new_line))

    if not edits:
        return raw_lines, 0

    # Apply edits in reverse line order so insertions don't shift later
    # line numbers.
    edits.sort(key=lambda e: e[0], reverse=True)
    out = list(raw_lines)
    changes = 0
    for ln, action, payload in edits:
        idx = ln - 1
        if action == 'replace':
            out[idx] = payload
            changes += 1
        elif action == 'insert-before':
            out.insert(idx, payload)
            changes += 1
    return out, changes


# ---------- file processing ----------

def process_file(path, write=False):
    """Process one file. Returns a per-file dict suitable for JSON output."""
    try:
        with open(path, 'r', encoding='utf-8') as f:
            text = f.read()
    except (IOError, OSError, UnicodeDecodeError) as e:
        return {
            'path': path,
            'read_error': str(e),
            'sections': [],
            'issues': [(0, 'error', 'read-failed', str(e))],
            'changed': False,
        }

    sections, issues, raw_lines = parse(text)
    section_reports = []
    for s in sections:
        st = section_status(s)
        section_reports.append(st)
        issues.extend(status_issues(s, st))

    issues.sort(key=lambda i: (i[0], i[1]))

    changed = False
    if write and sections:
        new_lines, n = rewrite_hashes(sections, raw_lines)
        if n > 0:
            # Preserve trailing newline if the original had one.
            had_trailing_nl = text.endswith('\n')
            new_text = '\n'.join(new_lines) + ('\n' if had_trailing_nl else '')
            with open(path, 'w', encoding='utf-8') as f:
                f.write(new_text)
            changed = True

    return {
        'path': path,
        'sections': section_reports,
        'issues': issues,
        'changed': changed,
    }


def walk_paths(paths, ext):
    """Expand paths into a sorted list of files matching `ext`."""
    out = []
    for p in paths:
        if os.path.isdir(p):
            for root, dirs, files in os.walk(p):
                # Skip dot-directories (.git, .venv, etc.)
                dirs[:] = [d for d in dirs if not d.startswith('.')]
                for fn in files:
                    if fn.endswith(ext):
                        out.append(os.path.join(root, fn))
        elif os.path.isfile(p):
            out.append(p)
        else:
            sys.stderr.write('warning: path not found: %s\n' % p)
    out.sort()
    return out


# ---------- output ----------

def render_text(reports, strict):
    """Print human-readable report. Returns exit code."""
    n_files = len(reports)
    n_sections = sum(len(r['sections']) for r in reports)
    n_errors = 0
    n_warns = 0
    n_info = 0
    n_changed = 0

    for r in reports:
        if r['changed']:
            n_changed += 1
        for lineno, sev, code, msg in r['issues']:
            if sev == 'error':
                n_errors += 1
            elif sev == 'warn':
                n_warns += 1
            else:
                n_info += 1
            print('%s:%d: %s [%s] %s' % (r['path'], lineno, sev, code, msg))

    print('')
    print('%d file(s), %d section(s), %d error(s), %d warning(s), %d info'
          % (n_files, n_sections, n_errors, n_warns, n_info))
    if n_changed:
        print('%d file(s) modified (--write)' % n_changed)

    if n_errors > 0:
        return 1
    if strict and n_warns > 0:
        return 1
    return 0


def render_json(reports, strict):
    n_errors = sum(1 for r in reports for i in r['issues'] if i[1] == 'error')
    n_warns = sum(1 for r in reports for i in r['issues'] if i[1] == 'warn')
    out = {
        'files': [
            {
                'path': r['path'],
                'changed': r['changed'],
                'sections': r['sections'],
                'issues': [
                    {'line': ln, 'severity': sv, 'code': cd, 'message': ms}
                    for (ln, sv, cd, ms) in r['issues']
                ],
            }
            for r in reports
        ],
        'summary': {
            'files': len(reports),
            'sections': sum(len(r['sections']) for r in reports),
            'errors': n_errors,
            'warnings': n_warns,
        },
    }
    print(json.dumps(out, indent=2, sort_keys=True))
    if n_errors > 0:
        return 1
    if strict and n_warns > 0:
        return 1
    return 0


# ---------- self-test ----------

SELF_TEST_FIXTURES = [
    # name, source, expected_issue_codes (set)
    ('well-formed',
     "!! one\n"
     "!! two\n"
     "    code line\n"
     "!! @hash deadbeef\n"
     "!!!\n",
     {'hash-stale'}),  # stored hash won't match the real one
    ('verified-fresh',
     "!! doc\n"
     "    code\n"
     "!! @hash %s\n"
     "!! @verified %s\n"
     "!!!\n" % (
         hashlib.sha256(b'    code').hexdigest()[:8],
         hashlib.sha256(b'    code').hexdigest()[:8],
     ),
     set()),
    ('unclosed',
     "!! starts here\n"
     "    some code\n",
     # Unclosed sections aren't appended to the section list, so secondary
     # checks (hash-missing etc.) don't run on them. Fix structure first.
     {'unclosed-section'}),
    ('orphan-terminator',
     "    just code\n"
     "!!!\n",
     {'orphan-terminator'}),
    ('no-convention',
     "    plain code\n"
     "    more code\n",
     set()),
    ('blank-prose-line',
     # bare "!!" inside a doc block is a paragraph break, NOT a terminator
     "!! para one\n"
     "!!\n"
     "!! para two\n"
     "    code\n"
     "!!!\n",
     {'hash-missing'}),
    ('overview-no-code',
     "!! just an overview\n"
     "!!\n"
     "!! second prose line\n"
     "!!!\n",
     set()),
    ('terminator-tolerates-trailing-ws',
     "!! doc\n"
     "    code\n"
     "!!!  \n",
     {'hash-missing'}),
]


def run_self_test():
    failures = 0
    for name, src, expected in SELF_TEST_FIXTURES:
        sections, issues, _ = parse(src)
        for s in sections:
            issues.extend(status_issues(s, section_status(s)))
        codes = {code for (_, _, code, _) in issues}
        if codes != expected:
            failures += 1
            print('FAIL %s' % name)
            print('  expected: %s' % sorted(expected))
            print('  got:      %s' % sorted(codes))
            for ln, sv, cd, ms in issues:
                print('    line %d %s [%s] %s' % (ln, sv, cd, ms))
        else:
            print('ok   %s' % name)
    print('')
    print('%d fixture(s), %d failure(s)' % (len(SELF_TEST_FIXTURES), failures))
    return 1 if failures else 0


# ---------- main ----------

def main(argv):
    ap = argparse.ArgumentParser(
        prog='asdoc-check',
        description='Validate doc blocks in AllSpeak (.as) sources.',
    )
    ap.add_argument('paths', nargs='*', help='files or directories')
    ap.add_argument('--write', action='store_true',
                    help='insert/update !! @hash lines in place')
    ap.add_argument('--json', action='store_true',
                    help='emit JSON report')
    ap.add_argument('--ext', default='.as',
                    help='extension to match when walking dirs (default .as)')
    ap.add_argument('--strict', action='store_true',
                    help='treat warnings as errors for exit code')
    ap.add_argument('--self-test', action='store_true',
                    help='run built-in fixtures and exit')
    args = ap.parse_args(argv)

    if args.self_test:
        return run_self_test()

    if not args.paths:
        ap.print_usage(sys.stderr)
        sys.stderr.write('error: no paths given\n')
        return 2

    files = walk_paths(args.paths, args.ext)
    if not files:
        sys.stderr.write('warning: no files matched\n')
        return 0

    reports = [process_file(p, write=args.write) for p in files]

    if args.json:
        return render_json(reports, args.strict)
    return render_text(reports, args.strict)


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
