#!/usr/bin/env bash
# deploy.sh — HNG DevOps Stage 1 automated deploy script (No Docker version)
set -euo pipefail

########################################
# Setup / logging (always absolute)
########################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$LOG_DIR/deploy_${TIMESTAMP}.log"

log()   { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%S%z)" "$*" | tee -a "$LOG_FILE"; }
info()  { log "INFO: $*"; }
error() { log "ERROR: $*"; }
succ()  { log "SUCCESS: $*"; }
die()   { error "$*"; exit "${2:-1}"; }

trap 'error "Unexpected error at line $LINENO. See $LOG_FILE"; exit 2' ERR
trap 'log "Interrupted"; exit 130' INT

########################################
# Args
########################################
CLEANUP_MODE=0
for a in "$@"; do
  case "$a" in
    --cleanup) CLEANUP_MODE=1 ;;
    -h|--help) echo "Usage: $0 [--cleanup]"; exit 0 ;;
  esac
done

########################################
# Interactive input (if needed)
########################################
########################################
# Interactive input (if needed)
########################################
read_input() {
  : "${GIT_URL:=$(printf '' ; read -p 'Git repository URL (https://...): ' REPLY && printf '%s' "$REPLY")}"
  : "${PAT:=$(printf '' ; read -s -p 'Personal Access Token (press Enter if public): ' REPLY && printf '%s' "$REPLY" && echo)}"
  : "${BRANCH:=$(printf '' ; read -p "Branch [main]: " REPLY && printf '%s' "${REPLY:-main}")}"
  : "${REMOTE_USER:=$(printf '' ; read -p 'Remote SSH username: ' REPLY && printf '%s' "$REPLY")}"
  : "${REMOTE_HOST:=$(printf '' ; read -p 'Remote server IP/hostname: ' REPLY && printf '%s' "$REPLY")}"
  : "${SSH_KEY:=$(printf '' ; read -p 'SSH key path (e.g. ~/.ssh/id_rsa): ' REPLY && printf '%s' "$REPLY")}"
  : "${APP_PORT:=$(printf '' ; read -p 'Application port (e.g. 3000): ' REPLY && printf '%s' "$REPLY")}"
  : "${REMOTE_PROJECT_DIR:=$(printf '' ; read -p 'Remote project directory (optional, leave blank for default): ' REPLY && printf '%s' "$REPLY")}"

  # Runtime selection prompt
  echo "Select application runtime:"
  echo "1) Node.js"
  echo "2) Python" 
  echo "3) Ruby"
  echo "4) PHP"
  echo "5) Static Website (HTML/CSS/JS)"
  echo "6) Other (manual setup)"
  
  while true; do
    read -p "Enter choice [1-6]: " RUNTIME_CHOICE
    case "$RUNTIME_CHOICE" in
      1) APP_TYPE="node"; break ;;
      2) APP_TYPE="python"; break ;;
      3) APP_TYPE="ruby"; break ;;
      4) APP_TYPE="php"; break ;;
      5) APP_TYPE="static"; break ;;
      6) APP_TYPE="other"; break ;;
      *) echo "Invalid choice. Please enter 1-6." ;;
    esac
  done

  # Additional runtime details for specific choices
  case "$APP_TYPE" in
    node)
      echo "Select Node.js version:"
      echo "1) Node.js 18 (LTS)"
      echo "2) Node.js 20 (Latest LTS)" 
      echo "3) Node.js 16 (Legacy)"
      read -p "Enter choice [1-3]: " NODE_CHOICE
      case "$NODE_CHOICE" in
        1) NODE_VERSION="18" ;;
        2) NODE_VERSION="20" ;;
        3) NODE_VERSION="16" ;;
        *) NODE_VERSION="18" ;;
      esac
      ;;
      
    python)
      echo "Select Python version:"
      echo "1) Python 3.8+ (Ubuntu default)"
      echo "2) Python 3.11 (Latest stable)"
      echo "3) Python 3.10"
      read -p "Enter choice [1-3]: " PYTHON_CHOICE
      case "$PYTHON_CHOICE" in
        1) PYTHON_VERSION="default" ;;
        2) PYTHON_VERSION="3.11" ;;
        3) PYTHON_VERSION="3.10" ;;
        *) PYTHON_VERSION="default" ;;
      esac
      ;;
      
    php)
      echo "Select PHP version:"
      echo "1) PHP 8.1"
      echo "2) PHP 8.2" 
      echo "3) PHP 8.0"
      echo "4) PHP 7.4 (Legacy)"
      read -p "Enter choice [1-4]: " PHP_CHOICE
      case "$PHP_CHOICE" in
        1) PHP_VERSION="8.1" ;;
        2) PHP_VERSION="8.2" ;;
        3) PHP_VERSION="8.0" ;;
        4) PHP_VERSION="7.4" ;;
        *) PHP_VERSION="8.1" ;;
      esac
      ;;
  esac

  # Initialize optional variables to avoid unbound errors
  : "${PYTHON_VERSION:=default}"
  : "${NODE_VERSION:=18}"
  : "${PHP_VERSION:=8.1}"

  # basic validation
  if [ -z "$GIT_URL" ] || [ -z "$REMOTE_USER" ] || [ -z "$REMOTE_HOST" ] || [ -z "$SSH_KEY" ] || [ -z "$APP_PORT" ]; then
    die "Missing required input (git url, remote user/host, ssh key, or application port)."
  fi

  # derive repo name and default remote dir
  REPO_NAME="$(basename -s .git "$GIT_URL")"
  if [ -z "$REMOTE_PROJECT_DIR" ]; then
    REMOTE_PROJECT_DIR="/home/${REMOTE_USER}/apps/${REPO_NAME}"
  fi
}

