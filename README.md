# org-auto

One job: run an Emacs command stored on an Org entry when that entry's
SCHEDULED or DEADLINE time arrives.

```org
* TODO Post weekly report
DEADLINE: <2026-11-13 Fri 14:00>
:PROPERTIES:
:EXEC: (my-notify "report due")
:END:
```

## Install

```elisp
(add-to-list 'load-path "~/path/to/org-auto")
(require 'org-auto)
(org-auto-mode 1)
```

## Rules

- Property `:EXEC:` (customizable, `org-auto-property`) holds an Elisp
  form starting with `(` or a command name (`my-cmd` or `M-x my-cmd`).
- TODO entries only — DONE entries and plain headings are ignored.
- Both SCHEDULED and DEADLINE work; put them on ONE planning line
  (`DEADLINE: <> SCHEDULED: <>`) so the properties drawer stays
  attached.
- A timestamp without a time-of-day fires at `org-auto-default-time`
  (default `09:00`).
- While the command runs, `org-auto-current-entry` is bound to
  `(:file FILE :heading HEADING)` for context.

## Timer lifecycle

Timers are re-armed when the mode turns on, after saving an agenda Org
file, and by hand with `M-x org-auto-refresh`. Disable the mode to
cancel everything.

## Limitations (v1, deliberate)

- No catch-up: times already past when a refresh happens are skipped.
- Repeaters and warning periods are ignored — each timestamp fires
  once.
- Diary-sexp timestamps are not supported.

## Development

```sh
emacs -Q --batch -L . -l tests/test-org-auto.el -f ert-run-tests-batch-and-exit
```

Requires Emacs 27.1+, Org 9.1+. License: MIT.
