#!/bin/bash -eu

ARCHIVE_HOST_NAME="$1"
ARCHIVE_PORT="$2"

nc -w1 -z "$ARCHIVE_HOST_NAME" "$ARCHIVE_PORT" > /dev/null 2>&1
