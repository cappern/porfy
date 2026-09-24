FROM alpine:latest

# Installer base dependencies
RUN apk add --no-cache \
    python3 py3-pip py3-venv \
    git curl wget ca-certificates \
    gcc g++ make cmake \
    openssl-dev libffi-dev \
    linux-lts linux-firmware-nvidia \
    grub grub-bios syslinux xorriso \
    e2fsprogs dosfstools \
    openssh openrc \
    bash

# WiFi & Network support
RUN apk add --no-cache \
    wpa_supplicant wireless-tools \
    dhcp dhclient \
    iw iproute2 \
    busybox-extras \
    networkmanager networkmanager-openrc

# NVIDIA CUDA 12.4+ support for RTX 4090 (Ada Lovelace)
RUN apk add --no-cache \
    nvidia-driver-open nvidia-utils \
    cuda-toolkit-12.4

# Setup ComfyUI
WORKDIR /opt/comfyui
RUN git clone https://github.com/comfyanonymous/ComfyUI.git . && \
    python3 -m venv venv && \
    . venv/bin/activate && \
    pip install --upgrade pip wheel setuptools && \
    # CUDA 12.4 with ROCm fallback
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124 && \
    # Install ComfyUI dependencies
    pip install -r requirements.txt 2>&1 | tail -20

# Create systemd service (more portable than OpenRC for this use case)
RUN mkdir -p /etc/systemd/system && \
    cat > /etc/systemd/system/comfyui.service <<'SERVICEEOF'
[Unit]
Description=ComfyUI Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/comfyui
Environment="PATH=/opt/comfyui/venv/bin"
Environment="CUDA_VISIBLE_DEVICES=0"
ExecStart=/opt/comfyui/venv/bin/python main.py --listen 0.0.0.0 --port 8188 --highvram
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICEEOF

# Enable ComfyUI on boot
RUN ln -s /etc/systemd/system/comfyui.service /etc/systemd/system/multi-user.target.wants/comfyui.service

# Network Manager startup
RUN mkdir -p /etc/systemd/system/multi-user.target.wants && \
    ln -s /usr/lib/systemd/system/networkmanager.service \
         /etc/systemd/system/multi-user.target.wants/networkmanager.service || true

# WiFi Configuration - WPA2 supplicant
RUN mkdir -p /etc/wpa_supplicant && \
    cat > /etc/wpa_supplicant/wpa_supplicant-wlan0.conf <<'WIFIEOF'
ctrl_interface=/run/wpa_supplicant
update_config=1

# Example network block - will be configured at boot
# network={
#     ssid="YOUR_WIFI_SSID"
#     psk="YOUR_WIFI_PASSWORD"
#     key_mgmt=WPA-PSK
# }
WIFIEOF
    chmod 600 /etc/wpa_supplicant/wpa_supplicant-wlan0.conf

# Boot setup script for WiFi interactive config
RUN cat > /usr/local/bin/setup-wifi.sh <<'SETUPEOF'
#!/bin/bash

echo "=== ComfyUI WiFi Setup ==="
echo ""
echo "Scanning available networks..."
iw dev wlan0 scan | grep "SSID:" | sed 's/.*SSID: //' | sort | uniq

echo ""
read -p "Enter WiFi SSID: " SSID
read -sp "Enter WiFi password: " PASSWORD
echo ""

# Configure wpa_supplicant
wpa_cli -i wlan0 <<EOF
add_network
set_network 0 ssid "$SSID"
set_network 0 psk "$PASSWORD"
set_network 0 key_mgmt WPA-PSK
enable_network 0
save_config
quit
EOF

echo "WiFi configured! Getting IP..."
dhclient wlan0

echo ""
ip addr show wlan0
echo ""
echo "ComfyUI running at: http://$(ip addr show wlan0 | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1):8188"
SETUPEOF
    chmod +x /usr/local/bin/setup-wifi.sh

# Boot script that configures WiFi if not already connected
RUN cat > /etc/systemd/system-preset/80-comfyui.preset <<'PRESETEOF'
enable comfyui.service
enable networkmanager.service
PRESETEOF

# Start script for first-time WiFi setup
RUN cat > /usr/local/bin/comfyui-first-boot.sh <<'FIRSTBOOTEOF'
#!/bin/bash

if ! ip link show wlan0 | grep -q "UP"; then
    echo "WiFi not connected. Starting WiFi setup..."
    /usr/local/bin/setup-wifi.sh
fi

# Start ComfyUI if not already running
systemctl is-active --quiet comfyui || systemctl start comfyui

echo "ComfyUI Server Ready!"
echo "Access at: http://$(hostname -I | awk '{print $1}'):8188"
FIRSTBOOTEOF
    chmod +x /usr/local/bin/comfyui-first-boot.sh

# Set hostname
RUN echo "comfyui-server" > /etc/hostname

# Root password - CHANGE THIS!
RUN echo "root:comfyui" | chpasswd

# Enable SSH for remote access
RUN ssh-keygen -A

# Prepare ComfyUI models directory structure
RUN mkdir -p /opt/comfyui/models/{checkpoints,loras,vae,embeddings,controlnet,upscale_models} && \
    chmod -R 755 /opt/comfyui/models

# Create logs directory
RUN mkdir -p /var/log/comfyui && \
    touch /var/log/comfyui/comfyui.log

# NVIDIA setup verification - test CUDA availability
RUN cat > /usr/local/bin/check-gpu.sh <<'GPUEOF'
#!/bin/bash
echo "=== GPU Check ==="
nvidia-smi
echo ""
echo "=== CUDA Info ==="
python3 -c "import torch; print(f'CUDA Available: {torch.cuda.is_available()}'); print(f'GPU Count: {torch.cuda.device_count()}'); print(f'GPU 0: {torch.cuda.get_device_name(0) if torch.cuda.is_available() else \"N/A\"}')"
GPUEOF
    chmod +x /usr/local/bin/check-gpu.sh

EXPOSE 8188 22

CMD ["/sbin/init"]
