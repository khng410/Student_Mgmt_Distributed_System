"""Dựng lại toàn bộ hệ thống trên 4 instance Docker (docker compose up -d trước). Dùng: python3 -I scripts/trien_khai.py
Thứ tự: 3 instance node tạo database và bảng của mình (02a), rồi mọi file còn lại chạy trên instance điều phối."""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from chay_sql import chay, doi_san_sang

D = os.path.join(os.path.dirname(__file__), "..", "database")
f = lambda n: os.path.join(D, n)
NODE = {14331: ("QLSV_CNTT", "CNTT"), 14332: ("QLSV_NgoaiNgu", "NN"), 14333: ("QLSV_DuLich", "DL")}
TH = 14330
for cong in [TH, *NODE]:
    doi_san_sang(cong)                              # sau docker compose up, SQL Server cần vài chục giây để sẵn sàng

for cong, (db, khoa) in NODE.items():               # mỗi instance node: database và bảng của một khoa
    print("== 02a_create_node.sql", db); chay(cong, f("02a_create_node.sql"), {"NODE_DB": db, "MA_KHOA": khoa})
for t in ["02_create_tables.sql", "02b_node_links.sql", "03_seed_data.sql", "04_fragmentation.sql", "05_views.sql", "06_queries_40.sql",
          "07_procedures.sql", "08_functions.sql", "09_triggers.sql", "10_security.sql",
          "11_transactions_concurrency.sql", "12_linked_server.sql", "13_dong_bo_kiem_thu.sql"][:int(sys.argv[1]) if len(sys.argv) > 1 else 99]:
    print("==", t); chay(TH, f(t))
print("\nXONG: đã dựng lại 4 instance và chạy hết các file SQL, không có lỗi. Kiểm tra kết quả demo: python3 -I scripts/kiem_tra_demo.py")
