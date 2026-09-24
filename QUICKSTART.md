# Quick Start - 5 Minutes to Bootable USB

## Step 1: Create GitHub Repo (1 min)

```bash
# Create new repo on github.com
# Choose: "New repository"
# Name: comfyui-usb-builder
# Make it Public (so Actions runs free)
# Click "Create repository"
```

## Step 2: Clone and Add Files (2 min)

```bash
git clone https://github.com/yourusername/comfyui-usb-builder.git
cd comfyui-usb-builder

# Copy these files from scratchpad:
# - Dockerfile
# - .github/workflows/build-image.yml
# - README.md
# - QUICKSTART.md
# - LICENSE
# - .gitignore

# If using this guide:
git add .
git commit -m "Initial ComfyUI USB builder setup"
git push origin main
```

## Step 3: Watch GitHub Actions Build (2 min)

1. Go to your repo on GitHub.com
2. Click **Actions** tab
3. You should see "Build ComfyUI USB/ISO Image" running
4. Wait for checkmark ✅ (takes ~5-10 minutes)

## Step 4: Download Image (immediately available after build)

1. Click the completed workflow run
2. Scroll to **Artifacts** section
3. Download `comfyui-usb-images`
4. Extract the ZIP file
5. You now have `.iso.gz` — a single hybrid image, `dd`-able straight to a USB stick

## Step 5: Write to USB (1 min)

### macOS
```bash
cd ~/Downloads
gunzip comfyui-server.iso.gz

# Find your USB device
diskutil list

# Unmount (replace disk2 with yours)
diskutil unmountDisk /dev/disk2

# Write image
sudo dd if=comfyui-server.iso of=/dev/rdisk2 bs=4m status=progress
```

### Linux
```bash
cd ~/Downloads
gunzip comfyui-server.iso.gz

# Find your USB device
lsblk

# Unmount (replace sdb1 with yours)
sudo umount /dev/sdb1

# Write image
sudo dd if=comfyui-server.iso of=/dev/sdb bs=4M status=progress
```

### Windows
1. Download [Balena Etcher](https://www.balena.io/etcher/)
2. Open Etcher
3. Select extracted `comfyui-server.iso`
4. Select USB device
5. Click Flash

---

## Done! 🎉

**Next**: Plug USB into your PC and boot it up.

After boot:
- ComfyUI starts automatically
- Find IP: `ip addr show`
- Open web UI: `http://<ip>:8188`
- Connect from your Mac!

### Default Login
- **User**: root
- **Password**: comfyui

⚠️ **Change password immediately!**

---

## Troubleshooting Quick Tips

**Image won't boot?**
- Make sure USB is fully unmounted before writing
- Re-`dd` the image; a partial/interrupted write is the most common cause

**Can't access web UI?**
- Check server IP: `ip addr show`
- Make sure you're on same WiFi/network
- Try `ping <server-ip>`

**ComfyUI not starting?**
```bash
ssh root@<server-ip>
systemctl status comfyui
```

---

## Next Steps

1. Edit `Dockerfile` to customize:
   - Default password
   - Startup flags (`--highvram`, etc)
   - Additional packages

2. Push changes:
   ```bash
   git add Dockerfile
   git commit -m "Customize ComfyUI settings"
   git push origin main
   ```

3. New build runs automatically!

---

See **README.md** for full documentation.
