# WiFi & NVIDIA RTX 4090 Setup Guide

## RTX 4090 GPU Support

This build includes the **CUDA 12.5 toolkit/driver** (nearest release NVIDIA still publishes for older pins — see the comment in `Dockerfile`) and **PyTorch cu124** wheels, optimized for NVIDIA Ada Lovelace architecture (RTX 4090). The PyTorch wheels bundle their own CUDA runtime, so they don't need to match the system toolkit version exactly.

### Verify GPU is Working

After first boot:

```bash
ssh root@comfyui-server

# Check GPU detection
nvidia-smi

# Should show:
# | NVIDIA-SMI 555.xx    Driver Version: 555.xx    CUDA Version: 12.5
# | RTX 4090 with 24GB VRAM

# Check PyTorch CUDA support
python3 -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}')"
# Should print: CUDA available: True

# Run the quick check script
/usr/local/bin/check-gpu.sh
```

### If GPU Not Detected

```bash
# Reinstall NVIDIA driver (if needed)
apt-get install --reinstall -y nvidia-driver-555

# Verify CUDA installation
nvcc --version

# Reload drivers
modprobe -r nvidia
modprobe nvidia
nvidia-smi
```

### RTX 4090 Performance Tuning

ComfyUI starts with `--highvram` flag to keep models resident (24GB VRAM available):

```bash
# Current setting in systemd service:
ExecStart=python main.py --listen 0.0.0.0 --port 8188 --highvram

# For Flux.1 or heavy workflows:
# --highvram    Keep all models in VRAM (requires 20GB+)
# --normalvram  Balanced (default)
# --lowvram     Aggressive offloading (slower but uses ~8GB)
```

To change:
```bash
# Edit systemd service
systemctl edit comfyui

# Change ExecStart line, save (Ctrl+D), then reload:
systemctl daemon-reload
systemctl restart comfyui
```

---

## WiFi Configuration

### Option A: Interactive Setup (Easiest)

After first boot:

```bash
ssh root@comfyui-server

# Run interactive WiFi setup
/usr/local/bin/setup-wifi.sh

# Follow prompts:
# 1. Scans available networks
# 2. Asks for SSID
# 3. Asks for password
# 4. Configures and connects
```

### Option B: Manual wpa_supplicant Config

```bash
ssh root@comfyui-server

# Edit WiFi config
vi /etc/wpa_supplicant/wpa_supplicant-wlan0.conf

# Add network block:
network={
    ssid="YOUR_SSID_HERE"
    psk="YOUR_PASSWORD_HERE"
    key_mgmt=WPA-PSK
    priority=1
}

# Save and activate
wpa_cli -i wlan0 reconfigure

# Get IP
dhclient wlan0
ip addr show wlan0
```

### Option C: Pre-boot WiFi (Recommended for Automation)

Edit `Dockerfile` before building:

```dockerfile
# Add after "Enable SSH" section:
RUN cat > /etc/wpa_supplicant/wpa_supplicant-wlan0.conf <<'EOF'
ctrl_interface=/run/wpa_supplicant
update_config=1

network={
    ssid="YOUR_SSID"
    psk="YOUR_PASSWORD"
    key_mgmt=WPA-PSK
    priority=1
}
EOF
```

Then rebuild and WiFi connects automatically at boot.

---

## First Boot Checklist

### 1. **Boot from USB**
- Insert USB and reboot
- Press F12/ESC/DEL during POST
- Select USB boot device
- Wait ~30 seconds for system to boot

### 2. **Find Server IP**
```bash
# On the server terminal (if connected to monitor/keyboard):
ip addr show

# Look for wlan0 inet address (e.g., 192.168.1.50)
```

Or from your Mac:
```bash
# Scan network for ComfyUI
ping comfyui-server.local

# Or scan your subnet
nmap -p 8188 192.168.1.0/24 | grep -B5 "8188"
```

### 3. **SSH In and Configure WiFi**
```bash
# From Mac
ssh root@comfyui-server.local
# or
ssh root@192.168.1.50

# If WiFi not connected yet, run:
/usr/local/bin/setup-wifi.sh
```

### 4. **Verify Everything**
```bash
# Check GPU
nvidia-smi

# Check ComfyUI service
systemctl status comfyui

# Check logs
journalctl -u comfyui -n 20

# Check network
ip addr show
ss -tlnp | grep 8188
```

