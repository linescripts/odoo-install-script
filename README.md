# Odoo Automated Install Script for Ubuntu 24.04

This script automates the installation of Odoo 18.0 (Community or Enterprise) on **Ubuntu 24.04**, including:
- Python virtual environment setup (required by Ubuntu 24.04)
- PostgreSQL 16 installation
- Nginx reverse proxy configuration
- SSL setup with Certbot (Let's Encrypt)
- **Systemd service for Odoo (replacing legacy SysV init scripts for reliability and auto-restart)**

---

## ⚡️ About This Script

**This script is based on the install script from [Yenthe Van Ginneken](https://github.com/Yenthe666/InstallScript/tree/16.0) and improved to work on Ubuntu 24.04 with venv, as Ubuntu 24.04 enforces packages to be installed within a Python virtual environment.**

---

## Why Systemd Instead of SysV Init?

On Ubuntu 24.04, systemd is the native and recommended init system. The original Yenthe script used SysV init scripts, but this approach is now considered legacy and problematic:

1. **SysV is legacy; systemd is standard**
   - SysV init scripts are older, sequential, and fragile.
   - Modern Ubuntu uses systemd natively — it's faster, parallel, and smarter.
   - On Ubuntu 24.04, relying on SysV is like trying to run diesel in a Tesla. It "works," but not properly.

2. **SysV can't monitor or auto-restart Odoo**
   - If Odoo crashes, SysV won't bring it back.
   - Systemd with `Restart=always` will automatically restart Odoo if it crashes or gets killed (e.g., by out-of-memory).

3. **Systemd improves reliability**
   - We observed more frequent system crashes and unreliable Odoo restarts with SysV on Ubuntu 24.04.
   - Systemd provides better logging, monitoring, and service management.

**This script creates a robust systemd service for Odoo, ensuring it starts at boot, restarts on failure, and integrates with modern Ubuntu service management tools.**

---

## Features
- Installs Odoo 18.0 from source in a Python venv
- Installs PostgreSQL 16 (or default)
- Optionally installs Odoo Enterprise (requires valid credentials)
- Sets up Nginx as a reverse proxy (with websocket and static file support)
- Optionally configures SSL with Certbot/Let's Encrypt
- Creates a dedicated system user and systemd service
- Supports custom ports, domain, and admin email
- Works on fresh Ubuntu 24.04 servers

---

## Usage

1. **Download the script:**
   ```bash
   wget https://raw.githubusercontent.com/linescripts/odoo-install-script/18.0/install_odoo.sh
   ```
2. **Edit the script variables** (top of the file) as needed:
   - `OE_USER` (system user)
   - `OE_PORT`, `LONGPOLLING_PORT`
   - `OE_VERSION` (Odoo version)
   - `IS_ENTERPRISE` (True/False)
   - `INSTALL_NGINX`, `ENABLE_SSL` (True/False)
   - `ADMIN_EMAIL`, `WEBSITE_NAME`
   - `OE_SUPERADMIN` (Odoo master password)
3. **Make the script executable:**
   ```bash
   chmod +x install_odoo.sh
   ```
4. **Run the script as root or with sudo:**
   ```bash
   sudo ./install_odoo.sh
   ```

---

## What the Script Does
- Updates and upgrades system packages
- Installs all required dependencies (Python, pip, venv, build tools, Node.js, etc.)
- Installs PostgreSQL and creates a database user
- Creates a dedicated system user for Odoo
- Clones Odoo source code (and Enterprise if enabled)
- Sets up a Python virtual environment and installs Python dependencies
- Configures Odoo, Nginx, and SSL (if enabled)
- Opens firewall ports 80/443 (if UFW is present)
- Sets up and starts Odoo as a systemd service

---

## Service & File Locations
- **Odoo config:** `/etc/odoo-server.conf`
- **Odoo log:** `/var/log/odoo/odoo-server.log`
- **Odoo code:** `/odoo/odoo-server`
- **Python venv:** `/odoo/venv`
- **Nginx config:** `/etc/nginx/sites-available/<your-domain>`
- **Systemd service:** `/etc/systemd/system/odoo-server.service`

---

## Credits
- Original script by [Yenthe Van Ginneken](https://github.com/Yenthe666/InstallScript/tree/16.0)
- Improvements for Ubuntu 24.04 and venv by [Your Name]

---

## License
MIT