#!/data/data/com.termux/files/usr/bin/bash

if [[ -d "/storage/emulated/0/Download" ]]; then
  export IDM_DOWNLOAD_DIR="/storage/emulated/0/Download"
elif [[ -d "/sdcard/Download" ]]; then
  export IDM_DOWNLOAD_DIR="/sdcard/Download"
fi
