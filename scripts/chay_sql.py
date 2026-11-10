"""Chạy file .sql (tách theo dòng GO) trên một instance. Dùng: python3 -I scripts/chay_sql.py <cổng> <file.sql> [...]
Cổng: 14330 điều phối, 14331 CNTT, 14332 Ngoại ngữ, 14333 Du lịch. Đăng nhập sa, mật khẩu trong .env.
Tùy chọn --bien=TEN=GIATRI,...: điền biến kiểu SQLCMD $(TEN) trong file, ví dụ cho 02a_create_node.sql:
    python3 -I scripts/chay_sql.py 14331 database/02a_create_node.sql --bien=NODE_DB=QLSV_CNTT,MA_KHOA=CNTT"""
import os, re, sys, time, pyodbc

def mat_khau():
    """Mật khẩu sa: biến môi trường MSSQL_SA_PASSWORD, hoặc dòng cùng tên trong file .env ở thư mục gốc dự án."""
    if os.environ.get("MSSQL_SA_PASSWORD"):
        return os.environ["MSSQL_SA_PASSWORD"]
    env = os.path.join(os.path.dirname(__file__), "..", ".env")
    if os.path.exists(env):
        for dong in open(env, encoding="utf-8"):
            if dong.startswith("MSSQL_SA_PASSWORD="):
                return dong.split("=", 1)[1].strip()
    raise SystemExit("Chưa có mật khẩu sa: sao chép .env.example thành .env và đặt MSSQL_SA_PASSWORD")

def ket_noi(cong, csdl="master", timeout=30):
    return pyodbc.connect("DRIVER={ODBC Driver 18 for SQL Server};SERVER=localhost,%s;UID=sa;PWD={%s};"
                          "TrustServerCertificate=yes;DATABASE=%s" % (cong, mat_khau(), csdl), autocommit=True, timeout=timeout)

def doi_san_sang(cong, giay=240):
    """Đợi instance ở cổng này nhận kết nối (sau docker compose up hoặc docker start)."""
    han = time.time() + giay
    while True:
        try:
            ket_noi(cong, timeout=3).close(); return
        except pyodbc.Error:
            if time.time() > han:
                raise SystemExit(f"Instance cổng {cong} không sẵn sàng sau {giay} giây (docker compose ps?)")
            time.sleep(3)

def chay(cong, tep, bien=None):
    van_ban = open(tep, encoding="utf-8-sig").read()
    for ten, gia_tri in {"SA_MATKHAU": mat_khau().replace("'", "''"), **(bien or {})}.items():
        van_ban = van_ban.replace(f"$({ten})", gia_tri)                     # biến kiểu SQLCMD
    thieu = re.search(r"\$\(\w+\)", van_ban)
    if thieu:
        raise SystemExit(f"{tep}: chưa có giá trị cho biến {thieu.group(0)} (dùng --bien=TEN=GIATRI)")
    c = ket_noi(cong)
    c.add_output_converter(-9, lambda b: b.decode("utf-16le", "replace"))
    q = c.cursor()
    for lo in re.split(r"^\s*GO\s*$", van_ban, flags=re.M | re.I):
        if not lo.strip():
            continue
        try:
            q.execute(lo)
            while True:
                if q.description:
                    for r in q.fetchall():
                        print(" | ".join(str(x) for x in r))
                for m in q.messages or []:
                    print(m[1].split("]")[-1])
                if not q.nextset():
                    break
        except pyodbc.Error as e:
            print("LỖI:", str(e)[:400]); raise SystemExit(1)

if __name__ == "__main__":
    bien = dict(cap.split("=", 1) for a in sys.argv if a.startswith("--bien=") for cap in a[7:].split(","))
    for t in [a for a in sys.argv[2:] if not a.startswith("--")]:
        print("==", t); chay(sys.argv[1], t, bien)
