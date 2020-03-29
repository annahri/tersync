#!/usr/bin/env bash

readonly cmd="${0##*/}"
readonly terfile_file="Terfile.ini"
readonly status_file="/var/lib/tersync/status"

function __usage_help() {
	cat <<-EOF | less
	$cmd

	USAGE: 
	  $cmd sync -s /src/dir/logs/ -d /dst/dir/frontend/ --name "Frontend" --exclude "PATTERN"
	  $cmd sync -s=/src/dir/logs/ -d=/dst/dir/backend/ -n=Backend
	  $cmd sync -nCoreSync -d/dst/dir/ -s/source/dir 

	  $cmd mkconfig
	  $cmd terfile 
	  $cmd unsync Frontend-Sync
		
	COMMANDS:
  sync [-s <source>] [-d <dst>] [-n <name>] ...
      Start sync
  unsync [name]
      Unsync a running sync
  list
      List running syncs
  mkconfig
      Create Terfile with unassigned parameters
  terfile
      Load parameters from Terfile in cwd
  help
      Display this message

	OPTIONS:
  -s --source  [DIR]
      Source directory to be synced
  -d --destination  [DIR]
      Destination directory, self-explanatory
  -n --name  [NAME]         
      Syncronization name. 
  -e --exclude  [PATTERN]      
      Exclude pattern.
  --append                  
      Incremental sync, instead of whole file syncronization.
  --modify                  
      Trigger sync on any file modifications.
  --delete                  
      Deletes any extraneous file on destination directory.

  -v --verbose
      Self-explanatory.
  -h --help
      Display this info message.
	EOF

  exit 0
}

function get_value() {
  key="$1"
  mandatory=${3:-0}
  value="$(sed -n "s/.*$key *= *\([^ ]*.*\)/\1/p" $terfile_file | tr -d ' ')"
  [[ $mandatory -eq 1 ]] && [[ -z "$value" ]] && msg_error "Tersync error. Empty parameter for key $key."
  case "$value" in
    "false") value=0;;
    "true") value=1;;
    *) value="$value";;
  esac
  echo "$value"
}

function msg_error() {
  echo "$@" >&2
  exit 1
}

function __mkconfig() {
  [[ -f "Terfile" ]] && {
    read -p "Terfile already exists. Overwrite? [Y]: " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] && exit 0
	}

  cat <<EOF > Terfile.ini
; Source directory to be synced
source_dir = 

; Destination directory or host. Examples: 
;  /path/to/dst/             # notice the '/' in the end
;  user@host:/path/to/dst/   # this one is experimental
destination = 

; Specify sync name, this is mandatory
name = 

; Run this sync as daemon, means it will create new systemd entry
; and can be managed via systemd
; Value [ true, false ]
daemon = false

; Enable file exclusion via pattern
; Value [ true, false ]
exclude = false
; Specify pattern to exclude files from syncronization
exclude_pattern =

; Do incremental sync instead of entire file sync. Suitable for log files
; Value [ true, false ]
append = false

; Trigger sync on file modify
; Value [ true, false ]
modify = false

; Delete extranous file from destination directory
; Value [ true, false ]
delete = false
EOF

  exit 0
}

function __getPid() { ps aux | grep -v grep | grep -E "$1.*$2" | awk '{print $2}' || pgrep "$name"; }

function __syncExists() { grep -q "$1" "$status_file"; }

function __storeSync() { tee -a "$status_file" <<<"$name:x:$source_dir:$destination:${opt_daemon:-false}"; }

function __storePid() { sed -i "/$name/ s/x/$1/" "$status_file"; }

function __checkSync() {
  if ! -f "$status_file"; then tee "$status_file" <<<"$cmd -- v${version:-0.0.1}"; fi
  if __syncExists "$name"; then msg_error "Duplicate sync name. Please specify other name."; fi
  if __syncExists "$source_dir" && __syncExists "$destination"; then msg_error "Duplicate source and destination pair. Exiting"; fi
}

function __startSync() {
  # Initial rsync
  rsync -a -z ${rsyncOpts[@]} "$source_dir" "$destination" 
  while inotifywait -e $(tr ' ' ',' <<<"${inotifyOpts[@]}") "$source_dir"; do
    rsync -a -z ${rsyncOpts[@]:-} ${rsyncFlags[@]:-} "$source_dir" "$destination"
  done &
  __storePid "$!"
}

function __checkProcess() {
  local _pid=`__getPid`
  [[ "$_pid" ]] && kill -9 $_pid > /dev/null 2>&1
}

function __parse_options() {
  [[ $verbose -eq 1 ]] && rsyncOpts+=("-v")
  [[ $opt_append -eq 1 ]] && rsyncOpts+=("--append")
  [[ $opt_delete -eq 1 ]] && { 
    inotifyOpts+=("delete")
    rsyncOpts+=("--delete")
  }
  [[ $opt_modify -eq 1 ]] && inotifyOpts+=("modify")
  [[ "$opt_exclude" ]] && {
    inotifyFlags+=("--exclude $opt_exclude")
    rsyncFlags+=("--exclude $opt_exclude")
  }
}

__arg_source=0
__arg_dest=0
__arg_name=0
__arg_exlude=0

opt_append=0
opt_daemon=0
opt_delete=0
opt_modify=0
opt_exclude=""
dry_run=0
verbose=0
inotifyOpts=("create")
rsyncOpts=()

