"""Cấu hình kết nối. Chỉ cần sửa file này khi chạy trên máy khác."""
import os

SERVER = os.getenv("QLSV_SERVER", "localhost,14330")   # instance điều phối trong Docker (docker-compose.yml)
DATABASE = "QLSV_TongHop"                              # ứng dụng chỉ nói chuyện với node điều phối
DRIVER = os.getenv("QLSV_DRIVER", "ODBC Driver 18 for SQL Server")   # hoặc "ODBC Driver 17 for SQL Server"
PHIEN_PHUT = int(os.getenv("QLSV_PHIEN_PHUT", "0"))      # số phút không dùng thì phiên đăng nhập hết hạn; 0 = không giới hạn
