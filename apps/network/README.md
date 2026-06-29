# Network Host Reporting

A lightweight script that automatically reports host information to an upstream service at configurable intervals.

## Features

- **Host Information Collection**: Gathers hostname, local IP, external IP, OS type, and version
- **Cross-Platform**: Works on macOS, Linux, and Unix systems
- **Configurable**: Set custom reporting intervals and upstream service URLs
- **Reliable**: Multiple fallback methods for IP detection and external service queries
- **Logging**: Comprehensive logging with timestamps
- **Easy Installation**: Simple setup script with interactive configuration

## Collected Data

The script reports the following information:

```json
{
    "hostname": "hostname.example.com",
    "local_ip": "192.168.1.100",
    "external_ip": "203.0.113.1",
    "os_type": "macOS",
    "os_version": "14.0",
    "timestamp": "2024-01-15T10:30:00Z",
    "uptime": "5d"
}
```

## Installation

The Network Host Reporting app is integrated into the main dotfiles installation system.

### Install Network Reporting Only
```bash
cd ~/Code/mydot
./install.sh network
```

### Install as Part of Complete Setup
```bash
cd ~/Code/mydot
./install.sh all
```

The installation will:
- Automatically detect your platform (macOS/Linux/Unix)
- Set up the appropriate service (launchd/systemd/cron)
- Configure default settings
- Test the installation

## Configuration

### Configuration File (`config.conf`)

```bash
# Upstream service URL
UPSTREAM_URL="https://your-service.com/api/host-report"

# Reporting interval in minutes (0 to disable)
REPORT_INTERVAL=60

# Verbose logging (0 or 1)
VERBOSE_LOGGING=0

# Include extra system information (0 or 1)
INCLUDE_EXTRA_INFO=0
```

### Manual Configuration

Edit the `config.conf` file to customize settings:

```bash
nano config.conf
```

## Usage

### Manual Execution

Run the report script manually:

```bash
./report.sh
```

### Viewing Logs

Monitor the log file:

```bash
tail -f network-report.log
```

### Cron Job Management

View current cron jobs:
```bash
crontab -l
```

Remove the network reporting cron job:
```bash
crontab -l | grep -v "report.sh" | crontab -
```

## Upstream Service Requirements

Your upstream service should accept POST requests with JSON data. The expected endpoint should:

1. **Accept POST requests** with `Content-Type: application/json`
2. **Return HTTP 2xx status codes** for successful submissions
3. **Handle the JSON payload** containing host information

### Example Server Implementation (Node.js/Express)

```javascript
app.post('/api/host-report', (req, res) => {
    const { hostname, local_ip, external_ip, os_type, os_version, timestamp, uptime } = req.body;
    
    // Process the host information
    console.log(`Received report from ${hostname} (${local_ip})`);
    
    // Store in database, send alerts, etc.
    
    res.json({ success: true, message: 'Report received' });
});
```

## Troubleshooting

### Common Issues

1. **"curl not found" error**:
   - Install curl: `brew install curl` (macOS) or `apt-get install curl` (Linux)

2. **"Configuration file not found" error**:
   - Run the installation script: `./install.sh`

3. **"UPSTREAM_URL not configured" error**:
   - Edit `config.conf` and set the `UPSTREAM_URL` variable

4. **External IP detection fails**:
   - The script tries multiple services for reliability
   - Check your internet connection and firewall settings

### Debug Mode

Enable verbose logging by setting `VERBOSE_LOGGING=1` in `config.conf`.

### Testing Connectivity

Test your upstream service manually:

```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"test": "data"}' \
  https://your-service.com/api/host-report
```

## Security Considerations

- **Network Security**: Use HTTPS for your upstream service URL
- **Data Privacy**: Be aware of what information is being sent
- **Access Control**: Ensure your upstream service has proper authentication
- **Log Rotation**: Consider setting up log rotation for the log file

## Uninstallation

1. **Remove the cron job**:
   ```bash
   crontab -l | grep -v "report.sh" | crontab -
   ```

2. **Delete the network directory**:
   ```bash
   rm -rf ~/Code/mydot/apps/network
   ```

## File Structure

```
network/
├── README.md           # This file
├── install.sh          # Installation script
├── report.sh           # Main reporting script
├── config.conf         # Configuration file
└── network-report.log  # Log file (created after first run)
```

## Dependencies

- `curl` - For HTTP requests
- `crontab` - For scheduling (usually pre-installed)
- Standard Unix utilities (`hostname`, `ifconfig`, `route`, etc.)

## License

This script is part of your dotfiles configuration. Use and modify as needed for your environment.
