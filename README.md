# Server Deploy - Automated Deployment Script

A robust, Docker-free automated deployment script that deploys applications directly to servers using native runtimes. Supports Node.js, Python, Ruby, PHP, and static websites.

## Features

- 🚀 **Docker-free** - Direct server deployment without containers
- 🔧 **Multi-runtime support** - Node.js, Python, Ruby, PHP, Static sites
- 📦 **Auto-dependency installation** - npm, pip, bundle, composer
- 🔒 **SSL-ready** - Pre-configured for easy SSL setup
- ⚡ **Process management** - PM2 for Node.js, systemd for others
- 🔄 **Zero-downtime** - Proper service management and restarts
- 📝 **Comprehensive logging** - Detailed deployment logs
- 🧹 **Cleanup utility** - Easy environment cleanup

## Supported Runtimes

- **Node.js** (v16, v18, v20) with PM2 process manager
- **Python** (3.8+, 3.10, 3.11) with systemd service
- **Ruby** with systemd service and Bundler
- **PHP** (7.4, 8.0, 8.1, 8.2) with PHP-FPM and systemd
- **Static Websites** - Direct Nginx serving

## Prerequisites

### Local Machine

- `git` - for repository cloning
- `ssh` - for remote server access
- `rsync` or `tar` - for file transfer
- `curl` - for health checks

### Remote Server

- Ubuntu/Debian or CentOS/RHEL based system
- SSH access with key authentication
- sudo privileges for the deployment user

## Quick Start

1. **Clone the repository**:
   ```bash
   git clone https://github.com/your-username/server-deploy.git
   cd server-deploy
   ```
2. Make the script executable:
   ```bash
   chmod +x deploy.sh
   ```
3. Run the deployment:

```bash
./deploy.sh
```

## Usage

```bash
./deploy.sh
```

The script will interactively prompt for:

- Git repository URL
- Personal Access Token (if needed)
- Branch name (default: main)
- Remote server SSH credentials
- Application port
- Project directory on server
- Application runtime type

## Cleanup Mode

```bash
./deploy.sh --cleanup
```

## Help

```bash
./deploy.sh --help
```

## Configuration

> Required Information
> Before running, have this information ready:

1. Git Repository: HTTPS URL of your application code
2. Access Token: PAT if repository is private
3. Server Details:
   - SSH username
   - Server IP/hostname
   - SSH private key path
4. Application Details:
   - Port number (e.g., 3000, 8000, 8080)
   - Runtime type (Node.js, Python, etc.)

## Example Deployment Flow

```bash

$ ./deploy.sh

Git repository URL (https://...): https://github.com/username/my-app.git
Personal Access Token (press Enter if public): [enter or provide token]
Branch [main]: develop
Remote SSH username: deployer
Remote server IP/hostname: 192.168.1.100
SSH key path (e.g. ~/.ssh/id_rsa): ~/.ssh/deploy_key
Application port (e.g. 3000): 3000
Remote project directory (optional, leave blank for default): /var/www/my-app

Select application runtime:
1) Node.js
2) Python
3) Ruby
4) PHP
5) Static Website (HTML/CSS/JS)
6) Other (manual setup)
Enter choice [1-6]: 1

Select Node.js version:
1) Node.js 18 (LTS)
2) Node.js 20 (Latest LTS)
3) Node.js 16 (Legacy)
Enter choice [1-3]: 2
```

## Runtime-Specific Details

Node.js

- Uses PM2 for process management
- Auto-detects start script from package.json
- Installs production dependencies only
- Supports ecosystem.config.js for advanced configuration

Python

- Creates virtual environment
- Installs from requirements.txt or Pipfile
- Supports Django, Flask, and other frameworks
- Uses systemd for service management

Ruby

- Uses Bundler for dependency management
- Supports Rails, Sinatra, and other frameworks
- Systemd service with proper restart policies

PHP

- Configures PHP-FPM if needed
- Composer for dependency management
- Supports Laravel, Symfony, and other frameworks

Static Websites

- Direct Nginx file serving
- No application process to manage
- Simple and efficient deployment

Server Setup
The script automatically installs and configures:

Nginx: Reverse proxy and static file serving

Runtime: Selected application runtime (Node.js, Python, etc.)

Process Manager: PM2 (Node.js) or systemd (others)

SSL Ready: Pre-configured for easy SSL certificate setup

## Manual SSL Setup (After Deployment)

1. Install Certbot:

```bash
sudo apt-get update
sudo apt-get install certbot python3-certbot-nginx
```

