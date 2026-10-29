#!/bin/zsh
# usage: w.sh SECONDS  -> wait SECONDS of emulated time
n0=$(${0:A:h}/c.sh state | sed -n 's/.*executed=\([0-9]*\).*/\1/p'); t=$((n0 + ${1%.*}*75000000 + 1))
while true; do n=$(${0:A:h}/c.sh state | sed -n 's/.*executed=\([0-9]*\).*/\1/p'); [ "$n" -ge $t ] && break; sleep 0.3; done
