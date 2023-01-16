#!/usr/bin/env bash
set -e

OS=""
WSL=FALSE
ROCKET_SUCCESS=""

# Set colors
BOLD='\033[1m'
RED='\033[91m'
GREEN='\033[92m'
BLUE='\033[94m'
ENDC='\033[0m'



# ----------------------------  Output functions  ------------------------------


error_msg() {
  echo -e "${BOLD}${RED}!!! $*${ENDC}" >&2
}


cleanup() {
  set +e
  if [ -z "$ROCKET_SUCCESS" ]; then
    echo 
    if [ -n "$ROCKET_STEP" ]; then
      error_msg "$ROCKET_STEP FAILED"
    else
      error_msg "FAILED"
    fi
  fi
}


# Run the cleanup function above, if there is an error
# or the user aborts the execution
trap "cleanup" EXIT


abort() {
  ROCKET_STEP=""
  error_msg "$*"
  exit 1
}

log() {
  ROCKET_STEP="$*"
  echo -e "${BLUE}==>${ENDC} ${BOLD}$*${ENDC}"
}

logn()  { 
  ROCKET_STEP="$*"
  printf -- "${BLUE}==>${ENDC} ${BOLD}%s${ENDC} " "$*"
}

logk()  {
  ROCKET_STEP=""
  echo -e "${GREEN}OK${ENDC}"
  echo
}


# ----------------------------  Main functions  --------------------------------


# Function to display a nice header
show_header() {
  echo
  echo
  echo -e "${BOLD}ROCKET LAUNCH - Installation${ENDC}"
  echo "-------------------------------------"
  echo
}


# Function to check the operating system and the version
check_os() {
  if [ "$(uname)" == "Darwin" ]; then
    OS="macOS"
    logn "Checking macOS version:"
    version="$(sw_vers -productVersion)"
    if [ ! "$(echo $version '>' 10.9 | bc)" -eq 1 ]; then
      abort "Please run ROCKET on macOS version greater 10.9!"
    fi
  elif [ "$(uname)" == "Linux" ]; then
    distro="$(lsb_release -si)"
    version="$(lsb_release -sr)"
    if grep -q Microsoft /proc/version; then
      WSL=TRUE
    fi
    if [ "$distro" != "Ubuntu" ] && [ "$distro" != "Debian" ]; then
      abort "Currently we only support Ubuntu and Debian."
    fi
    OS="Linux"
  elif [ "$(uname -s)" == "Windows" ]; then
    OS="Windows"
  else
    abort "Currently we only support macOS, Ubuntu/Debian and Windows from the WSL2 (also here only Ubuntu/Debian)."
  fi
  logk
}


# Function to check the current logged in user
check_user() {
  logn "Checking current user:"
  [ "$USER" = "root" ] && abort "Run rocket as yourself, not root."
  if [[ "$OS" == "Linux" ]]; then
    groups $username | grep -q '\bsudo\b' || abort "Add $USER to the admin group."
  elif [[ "$OS" == "macOS" ]]; then
    groups | grep -q admin || abort "Add $USER to the admin group."
  fi
  logk
}


# Function to check if git is installed
check_git() {
  logn "Checking git:"
  if ! command -v git 1>/dev/null 2>&1; then
    abort "Git is not installed, can't continue."
  fi
  logk
}


# Function to clone or update the rocket-launch repository
clone_repository() {
  local install_location="$2"
  local cwd=$(pwd)
  if [ ! -d "$2" ] ;then
    logn "Cloning git repository $1 into $install_location:"
    git clone "$1" "$2"
  else
    logn "Updating git repository in $install_location:"
    cd "$install_location"
    git pull origin master &> /dev/null
    cd "$cwd"
  fi
  logk
}


# ----------------------------  MAIN  ------------------------------------------


# Show the "ROCKET" header
show_header

# Check the macOS version
check_os

# Check the current user
check_user

# Check if git is installed
check_git

# Clone/Update the "ROCKET" repository into our home directory
clone_repository "https://github.com/oheinemann/rocket-launch.git" "$HOME/.rocket-launch"


ROCKET_SUCCESS="1"
export ROCKET_HEADER="1"

# Add the bin path to the global path and bootstrap "rocket"
export PATH="$HOME/.rocket-launch/bin:$PATH"
rocket bootstrap
