#!/usr/bin/env sh

CLOUD='db' # dropbox

rc lsf "$CLOUD":coauthor-backup | cut -d'/' -f1 | sort
