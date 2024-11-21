# Fedora 41 Elegant System Updater

A beautifully crafted Bash script for updating and upgrading Fedora 41 with enhanced visuals, dynamic progress bars, and meticulous logging.

---

## 🚀 Features

- **Enhanced Visuals:** Includes colorful output and an ASCII art header.
- **Dynamic Progress Bars:** Provides a responsive and stylish way to track progress.
- **Meticulous Logging:** Logs every step of the process to `/var/log/system_update.log`.
- **Automatic Cleanup:** Removes unnecessary packages and cleans up cached data after updates.

---

## 📜 Prerequisites

- Fedora 41 or compatible system.
- Root privileges to execute the script.
- `dnf` package manager installed and configured.

---

## 🔧 Installation

1. Clone this repository or download the script directly:
   ```bash
   git clone git@github.com:jalsarraf0/Fedora-41-Elegant-System-Updater.git
   ```
   Alternatively, you can download the script:
   ```bash
   wget https://github.com/jalsarraf0/Fedora-41-Elegant-System-Updater/raw/main/elegant-updater.sh
   ```

2. Ensure the script is executable:
   ```bash
   chmod +x elegant-updater.sh
   ```

---

## 🛠 Usage

1. Run the script with root privileges:
   ```bash
   sudo ./elegant-updater.sh
   ```

2. Watch the progress bars as your system is updated and upgraded!

---

## ✨ Script Highlights

- **ASCII Art Header**  
  The script greets you with a custom ASCII art header for a polished touch.

- **Dynamic Progress Bars**  
  Each major operation (e.g., refreshing repositories, updating packages) displays a responsive spinner animation.

- **Error Handling**  
  If any step fails, the script halts, logs the error, and exits gracefully.

- **Log Management**  
  Detailed logs are maintained in `/var/log/system_update.log` for troubleshooting and audit purposes.

---

## 📂 File Details

- **`elegant-updater.sh`**: The main script.
- **`/var/log/system_update.log`**: Log file created by the script for tracking update and upgrade details.

---

## 🚨 Disclaimer

This script is intended for Fedora 41. Running it on other versions may cause issues. Always back up your system before performing updates.

---

## 📜 License

This script is open-source and available under the [MIT License](LICENSE).
