# Ubuntu 24.04 (Noble) base — needed for real systemd, official NVIDIA/CUDA apt
# repos, and DKMS support. Alpine cannot supply any of these three things.
FROM ubuntu:24.04

# bash (not the default dash) so brace expansion below (models/{checkpoints,...})
# actually creates six directories instead of one literally-named one.
SHELL ["/bin/bash", "-c"]

ENV DEBIAN_FRONTEND=noninteractive

# Base dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv \
    git curl wget gnupg ca-certificates \
    build-essential cmake \
    libssl-dev libffi-dev \
    e2fsprogs dosfstools \
    openssh-server \
    && rm -rf /var/lib/apt/lists/*

# Live-boot kernel + headers. Installed *before* the NVIDIA driver so DKMS
# builds the nvidia.ko module against this exact kernel during postinst.
RUN apt-get update && apt-get install -y --no-install-recommends \
    linux-image-generic linux-headers-generic linux-firmware \
    && rm -rf /var/lib/apt/lists/*

# WiFi & Network support
RUN apt-get update && apt-get install -y --no-install-recommends \
    wpasupplicant wireless-tools iw \
    isc-dhcp-client iproute2 net-tools \
    network-manager \
    && rm -rf /var/lib/apt/lists/*

# NVIDIA driver + CUDA 12.4 (Ada Lovelace / RTX 4090) via NVIDIA's official
# apt repo — see https://developer.nvidia.com/cuda-12-4-0-download-archive
RUN curl -fsSL -o /tmp/cuda-keyring.deb \
    https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb && \
    dpkg -i /tmp/cuda-keyring.deb && rm -f /tmp/cuda-keyring.deb && \
    apt-get update && apt-get install -y --no-install-recommends \
    nvidia-driver-550 \
    cuda-toolkit-12-4 \
    && rm -rf /var/lib/apt/lists/*

ENV PATH="/usr/local/cuda-12.4/bin:${PATH}"
ENV LD_LIBRARY_PATH="/usr/local/cuda-12.4/lib64:${LD_LIBRARY_PATH}"

# live-boot teaches this kernel's initramfs how to boot from a squashfs on
# removable media (boot=live) — see .github/workflows/build-image-rtx4090.yml,
# which packs this rootfs into /live/filesystem.squashfs on the ISO/USB.
RUN apt-get update && apt-get install -y --no-install-recommends live-boot && \
    rm -rf /var/lib/apt/lists/* && \
    update-initramfs -u -k all

# Setup ComfyUI
WORKDIR /opt/comfyui
RUN git clone https://github.com/comfyanonymous/ComfyUI.git . && \
    python3 -m venv venv && \
    . venv/bin/activate && \
    pip install --upgrade pip wheel setuptools && \
    # CUDA 12.4 PyTorch wheels
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124 && \
    # Install ComfyUI dependencies
    pip install -r requirements.txt 2>&1 | tail -20

# Create systemd service
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

# Enable ComfyUI on boot (no running systemd inside the build container, so
# `systemctl enable` isn't available — symlink it directly instead).
RUN mkdir -p /etc/systemd/system/multi-user.target.wants && \
    ln -s /etc/systemd/system/comfyui.service \
          /etc/systemd/system/multi-user.target.wants/comfyui.service

# network-manager and openssh-server enable themselves via their own
# postinst scripts (deb-systemd-helper) when installed with apt above —
# no manual symlink needed for those two.

# WiFi Configuration - WPA2 supplicant
RUN mkdir -p /etc/wpa_supplicant && \
    cat > /etc/wpa_supplicant/wpa_supplicant-wlan0.conf <<'WIFIEOF' && \
    chmod 600 /etc/wpa_supplicant/wpa_supplicant-wlan0.conf
ctrl_interface=/run/wpa_supplicant
update_config=1

# Example network block - will be configured at boot
# network={
#     ssid="YOUR_WIFI_SSID"
#     psk="YOUR_WIFI_PASSWORD"
#     key_mgmt=WPA-PSK
# }
WIFIEOF

# Boot setup script for WiFi interactive config
RUN cat > /usr/local/bin/setup-wifi.sh <<'SETUPEOF' && \
    chmod +x /usr/local/bin/setup-wifi.sh
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

# Boot script that configures WiFi if not already connected
RUN mkdir -p /etc/systemd/system-preset && \
    cat > /etc/systemd/system-preset/80-comfyui.preset <<'PRESETEOF'
enable comfyui.service
enable NetworkManager.service
enable ssh.service
PRESETEOF

# Start script for first-time WiFi setup
RUN cat > /usr/local/bin/comfyui-first-boot.sh <<'FIRSTBOOTEOF' && \
    chmod +x /usr/local/bin/comfyui-first-boot.sh
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

# Set hostname
RUN echo "comfyui-server" > /etc/hostname

# Root password - CHANGE THIS!
RUN echo "root:comfyui" | chpasswd

# Enable SSH for remote access, allow root login with password (live/appliance image)
RUN ssh-keygen -A && \
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config

# Prepare ComfyUI models directory structure
RUN mkdir -p /opt/comfyui/models/{checkpoints,loras,vae,embeddings,controlnet,upscale_models} && \
    chmod -R 755 /opt/comfyui/models

# Create logs directory
RUN mkdir -p /var/log/comfyui && \
    touch /var/log/comfyui/comfyui.log

# NVIDIA setup verification - test CUDA availability
RUN cat > /usr/local/bin/check-gpu.sh <<'GPUEOF' && \
    chmod +x /usr/local/bin/check-gpu.sh
#!/bin/bash
echo "=== GPU Check ==="
nvidia-smi
echo ""
echo "=== CUDA Info ==="
/opt/comfyui/venv/bin/python -c "import torch; print(f'CUDA Available: {torch.cuda.is_available()}'); print(f'GPU Count: {torch.cuda.device_count()}'); print(f'GPU 0: {torch.cuda.get_device_name(0) if torch.cuda.is_available() else \"N/A\"}')"
GPUEOF

EXPOSE 8188 22

CMD ["/sbin/init"]
