#!/usr/bin/env sh

set -o xtrace

SERVER='meteorapp@coauthor.ulb.ac.be'

cd "$(dirname "$0")"
rsync -a coauthor-backup/ "$SERVER":dump/coauthor/ || exit 1
ssh "$SERVER" mongorestore -d coauthor dump/coauthor/

if [ "$?" -eq 0 ] ; then
  echo 'SUCCESS!!'
else
  echo 'FAILURE...'
fi
