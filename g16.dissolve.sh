#! /bin/bash

###
#
# tools-for-g16.bash -- 
#   A collection of tools for the help with Gaussian 16.
# Copyright (C) 2019 Martin C Schwarzer
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
###

# 
# The help lines are distributed throughout the script and grepped for
#
#hlp   This script reads an input file, extracts the route section,
#hlp   and writes a new input file adding solvent corrections.
#hlp
#hlp   tools-for-g16.bash  Copyright (C) 2019  Martin C Schwarzer
#hlp   This program comes with ABSOLUTELY NO WARRANTY; this is free software, 
#hlp   and you are welcome to redistribute it under certain conditions; 
#hlp   please see the license file distributed alongside this repository,
#hlp   which is available when you type 'g16.tools-info.sh -L',
#hlp   or at <https://github.com/polyluxus/tools-for-g16.bash>.
#hlp
#hlp   Usage: $scriptname [options] [--] <INPUT_FILE>
#hlp

#
# Generic functions to find the scripts 
# (Copy of ./resources/locations.sh)
#
# Let's know where the script is and how it is actually called
#

get_absolute_location ()
{
    # Resolves the absolute location of parameter and returns it
    # Taken from https://stackoverflow.com/a/246128/3180795
    local resolve_file="$1" description="$2" 
    local link_target directory_name filename resolve_dir_name 
    debug "Getting directory for '$resolve_file'."
    #  resolve $resolve_file until it is no longer a symlink
    while [[ -h "$resolve_file" ]]; do 
      link_target="$(readlink "$resolve_file")"
      if [[ $link_target == /* ]]; then
        debug "File '$resolve_file' is an absolute symlink to '$link_target'"
        resolve_file="$link_target"
      else
        directory_name="$(dirname "$resolve_file")" 
        debug "File '$resolve_file' is a relative symlink to '$link_target' (relative to '$directory_name')"
        #  If $resolve_file was a relative symlink, we need to resolve 
        #+ it relative to the path where the symlink file was located
        resolve_file="$directory_name/$link_target"
      fi
    done
    debug "File is '$resolve_file'" 
    filename="$(basename "$resolve_file")"
    debug "File name is '$filename'"
    resolve_dir_name="$(dirname "$resolve_file")"
    directory_name="$(cd -P "$(dirname "$resolve_file")" && pwd)"
    if [[ "$directory_name" != "$resolve_dir_name" ]]; then
      debug "$description '$directory_name' resolves to '$directory_name'."
    fi
    debug "$description is '$directory_name'"
    if [[ -z $directory_name ]] ; then
      directory_name="."
    fi
    echo "$directory_name/$filename"
}

get_absolute_filename ()
{
    # Returns only the filename
    local resolve_file="$1" description="$2" return_filename
    return_filename=$(get_absolute_location "$resolve_file" "$description")
    return_filename=${return_filename##*/}
    echo "$return_filename"
}

get_absolute_dirname ()
{
    # Returns only the directory
    local resolve_file="$1" description="$2" return_dirname
    return_dirname=$(get_absolute_location "$resolve_file" "$description")
    return_dirname=${return_dirname%/*}
    echo "$return_dirname"
}


get_scriptpath_and_source_files ()
{
    local error_count tmplog line
    tmplog=$(mktemp tmp.XXXXXXXX) 
    # Who are we and where are we?
    scriptname="$(get_absolute_filename "${BASH_SOURCE[0]}" "installname")"
    debug "Script is called '$scriptname'"
    # remove scripting ending (if present)
    scriptbasename=${scriptname%.sh} 
    debug "Base name of the script is '$scriptbasename'"
    scriptpath="$(get_absolute_dirname  "${BASH_SOURCE[0]}" "installdirectory")"
    debug "Script is located in '$scriptpath'"
    resourcespath="$scriptpath/resources"
    
    if [[ -d "$resourcespath" ]] ; then
      debug "Found library in '$resourcespath'."
    else
      (( error_count++ ))
    fi
    
    # Import default variables
    #shellcheck source=./resources/default_variables.sh
    source "$resourcespath/default_variables.sh" &> "$tmplog" || (( error_count++ ))
    
    # Set more default variables
    exit_status=0
    stay_quiet=0
    
    # Import other functions
    #shellcheck source=./resources/messaging.sh
    source "$resourcespath/messaging.sh" &> "$tmplog" || (( error_count++ ))
    #shellcheck source=./resources/rcfiles.sh
    source "$resourcespath/rcfiles.sh" &> "$tmplog" || (( error_count++ ))
    #shellcheck source=./resources/test_files.sh
    source "$resourcespath/test_files.sh" &> "$tmplog" || (( error_count++ ))
    #shellcheck source=./resources/process_gaussian.sh
    source "$resourcespath/process_gaussian.sh" &> "$tmplog" || (( error_count++ ))
    #shellcheck source=./resources/validate_numbers.sh
    source "$resourcespath/validate_numbers.sh" &> "$tmplog" || (( error_count++ ))

    if (( error_count > 0 )) ; then
      echo "ERROR: Unable to locate library functions. Check installation." >&2
      echo "ERROR: Expect functions in '$resourcespath'."
      debug "Errors caused by:"
      while read -r line || [[ -n "$line" ]] ; do
        debug "$line"
      done < "$tmplog"
      debug "$(rm -v -- "$tmplog")"
      exit 1
    else
      debug "$(rm -v -- "$tmplog")"
    fi
}

#
# Specific functions for this script only
#

process_inputfile ()
{
    local testfile="$1"
    debug "Processing Input: $testfile"
    read_g16_input_file "$testfile"
    if [[ -z "$route_section" ]] ; then
      warning "It appears that '$testfile' does not contain a valid (or recognised) route section."
      warning "Make sure this template file contains '#/#P/#N/#T' followed by a space."
      return 1
    else
      debug "Route (unmodified): $route_section"
    fi
    local modified_route="$route_section"
    local -a additional_keywords
    
    extract_jobname_inoutnames "$testfile"
    local use_file_suffix

    # Firstly assume it is a single point calculation, therefore
    # remove the opt keyword (it can be added later)
    if [[ $use_opt_keyword =~ [Tt][Rr][Uu][Ee] ]] ; then
      if check_opt_keyword "$modified_route" ; then
        message "Detected 'OPT' keyword in input stream, it will be preserved including options."
      else
        debug "'OPT' keyword not present in input stream."
        additional_keywords+=("OPT")
        message "Added '${additional_keywords[-1]}' to the route section."
      fi
    else
      while ! modified_route=$(remove_opt_keyword      "$modified_route") ; do : ; done
    fi
    
    # If adding solvent corrections, the molecular structure is not optimised
    # a frequency calculation would be meaningless, therefore
    # remove the freq keyword
    while ! modified_route=$(remove_freq_keyword     "$modified_route") ; do : ; done

    # Remove any solvent information present, and add new ones
    while ! modified_route=$(remove_scrf_keyword     "$modified_route") ; do : ; done
    if (( ${#use_scrf_opts[@]} == 0 )) ; then
      additional_keywords+=("SCRF(PCM,solvent=water)")
    else
      local collated_scrf_opts
      collated_scrf_opts=$(printf ',%s' "${use_scrf_opts[@]}")
      # Remove first character (comma)
      collated_scrf_opts=${collated_scrf_opts:1}
      debug "Found options: $collated_scrf_opts"
      additional_keywords+=("SCRF($collated_scrf_opts)")
    fi
    message "Added '${additional_keywords[-1]}' to the route section."

    # The guess/geom keyword will be added, it will clash if already present
    while ! modified_route=$(remove_guess_keyword    "$modified_route") ; do : ; done
    additional_keywords+=("guess(read)")
    message "Added '${additional_keywords[-1]}' to the route section."
    if check_allcheck_option "$modified_route" ; then 
      debug "Keyword 'AllCheck' detected in input stream."
    else 
      while ! modified_route=$(remove_geom_keyword     "$modified_route") ; do : ; done
      additional_keywords+=("geom(check)")
      message "Added '${additional_keywords[-1]}' to the route section."
    fi
    
    if modified_route=$(remove_gen_keyword "$modified_route") ; then
      debug "No gen keyword present."
    else
      warning "Additional basis set specifications have not been read,"
      warning "but will be retrieved from the checkpointfile."
      while ! modified_route=$(remove_gen_keyword "$modified_route") ; do : ; done
      additional_keywords+=('ChkBasis')
      message "Added '${additional_keywords[-1]}' to the route section."
      if check_denfit_keyword "$modified_route" ; then
        warning "Please check density fitting settings are compatible with 'ChkBasis'."
      else
        debug "No 'DenFit' present."
      fi
    fi

    # Add the custom route options
    if (( ${#use_custom_route_keywords[@]} == 0 )) ; then
      debug "No custom route keywords specified."
    else
      additional_keywords+=("${use_custom_route_keywords[@]}")
      debug "Added the following custom keywords to route section:"
      debug "$(fold -w80 -s <<< "${use_custom_route_keywords[*]}")"
    fi

    debug "Added the following keywords to route section:"
    debug "$(fold -w80 -s <<< "${additional_keywords[*]}")"

    # Merge all keywords
    route_section="$modified_route ${additional_keywords[*]}"

    local verified_checkpoint
    if [[ -z $checkpoint ]] ; then
      checkpoint="${jobname}.chk"
      # Check if the guessed checkpointfile exists
      # (We'll trust the user if it was specified in the input file,
      #  after all the calculation might not be completed yet.)
      if verified_checkpoint=$(test_file_location "$checkpoint") ; then
        debug "verified_checkpoint=$verified_checkpoint"
        fatal "Cannot find '$verified_checkpoint'."
      else
        old_checkpoint="$checkpoint"
      fi
    else
      old_checkpoint="$checkpoint"
    fi

    # Assign new checkpoint/inputfile
    # Hook in for better suffixes, like smd/pcm/etc
    if [[ -z $use_file_suffix ]] ; then
      jobname="${jobname}.scrf"
    else
      jobname="${jobname}.$use_file_suffix"
    fi
    [[ -z $inputfile_new ]] && inputfile_new="${jobname}.$g16_input_suffix"
    checkpoint="${inputfile_new%.*}.chk"
   
    backup_if_exists "$inputfile_new"

    # Throw away the body of the input file
    unset inputfile_body

    write_g16_input_file > "$inputfile_new"
    message "Written modified inputfile '$inputfile_new'."
}

#
# Process Options
#

process_options ()
{
    #hlp   Options:
    #hlp    
    local OPTIND=1 

    while getopts :o:S:Or:t:f:m:p:d:sh options ; do
        case $options in
          #hlp   -o <ARG>   Adds options <ARG> to the SCRF keyword.
          #hlp              May be specified multiple times.
          #hlp              If nothing specified, this defaults to 'SCRF(PCM,solvent=water)'
          #hlp              Example Options: CPCM, SMD, Dipole
          #hlp              Solvents can be set with the -S switch.
          #hlp
          o) 
            use_scrf_opts+=("$OPTARG")

            ;;

          #hlp   -S <ARG>   Adds 'solvent=<ARG>' to the SCRF options.
          #hlp              Example solvents: water, heptane, aceticacid, krypton
          #hlp
          S) 
            if [[ ${use_scrf_opts[*]} =~ [Ss][Oo][Ll][Vv][Ee][Nn][Tt] ]] ; then
              fatal "Multiple solvents specified in 'SCRF($(printf '%s,' "${use_scrf_opts[@]}" "solvent=$OPTARG"))'."
            else
              use_scrf_opts+=("solvent=$OPTARG")
            fi
            ;;

          #hlp   -O         Run an optimisation
          #hlp              This will preserve a present OPT keyword, or add it.
          #hlp              If you want to use specific options, use the -r switch instead.
          #hlp              For example: -r 'OPT(MaxCycles=222)'
          #hlp
          O)
            use_opt_keyword="true"
            ;;

          #hlp   -r <ARG>   Adds custom command <ARG> to the route section.
          #hlp              May be specified multiple times.
          #hlp              The stack will be collated, but no sanity check will be performed.
          #hlp 
          r) 
            use_custom_route_keywords+=("$OPTARG") 
            ;;

          #hlp   -t <ARG>   Adds <ARG> to the end (tail) of the new input file.
          #hlp              If specified multiple times, each argument goes to a new line.
          #hlp 
          t) 
            use_custom_tail+=("$OPTARG")
            ;;

          #hlp   -f <ARG>   Write inputfile to <ARG>.
          #hlp
          f)
            inputfile_new="$OPTARG"
            debug "Setting inputfile_new='$inputfile_new'."
            ;;

          # Link 0 related options
          #hlp   -m <ARG>   Define the total memory to be used in megabyte.
          #hlp              The total request will be larger to account for 
          #hlp              overhead which Gaussian may need. (Default: 512)
          #hlp
            m) 
               validate_integer "$OPTARG" "the memory"
               if (( OPTARG == 0 )) ; then
                 fatal "Memory limit must not be zero."
               fi
               requested_memory="$OPTARG" 
               ;;

          #hlp   -p <ARG>   Define number of professors to be used. (Default: 4)
          #hlp
            p) 
               validate_integer "$OPTARG" "the number of threads"
               if (( OPTARG == 0 )) ; then
                 fatal "Number of threads must not be zero."
               fi
               requested_numCPU="$OPTARG" 
               ;;

          #hlp   -d <ARG>   Define disksize via the MaxDisk keyword (MB).
          #hlp              This option does not set a parameter for the queueing system,
          #hlp              but will only modify the input file with the size specification.
          #hlp              
            d) 
               validate_integer "$OPTARG" "the 'MaxDisk' keyword"
               if (( OPTARG == 0 )) ; then
                 fatal "The keyword 'MaxDisk' must not be zero."
               fi
               requested_maxdisk="$OPTARG"
               ;;

          #hlp   -s         Suppress logging messages of the script.
          #hlp              (May be specified multiple times.)
          #hlp
          s) 
            (( stay_quiet++ )) 
            ;;

          #hlp   -h         this help.
          #hlp
          h) 
            helpme 
            ;;

          #hlp     --       Close reading options.
          # This is the standard closing argument for getopts, it needs no implemenation.

          \?) 
            fatal "Invalid option: -$OPTARG." 
            ;;

          :) 
            fatal "Option -$OPTARG requires an argument." 
            ;;

        esac
    done

    # Shift all variables processed to far
    shift $((OPTIND-1))

    if [[ -z "$1" ]] ; then 
      fatal "There is no inputfile specified"
    fi

    # If a filename is specified, it must exist, otherwise exit
    # different mode let's you only use the jobname
    requested_inputfile=$(is_readable_file_or_exit "$1") || exit 1 
    shift
    debug "Specified input: $requested_inputfile"

    # Issue a warning that the addidtional flag has no effect.
    warn_additional_args "$@"
}

#
# MAIN SCRIPT
#

# If this script is sourced, return before executing anything
if ( return 0 2>/dev/null ) ; then
  # [How to detect if a script is being sourced](https://stackoverflow.com/a/28776166/3180795)
  debug "Script is sourced. Return now."
  return 0
fi

# Save how script was called
printf -v script_invocation_spell "'%s' " "${0/#$HOME/<HOME>}" "$@"

# Sent logging information to stdout
exec 3>&1

# Need to define debug function if unknown
if ! command -v debug ; then
  debug () {
    echo "DEBUG  : " "$*" >&4
  }
fi

# Secret debugging switch
if [[ "$1" == "debug" ]] ; then
  exec 4>&1
  stay_quiet=0 
  shift 
else
  exec 4> /dev/null
fi

get_scriptpath_and_source_files || exit 1

# Check whether we have the right numeric format (set it if not)
warn_and_set_locale

# Check for settings in three default locations (increasing priority):
#   install path of the script, user's home directory, current directory
g16_tools_rc_searchlocations=( "$scriptpath" "$HOME" "$HOME/.config" "$PWD" )
g16_tools_rc_loc="$( get_rc "${g16_tools_rc_searchlocations[@]}" )"
debug "g16_tools_rc_loc=$g16_tools_rc_loc"

# Load custom settings from the rc

if [[ -n $g16_tools_rc_loc ]] ; then
  #shellcheck source=./g16.tools.rc 
  . "$g16_tools_rc_loc"
  message "Configuration file '${g16_tools_rc_loc/*$HOME/<HOME>}' applied."
  if [[ "${configured_version}" =~ ^${version%.*} ]] ; then 
    debug "Config: $configured_version ($configured_versiondate); Current: $version ($versiondate)."
  else
    warning "Configured version was ${configured_version:-unset} (${configured_versiondate:-unset}),"
    warning "and probably needs an update to $version ($versiondate)."
  fi
else
  debug "No custom settings found."
fi

# Initialise some variables

declare -a use_custom_route_keywords
declare -a use_scrf_opts
use_opt_keyword="false"

# Evaluate Options

process_options "$@" || exit_status=$?
process_inputfile "$requested_inputfile" || exit_status=$?

#hlp   $scriptname is part of $softwarename $version ($versiondate) 
message "$scriptname is part of $softwarename $version ($versiondate)"
debug "$script_invocation_spell"
exit $exit_status
