#!/bin/bash

echo "==========================================================="
echo "  KICH BAN CAI DAT: PROXMOX - CEPH PROMETHEUS DECO - DMS"
echo "==========================================================="
echo ""

# 1. Kiem tra Docker va Docker Compose
if ! command -v docker &> /dev/null; then
    echo "❌ Khong tim thay Docker! Vui long cai dat Docker truoc khi chay script."
    exit 1
fi

if ! docker compose version &> /dev/null && ! docker-compose --version &> /dev/null; then
    echo "❌ Khong tim thay Docker Compose! Vui long cai dat Docker Compose."
    exit 1
fi

echo "✅ Da tim thay Docker va Docker Compose."

# 2. Kiem tra file cau hinh credentials
CREDENTIALS_FILE="proxmox_credentials.yml"
if [ ! -f "$CREDENTIALS_FILE" ] || grep -q "PLEASE_ENTER_YOUR_SECRET_TOKEN_HERE" "$CREDENTIALS_FILE"; then
    echo "⚠️ Yeu cau cau hinh thong tin ket noi Proxmox API:"
    
    read -p "🔹 Nhap IP may chu Proxmox (Vi du: 10.8.10.21): " PVE_IP
    read -p "🔹 Nhap User name (Mac dinh: root@pam): " PVE_USER
    PVE_USER=$${PVE_USER:-root@pam}
    read -p "🔹 Nhap Token Name (Vi du: monitor-grafana): " PVE_TOKEN_NAME
    read -p "🔹 Nhap Token Value (Secret Key): " PVE_TOKEN_VALUE

    if [ -z "$PVE_TOKEN_VALUE" ] || [ -z "$PVE_IP" ] || [ -z "$PVE_TOKEN_NAME" ]; then
        echo "❌ Loi: Ban khong duoc de trong IP, Token Name hoac Token Value!"
        exit 1
    fi

    echo "Dang tao file cau hinh $CREDENTIALS_FILE..."
    cat <<EOF > $CREDENTIALS_FILE
default:
  user: $PVE_USER
  token_name: $PVE_TOKEN_NAME
  token_value: $PVE_TOKEN_VALUE
  verify_ssl: false
  api_host: $PVE_IP
EOF
    echo "✅ Da luu cau hinh ket noi!"
fi

echo "✅ Da tim thay cau hinh Token hop le."

# 3. Khoi tao thu muc metrics neu chua co
if [ ! -d "metrics" ]; then
    echo "📁 Dang tao thu muc ./metrics..."
    mkdir -p metrics
    chmod 777 metrics
fi

# 4. Chay Docker Compose
echo "🚀 Dang khoi dong he thong Exporter..."
docker compose up -d --build --force-recreate

# 5. Kiem tra trang thai
echo "==========================================================="
echo "✅ HOAN TAT! Dang kiem tra trang thai cac dich vu..."
echo "==========================================================="
sleep 3
docker compose ps

echo ""
echo "🎯 BUOC TIEP THEO:"
echo "1. Neu cac dich vu (pve-exporter, ha-exporter, node-exporter) deu bao 'Up', he thong da chay tot."
echo "2. Kiem tra file metrics tu dong sinh ra trong thu muc ./metrics"
echo "3. Vao Grafana Import file Dashboard JSON de xem ket qua."
