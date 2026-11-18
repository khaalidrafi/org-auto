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

Timers re-arm when the mode turns on, when an agenda Org file is
saved, and `org-auto-idle-delay` seconds (default 3) after you stop
editing an agenda file — moving a SCHEDULED timestamp or marking an
entry DONE re-arms without a save. Re-arm means: every armed timer is
cancelled, `org-agenda-files` is rescanned, and one built-in Emacs
timer (`run-at-time`) is armed per future SCHEDULED/DEADLINE that
carries an `:EXEC:` property. At fire time the entry is re-checked
against the file — if it is gone, DONE, or its `:EXEC:` changed since
arming, the command is skipped. Disable the mode to cancel
everything; `M-x org-auto-refresh` re-arms by hand.

## Limitations (v1, deliberate)

- No catch-up: times already past when a refresh happens are skipped.
- Repeaters and warning periods are ignored — each timestamp fires
  once.
- Diary-sexp timestamps are not supported.
- Edits made outside Emacs (git pull, sync tools) are not noticed;
  run `M-x org-auto-refresh` after them.

## Development

```sh
emacs -Q --batch -L . -l tests/test-org-auto.el -f ert-run-tests-batch-and-exit
```

Requires Emacs 27.1+, Org 9.1+. License: MIT.