2. Get SSL Certificate:

```bash
sudo certbot --nginx -d yourdomain.com
```

3. Auto-renewal (already configured by Certbot):

```bash
sudo certbot renew --dry-run
```

## Troubleshooting

Common Issues

1. SSH Connection Failed

```bash
# Verify SSH key permissions
chmod 600 ~/.ssh/your_key

# Ensure the key is added to SSH agent
ssh-add ~/.ssh/your_key

# Test SSH connection manually
ssh -i ~/.ssh/your_key user@server -o ConnectTimeout=10
```

2. Permission Denied Errors

```bash
# Check if user has sudo privileges
sudo -l

# Verify project directory permissions
ls -la /path/to/project
```

3. Application Not Starting

```bash
# Check application status based on runtime:

# For Node.js (PM2)
pm2 list
pm2 logs

# For Python/Ruby/PHP (systemd)
sudo systemctl status your-app-name
sudo journalctl -u your-app-name -f

# Check if port is in use
sudo netstat -tulpn | grep :3000
```

4. Nginx Configuration Errors

```bash
# Test Nginx configuration
sudo nginx -t

# Check Nginx status
sudo systemctl status nginx

# View Nginx error logs
sudo tail -f /var/log/nginx/error.log
```

5. Dependency Installation Failed

```bash
# Check available disk space
df -h

# Verify internet connectivity on server
curl -I https://github.com

# Check specific runtime installation
node --version    # For Node.js
python3 --version # For Python
php --version     # For PHP
ruby --version    # For Ruby
```

6. Application Health Check Failed

```bash
# Test application locally on server
curl http://localhost:3000

# Check firewall settings
sudo ufw status

# Verify security groups (cloud providers)
```

## Debug Mode

For detailed debugging, monitor the log file during deployment:

```bash
# Tail the deployment log in real-time
tail -f logs/deploy_$(date +%Y%m%d_%H%M).log

# Or check the latest log file
ls -lt logs/ | head -5
```

## Manual Service Management

1. Node.js (PM2)

```bash
# View running processes
pm2 list

# View logs
pm2 logs

# Restart application
pm2 restart your-app-name

# Monitor resources
pm2 monit
```

2. Systemd Services (Python/Ruby/PHP)

```bash
# Check service status
sudo systemctl status your-app-name

# View service logs
sudo journalctl -u your-app-name -f

# Restart service
sudo systemctl restart your-app-name

# Enable/disable service
sudo systemctl enable your-app-name
sudo systemctl disable your-app-name
```

3. Nginx Management

```bash
# Reload Nginx (preserves connections)
sudo systemctl reload nginx

# Restart Nginx (drops connections)
sudo systemctl restart nginx

# Test configuration
sudo nginx -t

# View access logs
sudo tail -f /var/log/nginx/access.log
```

## Copy the public key to your server:

```bash
ssh-copy-id -i ~/.ssh/your_key_name root@0.0.0.0
```

## Test the SSH connection with your key:

```bash
ssh -i ~/.ssh/your_key_name -o ConnectTimeout=10 root@0.81.0.0
```

## Common Error Messages and Solutions

Error Message Possible Cause Solution
"Connection refused" Application not running on specified port Check application logs and service status
"Permission denied (publickey)" SSH key not properly configured Verify key path and permissions
"Address already in use" Port conflict with another service Change application port or stop conflicting service
"Command not found" Runtime not installed properly Re-run deployment or install runtime manually
"502 Bad Gateway" Nginx can't reach application Check if app is running and accessible on localhost:port

## Security Considerations

1. Use dedicated deployment users with limited privileges
2. Store SSH keys securely with proper permissions
3. Regularly update system packages on the server
4. Use SSL/TLS encryption in production
5. Implement proper firewall rules
6. Use strong passwords and key-based authentication
7. Regular security updates and monitoring

## Best Practices

1. Testing: Always test deployments in a staging environment first
2. Backups: Maintain regular backups of your application and database
3. Monitoring: Set up monitoring for your application and server
4. Updates: Keep your application and server dependencies updated
5. Documentation: Maintain deployment documentation for your team

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

MIT License - see LICENSE file for details

## Support

1. For issues and questions:
2. Check the troubleshooting section above
3. Review deployment logs in the logs/ directory
4. Open an issue on GitHub with detailed information

> Note: This script is designed for deployment to clean Ubuntu/Debian servers. Test in a staging environment before production use. Always ensure you have proper backups before running deployments.
