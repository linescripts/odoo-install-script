#!/bin/bash
################################################################################
# Script for installing Odoo 18.0 on Ubuntu 24.04 (all-in-one).
# Author: Combined/Adapted from Yenthe Van Ginneken + linescripts + community
################################################################################
# This script:
#   1) Installs Odoo 18.0 from source in a Python virtual environment
#   2) Installs PostgreSQL (16 by default) and creates a PostgreSQL user
#   3) Creates a systemd service unit to manage Odoo as a service
#   4) Sets up Nginx as reverse proxy (including /websocket block)
#   5) Installs Certbot for HTTPS if desired
#
# USAGE:
#   1) Make executable:  sudo chmod +x install-odoo-18.sh
#   2) Run:              ./install-odoo-18.sh
################################################################################

#------------------------------------------------------------------------------
# 1. Variables (edit as needed)
#------------------------------------------------------------------------------
OE_USER="odoo"
OE_HOME="/${OE_USER}"
OE_HOME_EXT="${OE_HOME}/${OE_USER}-server"

# Odoo ports
OE_PORT="8069"
LONGPOLLING_PORT="8072"

# Odoo version/branch
OE_VERSION="18.0"   # or "master" if 18.0 not officially released

# Enterprise?
IS_ENTERPRISE="True"

# If True, install Nginx as reverse proxy
INSTALL_NGINX="True"

# SSL with Certbot?
ENABLE_SSL="True"
ADMIN_EMAIL="rajnish@linescripts.com"
WEBSITE_NAME="auto.linescripts.net"

# Superadmin password
OE_SUPERADMIN="admin"
GENERATE_RANDOM_PASSWORD="True"
OE_CONFIG="${OE_USER}-server"

# Python virtual environment path
OE_VENV="${OE_HOME}/venv"

# If True, install PostgreSQL 16 from official Postgres repo
INSTALL_POSTGRESQL_SIXTEEN="True"

#------------------------------------------------------------------------------
# 2. Update and upgrade
#------------------------------------------------------------------------------
echo -e "\n--- Updating and upgrading system packages ---"
sudo apt-get update -y
sudo apt-get upgrade -y

#------------------------------------------------------------------------------
# 3. Install basic dependencies
#------------------------------------------------------------------------------
echo -e "\n--- Installing base dependencies ---"
sudo apt-get install -y git python3 python3-pip python3-dev python3-venv python3-wheel \
    build-essential wget libxslt-dev libzip-dev libldap2-dev libsasl2-dev \
    nodejs npm libpq-dev libjpeg-dev libpng-dev gdebi curl ca-certificates

#------------------------------------------------------------------------------
# 4. Install Nginx (if needed)
#------------------------------------------------------------------------------
if [ "${INSTALL_NGINX}" = "True" ]; then
  echo -e "\n--- Installing Nginx ---"
  sudo apt-get install -y nginx
fi

# Install global Node.js modules (rtlcss, less, etc.)
echo -e "\n--- Installing global Node.js packages ---"
sudo npm install -g rtlcss less less-plugin-clean-css

#------------------------------------------------------------------------------
# 5. Install PostgreSQL
#------------------------------------------------------------------------------
echo -e "\n--- Installing PostgreSQL ---"
if [ "${INSTALL_POSTGRESQL_SIXTEEN}" = "True" ]; then
  echo "[INFO] Installing PostgreSQL 16 from official repository..."
  # Import Postgres key
  curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
    | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
  # Add repository
  echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
    | sudo tee /etc/apt/sources.list.d/pgdg.list
  sudo apt-get update -y
  sudo apt-get install -y postgresql-16
else
  echo "[INFO] Installing default PostgreSQL from Ubuntu repo..."
  sudo apt-get install -y postgresql postgresql-server-dev-all
fi

# Create PostgreSQL user
echo -e "\n--- Creating PostgreSQL user '${OE_USER}' ---"
sudo -u postgres createuser -s ${OE_USER} 2>/dev/null || true

