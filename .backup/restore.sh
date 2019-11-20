#!/usr/bin/env sh

set -o xtrace

SERVER='meteorapp@coauthor.ulb.ac.be'
IDENTITY="$HOME/.ssh/coauthor-meteorapp"

function onserver {
  ssh -i "$IDENTITY" "$SERVER" "$@"
}

function load {
  rsync -e "ssh -i $IDENTITY" -a "$@"
}

cd "$(dirname "$0")"
onserver rm -rf dump/coauthor coauthor.gz || exit 1
load coauthor-backup.gz "$SERVER":coauthor.gz || exit 1
onserver tar xzf coauthor.gz || exit 1
onserver mongorestore -d coauthor dump/coauthor/

if [ "$?" -eq 0 ] ; then
  echo 'SUCCESS!!'
else
  echo 'FAILURE...'
fi
