"""Mô phỏng một node mất kết nối rồi phục hồi (cần 4 container đang chạy và đã chạy trien_khai.py).
Dùng: python3 -I scripts/thu_mat_ket_noi.py [container]      (mặc định qlsv_dulich: khoa Du lịch)
Kịch bản: dừng container -> thử đọc/ghi từ điều phối -> sửa danh mục ở điều phối lúc node vắng
-> bật lại container -> đồng bộ lại (sp_DongBoDanhMuc) -> kiểm tra bản sao khớp bản chính."""
import os, subprocess, sys, time, pyodbc
sys.path.insert(0, os.path.dirname(__file__))
from chay_sql import ket_noi, doi_san_sang

NODE = sys.argv[1] if len(sys.argv) > 1 else "qlsv_dulich"
K = {"qlsv_cntt": "CNTT", "qlsv_ngoaingu": "NN", "qlsv_dulich": "DL"}[NODE]
DB = {"CNTT": "QLSV_CNTT", "NN": "QLSV_NgoaiNgu", "DL": "QLSV_DuLich"}[K]
LS = "LS_" + DB
CONG_NODE = {"qlsv_cntt": 14331, "qlsv_ngoaingu": 14332, "qlsv_dulich": 14333}[NODE]
BUOC = [0]

def chay(mo_ta, sql, tham_so=()):
    """Chạy 1 câu trên điều phối, in KẾT QUẢ hoặc LỖI (không dừng chương trình)."""
    BUOC[0] += 1
    t = time.time()
    try:
        c = ket_noi(14330, "QLSV_TongHop")
        q = c.cursor(); q.execute("SET XACT_ABORT ON; SET LOCK_TIMEOUT 20000;"); q.execute(sql, tham_so)
        rows = []
        while True:
            if q.description: rows = [tuple(r) for r in q.fetchall()]
            if not q.nextset(): break
        kq, ct = "OK  ", rows[:3]
    except pyodbc.Error as e:
        kq, ct = "LỖI", str(e.args[-1]).split("[SQL Server]")[-1].rsplit(" (", 2)[0][:260]
    finally:
        if "c" in locals():
            c.close()
    print(f"[{BUOC[0]:>2}] {kq} ({time.time()-t:4.1f}s) {mo_ta}\n       -> {ct}")
    return kq.strip() == "OK", ct

def docker(lenh):
    subprocess.run(["docker", lenh, NODE], check=True, capture_output=True)

KHOP = (f"SELECT (SELECT COUNT(*) FROM (SELECT MaMH, TenMH, SoTinChi, LoaiMH, MaKhoa FROM dbo.MonHoc EXCEPT "
        f"SELECT MaMH, TenMH, SoTinChi, LoaiMH, MaKhoa FROM {DB}.dbo.MonHoc) a)")
ok, ten = chay("Lấy tên một môn của khoa " + K + " ở bản chính", "SELECT TOP (1) MaMH + '|' + TenMH FROM dbo.MonHoc WHERE MaKhoa = ?", (K,))
if not ok:
    raise SystemExit("Không đọc được điều phối (docker compose up -d và scripts/trien_khai.py chưa chạy?)")
ma, ten_cu = ten[0][0].split("|", 1)
ten_cu = ten_cu.replace(" (bản mới)", "")      # chạy lại sau một lần bị ngắt giữa chừng vẫn trả về đúng tên gốc
chay("Đưa tên môn về bản gốc (phòng lần chạy trước bị ngắt)", "UPDATE dbo.MonHoc SET TenMH = ? WHERE MaMH = ?", (ten_cu, ma))
chay("Đồng bộ bản sao trước khi bắt đầu", "EXEC dbo.sp_DongBoDanhMuc @MaKhoa = ?", (K,))

print(f"\n=== A. Trước khi sự cố: bản sao ở {DB} khớp bản chính? ===")
chay("Số môn khác nhau giữa bản chính và bản sao (mong đợi 0)", KHOP + " AS Lech")