#------------------------------------------------------------------------------
# 5a. Install wkhtmltopdf with QT patches (REQUIRED for PDF reports)
#------------------------------------------------------------------------------
echo -e "\n--- Installing wkhtmltopdf with QT patches for PDF generation ---"

# Install dependencies first
sudo apt-get install -y fontconfig libfontconfig1 libjpeg-turbo8 libx11-6 libxcb1 \
    libxext6 libxrender1 xfonts-75dpi xfonts-base

# Download and install wkhtmltopdf
# Note: Using Jammy package for Noble (24.04) as specific Noble package might not be available yet
WKHTMLTOPDF_URL="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_amd64.deb"
echo "[INFO] Downloading wkhtmltopdf from: ${WKHTMLTOPDF_URL}"
wget -q -O /tmp/wkhtmltox.deb ${WKHTMLTOPDF_URL}

echo "[INFO] Installing wkhtmltopdf package..."
sudo dpkg -i /tmp/wkhtmltox.deb
# Fix any missing dependencies
sudo apt-get -f install -y
rm /tmp/wkhtmltox.deb

# Create symbolic links for Odoo to find it
echo "[INFO] Creating symbolic links..."
sudo ln -sf /usr/local/bin/wkhtmltopdf /usr/bin/wkhtmltopdf
sudo ln -sf /usr/local/bin/wkhtmltoimage /usr/bin/wkhtmltoimage

# Verify installation
echo -e "\n--- Verifying wkhtmltopdf installation ---"
if command -v wkhtmltopdf &> /dev/null; then
    wkhtmltopdf --version
    echo "[SUCCESS] wkhtmltopdf installed successfully!"
else
    echo "[WARNING] wkhtmltopdf installation may have failed!"
fi

#------------------------------------------------------------------------------
# 6. Create system user "odoo"
#------------------------------------------------------------------------------
echo -e "\n--- Creating system user '${OE_USER}' ---"
if id "${OE_USER}" &>/dev/null; then
  echo "[INFO] User '${OE_USER}' already exists."
else
  sudo adduser --system --quiet --shell=/bin/bash --home=${OE_HOME} --gecos 'ODOO' --group ${OE_USER}
  # Optionally add user to sudo group
  sudo adduser ${OE_USER} sudo
fi

# Create log directory
sudo mkdir -p /var/log/${OE_USER}
sudo chown ${OE_USER}:${OE_USER} /var/log/${OE_USER}

#------------------------------------------------------------------------------
# 7. Download Odoo source
#------------------------------------------------------------------------------
echo -e "\n--- Cloning Odoo branch ${OE_VERSION} into ${OE_HOME_EXT} ---"
sudo git clone --depth 1 --branch ${OE_VERSION} https://github.com/odoo/odoo.git ${OE_HOME_EXT} || true
sudo chown -R ${OE_USER}:${OE_USER} ${OE_HOME_EXT}

#------------------------------------------------------------------------------
# 7a. Create Python virtual environment
#------------------------------------------------------------------------------
echo -e "\n--- Creating Python virtual environment: ${OE_VENV} ---"
sudo -u ${OE_USER} python3 -m venv ${OE_VENV}

echo -e "\n--- Installing Odoo Python dependencies in the venv ---"
sudo -H -u ${OE_USER} bash -c "
    source ${OE_VENV}/bin/activate &&
    pip install --upgrade pip wheel setuptools &&
    pip install -r ${OE_HOME_EXT}/requirements.txt
