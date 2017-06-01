#!/usr/bin/env sh

set -o xtrace

cd "$(dirname "$0")"
ssh meteorapp@coauthor.ulb.ac.be mongodump --db coauthor
rsync -a meteorapp@coauthor.ulb.ac.be:dump/coauthor/ coauthor-backup/

if rc copy coauthor-backup db:coauthor-backup/"$(date '+%Y-%m-%d_%H:%M:%S')"
then
  echo 'SUCCESS!!'
else
  echo 'FAILURE...'
fi
