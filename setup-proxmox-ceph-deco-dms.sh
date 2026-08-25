#!/bin/bash

echo "==========================================================="
echo "  KỊCH BẢN CÀI ĐẶT: PROXMOX - CEPH PROMETHEUS DECO - DMS"
echo "==========================================================="
echo ""

# 1. Kiểm tra Docker và Docker Compose
if ! command -v docker &> /dev/null; then
    echo "❌ Không tìm thấy Docker! Vui lòng cài đặt Docker trước khi chạy script."
    exit 1
fi

if ! docker compose version &> /dev/null && ! docker-compose --version &> /dev/null; then
    echo "❌ Không tìm thấy Docker Compose! Vui lòng cài đặt Docker Compose."
    exit 1
fi

echo "✅ Đã tìm thấy Docker và Docker Compose."

# 2. Kiểm tra file cấu hình credentials
CREDENTIALS_FILE="proxmox_credentials.yml"
if [ ! -f "$CREDENTIALS_FILE" ]; then
    echo "⚠️ Không tìm thấy file $CREDENTIALS_FILE!"
    echo "Đang tạo file mẫu $CREDENTIALS_FILE..."
    cat <<EOF > $CREDENTIALS_FILE
default:
  user: root@pam
  token_name: monitor-grafana
  token_value: PLEASE_ENTER_YOUR_SECRET_TOKEN_HERE
  verify_ssl: false
  api_host: 10.8.10.21 # <-- Nhập IP máy chủ Proxmox của bạn vào đây
EOF
    echo "❌ Đã tạo file mẫu $CREDENTIALS_FILE."
    echo "VUI LÒNG: Mở file $CREDENTIALS_FILE, điền đúng 'token_value' của bạn rồi chạy lại script này!"
    exit 1
fi

# Kiểm tra xem người dùng đã đổi token mẫu chưa
if grep -q "PLEASE_ENTER_YOUR_SECRET_TOKEN_HERE" "$CREDENTIALS_FILE"; then
    echo "❌ BẠN CHƯA ĐIỀN TOKEN! Vui lòng mở file $CREDENTIALS_FILE và cập nhật 'token_value' trước khi build hệ thống."
    exit 1
fi

echo "✅ Đã tìm thấy cấu hình Token hợp lệ."

# 3. Khởi tạo thư mục metrics nếu chưa có
if [ ! -d "metrics" ]; then
    echo "📁 Đang tạo thư mục ./metrics..."
    mkdir -p metrics
    chmod 777 metrics
fi

# 4. Chạy Docker Compose
echo "🚀 Đang khởi động hệ thống Exporter..."
docker compose up -d --build --force-recreate

# 5. Kiểm tra trạng thái
echo "==========================================================="
echo "✅ HOÀN TẤT! Đang kiểm tra trạng thái các dịch vụ..."
echo "==========================================================="
sleep 3
docker compose ps

echo ""
echo "🎯 BƯỚC TIẾP THEO:"
echo "1. Nếu các dịch vụ (pve-exporter, ha-exporter, node-exporter) đều báo 'Up', hệ thống đã chạy tốt."
echo "2. Hãy copy nội dung file prometheus/prometheus.yml dán vào máy chủ Prometheus của bạn và restart Prometheus."
echo "3. Vào Grafana Import file Dashboard JSON để xem kết quả."