"
#------------------------------------------------------------------------------
# (Optional) 7b. Install Odoo Enterprise
#------------------------------------------------------------------------------
if [ "${IS_ENTERPRISE}" = "True" ]; then
    echo -e "\n--- Installing Odoo Enterprise dependencies and code ---"
    
    # Make sure the node -> nodejs symlink exists (some distros only ship `nodejs`)
    sudo ln -sf /usr/bin/nodejs /usr/bin/node
    
    # Create an Enterprise folder structure inside /odoo/enterprise
    sudo su ${OE_USER} -c "mkdir -p ${OE_HOME}/enterprise/addons"
    
    echo -e "\n--- Cloning the Odoo Enterprise repository ---"
    # IMPORTANT: You must have valid credentials/access to https://github.com/odoo/enterprise
    # If you do not have official Odoo Enterprise access, this clone step will fail with "Authentication" errors.
    GITHUB_RESPONSE=$(
      sudo su ${OE_USER} -c \
        "git -c credential.helper= clone --depth 1 --branch ${OE_VERSION} \
        https://github.com/odoo/enterprise ${OE_HOME}/enterprise/addons" 2>&1
    )

    # Improved error handling and retry logic
    while echo "$GITHUB_RESPONSE" | grep -q "Authentication"; do
        echo "------------------------WARNING------------------------------"
        echo "Your authentication with Github has failed! Please try again."
        printf "In order to clone and install the Odoo enterprise version you \nneed to be an official Odoo partner and you need access to\nhttp://github.com/odoo/enterprise.\n"
        echo "TIP: Press ctrl+c to stop this script."
        echo "-------------------------------------------------------------"
        echo " "
        
        # Ask for credentials
        read -p "Github Username: " GITHUB_USER
        read -s -p "Github Password: " GITHUB_PASS
        echo ""
        
        GITHUB_RESPONSE=$(
          sudo su ${OE_USER} -c \
            "git clone --depth 1 --branch ${OE_VERSION} \
            https://$GITHUB_USER:$GITHUB_PASS@github.com/odoo/enterprise \
            ${OE_HOME}/enterprise/addons" 2>&1
        )
    done
    
    echo -e "\n--- Installing extra Python dependencies for Enterprise in the same virtualenv ---"
    sudo -H -u ${OE_USER} bash -c "
        source ${OE_VENV}/bin/activate &&
        # These are commonly required by Enterprise modules
        pip install psycopg2-binary pdfminer.six num2words ofxparse dbfread ebaysdk firebase_admin pyOpenSSL
    "

    echo -e "\n--- Installing LESS compiler for Enterprise assets ---"
    sudo npm install -g less less-plugin-clean-css
fi

#------------------------------------------------------------------------------
# 9. Create Odoo configuration file
#------------------------------------------------------------------------------
echo -e "\n--- Creating /etc/${OE_CONFIG}.conf ---"
sudo touch /etc/${OE_CONFIG}.conf
sudo chmod 640 /etc/${OE_CONFIG}.conf

if [ "${GENERATE_RANDOM_PASSWORD}" = "True" ]; then
  OE_SUPERADMIN=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
fi

sudo bash -c "cat <<EOF > /etc/${OE_CONFIG}.conf
[options]
admin_passwd = ${OE_SUPERADMIN}
http_port = ${OE_PORT}
longpolling_port = ${LONGPOLLING_PORT}
logfile = /var/log/${OE_USER}/${OE_CONFIG}.log
log_level = info
proxy_mode = True
EOF
"

# If enterprise
if [ "${IS_ENTERPRISE}" = "True" ]; then
  echo "addons_path = ${OE_HOME}/enterprise/addons,${OE_HOME_EXT}/addons" | sudo tee -a /etc/${OE_CONFIG}.conf
else
  # Also make a custom addons folder
  sudo -u ${OE_USER} mkdir -p ${OE_HOME}/custom/addons
  echo "addons_path = ${OE_HOME_EXT}/addons,${OE_HOME}/custom/addons" | sudo tee -a /etc/${OE_CONFIG}.conf
fi

sudo chown ${OE_USER}:${OE_USER} /etc/${OE_CONFIG}.conf

#------------------------------------------------------------------------------
# 10. Create systemd service unit
#------------------------------------------------------------------------------
echo -e "\n--- Creating systemd service unit /etc/systemd/system/${OE_CONFIG}.service ---"
cat <<EOF > /tmp/${OE_CONFIG}.service
[Unit]
Description=Odoo 18.0
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=${OE_USER}
Group=${OE_USER}
ExecStart=${OE_VENV}/bin/python ${OE_HOME_EXT}/odoo-bin -c /etc/${OE_CONFIG}.conf
StandardOutput=journal+console
Restart=always
RestartSec=5
SyslogIdentifier=${OE_CONFIG}