########################################
# Local prereqs
########################################
check_local_prereqs() {
  for c in git ssh rsync curl; do
    command -v "$c" >/dev/null 2>&1 || die "$c is required locally"
  done
  info "Local prerequisites satisfied"
}

########################################
# Prepare local repo (clone or pull)
########################################
prepare_local_repo() {
  info "Preparing local repo for $GIT_URL (branch: $BRANCH)"
  if [ -n "$PAT" ] && printf '%s' "$GIT_URL" | grep -qE '^https?://'; then
    AUTH_GIT_URL="$(printf '%s' "$GIT_URL" | sed -E "s#https?://#https://${PAT}@#")"
  else
    AUTH_GIT_URL="$GIT_URL"
  fi

  if [ -d "$SCRIPT_DIR/$REPO_NAME/.git" ]; then
    info "Repo exists locally — pulling latest"
    (cd "$SCRIPT_DIR/$REPO_NAME" && git fetch --all --prune >>"$LOG_FILE" 2>&1 && git checkout "$BRANCH" >>"$LOG_FILE" 2>&1 && git pull origin "$BRANCH" >>"$LOG_FILE" 2>&1) || die "Git pull failed"
  else
    info "Cloning $AUTH_GIT_URL ..."
    (cd "$SCRIPT_DIR" && git clone --branch "$BRANCH" "$AUTH_GIT_URL" >>"$LOG_FILE" 2>&1) || die "Git clone failed"
  fi

  # change to repo dir for local checks
  cd "$SCRIPT_DIR/$REPO_NAME"
  
  # Auto-detect application type if not already specified
  if [ "$APP_TYPE" = "other" ]; then
    info "Auto-detecting application type..."
    if [ -f "package.json" ]; then
      APP_TYPE="node"
      info "Auto-detected: Node.js application"
    elif [ -f "requirements.txt" ] || [ -f "Pipfile" ] || [ -f "pyproject.toml" ]; then
      APP_TYPE="python"
      info "Auto-detected: Python application"
    elif [ -f "Gemfile" ]; then
      APP_TYPE="ruby"
      info "Auto-detected: Ruby application"
    elif [ -f "composer.json" ] || [ -f "index.php" ]; then
      APP_TYPE="php"
      info "Auto-detected: PHP application"
    elif [ -f "index.html" ] || [ -d "static" ] || [ -d "public" ]; then
      APP_TYPE="static"
      info "Auto-detected: Static website"
    else
      info "Could not auto-detect application type. Using manual setup."
    fi
  fi
  
  info "Using application type: $APP_TYPE"
}

