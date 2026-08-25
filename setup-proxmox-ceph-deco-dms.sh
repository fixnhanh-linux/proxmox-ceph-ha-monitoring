#!/bin/bash

echo "==========================================================="
echo "  KICH BAN CAI DAT NANG CAO: PROXMOX - CEPH HA MONITORING"
echo "==========================================================="
echo ""

# 1. Kiem tra Docker va Docker Compose
if ! command -v docker &> /dev/null; then
    echo "❌ Khong tim thay Docker! Vui long cai dat Docker truoc khi chay script."
    exit 1
fi
echo "✅ Da tim thay Docker."

# Ham kiem tra cong (Port checking)
check_port() {
    local port=$1
    if command -v ss &> /dev/null; then
        ss -tuln | awk '{print $5}' | grep -qE ":$port$"
    elif command -v netstat &> /dev/null; then
        netstat -tuln | awk '{print $4}' | grep -qE ":$port$"
    else
        return 1
    fi
}

# 2. Thu thap thong tin cau hinh tu nguoi dung
echo "⚠️ Yeu cau cau hinh thong tin he thong:"

read -p "🔹 Nhap Ten Project (Mac dinh: dms-monitoring): " PROJECT_NAME
PROJECT_NAME=${PROJECT_NAME:-dms-monitoring}

if docker ps -a --format '{{.Names}}' | grep -q "${PROJECT_NAME}"; then
    echo "⚠️ Phat hien cac container cua project '${PROJECT_NAME}' dang ton tai!"
    read -p "❓ Ban co muon xoa va tai tao lai khong? (y/n, Mac dinh: y): " REBUILD
    REBUILD=${REBUILD:-y}
    if [[ "$REBUILD" == "y" || "$REBUILD" == "Y" ]]; then
        docker compose -p "${PROJECT_NAME}" down 2>/dev/null || true
    else
        echo "🛑 Da huy cai dat do xoa project bi tu choi."
        exit 0
    fi
fi

read -p "🔹 Nhap IP may chu Proxmox (Vi du: 10.8.10.21): " PVE_IP
read -p "🔹 Nhap User name (Mac dinh: root@pam): " PVE_USER
PVE_USER=${PVE_USER:-root@pam}
read -p "🔹 Nhap Token Name (Vi du: monitor-grafana): " PVE_TOKEN_NAME
read -p "🔹 Nhap Token Value (Secret Key): " PVE_TOKEN_VALUE

if [ -z "$PVE_TOKEN_VALUE" ] || [ -z "$PVE_IP" ] || [ -z "$PVE_TOKEN_NAME" ]; then
    echo "❌ Loi: Ban khong duoc de trong IP, Token Name hoac Token Value!"
    exit 1
fi

PVE_PORT=9224
NODE_PORT=9393

echo "🔍 Dang kiem tra cong mang tren he thong..."
while check_port $PVE_PORT; do
    echo "⚠️ Cong $PVE_PORT (PVE Exporter) da bi chiem! Tu dong thu cong $((PVE_PORT+1))..."
    PVE_PORT=$((PVE_PORT+1))
done
echo "✅ Da chon cong $PVE_PORT cho PVE Exporter."

while check_port $NODE_PORT; do
    echo "⚠️ Cong $NODE_PORT (Node Exporter) da bi chiem! Tu dong thu cong $((NODE_PORT+1))..."
    NODE_PORT=$((NODE_PORT+1))
done
echo "✅ Da chon cong $NODE_PORT cho Node Exporter."

# 3. Tao file credentials
CREDENTIALS_FILE="proxmox_credentials.yml"
echo "Dang tao file cau hinh $CREDENTIALS_FILE..."
cat <<EOF > $CREDENTIALS_FILE
default:
  user: $PVE_USER
  token_name: $PVE_TOKEN_NAME
  token_value: $PVE_TOKEN_VALUE
  verify_ssl: false
  api_host: $PVE_IP
EOF

