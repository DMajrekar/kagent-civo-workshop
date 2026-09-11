# kagent on Civo -- workshop driver.
#
# Attendee path:   make doctor && make step-01 ... make step-08
# Instructor path: make hub-01 ... make hub-06   (run before the event)
#
# Every target is idempotent: re-running a step is always safe. If something
# fails mid-step, fix it and run the same target again.
#
#   make            list the steps
#   make all        run the whole attendee workshop, pausing at each command
#   make rehearse   run the whole thing with no pauses (use this to test)
#   make doctor     check prerequisites
#   make clean      delete your cluster

SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

WORKSHOP_STEPS := $(sort $(notdir $(wildcard workshop/step-*)))
HUB_STEPS      := $(sort $(notdir $(wildcard hub/step-*)))

# ---------------------------------------------------------------------- help

help:
	@printf '\n\033[1;34m  kagent on Civo -- workshop\033[0m\n\n'
	@printf '  \033[1mAttendee steps\033[0m\n'
	@for s in $(WORKSHOP_STEPS); do \
	  n=$${s#step-}; n=$${n%%-*}; \
	  d=$$(sed -n 's/^# title: //p' workshop/$$s/run.sh 2>/dev/null | head -1); \
	  printf '    \033[32mmake step-%s\033[0m %s %s\n' "$$n" \
	    "$$(printf '%*s' $$((4 - $${#n})) '')" "$$d"; \
	done
	@printf '\n  \033[1mInstructor / hub steps\033[0m  (run these before the event)\n'
	@for s in $(HUB_STEPS); do \
	  n=$${s#step-}; n=$${n%%-*}; \
	  d=$$(sed -n 's/^# title: //p' hub/$$s/run.sh 2>/dev/null | head -1); \
	  printf '    \033[36mmake hub-%s\033[0m  %s %s\n' "$$n" \
	    "$$(printf '%*s' $$((4 - $${#n})) '')" "$$d"; \
	done
	@printf '\n  \033[1mOther\033[0m\n'
	@printf '    \033[32mmake doctor\033[0m      check your laptop has the right tools\n'
	@printf '    \033[32mmake all\033[0m         run every attendee step in order\n'
	@printf '    \033[32mmake rehearse\033[0m    run every step with no pauses (testing)\n'
	@printf '    \033[32mmake clean\033[0m       delete your workshop cluster\n\n'

.PHONY: help doctor all rehearse clean hub-all

# -------------------------------------------------------------------- checks

doctor:
	@scripts/doctor.sh

# --------------------------------------------------------------- dynamic steps
#
# `make step-03` finds workshop/step-03-*/run.sh and executes it. Adding a step
# is just adding a directory -- no Makefile edit needed.

step-%:
	@d=$$(echo workshop/step-$**/); \
	if [ ! -d "$$d" ]; then echo "no such step: step-$*" >&2; exit 1; fi; \
	bash $$d/run.sh

hub-%:
	@d=$$(echo hub/step-$**/); \
	if [ ! -d "$$d" ]; then echo "no such hub step: hub-$*" >&2; exit 1; fi; \
	bash $$d/run.sh

# ------------------------------------------------------------------ sequences

all:
	@for s in $(WORKSHOP_STEPS); do \
	  case "$$s" in *step-99-*) continue;; esac; \
	  bash workshop/$$s/run.sh || exit $$?; \
	done

# Rehearsal: no pauses, fail fast. If this passes end to end, the live run will
# not surprise you. Run it at least once the day before the event.
rehearse:
	@DEMO_AUTO=1 $(MAKE) all

hub-all:
	@for s in $(HUB_STEPS); do \
	  case "$$s" in *step-99-*) continue;; esac; \
	  bash hub/$$s/run.sh || exit $$?; \
	done

clean:
	@bash workshop/step-99-cleanup/run.sh
