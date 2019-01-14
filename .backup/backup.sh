#!/usr/bin/env sh

set -o xtrace

SERVER='meteorapp@coauthor.ulb.ac.be'
CLOUD='db' # dropbox

cd "$(dirname "$0")"
ssh "$SERVER" rm -rf dump/coauthor coauthor.gz || exit 1
ssh "$SERVER" mongodump --db coauthor || exit 1
ssh "$SERVER" tar czf coauthor.gz dump/coauthor || exit 1
rsync -a "$SERVER":coauthor.gz coauthor-backup.gz || exit 1
rc copy coauthor-backup.gz "$CLOUD":coauthor-backup/"$(date '+%Y-%m-%d_%H:%M:%S')"

if [ "$?" -eq 0 ] ; then
  echo 'SUCCESS!!'
else
  echo 'FAILURE...'
fi