# 4. Tu dong tao file docker-compose.yml
echo "Dang tu dong sinh ra file docker-compose.yml moi..."
cat <<EOF > docker-compose.yml
version: "3.9"
services:
  pve-exporter:
    image: prompve/prometheus-pve-exporter:latest
    container_name: ${PROJECT_NAME}-pve-exporter
    volumes:
      - ./proxmox_credentials.yml:/etc/prometheus/pve.yml:ro
    ports:
      - "${PVE_PORT}:9221"
    restart: unless-stopped
  node-exporter:
    image: prom/node-exporter:latest
    container_name: ${PROJECT_NAME}-node-exporter
    volumes:
      - ./metrics:/etc/node-exporter:ro
    command:
      - '--collector.textfile.directory=/etc/node-exporter'
    ports:
      - "${NODE_PORT}:9100"
    restart: unless-stopped
  ha-exporter:
    image: alpine:latest
    container_name: ${PROJECT_NAME}-ha-exporter
    command:
      - /bin/sh
      - -c
      - |
        apk add --no-cache curl jq bash
        USER_VAL=\$\$(awk '/user:/ {print \$\$2}' /config.yml | tr -d '\r')
        NAME_VAL=\$\$(awk '/token_name:/ {print \$\$2}' /config.yml | tr -d '\r')
        TOKEN_VAL=\$\$(awk '/token_value:/ {print \$\$2}' /config.yml | tr -d '\r')
        PVE_API_TOKEN="\$\$USER_VAL!\$\$NAME_VAL=\$\$TOKEN_VAL"
        PVE_API_HOST=\$\$(awk '/api_host:/ {print \$\$2}' /config.yml | tr -d '\r')
        if [ -z "\$\$PVE_API_HOST" ]; then PVE_API_HOST="10.8.10.21"; fi
        while true; do
          JSON_DATA=\$\$(curl -s -k -H "Authorization: PVEAPIToken=\$\$PVE_API_TOKEN" "https://\$\$PVE_API_HOST:8006/api2/json/cluster/ha/groups")
          if [ -n "\$\$JSON_DATA" ] && echo "\$\$JSON_DATA" | jq -e . >/dev/null 2>&1; then
            DATA_SPLIT=\$\$(echo "\$\$JSON_DATA" | jq -r '.data[]? | .group as \$\$g | .nodes | split(",")[]? | "pve_ha_group_custom_info{group=\"\(\$\$g)\",host=\"\(.)\"} 1"')
            DATA_MERGED=\$\$(echo "\$\$JSON_DATA" | jq -r '.data[]? | "pve_ha_group_custom_info_merged{group=\"" + .group + "\",nodes=\"" + .nodes + "\"} 1"')
            echo "# HELP pve_ha_group_custom_info HA group info split by host" > /metrics/pve_ha.prom.tmp
            echo "# TYPE pve_ha_group_custom_info gauge" >> /metrics/pve_ha.prom.tmp
            echo "\$\$DATA_SPLIT" >> /metrics/pve_ha.prom.tmp
            echo "# HELP pve_ha_group_custom_info_merged HA group info with all nodes" >> /metrics/pve_ha.prom.tmp
            echo "# TYPE pve_ha_group_custom_info_merged gauge" >> /metrics/pve_ha.prom.tmp
            echo "\$\$DATA_MERGED" >> /metrics/pve_ha.prom.tmp
            mv /metrics/pve_ha.prom.tmp /metrics/pve_ha.prom
          fi
          CLUSTER_STATUS=\$\$(curl -s -k -H "Authorization: PVEAPIToken=\$\$PVE_API_TOKEN" "https://\$\$PVE_API_HOST:8006/api2/json/cluster/status")
          if [ -n "\$\$CLUSTER_STATUS" ] && echo "\$\$CLUSTER_STATUS" | jq -e . >/dev/null 2>&1; then
            NODE_IPS=\$\$(echo "\$\$CLUSTER_STATUS" | jq -r '.data[]? | select(.type=="node" and .online==1) | .ip')
            if [ -n "\$\$NODE_IPS" ]; then
              PVE_TARGETS=\$\$(echo "\$\$NODE_IPS" | jq -R . | jq -s '[{targets: .}]')
              echo "\$\$PVE_TARGETS" > /metrics/proxmox_targets.json.tmp
              mv /metrics/proxmox_targets.json.tmp /metrics/proxmox_targets.json
              CEPH_TARGETS=\$\$(echo "\$\$NODE_IPS" | awk '{print \$\$1":9283"}' | jq -R . | jq -s '[{targets: .}]')
              echo "\$\$CEPH_TARGETS" > /metrics/ceph_targets.json.tmp
              mv /metrics/ceph_targets.json.tmp /metrics/ceph_targets.json
            fi
          fi
          sleep 15
        done
    volumes:
      - ./metrics:/metrics
      - ./proxmox_credentials.yml:/config.yml:ro
    restart: unless-stopped
EOF
echo "✅ Da tao xong file docker-compose.yml"

if [ ! -d "metrics" ]; then
    echo "📁 Dang tao thu muc ./metrics..."
    mkdir -p metrics
    chmod 777 metrics
fi

# 5. Chay Docker Compose
echo "🚀 Dang khoi dong he thong Exporter..."
docker compose -p "${PROJECT_NAME}" up -d --build --force-recreate

# 6. Kiem tra trang thai
echo "==========================================================="
echo "✅ HOAN TAT! Dang kiem tra trang thai cac dich vu..."
echo "==========================================================="
sleep 3
docker compose -p "${PROJECT_NAME}" ps

echo ""
# 7. Tu dong tao file cho Prometheus scrape_configs
SCRAPE_DIR="/etc/prometheus/scrape_configs"
if [ -d "$SCRAPE_DIR" ]; then
    SCRAPE_FILE="$SCRAPE_DIR/${PROJECT_NAME}.yml"
    CURRENT_DIR=$(pwd)
    CURRENT_IP=$(hostname -I | awk '{print $1}')
    
    echo "📝 Dang tu dong tao cau hinh Prometheus tai $SCRAPE_FILE ..."
    cat <<EOF > "$SCRAPE_FILE"
  - job_name: '${PROJECT_NAME}-proxmox'
    metrics_path: /pve
    file_sd_configs:
      - files:
        - '${CURRENT_DIR}/metrics/proxmox_targets.json'
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: ${CURRENT_IP}:${PVE_PORT}

  - job_name: '${PROJECT_NAME}-ceph'
    file_sd_configs:
      - files:
        - '${CURRENT_DIR}/metrics/ceph_targets.json'

  - job_name: '${PROJECT_NAME}-node_exporter_ha'
    static_configs:
      - targets:
        - '${CURRENT_IP}:${NODE_PORT}'
EOF
    echo "✅ Da tao xong file $SCRAPE_FILE!"
    
    echo "🔄 Dang gui lenh Reload den Prometheus..."
    curl -s -X POST http://localhost:9090/-/reload
    echo "✅ Prometheus da duoc cap nhat (Reload) thanh cong!"
else
    echo "🎯 THONG TIN CAU HINH QUAN TRONG:"
    echo "Khong tim thay thu muc $SCRAPE_DIR."
    echo "Hay cap nhat file prometheus.yml cho cac targets sau:"
    echo "  - PVE Exporter Port: ${PVE_PORT}"
    echo "  - Node Exporter Port: ${NODE_PORT}"
fi
