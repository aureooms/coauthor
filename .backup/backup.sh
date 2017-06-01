#!/usr/bin/env sh

set -o xtrace

SERVER='meteorapp@coauthor.ulb.ac.be'
CLOUD='db' # dropbox

cd "$(dirname "$0")"
ssh "$SERVER" mongodump --db coauthor || exit 1
rsync -a "$SERVER":dump/coauthor/ coauthor-backup/ || exit 1
rc copy coauthor-backup "$CLOUD":coauthor-backup/"$(date '+%Y-%m-%d_%H:%M:%S')"

if [ "$?" -eq 0 ] ; then
  echo 'SUCCESS!!'
else
  echo 'FAILURE...'
fi
