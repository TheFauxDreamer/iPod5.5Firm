#!/bin/zsh
# usage: c.sh "command" ...  each command sent on its own connection
for x in "$@"; do printf '%s\nquit\n' "$x" | nc -U /tmp/pf-$(id -u).sock | head -c 2000; echo; done
