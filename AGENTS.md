# AGENTS.md — org-auto

Global law lives at khaalidrafi/agent-team-ci (`AGENTS.md`, repo root).
It is binding here in full: model author identity, both Co-authored-by
trailers, ai/* task branches, small commits, secret law (env var names
only), no landing claim without tests + guard + ls-remote.

## Repo specifics

- Branch law: land on `ai/main` (never trunk directly).
- Landing gate: byte-compile 0 warnings + `emacs -Q --batch -L . -l
  tests/test-org-auto.el -f ert-run-tests-batch-and-exit` green, no
  network.
- Single package: `org-auto.el`. One feature per file; new features
  get their own file + ERT suite in `tests/`.
- Property default is `EXEC` (`org-auto-property`); do not break the
  documented grammar in README.md without bumping the version.