########################################
# Check SSH connectivity
########################################
check_ssh_connectivity() {
  info "Checking SSH to ${REMOTE_USER}@${REMOTE_HOST}"
  ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no "${REMOTE_USER}@${REMOTE_HOST}" "echo connected" >/dev/null 2>&1 || die "SSH connectivity failed. Ensure key is authorized on remote."
  succ "SSH connectivity OK"
}

########################################
# Install Nginx if not exists
########################################
install_nginx_if_needed() {
  info "Checking Nginx installation..."
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${REMOTE_USER}@${REMOTE_HOST}" /bin/bash <<'NGINX_CHECK'
set -euo pipefail

if command -v nginx >/dev/null 2>&1; then
    echo "Nginx is already installed: $(nginx -v 2>&1)"
    exit 0
fi

echo "Installing Nginx..."
LOG=/tmp/nginx_install.log

# Detect package manager
if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -y >> "$LOG" 2>&1
    sudo apt-get install -y nginx >> "$LOG" 2>&1
elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y epel-release >> "$LOG" 2>&1
    sudo yum install -y nginx >> "$LOG" 2>&1
else
    echo "Unsupported package manager"
    exit 1
fi

# Start and enable Nginx
sudo systemctl enable --now nginx >> "$LOG" 2>&1

echo "Nginx installed: $(nginx -v 2>&1)"
NGINX_CHECK
  succ "Nginx installation verified"
}

########################################
# Install runtime dependencies based on app type
########################################
install_app_runtime() {
  info "Installing runtime dependencies for $APP_TYPE"
  
  case "$APP_TYPE" in
    node)
      ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${REMOTE_USER}@${REMOTE_HOST}" /bin/bash <<NODE_SETUP
set -euo pipefail

if command -v node >/dev/null 2>&1; then
    echo "Node.js already installed: \$(node --version)"
    exit 0
fi

# Install Node.js using NodeSource repository
curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | sudo -E bash -
sudo apt-get install -y nodejs

echo "Node.js installed: \$(node --version)"
echo "npm installed: \$(npm --version)"
NODE_SETUP
      ;;

      python)
      ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${REMOTE_USER}@${REMOTE_HOST}" /bin/bash <<'PYTHON_SETUP'
set -euo pipefail

if command -v python3 >/dev/null 2>&1; then
    echo "Python3 already installed: $(python3 --version)"
fi

# Install Python and pip if not present
sudo apt-get update
sudo apt-get install -y python3 python3-pip python3-venv

# Skip version-specific installation for now
# if [ "$PYTHON_VERSION" = "3.11" ]; then
#     ... version installation code ...
# fi

echo "Python3 installed: $(python3 --version)"
echo "pip3 installed: $(pip3 --version)"
PYTHON_SETUP
      ;;

    ruby)
      ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${REMOTE_USER}@${REMOTE_HOST}" /bin/bash <<'RUBY_SETUP'
set -euo pipefail

if command -v ruby >/dev/null 2>&1; then
    echo "Ruby already installed: $(ruby --version)"
    exit 0
fi

# Install Ruby and Bundler
sudo apt-get update
sudo apt-get install -y ruby-full build-essential
sudo gem install bundler

echo "Ruby installed: $(ruby --version)"
echo "Bundler installed: $(bundler --version)"
RUBY_SETUP
      ;;

    php)
      ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${REMOTE_USER}@${REMOTE_HOST}" /bin/bash <<PHP_SETUP
set -euo pipefail

if command -v php >/dev/null 2>&1; then
    echo "PHP already installed: \$(php --version | head -1)"
    exit 0
fi

# Install PHP and common extensions
sudo apt-get update
sudo apt-get install -y software-properties-common
sudo add-apt-repository -y ppa:ondrej/php
sudo apt-get update

sudo apt-get install -y php${PHP_VERSION}-fpm php${PHP_VERSION}-cli php${PHP_VERSION}-mysql php${PHP_VERSION}-curl php${PHP_VERSION}-gd php${PHP_VERSION}-mbstring php${PHP_VERSION}-xml php${PHP_VERSION}-zip

