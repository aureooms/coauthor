#!/usr/bin/env sh

set -o xtrace

SERVER='meteorapp@coauthor.ulb.ac.be'
CLOUD='db' # dropbox
IDENTITY="$HOME/.ssh/coauthor-meteorapp"

function onserver {
  ssh -i "$IDENTITY" "$SERVER" "$@"
}

function load {
  rsync -e "ssh -i $IDENTITY" -a "$@"
}

cd "$(dirname "$0")"
onserver rm -rf dump/coauthor coauthor.gz || exit 1
onserver mongodump --db coauthor || exit 1
onserver tar czf coauthor.gz dump/coauthor || exit 1
load "$SERVER":coauthor.gz coauthor-backup.gz || exit 1
rc copy coauthor-backup.gz "$CLOUD":coauthor-backup/"$(date '+%Y-%m-%d_%H:%M:%S')"

if [ "$?" -eq 0 ] ; then
  echo 'SUCCESS!!'
else
  echo 'FAILURE...'
fi
