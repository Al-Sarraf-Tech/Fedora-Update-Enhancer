#!/bin/bash

#==========================================================
#          Fedora 42 Elegant System Updater
#==========================================================
# Author: Jamal Al-Sarraf (Snake)
# Description: A beautifully crafted script to update and
#              upgrade Fedora 42 with enhanced visuals,
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
echo "           Elegant Fedora 42 System Updater               "
echo "=========================================================="
echo -e "${NC}"

# Function for logging
log() {
    echo -e "[$(date +"%Y-%m-%d %H:%M:%S")] $1" | tee -a "$LOGFILE"
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
        eval "$cmd" >> "$LOGFILE" 2>&1
    } &
    local pid=$!
    local delay=0.1
    local spinstr='|/-\'
    local temp
    echo -ne " "
    while ps -p "$pid" &>/dev/null; do
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

# Start Update Process
log "${CYAN}Starting system update and upgrade on Fedora 42.${NC}"

# Step 0: Ensure delta RPMs are enabled
progress_bar "sed -i 's/^#*deltarpm=.*/deltarpm=1/' /etc/dnf/dnf.conf" "Ensuring delta RPMs are enabled"

# Step 1: Refresh repository data
progress_bar "dnf5 makecache -y" "Refreshing repository data"

# Step 2: System update
progress_bar "dnf5 update -y" "Updating system packages"

# Step 3: System upgrade (ensure all upgrades applied)
progress_bar "dnf5 upgrade -y" "Upgrading system packages"

# Step 4: Clean up unnecessary packages
progress_bar "dnf5 autoremove -y && dnf5 clean all" "Cleaning up old packages"

# Step 5: Flatpak updates (optional, include if using Flatpak)
if command -v flatpak &>/dev/null; then
    progress_bar "flatpak update -y" "Updating Flatpak applications"
fi

log "${GREEN}$SUCCESS_MESSAGE${NC}"

# Check if reboot is required
if [ -f /var/run/reboot-required ] || [ "$(rpm -q --last kernel | head -n 1 | grep -c $(uname -r))" -eq 0 ]; then
    echo -e "${YELLOW}A system reboot is recommended to apply kernel updates.${NC}"
    read -p "Do you want to reboot now? (y/n): " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        log "System is rebooting as per user confirmation."
        reboot
    else
        log "Reboot skipped by user."
    fi
fi

# Footer
echo -e "${CYAN}"
echo "=========================================================="
echo "             Update and Upgrade Complete!                 "
echo "=========================================================="
echo -e "${NC}"
