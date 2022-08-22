#!/bin/bash

# First parameter specifies if certificate expire in the next X days
DAYS=$1

target=$2
if [ ! -f "$target" ]; then
    echo "Certificate does not exist (RC=2)"
    exit 2;
fi

openssl x509 -checkend $(( 86400 * $DAYS )) -enddate -in "$target" >/dev/null 2>&1
expiry=$?
if [ $expiry -eq 0 ]; then
    echo "Certificate will not expire (RC=0)"
    exit 0
else
    echo "Certificate will expire (RC=1)"
    exit 1
fi

