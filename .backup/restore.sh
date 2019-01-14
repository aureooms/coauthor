#!/usr/bin/env sh

set -o xtrace

SERVER='meteorapp@coauthor.ulb.ac.be'

cd "$(dirname "$0")"
ssh "$SERVER" rm -rf dump/coauthor coauthor.gz || exit 1
rsync -a coauthor-backup.gz "$SERVER":coauthor.gz || exit 1
ssh "$SERVER" tar xzf coauthor.gz || exit 1
ssh "$SERVER" mongorestore -d coauthor dump/coauthor/

if [ "$?" -eq 0 ] ; then
  echo 'SUCCESS!!'
else
  echo 'FAILURE...'
fi
