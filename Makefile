EMACS ?= emacs

# Pure Org elisp: agenda collection and time planning over files, no
# external processes.  No -Q here, so a distribution's site-lisp is
# still found (same law as the rest of the family).
LOAD = -L .

SRCS = org-auto.el

all: compile

compile:
	$(EMACS) --batch $(LOAD) --eval '(setq byte-compile-error-on-warn t)' \
	  -f batch-byte-compile $(SRCS)

# The suite locates its fixture.org relative to the test file itself,
# so a plain load from the repo root is enough.
test:
	$(EMACS) --batch $(LOAD) -l tests/test-org-auto.el \
	  -f ert-run-tests-batch-and-exit

clean:
	rm -f $(SRCS:.el=.elc)

.PHONY: all compile test clean