function __parse_terfile() {
  [[ "$2" = "--debug" ]] && debug=1
  source_dir="$(get_value source_dir 1)"
  destination="$(get_value destination 1)"
  name="$(get_value name 1)"
  daemon="$(get_value daemon)"
  [[ "$(get_value exclude)" -eq 1 ]] && opt_exclude="$(get_value exclude_pattern)"
  opt_append="$(get_value append)"
  opt_modify="$(get_value modify)"
  opt_delete="$(get_value delete)"

  __parse_options
}

function __parse_arguments() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -s|--source)
        [[ $__arg_source -eq 1 ]] && exit 2 
        source_dir="${2:-}"
        [[ -z "$souce_dir" ]] && msg_error "Please specify source dir."
        __arg_source=1
        shift 2
        ;;
      -s=*)
        [[ $__arg_source -eq 1 ]] && exit 2 
        [[ -z "${1#*=}" ]] && msg_error "Please specify source dir."
        source_dir="${1#*=}"
        __arg_source=1
        shift
        ;;
      -s*)
        [[ $__arg_source -eq 1 ]] && exit 2 
        [[ -z "${1#-s}" ]] && msg_error "Please specify source dir."
        source_dir="${1#-s}"
        __arg_source=1
        shift
        ;;
      -d|--destination) 
        [[ $__arg_dest -eq 1 ]] && exit 2 
        destination="${2:-}"
        [[ -z "$destination" ]] && msg_error "Please specify destination dir/host."
        __arg_dest=1
        shift 2
        ;;
      -d=*) 
        [[ $__arg_dest -eq 1 ]] && exit 2 
        [[ -z "${1#*=}" ]] && msg_error "Please specify destination dir/host."
        destination="${1#*=}"
        __arg_dest=1
        shift
        ;;
      -d*) 
        [[ $__arg_dest -eq 1 ]] && exit 2 
        [[ -z "${1#-d}" ]] && msg_error "Please specify destination dir/host."
        destination="${1#-d}"
        __arg_dest=1
        shift		
        ;;
      -n|--name) 
        [[ $__arg_name -eq 1 ]] && exit 2 
        name="${2:-}"
        [[ -z "$name" ]] && msg_error "Please specify sync name."
        __arg_name=1
        shift 2
        ;;
      -n=*) 
        [[ $__arg_name -eq 1 ]] && exit 2 
        [[ -z "${1#*=}" ]] && msg_error "Please specify sync name."
        name="${1#*=}"
        __arg_name=1
        shift
        ;;
      -n*) 
        [[ $__arg_name -eq 1 ]] && exit 2 
        [[ -z "${1#-n}" ]] && msg_error "Please specify sync name."
        name="${1#-n}"
        __arg_name=1
        shift
        ;;
      -e|--exclude)
        [[ $__arg_exclude -eq 1 ]] && exit 2
        opt_exclude="${2:-}"
        [[ -z "$opt_exclude" ]] && msg_error "Please specify exlude pattern."
        __arg_exlude=1
        shift 2
        ;;
      -e=*)
        [[ $__arg_exclude -eq 1 ]] && exit 2
        [[ -z "${1#*=}" ]] && msg_error "Please specify exlude pattern."
        opt_exclude="${1#*=}"
        __arg_exlude=1
        shift
        ;;
      -e*)
        [[ $__arg_exclude -eq 1 ]] && exit 2
        [[ -z "${1#-e}" ]] && msg_error "Please specify exlude pattern."
        opt_exclude="${1#-e}"
        __arg_exlude=1
        shift
        ;;
      --append)			opt_append=1;	shift ;;
      --daemon)     opt_daemon=1; shift ;;
      --delete)			opt_delete=1;	shift	;;
      --dry-run)		dry_run=1;		shift ;;
      --modify)			opt_modify=1; shift ;;
      -v|--verbose) verbose=1;		shift ;;
      -?|-h|--help) __usage_help				;;
      --debug)      debug=1;            ;;
      *) msg_error "Unknown option: $1" ;;
    esac
  done
  __parse_options
}

function __unsync() {
  name="${1:-}"
  [[ -z "$name" ]] && msg_error "Please specify sync name to be stopped."
}

function __debug_args() {
  echo "Name        = $name"
  echo "Source      = $source_dir"
  echo "Destination = $destination"
  echo "OPT Daemon  = $opt_daemon"
  echo "OPT Exlude  = $opt_exclude"
  echo "OPT Append  = $opt_append"
  echo "OPT Delete  = $opt_delete"
  echo "OPT Modify  = $opt_modify"
  echo " --- rsync -a -z ${rsyncOpts[@]:-} ${rsyncFlags[@]:-} $source_dir $destination" 
  echo " --- inotifywait -e $(tr ' ' ',' <<<"${inotifyOpts[@]:-}") ${inotifyFlags[@]:-} $source_dir" 

  exit
}

[[ $# -eq 0 ]] && __usage_help

case "$1" in
  sync)	shift; __parse_arguments $@ ;;
  unsync) shift; __unsync "${1?Specify sync name to be unsynced.}" ;;
  list) __list ;;
  mkconfig)	__mkconfig ;;
  terfile) __parse_terfile $@;;
  help|-h|--help|-?) __usage_help ;; 
esac

[[ $debug -eq 1 ]] && __debug_args

__checkSync
__storeSync
__startSync