sudo systemctl enable --now php${PHP_VERSION}-fpm

echo "PHP installed: \$(php --version | head -1)"
PHP_SETUP
      ;;

    static)
      info "Static website - no runtime dependencies needed"
      ;;
      
    other)
      info "Manual setup required - no runtime auto-installation"
      ;;
  esac
  
  succ "Runtime dependencies installed for $APP_TYPE"
}

########################################
# Setup process manager (PM2 for Node.js, systemd for others)
########################################
setup_process_manager() {
  info "Setting up process manager"
  
  case "$APP_TYPE" in
    node)
      ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${REMOTE_USER}@${REMOTE_HOST}" /bin/bash <<'PM2_SETUP'
set -euo pipefail

# Install PM2 globally if not present
if ! command -v pm2 >/dev/null 2>&1; then
    sudo npm install -g pm2
fi

# Setup PM2 startup
sudo env PATH=$PATH:/usr/bin /usr/lib/node_modules/pm2/bin/pm2 startup systemd -u $USER --hp /home/$USER
echo "PM2 installed: $(pm2 --version)"
PM2_SETUP
      ;;

    python|ruby|php)
      # Create systemd service for non-Node applications
      SERVICE_FILE="/tmp/${REPO_NAME}.service"
      START_CMD=$(get_start_command)
      cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=${REPO_NAME} application
After=network.target

[Service]
Type=simple
User=${REMOTE_USER}
WorkingDirectory=${REMOTE_PROJECT_DIR}
ExecStart=/bin/bash -c 'cd ${REMOTE_PROJECT_DIR} && ${START_CMD}'
Restart=always
RestartSec=5
Environment=NODE_ENV=production
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

      scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SERVICE_FILE" "${REMOTE_USER}@${REMOTE_HOST}:/tmp/app.service" >>"$LOG_FILE" 2>&1

      ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${REMOTE_USER}@${REMOTE_HOST}" /bin/bash <<SYSTEMD_SETUP
set -euo pipefail

sudo mv /tmp/app.service /etc/systemd/system/${REPO_NAME}.service
sudo systemctl daemon-reload
echo "Systemd service created: ${REPO_NAME}.service"
SYSTEMD_SETUP
      
      rm -f "$SERVICE_FILE"
      ;;
      
    static)
      info "Static website - no process manager needed"
      ;;
      
    other)
      info "Manual setup - no process manager configured"
      ;;
  esac
  
  succ "Process manager configured"
}

########################################
# Get application start command
########################################
get_start_command() {
  case "$APP_TYPE" in
    node)
      if [ -f "$SCRIPT_DIR/$REPO_NAME/package.json" ]; then
        # Check for start script
        if grep -q '"start"' "$SCRIPT_DIR/$REPO_NAME/package.json"; then
          echo "npm start"
        elif grep -q '"dev"' "$SCRIPT_DIR/$REPO_NAME/package.json"; then
          echo "npm run dev"
        else
          echo "node app.js || node index.js || node server.js"
        fi
      else
        echo "node app.js || node index.js || node server.js"
      fi
      ;;
      
    python)
      if [ -f "$SCRIPT_DIR/$REPO_NAME/requirements.txt" ]; then
        echo "./venv/bin/python app.py || ./venv/bin/python main.py || ./venv/bin/python manage.py runserver 0.0.0.0:${APP_PORT}"
      else
        echo "./venv/bin/python app.py || ./venv/bin/python main.py || ./venv/bin/python manage.py runserver 0.0.0.0:${APP_PORT}"
      fi
      ;;
      
       ruby)
      if [ -f "$SCRIPT_DIR/$REPO_NAME/Gemfile" ]; then
        echo "bundle install && bundle exec ruby app.rb || bundle exec rackup -p ${APP_PORT}"
      else
        echo "ruby app.rb || rackup -p ${APP_PORT}"
      fi
      ;;
      
    php)
      echo "php -S 0.0.0.0:${APP_PORT} -t ."
      ;;
      
    static)
      echo "echo 'Static website - no process to start'"
      ;;
      
    other)
      echo "echo 'Manual setup required - update start command in systemd service'"
      ;;
  esac
}

