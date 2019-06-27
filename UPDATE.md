Update instructions
==

In this order:

### Make a backup

```
sh .backup/backup.sh
```

### Pull last changes

```
git pull
```

### Merge upstream

Check upstream remote settings

```
$ git remote -v
...
upstream	https://github.com/edemaine/coauthor (fetch)
upstream	git@github.com:edemaine/coauthor (push)
```

Then

```
git fetch upstream
git merge upstream/master
```

And commit if necessary.

### Update npm dependencies

```
rm -rf node_modules package-lock.json
meteor npm install
```

### Deploy new version

```
mup deploy
```
