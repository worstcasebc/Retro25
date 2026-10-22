# SPDX-License-Identifier: GPL-3.0-or-later
# Bauumgebung für Main_MiSTer: dasselbe Ubuntu (22.04, gcc 11) wie auf dem
# DE25-Nano, aber als arm64-Container auf dem PC (Docker Desktop führt
# arm64 per QEMU aus). Das Ergebnis läuft unverändert auf dem Board.
# Gebaut und benutzt von tools/build_main.py (Image-Name retro25-arm64).
FROM --platform=linux/arm64 ubuntu:22.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
        build-essential libimlib2-dev libfreetype-dev libpng-dev \
        libbz2-dev zlib1g-dev libbluetooth-dev patch \
    && rm -rf /var/lib/apt/lists/*