########################################
# Prepare SSL certificates (placeholder for Certbot)
########################################
setup_ssl_placeholder() {
  info "Setting up SSL readiness..."
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${REMOTE_USER}@${REMOTE_HOST}" /bin/bash <<'SSL_SETUP'
set -euo pipefail

# Create SSL directory structure
sudo mkdir -p /etc/nginx/ssl

# Create placeholder SSL configuration comment
if [ ! -f /etc/nginx/ssl/README ]; then
sudo tee /etc/nginx/ssl/README > /dev/null <<'EOF'
# SSL Certificate Directory
# 
# To enable SSL:
# 1. Install Certbot: sudo apt-get install certbot python3-certbot-nginx
# 2. Get certificate: sudo certbot --nginx -d yourdomain.com
# 3. Certbot will automatically update Nginx configuration
#
# For self-signed certificates (testing):
# sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
#   -keyout /etc/nginx/ssl/selfsigned.key \
#   -out /etc/nginx/ssl/selfsigned.crt
EOF
fi

echo "SSL directory structure prepared"
echo "To enable SSL later, run: sudo certbot --nginx -d your-domain.com"
SSL_SETUP
  succ "SSL readiness configured"
}

########################################
# Prepare remote environment
########################################
########################################
# Prepare remote environment
########################################
remote_prepare() {
  info "Preparing remote environment"
  
  install_nginx_if_needed
  install_app_runtime
  setup_ssl_placeholder
  
  # Verify all services - pass variables explicitly
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${REMOTE_USER}@${REMOTE_HOST}" "APP_TYPE='$APP_TYPE' PHP_VERSION='${PHP_VERSION:-}' /bin/bash" <<'VERIFY'
set -euo pipefail
echo "=== Service Verification ==="
echo "Nginx: $(nginx -v 2>&1 2>/dev/null || echo 'NOT_FOUND')"
echo "Nginx Service: $(systemctl is-active nginx 2>/dev/null || echo 'INACTIVE')"

# Check runtime based on app type
case "$APP_TYPE" in
  node) 
    echo "Node.js: $(node --version 2>/dev/null || echo 'NOT_FOUND')"
    echo "npm: $(npm --version 2>/dev/null || echo 'NOT_FOUND')"
    ;;
  python) 
    echo "Python3: $(python3 --version 2>/dev/null || echo 'NOT_FOUND')"
    echo "pip3: $(pip3 --version 2>/dev/null || echo 'NOT_FOUND')"
    ;;
  ruby) 
    echo "Ruby: $(ruby --version 2>/dev/null || echo 'NOT_FOUND')"
    echo "Bundler: $(bundler --version 2>/dev/null || echo 'NOT_FOUND')"
    ;;
  php) 
    echo "PHP: $(php --version 2>/dev/null | head -1 || echo 'NOT_FOUND')"
    # Only check PHP-FPM if PHP_VERSION is set
    if [ -n "$PHP_VERSION" ]; then
      echo "PHP-FPM: $(systemctl is-active php${PHP_VERSION}-fpm 2>/dev/null || echo 'INACTIVE')"
    else
      echo "PHP-FPM: PHP_VERSION not set"
    fi
    ;;
  static)
    echo "Static website - runtime verified"
    ;;
  other)
    echo "Manual setup - runtime verification skipped"
    ;;
esac
VERIFY

  succ "Remote environment prepared successfully"
}

