# Your cluster called -- a capture-the-flag in a week of production logs.
#
# Players need nothing but a phone. Everything here is for the instructor:
# it builds the one cluster ("the hub") that the whole room plays against.
#
#   make             list the steps
#   make hub-all     build the hub end to end
#   make agent-01    add an agent to kagent -- do these while you present
#   make status      where everything is, and the admin key
#
# Every target is idempotent: re-running a step is always safe. If something
# fails mid-step, fix it and run the same target again.

SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

HUB_STEPS := $(sort $(notdir $(wildcard hub/step-*)))
AGENTS    := $(sort $(notdir $(wildcard agents/*.yaml)))
HUB_KUBECONFIG := .state/hub.kubeconfig

help:
	@printf '\n\033[1;34m  Your cluster called -- the CTF\033[0m\n\n'
	@printf '  \033[1mBuild the hub\033[0m  (before the event)\n'
	@for s in $(HUB_STEPS); do \
	  n=$${s#step-}; n=$${n%%-*}; \
	  d=$$(sed -n 's/^# title: //p' hub/$$s/run.sh 2>/dev/null | head -1); \
	  printf '    \033[36mmake hub-%s\033[0m        %s\n' "$$n" "$$d"; \
	done
	@printf '\n  \033[1mAdd agents\033[0m  (during the session, before round two)\n'
	@for a in $(AGENTS); do \
	  n=$${a%%-*}; name=$${a#*-}; name=$${name%.yaml}; \
	  printf '    \033[32mmake agent-%s\033[0m      %s\n' "$$n" "$$name"; \
	done
	@printf '    \033[32mmake agents-clear\033[0m  take every agent away again\n'
	@printf '\n  \033[1mOther\033[0m\n'
	@printf '    \033[32mmake hub-all\033[0m       every hub step in order\n'
	@printf '    \033[32mmake status\033[0m        addresses, admin key, what is running\n\n'

.PHONY: help hub-all status agents-clear

hub-%:
	@d=$$(echo hub/step-$**/); \
	if [ ! -d "$$d" ]; then echo "no such hub step: hub-$*" >&2; exit 1; fi; \
	bash $$d/run.sh

hub-all:
	@for s in $(HUB_STEPS); do \
	  case "$$s" in *step-99-*) continue;; esac; \
	  bash hub/$$s/run.sh || exit $$?; \
	done

# `make agent-02` applies agents/02-*.yaml and waits until it can answer. The
# file is printed first: on a projector, the manifest is the slide.
agent-%:
	@scripts/add-agent.sh $*

agents-clear:
	@scripts/add-agent.sh --clear

status:
	@for f in ctf-endpoint kagent-endpoint grafana-endpoint ctf-admin-key; do \
	  printf '  %-18s %s\n' "$$f" "$$(cat .state/$$f 2>/dev/null || echo '(not set yet)')"; \
	done; \
	if [ -f $(HUB_KUBECONFIG) ]; then \
	  printf '\n'; KUBECONFIG=$(HUB_KUBECONFIG) kubectl -n kagent get agents.kagent.dev 2>/dev/null || true; \
	fi
