#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later

# Copyright 2020 Benjamin Gordon.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

BASEDIR="$(dirname "$(readlink -f "$0")")"
if [ ! -r "${BASEDIR}/config" ]; then
    echo "${BASEDIR}/config not found"
    exit 1
fi
. "${BASEDIR}/config"

# Default values for anything not set in config.
: "${START_DELAY:=3}"
: "${MODEM_TYPE:=none}"
: "${MODEM_IP:=}"
: "${EXTERNAL_IFACE:=}"
: "${PING_HOST:=google.com}"
: "${LOGFILE:="/tmp/uplog.$(date +%Y%m).csv"}"
: "${BASE_URL:=}"
: "${CONNECT_TIMEOUT:=5}"

sleep "${START_DELAY}"

# Data to be extracted from modem.
BWDN=""
BWUP=""
SNRDN=""
SNRUP=""
UPDAYS=""
UPHOURS=""
UPMINS=""

if [ -n "${MODEM_IP}" ] && [ -r "${BASEDIR}/modem-${MODEM_TYPE}" ]; then
    . "${BASEDIR}/modem-${MODEM_TYPE}"
fi

# Time right after grabbing modem stats.  Captured here instead of right before
# logging because it will take several seconds to check latency below.
STATS_TS="$(date +%Y-%m-%dT%H:%M:%S)"
UPTIME="$(printf "%02d:%02d" $((${UPDAYS:-0} * 24 + ${UPHOURS:-0})) "${UPMINS:-0}")"

if [ x"${EXTERNAL_IFACE}" = x"detect" ]; then
    EXTERNAL_IFACE=$(ip route show  | grep default | sed -ne 's/.* dev \([^ ]*\) .*/\1/p')
fi
if [ -n "${EXTERNAL_IFACE}" ]; then
    IPADDR="$(ip -o -4 addr show dev "${EXTERNAL_IFACE}" 2>/dev/null | sed -ne 's/.*inet \([0-9.]*\).*/\1/p')"
else
    IPADDR=""
fi
if [ -z "${EXTERNAL_IFACE}" ] || [ -n "${IPADDR}" ] ; then
    LATENCY="$(ping -c 5 "${PING_HOST}" 2>/dev/null | tail -n1 | sed -ne 's/.*= \([0-9.][0-9.]*\).*$/\1/p')"
else
    IPADDR="0.0.0.0"
    LATENCY="0.0"
fi

if [ ! -f "$LOGFILE" ]; then
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "Check Timestamp" "External IP" "Uptime" "Dn Kbps" "Up Kbps" "SNR Dn" "SNR Up" "Latency" > "$LOGFILE"
fi
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%0.1f\n' "$STATS_TS" "$IPADDR" "$UPTIME" "$BWDN" "$BWUP" "$SNRDN" "$SNRUP" "$LATENCY" >> "$LOGFILE"

# Time of the start of the request.  Not reusing $STATS_TS from above because
# several seconds of running ping have probably elapsed since then.
REQ_TS=$(date +%Y%m%d%H%M%S)
if [ -z "${BASE_URL}" ]; then
    exit 0
fi
URL="$(printf '%s?%s&d=%s&u=%s&t=%s' "$BASE_URL" "$REQ_TS" "$BWDN" "$BWUP" "$UPTIME")"

START=$(date +%s)
OUTPUT=$(curl --connect-timeout "${CONNECT_TIMEOUT}" --max-time "$((CONNECT_TIMEOUT+2))" -f -s "$URL")
STATUS=$?
FINISH=$(date +%s)

if [ -n "$OUTPUT" ]; then
    logger -t uplog "$(printf "Unexpected output:\n%s" "$OUTPUT")"
    exit 1
fi
if [ "$STATUS" != 0 ]; then
    logger -t uplog "$(printf "Curl exited with non-zero status %s" "$STATUS")"
    exit 1
fi
logger -t uplog "$(printf "Succeeded in %d seconds" "$((FINISH - START))")"
