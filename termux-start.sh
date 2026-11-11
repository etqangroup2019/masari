#!/data/data/com.termux/files/usr/bin/bash
# Masari audio server for Termux (Android). One command to install, update and run.
#   first time:  curl -L https://raw.githubusercontent.com/etqangroup2019/masari/main/termux-start.sh | bash
#   next times:  ~/masari/start.sh
set -e
RAW="https://raw.githubusercontent.com/etqangroup2019/masari/main"
DIR="$HOME/masari"
mkdir -p "$DIR"
cd "$DIR"
if ! command -v python >/dev/null 2>&1; then
  pkg update -y
  pkg install -y python
fi
echo "Installing / updating yt-dlp ..."
pip install -q -U yt-dlp
echo "Downloading the latest server.py ..."
curl -fsSL "$RAW/server.py" -o server.py
curl -fsSL "$RAW/termux-start.sh" -o start.sh && chmod +x start.sh
command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock || true
echo
echo "Server is starting on http://localhost:8787 - keep Termux running while you listen."
exec python server.py 8787