########################################
# Transfer project
########################################
transfer_project() {
  info "Transferring project to ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PROJECT_DIR}"
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${REMOTE_USER}@${REMOTE_HOST}" "mkdir -p '${REMOTE_PROJECT_DIR}' && chown ${REMOTE_USER}:${REMOTE_USER} '${REMOTE_PROJECT_DIR}'" || die "Failed to create remote directory"
  
  if command -v rsync >/dev/null 2>&1; then
    rsync -avz --delete -e "ssh -i ${SSH_KEY} -o StrictHostKeyChecking=no" \
      --exclude '.git' \
      --exclude 'node_modules' \
      --exclude '__pycache__' \
      --exclude '.venv' \
      --exclude '.env' \
      "$SCRIPT_DIR/$REPO_NAME/" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PROJECT_DIR}/" >>"$LOG_FILE" 2>&1 || die "rsync failed"
  else
    # Use tar for efficient transfer if rsync not available
    (cd "$SCRIPT_DIR/$REPO_NAME" && tar czf - --exclude='.git' --exclude='node_modules' --exclude='__pycache__' --exclude='.venv' --exclude='.env' .) | \
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${REMOTE_USER}@${REMOTE_HOST}" "cd '${REMOTE_PROJECT_DIR}' && tar xzf -" >>"$LOG_FILE" 2>&1 || die "tar transfer failed"
  fi
  succ "Project files transferred"
}

########################################
# Install application dependencies
########################################
########################################
# Install application dependencies
########################################
install_dependencies() {
  info "Installing application dependencies"
  
  case "$APP_TYPE" in
    node)
      ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${REMOTE_USER}@${REMOTE_HOST}" "cd '${REMOTE_PROJECT_DIR}' && /bin/bash" <<'NODE_DEPS'
set -euo pipefail

if [ -f "package.json" ]; then
  if [ -f "package-lock.json" ] || [ -f "npm-shrinkwrap.json" ]; then
    npm ci --production
  else
    npm install --production
  fi
  echo "Node.js dependencies installed"
else
  echo "No package.json found - skipping npm install"
fi
NODE_DEPS
      ;;

    python)
      ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${REMOTE_USER}@${REMOTE_HOST}" "cd '${REMOTE_PROJECT_DIR}' && /bin/bash" <<'PYTHON_DEPS'
set -euo pipefail

echo "Creating Python virtual environment..."
python3 -m venv venv

echo "Upgrading pip in virtual environment..."
./venv/bin/pip install --upgrade pip

if [ -f "requirements.txt" ]; then
  echo "Installing dependencies from requirements.txt..."
  ./venv/bin/pip install -r requirements.txt
  echo "✅ Python dependencies installed from requirements.txt in virtual environment"
elif [ -f "Pipfile" ]; then
  echo "Installing dependencies from Pipfile..."
  ./venv/bin/pip install pipenv
  ./venv/bin/pipenv install --deploy
  echo "✅ Python dependencies installed from Pipfile in virtual environment"
else
  echo "⚠️ No requirements.txt or Pipfile found - virtual environment created but no dependencies installed"
fi

echo "Virtual environment setup completed"
PYTHON_DEPS
      ;;

    ruby)
      ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${REMOTE_USER}@${REMOTE_HOST}" "cd '${REMOTE_PROJECT_DIR}' && /bin/bash" <<'RUBY_DEPS'
set -euo pipefail

if [ -f "Gemfile" ]; then
  bundle install --without development test --deployment
  echo "Ruby dependencies installed"
else
  echo "No Gemfile found - skipping bundle install"
fi
RUBY_DEPS
      ;;

    php)
      ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${REMOTE_USER}@${REMOTE_HOST}" "cd '${REMOTE_PROJECT_DIR}' && /bin/bash" <<'PHP_DEPS'
set -euo pipefail

if [ -f "composer.json" ]; then
  if command -v composer >/dev/null 2>&1; then
    composer install --no-dev --optimize-autoloader
    echo "PHP dependencies installed via composer"
  else
    # Install composer
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
    php composer-setup.php --install-dir=/usr/local/bin --filename=composer
    php -r "unlink('composer-setup.php');"
    composer install --no-dev --optimize-autoloader
    echo "Composer installed and PHP dependencies installed"
  fi
else
  echo "No composer.json found - skipping composer install"
fi
PHP_DEPS
      ;;

    static)
      info "Static website - no dependencies to install"
      ;;
      
    other)
      info "Manual setup - dependencies must be installed manually"
      ;;
  esac
  
  succ "Application dependencies installed"
}