# Security
PrivateTmp=true
ProtectHome=true
NoNewPrivileges=true
ProtectSystem=full

[Install]
WantedBy=multi-user.target
EOF

sudo mv /tmp/${OE_CONFIG}.service /etc/systemd/system/${OE_CONFIG}.service
sudo chmod 644 /etc/systemd/system/${OE_CONFIG}.service
sudo chown root: /etc/systemd/system/${OE_CONFIG}.service

echo -e "\n--- Enabling Odoo service at boot with systemd ---"
sudo systemctl daemon-reload
sudo systemctl enable ${OE_CONFIG}.service

#------------------------------------------------------------------------------
# 11. Configure Nginx with double-escaped $ variables
#------------------------------------------------------------------------------
if [ "${INSTALL_NGINX}" = "True" ]; then
  echo -e "\n--- Configuring Nginx reverse proxy for Odoo ---"
  NGINX_CONF_DIR="/etc/nginx/sites-available"
  NGINX_ENABLED_DIR="/etc/nginx/sites-enabled"
  NGINX_CONFIG_FILE="${NGINX_CONF_DIR}/${WEBSITE_NAME}"

  sudo bash -c "cat <<'EOF' > ${NGINX_CONFIG_FILE}
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}

upstream ${OE_USER} {
    server 127.0.0.1:${OE_PORT};
}

upstream ${OE_USER}_chat {
    server 127.0.0.1:${LONGPOLLING_PORT};
}