### 5. **Access Web UI**
```
http://192.168.1.50:8188
```

---

## Troubleshooting

### WiFi Not Connecting

```bash
# Check WiFi interface exists
iw dev

# Scan for networks
iw dev wlan0 scan | grep "SSID:"

# Check wpa_supplicant status
wpa_cli -i wlan0 status

# Restart network manager
systemctl restart NetworkManager

# Manual connection attempt
wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant-wlan0.conf
dhclient wlan0
```

### GPU Not Detected

```bash
# Check kernel module loaded
lsmod | grep nvidia

# Reload drivers
modprobe -r nvidia
modprobe nvidia

# Check CUDA installation
ls /usr/local/cuda*

# Verify PyTorch can see GPU
python3 -c "import torch; print(torch.cuda.device_count())"
```

### ComfyUI Not Starting

```bash
# Check service status
systemctl status comfyui

# View logs
journalctl -u comfyui -n 50

# Manual start for debugging
cd /opt/comfyui
source venv/bin/activate
python main.py --listen 0.0.0.0 --port 8188 --highvram
```

### Can't SSH In

```bash
# Check SSH is running
systemctl status ssh

# Start if needed
systemctl start ssh

# Verify port 22 open
ss -tlnp | grep 22
```

---

## Network Tips

### Static IP (Optional)

For stable access, set static IP:

```bash
# Edit /etc/network/interfaces
vi /etc/network/interfaces

# Example config:
auto wlan0
iface wlan0 inet static
    address 192.168.1.50
    netmask 255.255.255.0
    gateway 192.168.1.1
    dns-nameservers 8.8.8.8

# Restart networking
ifdown wlan0 && ifup wlan0
```

### mDNS Hostname (Best Practice)

Access by hostname instead of IP:

```bash
# Install mDNS (avahi)
apt-get install -y avahi-daemon avahi-utils

# Enable at boot
systemctl enable avahi-daemon
systemctl start avahi-daemon

# From Mac, now use:
http://comfyui-server.local:8188
```

### Port Forwarding (for Remote Access)

If accessing from outside your network:

```bash
# Install Caddy reverse proxy
apt-get install -y caddy

# Configure /etc/caddy/Caddyfile
# See README.md for production setup
```

---

## Performance Metrics

With RTX 4090 + --highvram:

| Model | Resolution | Time | VRAM |
|-------|-----------|------|------|
| SDXL 1.0 | 1024×1024 | ~3-4s | 18GB |
| Flux.1-dev | 1024×1024 | ~8-10s | 23GB |
| AnimateDiff | 512×512 | ~30s | 20GB |

If OOM errors occur:
1. Change to `--normalvram` (slightly slower)
2. Reduce batch size in UI
3. Use FP8 quantization for Flux

---

## Security Notes

⚠️ **Before production:**

1. **Change root password**
   ```bash
   ssh root@comfyui-server
   passwd
   ```

2. **Disable SSH if not needed**
   ```bash
   systemctl disable --now ssh
   ```

3. **Setup firewall**
   ```bash
   apt-get install -y ufw
   ufw enable
   ufw allow 8188/tcp
   ufw deny 22/tcp  # Or allow only from your IP
   ```

4. **Setup reverse proxy with auth** (see README.md)

---

## Customizing Before Build

Edit `Dockerfile` before pushing:

```dockerfile
# 1. Change WiFi SSID/password (line ~92)
network={
    ssid="YOUR_HOME_SSID"
    psk="YOUR_PASSWORD"
    ...
}

# 2. Change root password (line ~130)
RUN echo "root:yourpassword" | chpasswd

# 3. Add more Python packages
RUN . venv/bin/activate && pip install <package>
```

Then:
```bash
git add Dockerfile
git commit -m "Configure WiFi and GPU settings"
git push origin main
```

Build runs automatically!

---

## Monitoring

Check system while running:

```bash
# GPU usage
watch nvidia-smi

# System resources
top

# ComfyUI logs
journalctl -u comfyui -f  # Follow logs in real-time

# Network
ss -tlnp
```

---

**All set! Enjoy your personal RTX 4090 ComfyUI server! 🚀**