########################################
# Start application
########################################
########################################
# Start application
########################################
start_application() {
  info "Starting application"
  
  case "$APP_TYPE" in
    node)
      # Get the start command locally first
      START_CMD=$(get_start_command)
      ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${REMOTE_USER}@${REMOTE_HOST}" /bin/bash <<NODE_START
set -euo pipefail
cd "${REMOTE_PROJECT_DIR}"

# Stop existing PM2 process if running
pm2 delete "${REPO_NAME}" 2>/dev/null || true

# Start with PM2
if [ -f "ecosystem.config.js" ] || [ -f "ecosystem.config.json" ]; then
  pm2 start ecosystem.config.js --env production
else
  # Use the pre-determined start command
  pm2 start "$START_CMD" --name "${REPO_NAME}"
fi

pm2 save
pm2 list
NODE_START
      ;;

    python|ruby|php)
      # Get the start command locally first
      START_CMD=$(get_start_command)
      ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${REMOTE_USER}@${REMOTE_HOST}" /bin/bash <<SYSTEMD_START
set -euo pipefail

# Stop existing service if running
sudo systemctl stop "${REPO_NAME}.service" 2>/dev/null || true

# Start with systemd
sudo systemctl enable "${REPO_NAME}.service"
sudo systemctl start "${REPO_NAME}.service"
sudo systemctl status "${REPO_NAME}.service" --no-pager
SYSTEMD_START
      ;;

    static)
      info "Static website - no application process to start"
      ;;
      
    other)
      info "Manual setup - application must be started manually"
      ;;
  esac
  
  succ "Application started"
}

########################################
# Nginx config with SSL readiness
########################################
########################################
# Nginx config with SSL readiness
########################################
configure_nginx() {
  info "Configuring Nginx reverse proxy with SSL readiness"
  
  # Determine upstream based on app type
  if [ "$APP_TYPE" = "static" ]; then
    UPSTREAM_CONFIG="root ${REMOTE_PROJECT_DIR};
    index index.html index.htm;"
    LOCATION_CONFIG="try_files \$uri \$uri/ =404;"
  else
    UPSTREAM_CONFIG=""
    LOCATION_CONFIG="proxy_pass http://127.0.0.1:${APP_PORT};
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    
    # WebSocket support
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \"upgrade\";"
  fi
  
  # Create nginx config with SSL placeholder
  NGINX_CONFIG_FILE="/tmp/nginx_${REPO_NAME}.conf"
  cat > "$NGINX_CONFIG_FILE" <<EOF
# HTTP to HTTPS redirect (commented until SSL is configured)
# server {
#     listen 80;
#     server_name _;
#     return 301 https://\$server_name\$request_uri;
# }

server {
    listen 80;
    # listen 443 ssl http2;  # Uncomment when SSL is configured
    server_name _;
    
    # SSL placeholder (uncomment when certificates are available)
    # ssl_certificate /etc/nginx/ssl/selfsigned.crt;
    # ssl_certificate_key /etc/nginx/ssl/selfsigned.key;
    # ssl_protocols TLSv1.2 TLSv1.3;
    # ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512;
    
    $UPSTREAM_CONFIG
    
    location / {
        $LOCATION_CONFIG
    }
    
    # Security headers
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
}
EOF

  # Copy the config file to remote server
  scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$NGINX_CONFIG_FILE" "${REMOTE_USER}@${REMOTE_HOST}:/tmp/nginx_config.conf" >>"$LOG_FILE" 2>&1 || die "Failed to copy nginx config"

  # Set up nginx on remote
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${REMOTE_USER}@${REMOTE_HOST}" /bin/bash <<'NGINX_SETUP'
set -euo pipefail

# Move config to proper location
sudo mv /tmp/nginx_config.conf /etc/nginx/sites-available/app.conf

# Create symlink
sudo ln -sf /etc/nginx/sites-available/app.conf /etc/nginx/sites-enabled/

# Remove default config if it exists
sudo rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

# Test configuration
sudo nginx -t

# Reload nginx
sudo systemctl reload nginx
NGINX_SETUP

  # Clean up local temp file
  rm -f "$NGINX_CONFIG_FILE"
  
  succ "Nginx configured with SSL readiness"
}

