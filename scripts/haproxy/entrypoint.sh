#!/bin/sh
set -e

TEMPLATE="/usr/local/etc/haproxy/haproxy.cfg.template"
OUTPUT="/tmp/haproxy.cfg"

echo ">>> HAProxy Starting (MODE=${APP_ENV:-unknown})"
echo "    PRIMARY_IP=${PRIMARY_IP} REPLICA1_IP=${REPLICA1_IP} REPLICA2_IP=${REPLICA2_IP}"

if [ -z "${PRIMARY_IP}" ] || [ -z "${REPLICA1_IP}" ] || [ -z "${REPLICA2_IP}" ]; then
    echo ">>> ERROR: Missing env vars"
    exit 1
fi

if command -v envsubst >/dev/null 2>&1; then
    envsubst '${PRIMARY_IP} ${REPLICA1_IP} ${REPLICA2_IP}' < "${TEMPLATE}" > "${OUTPUT}"
else
    sed -e "s|\${PRIMARY_IP}|${PRIMARY_IP}|g" \
        -e "s|\${REPLICA1_IP}|${REPLICA1_IP}|g" \
        -e "s|\${REPLICA2_IP}|${REPLICA2_IP}|g" \
        "${TEMPLATE}" > "${OUTPUT}"
fi

cat "${OUTPUT}"
haproxy -c -f "${OUTPUT}"
exec haproxy -W -db -f "${OUTPUT}"
