#! /bin/bash

set -e

# Ping healthchecks.io (or any compatible endpoint) if HC_PING_URL is set.
# $1 = path suffix ("", "/start", "/fail"), $2 = optional file sent as body.
# A query string in HC_PING_URL (e.g. ?create=1) is kept after the suffix.
hc_ping() {
    [ -n "${HC_PING_URL}" ] || return 0
    HC_BASE="${HC_PING_URL%%\?*}"
    HC_QUERY="${HC_PING_URL#"${HC_BASE}"}"
    if [ -n "$2" ]; then
        tail -c 90000 "$2" | curl -fsS -m 15 --retry 5 -o /dev/null --data-binary @- "${HC_BASE}$1${HC_QUERY}" \
            || echo "WARNING: healthcheck ping $1 failed"
    else
        curl -fsS -m 15 --retry 5 -o /dev/null "${HC_BASE}$1${HC_QUERY}" \
            || echo "WARNING: healthcheck ping $1 failed"
    fi
}

run_backup() {
    LOG=/tmp/backup.log
    hc_ping /start
    if sh backup.sh > "${LOG}" 2>&1; then RC=0; else RC=$?; fi
    cat "${LOG}"
    if [ "${RC}" -eq 0 ]; then
        hc_ping "" "${LOG}"
    else
        echo "ERROR: backup failed with exit code ${RC}"
        hc_ping /fail "${LOG}"
    fi
    return "${RC}"
}

if [ "${S3_S3V4}" = "yes" ]; then
    aws configure set default.s3.signature_version s3v4
fi

if [ -n "${CRON_TIME}" ]; then
    echo "Running with schedule: ${CRON_TIME}"
    echo "Waiting for first scheduled run..."
    while true; do
        # Calculate seconds until next cron match
        NEXT=$(python3 -c "
import time, re, sys
fields = '${CRON_TIME}'.split()
if len(fields) != 5:
    print(60)
    sys.exit()
m, h, dom, mon, dow = fields
now = time.localtime()
# Simple: sleep 60s and check each minute
print(60)
")
        sleep "${NEXT}"
        # Check if current time matches cron expression
        MATCH=$(python3 -c "
import time
fields = '${CRON_TIME}'.split()
m, h, dom, mon, dow = fields
now = time.localtime()
def match(field, val):
    if field == '*': return True
    for part in field.split(','):
        if '/' in part:
            base, step = part.split('/')
            start = 0 if base == '*' else int(base)
            if (val - start) % int(step) == 0: return True
        elif '-' in part:
            lo, hi = part.split('-')
            if int(lo) <= val <= int(hi): return True
        elif int(part) == val:
            return True
    return False
if (match(m, now.tm_min) and match(h, now.tm_hour) and
    match(dom, now.tm_mday) and match(mon, now.tm_mon) and
    match(dow, (now.tm_wday + 1) % 7)):
    print('yes')
else:
    print('no')
")
        if [ "${MATCH}" = "yes" ]; then
            echo "=== Backup triggered at $(date) ==="
            run_backup || true
            echo "=== Backup finished at $(date) ==="
            # Sleep 60s to avoid running twice in the same minute
            sleep 60
        fi
    done
else
    # One-shot mode (original behavior)
    run_backup
fi