server {
    listen 80;
    server_name ${WEBSITE_NAME};

    # Proxy headers
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Client-IP \$remote_addr;

    # Security headers
    add_header X-Frame-Options \"SAMEORIGIN\";
    add_header X-XSS-Protection \"1; mode=block\";
    add_header X-Content-Type-Options nosniff;
    add_header Strict-Transport-Security \"max-age=31536000; includeSubDomains\" always;

    # Logs
    access_log  /var/log/nginx/${OE_USER}-access.log;
    error_log   /var/log/nginx/${OE_USER}-error.log;

    # Increase proxy buffer size
    proxy_buffers       16  64k;
    proxy_buffer_size   128k;

    # Timeouts
    proxy_read_timeout 900s;
    proxy_connect_timeout 900s;
    proxy_send_timeout 900s;

    # Retry if error
    proxy_next_upstream error timeout invalid_header http_500 http_502 http_503;

    # Gzip
    gzip on;
    gzip_min_length 1100;
    gzip_buffers 4 32k;
    gzip_types text/css text/less text/plain text/xml application/xml application/json application/javascript application/pdf image/jpeg image/png;
    gzip_vary on;

    # Buffer sizes
    client_header_buffer_size 4k;
    large_client_header_buffers 4 64k;
    client_max_body_size 0;

    # Odoo main app
    location / {
        proxy_pass http://${OE_USER};
        proxy_redirect off;
    }

    # Odoo longpolling
    location /longpolling {
        proxy_pass http://${OE_USER}_chat;
    }

    # WebSocket endpoint
    location /websocket {
        proxy_pass http://${OE_USER}_chat;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header X-Forwarded-Host \$http_host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    # Static files (cache 2 days)
    location ~* \\.?(js|css|png|jpg|jpeg|gif|ico)\$ {
        expires 2d;
        proxy_pass http://${OE_USER};
        add_header Cache-Control \"public, no-transform\";
    }

    # Cache static data
    location ~ /[a-zA-Z0-9_-]*/static/ {
        proxy_cache_valid 200 302 60m;
        proxy_cache_valid 404 1m;
        proxy_buffering on;
        expires 864000;
        proxy_pass http://${OE_USER};
    }
}
EOF"

  # Enable new site
  sudo ln -sf ${NGINX_CONFIG_FILE} ${NGINX_ENABLED_DIR}/${WEBSITE_NAME}
  sudo rm -f ${NGINX_ENABLED_DIR}/default

  # Test and reload
  sudo nginx -t
  sudo systemctl reload nginx
fi

#------------------------------------------------------------------------------
# 11b. Open firewall ports 80 and 443 (if UFW is installed)
#------------------------------------------------------------------------------
echo -e "\n--- Checking if UFW firewall is installed/enabled; allowing HTTP (80) and HTTPS (443) ---"
if command -v ufw &>/dev/null; then
  # If you want to ensure UFW is enabled, uncomment the next line:
  # sudo ufw enable

  sudo ufw allow 80/tcp
  sudo ufw allow 443/tcp

  echo -e "\n--- Reloading UFW rules ---"
  sudo ufw reload

  echo -e "\n--- UFW status ---"
  sudo ufw status verbose
else
  echo -e "\n[WARNING] UFW not found or not installed. Skipping firewall configuration."
fi

#------------------------------------------------------------------------------
# 12. Install Certbot for SSL
#------------------------------------------------------------------------------
if [ "${INSTALL_NGINX}" = "True" ] && [ "${ENABLE_SSL}" = "True" ] \
   && [ "${ADMIN_EMAIL}" != "odoo@example.com" ] && [ "${WEBSITE_NAME}" != "_" ]; then
  echo -e "\n--- Installing Certbot and obtaining SSL certificate ---"
  # Install snapd if missing
  if ! dpkg -l | grep -q snapd; then
    sudo apt-get update -y
    sudo apt-get install -y snapd
  fi

  # Ensure snap core is up to date
  sudo snap install core
  sudo snap refresh core

  # Install certbot (classic)
  sudo snap install --classic certbot
  sudo ln -sf /snap/bin/certbot /usr/bin/certbot

  # Obtain certificate
  sudo certbot --nginx -d ${WEBSITE_NAME} --non-interactive --agree-tos --email ${ADMIN_EMAIL} --redirect
  sudo systemctl reload nginx
  
  # Set up auto-renewal
  echo -e "\n--- Setting up Certbot auto-renewal ---"
  sudo systemctl enable --now certbot.timer
fi

#------------------------------------------------------------------------------
# 13. Start Odoo service
#------------------------------------------------------------------------------
echo -e "\n--- Starting Odoo service ---"
sudo systemctl start ${OE_CONFIG}.service

# Verify service status
echo -e "\n--- Checking Odoo service status ---"
sudo systemctl status ${OE_CONFIG}.service --no-pager

#------------------------------------------------------------------------------
# Done!
#------------------------------------------------------------------------------
echo "-----------------------------------------------------------"
echo " Done! Odoo 18.0 is installed and up & running."
echo " Service control:  sudo systemctl {start|stop|restart|status} ${OE_CONFIG}"
echo " Port:             ${OE_PORT}"
echo " Longpolling:      ${LONGPOLLING_PORT}"
echo " Websocket route:  /websocket"
echo " Config file:      /etc/${OE_CONFIG}.conf"
echo " Logfile:          /var/log/${OE_USER}/${OE_CONFIG}.log"
echo " Service logs:     sudo journalctl -u ${OE_CONFIG}"
echo " PostgreSQL user:  ${OE_USER}"
echo " Code location:    ${OE_HOME_EXT}"
echo " Python venv:      ${OE_VENV}"
echo "-----------------------------------------------------------"
if [ "${INSTALL_NGINX}" = "True" ]; then
  echo "Nginx config: /etc/nginx/sites-available/${WEBSITE_NAME}"
  echo "Domain:       http://${WEBSITE_NAME}"
fi
if [ "${INSTALL_NGINX}" = "True" ] && [ "${ENABLE_SSL}" = "True" ]; then
  echo "SSL:          https://${WEBSITE_NAME}"
fi
echo "Superadmin (DB) password: ${OE_SUPERADMIN}"
echo "-----------------------------------------------------------"
