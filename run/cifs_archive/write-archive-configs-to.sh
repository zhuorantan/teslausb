#!/bin/bash -eu

FILE_PATH="$1"

(
  echo "username=$SHARE_USER"
  echo "password=$SHARE_PASSWORD"
) > "$FILE_PATH"
