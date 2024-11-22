#!/bin/bash

#==========================================================
#          Fedora 41 Elegant System Updater
#==========================================================
# Author: Jamal Al-Sarraf (Snake)
# Description: A beautifully crafted script to update and
#              upgrade Fedora 41 with enhanced visuals,
#              dynamic progress bars, and meticulous logging.
#==========================================================

# Constants
LOGFILE="/var/log/system_update.log"
DATE=$(date +"%Y-%m-%d")
SUCCESS_MESSAGE="System update completed successfully."
ERROR_MESSAGE="System update encountered an error."

# Color Codes
GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m' # No Color

# ASCII Art Header
echo -e "${CYAN}"
echo "=========================================================="
echo "               [ S N A K E ]                              "
echo "           Elegant Fedora 41 System Updater               "
echo "=========================================================="
echo -e "${NC}"

# Function to display the man page
show_help() {
    echo "NAME
       elegant-updater.sh - Fedora 41 Elegant System Updater

SYNOPSIS
       ./elegant-updater.sh [OPTIONS]

DESCRIPTION
       A beautifully crafted script to update and upgrade Fedora 41 with enhanced visuals, dynamic progress bars,
       and meticulous logging. This script performs the following tasks:
       - Refreshes repository data
       - Updates system packages
       - Upgrades system packages
       - Cleans up unnecessary packages

OPTIONS
       -h, --help
              Display this help message and exit.

USAGE
       Ensure the script has execute permissions:
           chmod +x elegant-updater.sh

       Run the script with:
           ./elegant-updater.sh

AUTHOR
       Written by Jamal Al-Sarraf (Snake). Contributions are welcome.

LICENSE
       Released under the MIT License."
}

# Check for help option
if [[ $1 == "-h" || $1 == "--help" ]]; then
    show_help
    exit 0
fi

# Function for logging
log() {
    echo -e "[$(date +"%Y-%m-%d")] $1" | tee -a $LOGFILE
}

# Root permission check
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: This script must be run as root.${NC}"
    exit 1
fi

# Dynamic Progress Bar Function
progress_bar() {
    local cmd="$1"
    local msg="$2"
    echo -ne "${YELLOW}$msg...${NC}\n"
    {
        eval "$cmd" >> $LOGFILE 2>&1
    } &
    local pid=$!
    local delay=0.1
    local spinstr='|/-\'
    local temp
    echo -ne " "
    while ps a | awk '{print $1}' | grep -q "$pid"; do
        temp="${spinstr#?}"
        printf " [%c]  " "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    wait $pid
    if [ $? -eq 0 ]; then
        echo -ne " [${GREEN}Done${NC}]\n"
    else
        echo -ne " [${RED}Failed${NC}]\n"
        log "${RED}$ERROR_MESSAGE${NC}"
        exit 1
    fi
}

# Update and Upgrade Process
log "${CYAN}Starting system update and upgrade on Fedora 41.${NC}"

# Step 1: Refresh repository data
progress_bar "dnf makecache -y" "Refreshing repository data"

# Step 2: System update
progress_bar "dnf -y update" "Updating system packages"

# Step 3: System upgrade
progress_bar "dnf -y upgrade" "Upgrading system packages"

# Step 4: Clean up unnecessary packages
progress_bar "dnf -y autoremove && dnf clean all" "Cleaning up old packages"

log "${GREEN}$SUCCESS_MESSAGE${NC}"

# Footer
echo -e "${CYAN}"
echo "=========================================================="
echo "             Update and Upgrade Complete!                 "
echo "=========================================================="
echo -e "${NC}"
