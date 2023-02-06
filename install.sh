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



# Function to check if the Xcode license is agreed to and agree if not.
xcode_license() {
  if /usr/bin/xcrun clang 2>&1 | grep $Q license; then
    if [ -n "$ROCKET_INTERACTIVE" ]; then
      logn "Asking for Xcode license confirmation"
      sudo xcodebuild -license
      logk
    else
      abort "Run 'sudo xcodebuild -license' to agree to the Xcode license."
    fi
  fi
}


# Function to install the Xcode Command Line Tools.
install_xcode_commandline_tools() {
  ROCKET_DIR=$("xcode-select" -print-path 2>/dev/null || true)
  if [ -z "$ROCKET_DIR" ] || ! [ -f "$ROCKET_DIR/usr/bin/git" ] \
                          || ! [ -f "/usr/include/iconv.h" ]
  then
    log "Installing the Xcode Command Line Tools"
    if ! [ $(xcode-select -p 1>/dev/null;echo $?) ]; then
      if [ -n "$ROCKET_INTERACTIVE" ]; then
        logn "Requesting user install of Xcode Command Line Tools"
        xcode-select --install
      else
        abort "Run 'xcode-select --install' to install the Xcode Command Line Tools."
      fi
    else
      log "Already installed."
    fi
    logk
  fi

  xcode_license
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


install_path() {
  logn "Install path to the shell"
  # path to the rocket binary
  ROCKET_BIN="$HOME/.rocket-launch/bin"

  # check which shell you are using
  if [ "$SHELL" = "/bin/bash" ]; then
      SHELL_CONFIG="$HOME/.bashrc"
  elif [ "$SHELL" = "/bin/sh" ]; then
      SHELL_CONFIG="$HOME/.profile"
  elif [ "$SHELL" = "/bin/zsh" ] || [ "$SHELL" = "/usr/bin/zsh" ]; then
      SHELL_CONFIG="$HOME/.zshrc"
  fi

  # check if the path is already in your config
  if grep -q "^export PATH=.*$ROCKET_BIN" $SHELL_CONFIG; then
      echo "Directory $ROCKET_BIN is already saved in $SHELL_CONFIG."
  else
      # adding the path to your config
      echo "export PATH=\"$ROCKET_BIN:\$PATH\"" >> $SHELL_CONFIG
  fi

  # check if the path is added to your environment variable
  if [[ ":$PATH:" != *":$ROCKET_BIN:"* ]]; then
      # adding path to the environment
      export PATH="$ROCKET_BIN:$PATH"
  fi
  logk
}


# ----------------------------  MAIN  ------------------------------------------


# Show the "ROCKET" header
show_header

# Check the OS and version
check_os

# Check the current user
check_user

# Check if git is installed
check_git

# we need command line tools for the git clone
if [[ "$OS" == "macOS" ]]; then
  # Install the Xcode Command Line Tools.
  install_xcode_commandline_tools
fi

# Clone/Update the "ROCKET" repository into our home directory
clone_repository "https://github.com/oheinemann/rocket-launch.git" "$HOME/.rocket-launch"


ROCKET_SUCCESS="1"
export ROCKET_HEADER="1"

# Add the bin path to the global path and bootstrap "rocket"
install_path

rocket bootstrap
