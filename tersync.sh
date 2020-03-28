#!/usr/bin/env bash

readonly terfile_file="Terfile"

function __usage_help() {
	cat <<-EOF | less
	tersync.sh

	USAGE: 
	  tersync.sh sync -s /src/dir/logs/ -d /dst/dir/frontend/ --name "Frontend" --exclude "PATTERN"
	  tersync.sh mkconfig
	  tersync.sh terfile 
	  tersync.sh unsync Frontend-Sync
		
	COMMANDS
  sync  [OPTIONS]
      Start sync
  unsync  [NAME]
      Unsync a sync?
  mkconfig
      Create Terfile with unassigned parameters
  terfile
      Load parameters from Terfile in cwd
  help
      Display this message.

	OPTIONS
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
  echo "$value"
}

function msg_error() {
  echo "$@"
  exit 1
}

function __mkconfig() {
  [[ -f "Terfile" ]] && {
    read -p "Terfile already exists. Overwrite? [Y]: " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] && exit 0
	}

  cat<<-EOF > Terfile
		; Source directory to be synced
		source_dir = 

		; Destination directory or host
		; - /path/to/dst/  <-- notice the '/' in the end
		; - user@host:/path/to/dst/ <-- !! EXPERIMENTAL !!
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

function __terfile() {
  source_dir="$(get_value source_dir 1)"
  destination="$(get_value destination 1)"
  name="$(get_value name 1)"
  daemon="$(get_value daemon)"
  [[ "$(get_value exclude)" = "true" ]] && opt_exclude="$(get_value exclude_pattern)"
  opt_append="$(get_value append)"
  opt_modify="$(get_value modify)"
  opt_delete="$(get_value delete)"
}

function __unsync() {
  name="${1:-}"
  [[ -z "$name" ]] && msg_error "Please specify sync name to be stopped."
}

function __parse_arguments() {
  __arg_source=0
  __arg_dest=0
  __arg_name=0
  __arg_exlude=0

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
      --delete)			opt_delete=1;	shift	;;
      --dry-run)		dry_run=1;		shift ;;
      --modify)			opt_modify=1; shift ;;
      -v|--verbose) verbose=1;		shift ;;
      -?|-h|--help) __usage_help				;;
      *) msg_error "Unknown option: $1" ;;
    esac
  done
}

function __debug_args() {
  echo "Source      = $source_dir"
  echo "Destination = $destination"
  echo "Name        = $name"
  echo "Exlude      = $opt_exclude"
  echo "Append      = $opt_append"
  echo "Delete      = $opt_delete"
  echo "Modify      = $opt_modify"
}

case "$1" in
  sync)	shift; __parse_arguments $@ ;;
  unsync) shift; __unsync "$1" ;;
  mkconfig)	__mkconfig ;;
  terfile) __terfile ;;
  help|-h|--help|-?) __usage_help ;; 
esac

__debug_args
