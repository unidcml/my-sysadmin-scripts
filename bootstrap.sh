#!/bin/bash
set -eu

if [ "$EUID" -ne 0 ]; then
    echo "Запустите скрипт через sudo" >&2
    exit 1
fi

PROJECT_DIR=$(cd "$(dirname "$0")" && pwd)
export DEBIAN_FRONTEND=noninteractive

if [ ! -s /etc/ssl/certs/my-app.crt ] || [ ! -s /etc/ssl/private/my-app.key ]; then
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/private/my-app.key \
        -out /etc/ssl/certs/my-app.crt \
        -subj "/CN=my-app.local"
fi

apt-get update
apt-get install -y docker.io mdadm lvm2 nginx curl
systemctl enable --now docker

docker build -t my-script "$PROJECT_DIR"

attach_loop() {
    local image=$1
    local device
    device=$(losetup -j "$image" | head -n 1 | cut -d: -f1)
    if [ -z "$device" ]; then
        device=$(losetup -fP --show "$image")
    fi
    echo "$device"
}

mkdir -p /mnt/raid-lab /mnt/raid /mnt/logs

if ! mountpoint -q /mnt/raid; then
    for image in disk1.img disk2.img; do
        if [ ! -f "/mnt/raid-lab/$image" ]; then
            dd if=/dev/zero "of=/mnt/raid-lab/$image" bs=1M count=512 status=none
        fi
    done
    LOOP1=$(attach_loop /mnt/raid-lab/disk1.img)
    LOOP2=$(attach_loop /mnt/raid-lab/disk2.img)
    if [ ! -b /dev/md0 ]; then
        yes | mdadm --create /dev/md0 --level=1 --raid-devices=2 "$LOOP1" "$LOOP2"
        udevadm settle
    fi
    if ! blkid /dev/md0 >/dev/null; then
        mkfs.ext4 /dev/md0
    fi
    mount /dev/md0 /mnt/raid
fi

if ! mountpoint -q /mnt/logs; then
    if [ ! -f /mnt/raid-lab/disk3.img ]; then
        dd if=/dev/zero of=/mnt/raid-lab/disk3.img bs=1M count=512 status=none
    fi
    LOOP3=$(attach_loop /mnt/raid-lab/disk3.img)
    if ! pvs "$LOOP3" >/dev/null 2>&1; then
        yes | pvcreate "$LOOP3"
    fi
    if ! vgs vg_data >/dev/null 2>&1; then
        vgcreate vg_data "$LOOP3"
    fi
    if ! lvs /dev/vg_data/lv_logs >/dev/null 2>&1; then
        yes | lvcreate -L 200M -n lv_logs vg_data
        udevadm settle
    fi
    if ! blkid /dev/vg_data/lv_logs >/dev/null; then
        mkfs.ext4 /dev/vg_data/lv_logs
    fi
    mount /dev/vg_data/lv_logs /mnt/logs
fi

install -m 644 "$PROJECT_DIR/my-app.conf" /etc/nginx/sites-available/my-app
ln -sfn /etc/nginx/sites-available/my-app /etc/nginx/sites-enabled/my-app
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable nginx
systemctl restart nginx

install -m 644 "$PROJECT_DIR/my-app.service" /etc/systemd/system/my-app.service
systemctl daemon-reload
systemctl stop my-app 2>/dev/null || true
docker rm -f my-app 2>/dev/null || true
docker run -d -p 8080:8080 --name my-app my-script
systemctl enable my-app
systemctl restart my-app
sleep 3
curl --fail --silent --show-error --insecure --head https://127.0.0.1 >/dev/null
