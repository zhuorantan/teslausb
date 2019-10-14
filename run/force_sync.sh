#!/bin/bash -eu

printf "Forcing archiveloop to sync by pretending to take archive host offline and back online.\n"
printf "Setting archive unreachable..\n"
if ! touch /tmp/archive-is-unreachable
then
  printf "Something went wrong!  Error %d\nAborting.\n" "$?" 1>&2
  exit 1
fi
while [[ -f /tmp/archive-is-unreachable ]]
do
  printf "Waiting for archiveloop to see canary file..\n"
  sleep 5
done
printf "Done!  archiveloop process should now start its sync process automagically as soon as it sees the archive.\n"