########################################
# Validation
########################################
validate_deployment() {
  info "Validating deployment"
  sleep 5  # Give services time to start
  
  # Check if nginx is running
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${REMOTE_USER}@${REMOTE_HOST}" "sudo systemctl is-active nginx" >/dev/null 2>&1 || die "Nginx is not active on remote"
  
  # Test nginx configuration
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${REMOTE_USER}@${REMOTE_HOST}" "sudo nginx -t" >>"$LOG_FILE" 2>&1 || die "Nginx configuration test failed"
  
  # Check application process status
  case "$APP_TYPE" in
    node)
      ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${REMOTE_USER}@${REMOTE_HOST}" "pm2 list" >>"$LOG_FILE" 2>&1 || info "PM2 status check failed"
      ;;
    python|ruby|php)
      ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${REMOTE_USER}@${REMOTE_HOST}" "sudo systemctl is-active ${REPO_NAME}.service" >/dev/null 2>&1 || die "Application service is not active"
      ;;
  esac
  
  # Test application health (only for non-static apps)
  if [ "$APP_TYPE" != "static" ] && [ "$APP_TYPE" != "other" ]; then
    info "Testing application health..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${REMOTE_USER}@${REMOTE_HOST}" "curl -sfS --connect-timeout 10 http://127.0.0.1:${APP_PORT} >/dev/null 2>&1 && echo '✅ Application is healthy' || echo '❌ Application health check failed'" >>"$LOG_FILE" 2>&1
  fi
  
  # public reachability
  info "Testing public reachability at http://${REMOTE_HOST}"
  if curl -sfS --connect-timeout 10 "http://${REMOTE_HOST}" >/dev/null 2>&1; then
    succ "✅ Application reachable via http://${REMOTE_HOST}"
  else
    info "⚠️  Application not reachable from this network (http://${REMOTE_HOST}) — check firewall/security groups"
  fi
}

########################################
# Cleanup (optional)
########################################
cleanup_remote() {
  info "Running cleanup on remote host"
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${REMOTE_USER}@${REMOTE_HOST}" /bin/bash <<REMOTE_CLEAN
set -euo pipefail

# Stop application processes
case "$APP_TYPE" in
  node)
    pm2 delete "${REPO_NAME}" 2>/dev/null || true
    pm2 save 2>/dev/null || true
    ;;
  python|ruby|php)
    sudo systemctl stop "${REPO_NAME}.service" 2>/dev/null || true
    sudo systemctl disable "${REPO_NAME}.service" 2>/dev/null || true
    sudo rm -f /etc/systemd/system/${REPO_NAME}.service
    sudo systemctl daemon-reload
    ;;
esac

# Clean up nginx (only our config, not nginx itself)
sudo rm -f /etc/nginx/sites-enabled/app.conf || true
sudo rm -f /etc/nginx/sites-available/app.conf || true
sudo nginx -t && sudo systemctl reload nginx || true

# Remove project directory
sudo rm -rf "${REMOTE_PROJECT_DIR}" || true

echo "Cleanup completed"
REMOTE_CLEAN
  succ "Remote cleanup completed"
}

########################################
# Main
########################################
main() {
  if [ "$CLEANUP_MODE" -eq 1 ]; then
    read_input
    check_local_prereqs
    check_ssh_connectivity
    cleanup_remote
    succ "Cleanup finished"
    exit 0
  fi

  read_input
  check_local_prereqs
  prepare_local_repo
  check_ssh_connectivity
  remote_prepare
  transfer_project
  install_dependencies
  setup_process_manager
  start_application
  configure_nginx
  validate_deployment

  succ "Deployment completed successfully! 🚀"
  info "Your application is accessible at: http://${REMOTE_HOST}"
  info "Application type: $APP_TYPE"
  if [ "$APP_TYPE" = "node" ]; then
    info "Node.js version: $NODE_VERSION"
  elif [ "$APP_TYPE" = "php" ]; then
    info "PHP version: $PHP_VERSION"
  fi
  info "SSL is ready for configuration - see /etc/nginx/ssl/README on the server"
  info "Detailed logs: $LOG_FILE"
}

main "$@"