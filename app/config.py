"""Cấu hình kết nối. Chỉ cần sửa file này khi chạy trên máy khác."""
import os

SERVER = os.getenv("QLSV_SERVER", "localhost")        # ví dụ: localhost\SQLEXPRESS
DATABASE = "QLSV_TongHop"                              # ứng dụng chỉ nói chuyện với node điều phối
DRIVER = os.getenv("QLSV_DRIVER", "ODBC Driver 18 for SQL Server")   # hoặc "ODBC Driver 17 for SQL Server"
