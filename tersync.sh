#!/usr/bin/env bash

readonly cmd="${0##*/}"
readonly terfile_file="Terfile.ini"
readonly status_file="status"
#readonly status_file="/var/lib/tersync/status"

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
__checkProcessyncOpts=()

function __usage_help {
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
  add [-s <source>] [-d <dst>] [-n <name>] ...
      Add a sync to sync entry
  sync [name]
      Start a specified sync
  unsync [name]
      Remove a sync from sync list
  stop [name]
      Stop a running sync
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

function __usage_add {
  cat <<EOF
  add
EOF
  exit 0
}

function msg_error { echo "[x] $@" >&2; exit 1; }

function msg_info { echo "[i] $@" >&2; }

function msg_success { echo "[v] $@" >&2; }

function get_value {
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

function get_valueJson {
  local key=${1?No argument.}
  local search=$name
  jq -M "map(select(.name == \"$search\")) | .[].$key" $status_file | sed 's/"//g'
}

function __mkconfig {
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

function __getPidFromName { pgrep "$name"; }

function __syncExists { grep -q "$1" "$status_file"; }

function __syncRunning { if [[ "$(__getPidFromName)" ]]; then return 1; else return 0; fi; }

function __storeSync { 
  # tee -a "$status_file" <<<"$name:x:$source_dir:$destination:${opt_daemon:-false}" > /dev/null; 
  json_string=$( jq -n \
		--arg sd "$source_dir" \
		--arg dst "$destination" \
		--arg nm "$name" \
		--arg oe "$opt_exclude" \
		--arg oa "$opt_append" \
		--arg om "$opt_modify" \
		--arg od "$opt_delete" \
		--arg da "$opt_daemon" \
		--arg pd "" \ '[{name: $nm, pid: $pd, source_dir: $sd, destination: $dst, daemon: $da, exclude: $oe, append: $oa, modify: $om, delete: $od}]'
	)

  jq ". += $json_string" $status_file | sponge $status_file
}

function __storePid { jq "map(if .name == \"$name\" then . + {"pid":\"$1\"} else . end)" $status_file | sponge $status_file; }

function __removePid { __storePid ""; }

function __checkSyncForDuplicates {
  if [[ ! -f "$status_file" ]]; then tee "$status_file" <<<"[]" > /dev/null; fi
  if __syncExists "$name"; then msg_error "Sync name: $name already exists. Please specify other name."; fi
  if __syncExists "$source_dir" && __syncExists "$destination"; then msg_error "Duplicate source and destination pair. Exiting"; fi
}

function __syncAdd {
  # Check for dupes
  __checkSyncForDuplicates
  # Then store the detail to status_file
  [[ $opt_daemon -eq 1 ]] && __createService
  __storeSync

  msg_success "$name has been added to sync list."
}

function __startSync {
  __storePid "$!"
  # Initial rsync
  rsync -a -z ${rsyncOpts[@]} "$source_dir" "$destination" 
  while inotifywait -e $(tr ' ' ',' <<<"${inotifyOpts[@]}") "$source_dir"; do
    rsync -a -z ${rsyncOpts[@]:-} ${rsyncFlags[@]:-} "$source_dir" "$destination"
  done &
}

function __stopSync {
  echo
}

function __createService {
  local service_file="/etc/systemd/system/${name}.service"
  [[ -f $service_file ]] && msg_error "Service $name already exist."
  
  cat<<EOF > $service_file
[Unit]
Description= $name sync daemon

[Service]
Type=oneshot
ExecStart=$(realpath $0) sync $name
RemainAfterExit=true
ExecStop=$(realpath $0) stop $name

[Install]
WantedBy=default.target
EOF
  msg_success "Service $name has been successfully created. You can now start it using systemctl"
}

function __verifyOptions {
  if [[ -d $source_dir ]]; then 
    : # do nothing
  elif [[ -f $source_dir ]]; then 
    : # do nothing
  else
    msg_error "Source path given [$source_dir] is not valid."
  fi

  [[ ! -d "$destination" ]] && msg_error "Destination path given [$destination] is not valid."

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

  [[ $debug -eq 1 ]] && __debug_args
}

function __parse_terfile {
  [[ "$2" = "--debug" ]] && debug=1
  source_dir="$(get_value source_dir 1)"
  destination="$(get_value destination 1)"
  name="$(get_value name 1)"
  daemon="$(get_value daemon)"
  [[ "$(get_value exclude)" -eq 1 ]] && opt_exclude="$(get_value exclude_pattern)"
  opt_append="$(get_value append)"
  opt_modify="$(get_value modify)"
  opt_delete="$(get_value delete)"

  __syncAdd
}

function __parse_arguments {
  [[ $# -eq 0 ]] && __usage_add
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

  __syncAdd
}

function __sync {
  name="$1"
  if [[ -z $name ]]; then msg_error "Please specify sync name."; fi
  if [[ $2 = "-d" ]]; then debug=1; fi

  __syncExists "$name" || msg_error "$name doesn't exist in sync list. Please add it first."

  source_dir="$(get_valueJson source_dir)"
  destination="$(get_valueJson destination)"
  name="$(get_valueJson name)"
  opt_exclude="$(get_valueJson exclude)"
  opt_append="$(get_valueJson append)"
  opt_modify="$(get_valueJson modify)"
  opt_delete="$(get_valueJson delete)"
  
  __verifyOptions

  # Check if it's not running yet
  __syncRunning || msg_error "$name is already running."

  # Execute
  __startSync
}

function __unsync {
  name="${1:-}"
  [[ -z "$name" ]] && msg_error "Please specify sync name to be stopped."
}

function __debug_args {
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

function main {
  [[ $# -eq 0 ]] && __usage_help
  
  case "$1" in
    add) shift; __parse_arguments $@ ;;
    sync)	shift; __sync $@ ;;
    unsync) shift; __unsync $@ ;;
    stop) shift; __stopSync $@;;
    status) shift; __syncStatus $@;;
    list) shift; __list $@ ;;
    mkconfig)	__mkconfig ;; 
    terfile) __parse_terfile $@;;
    help|-h|--help|-?) __usage_help ;; 
  esac
  
}

main $@
