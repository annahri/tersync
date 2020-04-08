# tersync
Synchronizes / Backs up your specified dir/files to another location.

## Usage
```
tersync.sh

USAGE:
  tersync.sh add -S /src/dir/logs/ -D /dst/dir/frontend/ --name "Frontend" --exclude "PATTERN" --modify
  tersync.sh add -S=/src/dir/logs/ -D=/dst/dir/backend/ -N=Backend -m
  tersync.sh add -NCoreSync -D/dst/dir/ -S/source/dir -m

  tersync.sh mkconfig
  tersync.sh config
  tersync.sh start Frontend-Sync
  tersync.sh stop Frontend-Sync
  tersync.sh rm Frontend-Sync

COMMANDS:
  add [-S <source>] [-D <dst>] [-N <name>] ...
      Add a sync to sync entry
  start [name]
      Start a specified sync
  remove [name]
      Remove a sync from sync list
  stop [name]
      Stop a running sync
  ps < -a >
      List running syncs
  mkconfig
      Create Terfile with unassigned parameters
  config
      Load parameters from config.ini in cwd
  help
      Display this message

OPTIONS:
  -S --source  [DIR]
      Source directory to be synced
  -D --destination  [DIR]
      Destination directory, self-explanatory
  -N --name  [NAME]
      Syncronization name.
  -E --exclude  [PATTERN]
      Exclude pattern.
  -a --append
      Incremental sync, instead of whole file syncronization.
  -v --verbose
      Self-explanatory.

TRIGGERS:
  -m --modify
      Trigger sync on any file modification.
  -c --create
      Trigger sync on any file creation.
  -d --delete
      Trigger sync on any file deletion.

  -h --help
      Display this info message.
```

## Dependencies
- sponge from moreutils
- inotify-tools
- jq

## TODO
- Update status file on unexpected exit
- ...
