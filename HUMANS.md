# HUMANS.md — org-auto

A guide for humans navigating and developing this codebase. Written
2026-11-18 by the agent that maintains it, per the org-wide rule that
every agent-developed repo carries one.

## What this is

One Emacs package, one file (`org-auto.el`), one job: run the Elisp
command stored in an Org entry's `:EXEC:` property at the moment that
entry's SCHEDULED or DEADLINE timestamp arrives. Think "cron entries
that live inside my agenda files, one line each, editable as plain
Org".

## The mental model

The whole package is a three-stage pipeline:

1. **Scan** — walk every entry in `org-agenda-files`, keep the TODO
   entries that carry an `:EXEC:` property and a future SCHEDULED or
   DEADLINE.
2. **Arm** — for each collected item, arm one built-in Emacs one-shot
   timer (`run-at-time`) that fires at that timestamp.
3. **Fire** — when the timer goes off, re-check the entry against the
   file (it may have changed since arming), then run the command.

Everything else in the file exists to decide *when to re-run stages
1–2* (the "refresh").

## Code map (org-auto.el, in reading order)

| Symbol | Stage | What it does |
|---|---|---|
| `org-auto-property` | config | Which entry property holds the command (default `"EXEC"`). |
| `org-auto-default-time` | config | HH:MM used when a timestamp has no time-of-day. |
| `org-auto-idle-delay` | config | Idle seconds after an edit before re-arming; nil = only saves re-arm. |
| `org-auto--collect` | scan | `org-map-entries` over the agenda scope → list of `(TIME FILE HEADING CMD)`. |
| `org-auto--ts-to-time` | scan | Org timestamp string → absolute time; handles the no-time-of-day case and rejects diary sexps. |
| `org-auto--fire` | fire | Runs one command (Elisp form or `M-x` command), binding `org-auto-current-entry` for context. Errors are caught and messaged, never propagate. |
| `org-auto--entry-live-p` | fire | The fire-time re-check: rescans only the owning file (`org-map-entries` with a `(list file)` scope) and returns non-nil only if the heading still exists, is not DONE, and still carries the same EXEC string. |
| `org-auto--fire-maybe` | fire | What the timer actually calls: liveness check, then `org-auto--fire` or a skip message. |
| `org-auto-refresh` | arm | Cancel-all + rescan + re-arm. The single entry point for stages 1–2. Cancels any pending idle refresh so save-then-idle doesn't double-run. |
| `org-auto--after-save` | trigger | Runs the refresh when an agenda file is saved (`after-save-hook`). |
| `org-auto--after-change` | trigger | Runs on every edit in an Org buffer (`after-change-functions`, buffer-local); if the buffer's file is an agenda file, restarts a debounced `run-with-idle-timer` so the refresh happens `org-auto-idle-delay` seconds after you stop typing. |
| `org-auto-mode` | wiring | Global minor mode: adds/removes the hooks, wires already-open buffers, arms on enable, cancels everything on disable. |

## The refresh triggers (why there are three)

A timer armed at 09:00 for a deadline you moved to 11:00 at 08:55 is
wrong unless something re-arms it. Three triggers cover the realistic
edit paths:

- **mode enable** — the baseline arming;
- **save** (`after-save-hook`) — the classic "I edited and saved";
- **idle after edit** (`after-change-functions` + `run-with-idle-timer`)
  — the "I moved the timestamp but haven't saved" case; debounced so
  a burst of typing costs one rescan, not one per keystroke.

External edits (git pull, sync tools) are seen by none of these;
`M-x org-auto-refresh` is the documented manual escape hatch.

## Invariants worth knowing before you hack

- TODO-only: DONE and plain headings are never armed, and a timer
  whose entry became DONE between arming and firing is skipped by
  `org-auto--entry-live-p`. Don't arm on state you didn't re-check.
- One timer per timestamp: an entry with both SCHEDULED and DEADLINE
  arms two. Repeaters fire once (documented v1 limitation, not a bug).
- No catch-up: past timestamps are skipped at refresh time.
- The scan uses Org's own machinery (`org-map-entries`,
  `org-agenda-file-p`, `org-time-string-to-time`). If you find
  yourself hand-parsing an Org timestamp or hand-rolling agenda-file
  membership, stop — that reinvention was removed once already
  (2026-11-18, see AI-REVIEW.org).
- `org-auto--fire` must never signal: a broken command messages and
  dies alone; it must not take the timer loop down.

## Developing

```sh
# Both gates the repo law requires before landing:
emacs -Q --batch -L . --eval "(setq byte-compile-error-on-warn t)" \
  -f batch-byte-compile org-auto.el
emacs -Q --batch -L . -l tests/test-org-auto.el \
  -f ert-run-tests-batch-and-exit
```

- Tests are ERT (`tests/test-org-auto.el`) against a checked-in
  fixture agenda (`tests/fixture.org`). The fixture's headings are
  load-bearing — tests assert on their exact text.
- Land on `ai/main` (repo law); the EXEC grammar is the public API,
  bump the version if you touch it.
- Floor: Emacs 27.1, Org 9.1.
