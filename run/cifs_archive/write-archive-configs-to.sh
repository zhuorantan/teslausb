#!/bin/bash -eu

FILE_PATH="$1"

(
  echo "username=$SHARE_USER"
  echo "password=$SHARE_PASSWORD"
  if [ -n "${SHARE_DOMAIN+x}" ]
  then
    echo "domain=$SHARE_DOMAIN"
  fi
) > "$FILE_PATH"
