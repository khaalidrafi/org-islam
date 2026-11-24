EMACS ?= emacs

# Pure elisp: cal-islam and solar are built-ins, org is a built-in,
# Awqat is optional at runtime and never needed for tests.  No -Q
# here, so a distribution's site-lisp is still found (same law as
# the other packages in the family).
LOAD = -L .

SRCS = org-islam.el

all: compile

compile:
	$(EMACS) --batch $(LOAD) --eval '(setq byte-compile-error-on-warn t)' \
  -f batch-byte-compile $(SRCS)

test: compile
	$(EMACS) --batch $(LOAD) -l tests/test-org-islam.el -f ert-run-tests-batch-and-exit

clean:
	rm -f $(SRCS:.el=.elc) tests/*.elc

.PHONY: all compile test clean