print(f"\n=== B. Dừng {NODE} (docker stop) ===")
docker("stop")
chay(f"Đọc trực tiếp node vắng mặt qua tên 4 phần", f"SELECT COUNT(*) FROM {LS}.{DB}.dbo.SinhVien")
chay("VIEW toàn cục (cần đủ 3 node)", "SELECT COUNT(*) FROM dbo.vw_SinhVien_ToanCuc")
chay("Đọc thống kê của khoa còn lại (CNTT hoặc NN) trực tiếp: vẫn sống" , "SELECT COUNT(*) FROM LS_QLSV_NgoaiNgu.QLSV_NgoaiNgu.dbo.SinhVien" if K != "NN" else "SELECT COUNT(*) FROM LS_QLSV_CNTT.QLSV_CNTT.dbo.SinhVien")
chay("Đọc dữ liệu chỉ nằm ở điều phối (SinhVien_HoSo): vẫn sống", "SELECT COUNT(*) FROM dbo.SinhVien_HoSo")
chay("Thêm sinh viên (thủ tục tìm lớp ở cả 3 node)",
     "EXEC dbo.sp_ThemSinhVien @MaSV='24019998', @HoTen=N'Thử Mất Kết Nối', @NgaySinh='2006-01-01', @GioiTinh=N'Nam', "
     "@MaLop='66.CNTT-1', @CCCD='001306009998', @Email='24019998@sv.qlsv.edu.vn'")
chay("Giao dịch phân tán chạm node vắng: sửa 1 dòng ở điều phối rồi 1 dòng ở node",
     f"BEGIN DISTRIBUTED TRAN; UPDATE dbo.SinhVien_HoSo SET DiaChi = N'x' WHERE MaSV = '23010001'; "
     f"UPDATE {LS}.{DB}.dbo.SinhVien SET HoTen = HoTen WHERE MaSV = 'x'; COMMIT")
chay("Sau lỗi: điều phối không giữ dòng sửa dở (DiaChi của 23010001 không phải 'x')", "SELECT COUNT(*) FROM dbo.SinhVien_HoSo WHERE DiaChi = N'x'")
chay("Đồng bộ danh mục khi node vắng", "EXEC dbo.sp_DongBoDanhMuc @MaKhoa = ?", (K,))

print(f"\n=== C. Trong lúc node vắng, trung tâm sửa danh mục (bản sao ở node sẽ cũ) ===")
chay(f"Đổi tên môn {ma} ở bản chính", "UPDATE dbo.MonHoc SET TenMH = ? WHERE MaMH = ?", (ten_cu + " (bản mới)", ma))

print(f"\n=== D. Bật lại {NODE} (docker start) và phục hồi ===")
docker("start"); doi_san_sang(CONG_NODE); time.sleep(5)
chay("Bản sao ở node CŨ so với bản chính (mong đợi lệch 1)", KHOP + " AS Lech")
chay("Đồng bộ lại danh mục cho node vừa phục hồi", "EXEC dbo.sp_DongBoDanhMuc @MaKhoa = ?", (K,))
chay("Sau đồng bộ: bản sao khớp bản chính (mong đợi 0)", KHOP + " AS Lech")
chay("VIEW toàn cục trở lại bình thường (72 sinh viên)", "SELECT COUNT(*) FROM dbo.vw_SinhVien_ToanCuc")
chay("Thêm sinh viên lại được rồi xóa (kiểm tra ghi 2 mảnh)",
     "BEGIN TRAN; EXEC dbo.sp_ThemSinhVien @MaSV='24019998', @HoTen=N'Thử Mất Kết Nối', @NgaySinh='2006-01-01', "
     "@GioiTinh=N'Nam', @MaLop='66.CNTT-1', @CCCD='001306009998', @Email='24019998@sv.qlsv.edu.vn'; ROLLBACK")
chay("Trả tên môn về như cũ", "UPDATE dbo.MonHoc SET TenMH = ? WHERE MaMH = ?", (ten_cu, ma))
chay("Đồng bộ lần cuối để bản sao về như cũ", "EXEC dbo.sp_DongBoDanhMuc @MaKhoa = ?", (K,))
