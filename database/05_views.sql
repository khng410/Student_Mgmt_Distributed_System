/* =====================================================================
   ĐỒ ÁN CSDL PHÂN TÁN – QUẢN LÝ SINH VIÊN NHIỀU KHOA
   File   : 05_views.sql
   Mục đích: 5 VIEW ở node điều phối QLSV_TongHop, che vị trí dữ liệu: người
             dùng và ứng dụng chỉ truy vấn VIEW, không cần biết dòng nào nằm ở
             node nào.
   Người viết: ...............          Ngày: ..../11/2026
   Chạy sau : 04_fragmentation.sql        Chạy lại nhiều lần được.

   DANH SÁCH VIEW
   ---------------------------------------------------------------------
   #  Tên                      Loại                Nguồn
   1  vw_SinhVien_ToanCuc      TOÀN CỤC + BẢO MẬT  UNION ALL SinhVien+Lop của 3 node khoa
                                                   (không có CCCD/SĐT/địa chỉ)
   2  vw_SinhVien_DayDu        TÁI THIẾT mảnh dọc  vw_SinhVien_ToanCuc JOIN SinhVien_HoSo
                                                   (chỉ Phòng Đào tạo được xem)
   3  vw_DangKy_ToanCuc        TOÀN CỤC            UNION ALL DangKy+LopHocPhan của 3 node
   4  vw_BangDiem              BÁO CÁO             bảng điểm chi tiết toàn trường
   5  vw_ThongKe_Khoa_HocKy    BÁO CÁO             thống kê theo khoa và học kỳ

   Phạm vi khoa: vw_SinhVien_ToanCuc và vw_DangKy_ToanCuc chỉ trả khoa của giáo vụ đang đăng nhập,
   qua hàm dbo.PhamViKhoaCuaToi() (mục 0). Các view còn lại (vw_SinhVien_DayDu, vw_BangDiem,
   vw_ThongKe_Khoa_HocKy) đọc từ hai view đó nên tự bị lọc theo. Tài khoản khác thấy cả 3 khoa.
   Dùng CREATE OR ALTER nên chạy lại file này không làm mất quyền GRANT đã cấp ở 10_security.sql.

   Quy ước điểm: DiemTK = NULL khi chưa đủ DiemQT và DiemThi -> "Chưa có điểm",
   không tính vào điểm trung bình.

   LƯU Ý QUYỀN (làm ở 10_security.sql): VIEW đọc bảng của 3 node qua database đại diện (synonym -> Linked Server),
   nên người dùng cần quyền SELECT ở cả 3 node, nếu không sẽ báo lỗi quyền khi SELECT từ VIEW.
   ===================================================================== */

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
USE QLSV_TongHop;
GO

/* ---------- 0. PHẠM VI KHOA CỦA NGƯỜI ĐANG ĐĂNG NHẬP ----------
   Giáo vụ từng khoa chỉ được xem dữ liệu khoa mình; mọi tài khoản khác thấy cả 3 khoa.
   Dùng trong vw_SinhVien_ToanCuc và vw_DangKy_ToanCuc. Thêm giáo vụ mới: thêm một dòng vào VALUES.
   THẤT BẠI AN TOÀN: thành viên rl_GiaoVu (10_security.sql) chưa có dòng trong VALUES không thấy khoa nào.
   (Không đặt tên bắt đầu bằng fn_ để không lẫn vào 8 hàm của 08_functions.sql.) */
CREATE OR ALTER FUNCTION dbo.PhamViKhoaCuaToi ()
RETURNS TABLE
AS
RETURN
(
    WITH g (tai_khoan, ma_khoa) AS (
        SELECT * FROM (VALUES (N'lg_giaovu_cntt', 'CNTT'), (N'lg_giaovu_nn', 'NN'), (N'lg_giaovu_dl', 'DL')) v (a, b)
    )
    SELECT k.MaKhoa
    FROM dbo.Khoa k
    WHERE k.MaKhoa IN (SELECT ma_khoa FROM g WHERE tai_khoan = SUSER_SNAME())
       OR (ISNULL(IS_MEMBER(N'rl_GiaoVu'), 0) = 0 AND SUSER_SNAME() NOT IN (SELECT tai_khoan FROM g))
);
GO

/* ---------- 1. VIEW TOÀN CỤC: sinh viên của cả trường ---------- */
CREATE OR ALTER VIEW dbo.vw_SinhVien_ToanCuc
AS
SELECT s.MaSV, s.HoTen, s.NgaySinh, s.GioiTinh, s.MaLop, s.TenLop,
       s.MaKhoa, k.TenKhoa, s.TrangThai
FROM (
    SELECT sv.MaSV, sv.HoTen, sv.NgaySinh, sv.GioiTinh, sv.MaLop, l.TenLop, l.MaKhoa, sv.TrangThai
    FROM QLSV_CNTT.dbo.SinhVien sv     JOIN QLSV_CNTT.dbo.Lop l     ON l.MaLop = sv.MaLop
    UNION ALL
    SELECT sv.MaSV, sv.HoTen, sv.NgaySinh, sv.GioiTinh, sv.MaLop, l.TenLop, l.MaKhoa, sv.TrangThai
    FROM QLSV_NgoaiNgu.dbo.SinhVien sv JOIN QLSV_NgoaiNgu.dbo.Lop l ON l.MaLop = sv.MaLop
    UNION ALL
    SELECT sv.MaSV, sv.HoTen, sv.NgaySinh, sv.GioiTinh, sv.MaLop, l.TenLop, l.MaKhoa, sv.TrangThai
    FROM QLSV_DuLich.dbo.SinhVien sv   JOIN QLSV_DuLich.dbo.Lop l   ON l.MaLop = sv.MaLop
) s
JOIN dbo.Khoa k ON k.MaKhoa = s.MaKhoa
WHERE s.MaKhoa IN (SELECT MaKhoa FROM dbo.PhamViKhoaCuaToi());      -- giáo vụ chỉ thấy khoa mình
GO

/* ---------- 2. VIEW TÁI THIẾT mảnh dọc: ghép học vụ + hồ sơ ---------- */
CREATE OR ALTER VIEW dbo.vw_SinhVien_DayDu
AS
SELECT s.MaSV, s.HoTen, s.NgaySinh, s.GioiTinh, s.MaLop, s.TenLop, s.MaKhoa, s.TenKhoa, s.TrangThai,
       h.CCCD, h.DienThoai, h.Email, h.DiaChi
FROM dbo.vw_SinhVien_ToanCuc s
JOIN dbo.SinhVien_HoSo h ON h.MaSV = s.MaSV;
GO

/* ---------- 3. VIEW TOÀN CỤC: đăng ký học phần và điểm ---------- */
CREATE OR ALTER VIEW dbo.vw_DangKy_ToanCuc
AS
SELECT d.MaSV, d.MaLHP, d.MaMH, m.TenMH, m.SoTinChi, d.MaHK, d.Nhom, d.MaGV,
       d.MaKhoa, d.NgayDangKy, d.DiemQT, d.DiemThi, d.DiemTK
FROM (
    SELECT dk.MaSV, dk.MaLHP, lp.MaMH, lp.MaHK, lp.Nhom, lp.MaGV, 'CNTT' AS MaKhoa,
           dk.NgayDangKy, dk.DiemQT, dk.DiemThi, dk.DiemTK
    FROM QLSV_CNTT.dbo.DangKy dk     JOIN QLSV_CNTT.dbo.LopHocPhan lp     ON lp.MaLHP = dk.MaLHP
    UNION ALL
    SELECT dk.MaSV, dk.MaLHP, lp.MaMH, lp.MaHK, lp.Nhom, lp.MaGV, 'NN',
           dk.NgayDangKy, dk.DiemQT, dk.DiemThi, dk.DiemTK
    FROM QLSV_NgoaiNgu.dbo.DangKy dk JOIN QLSV_NgoaiNgu.dbo.LopHocPhan lp ON lp.MaLHP = dk.MaLHP
    UNION ALL
    SELECT dk.MaSV, dk.MaLHP, lp.MaMH, lp.MaHK, lp.Nhom, lp.MaGV, 'DL',
           dk.NgayDangKy, dk.DiemQT, dk.DiemThi, dk.DiemTK
    FROM QLSV_DuLich.dbo.DangKy dk   JOIN QLSV_DuLich.dbo.LopHocPhan lp   ON lp.MaLHP = dk.MaLHP
) d
JOIN dbo.MonHoc m ON m.MaMH = d.MaMH
WHERE d.MaKhoa IN (SELECT MaKhoa FROM dbo.PhamViKhoaCuaToi());      -- giáo vụ chỉ thấy khoa mình
GO

/* ---------- 4. VIEW BÁO CÁO: bảng điểm chi tiết ---------- */
CREATE OR ALTER VIEW dbo.vw_BangDiem
AS
SELECT s.MaSV, s.HoTen, s.TenLop, s.MaKhoa, s.TenKhoa,
       d.MaHK, d.MaLHP, d.MaMH, d.TenMH, d.SoTinChi,
       d.DiemQT, d.DiemThi, d.DiemTK,
       CASE WHEN d.DiemTK IS NULL THEN N'Chưa có điểm'
            WHEN d.DiemTK >= 4     THEN N'Đạt'
            ELSE N'Không đạt' END AS KetQua
FROM dbo.vw_DangKy_ToanCuc d
JOIN dbo.vw_SinhVien_ToanCuc s ON s.MaSV = d.MaSV;
GO

/* ---------- 5. VIEW BÁO CÁO: thống kê theo khoa và học kỳ ---------- */
CREATE OR ALTER VIEW dbo.vw_ThongKe_Khoa_HocKy
AS
SELECT MaKhoa, TenKhoa, MaHK,
       COUNT(DISTINCT MaSV)  AS SoSinhVien,
       COUNT(*)              AS SoLuotDangKy,
       COUNT(DiemTK)         AS SoLuotCoDiem,
       CAST(AVG(DiemTK) AS DECIMAL(4,2)) AS DiemTB,
       SUM(CASE WHEN DiemTK < 4 THEN 1 ELSE 0 END) AS SoLuotKhongDat,
       CAST(100.0 * SUM(CASE WHEN DiemTK >= 4 THEN 1 ELSE 0 END)
            / NULLIF(COUNT(DiemTK), 0) AS DECIMAL(5,2)) AS TyLeDat
FROM dbo.vw_BangDiem
GROUP BY MaKhoa, TenKhoa, MaHK;
GO


/* =====================================================================
   KIỂM TRA: VIEW toàn cục phải tương đương dữ liệu logic của CSDL tập trung
   Thieu = có ở QLSV_TapTrung nhưng không có ở VIEW; Thua = ngược lại. Cả hai = 0 là đạt.
   ===================================================================== */
SELECT N'vw_SinhVien_ToanCuc' AS KiemTra,
  (SELECT COUNT(*) FROM (SELECT MaSV, HoTen, NgaySinh, GioiTinh, MaLop, TrangThai FROM QLSV_TapTrung.dbo.SinhVien
                         EXCEPT SELECT MaSV, HoTen, NgaySinh, GioiTinh, MaLop, TrangThai FROM dbo.vw_SinhVien_ToanCuc) a) AS Thieu,
  (SELECT COUNT(*) FROM (SELECT MaSV, HoTen, NgaySinh, GioiTinh, MaLop, TrangThai FROM dbo.vw_SinhVien_ToanCuc
                         EXCEPT SELECT MaSV, HoTen, NgaySinh, GioiTinh, MaLop, TrangThai FROM QLSV_TapTrung.dbo.SinhVien) b) AS Thua
UNION ALL
SELECT N'vw_SinhVien_DayDu (tái thiết dọc)',
  (SELECT COUNT(*) FROM (SELECT MaSV, HoTen, NgaySinh, GioiTinh, MaLop, TrangThai, CCCD, DienThoai, Email, DiaChi FROM QLSV_TapTrung.dbo.SinhVien
                         EXCEPT SELECT MaSV, HoTen, NgaySinh, GioiTinh, MaLop, TrangThai, CCCD, DienThoai, Email, DiaChi FROM dbo.vw_SinhVien_DayDu) a),
  (SELECT COUNT(*) FROM (SELECT MaSV, HoTen, NgaySinh, GioiTinh, MaLop, TrangThai, CCCD, DienThoai, Email, DiaChi FROM dbo.vw_SinhVien_DayDu
                         EXCEPT SELECT MaSV, HoTen, NgaySinh, GioiTinh, MaLop, TrangThai, CCCD, DienThoai, Email, DiaChi FROM QLSV_TapTrung.dbo.SinhVien) b)
UNION ALL
SELECT N'vw_DangKy_ToanCuc',
  (SELECT COUNT(*) FROM (SELECT MaSV, MaLHP, NgayDangKy, DiemQT, DiemThi, DiemTK FROM QLSV_TapTrung.dbo.DangKy
                         EXCEPT SELECT MaSV, MaLHP, NgayDangKy, DiemQT, DiemThi, DiemTK FROM dbo.vw_DangKy_ToanCuc) a),
  (SELECT COUNT(*) FROM (SELECT MaSV, MaLHP, NgayDangKy, DiemQT, DiemThi, DiemTK FROM dbo.vw_DangKy_ToanCuc
                         EXCEPT SELECT MaSV, MaLHP, NgayDangKy, DiemQT, DiemThi, DiemTK FROM QLSV_TapTrung.dbo.DangKy) b);
GO

/* ---------- Ví dụ dùng VIEW (chụp ảnh cho báo cáo) ---------- */
SELECT TOP (10) * FROM dbo.vw_SinhVien_ToanCuc ORDER BY MaSV;
SELECT TOP (5)  MaSV, HoTen, CCCD, DienThoai FROM dbo.vw_SinhVien_DayDu ORDER BY MaSV;
SELECT * FROM dbo.vw_ThongKe_Khoa_HocKy ORDER BY MaKhoa, MaHK;
SELECT TOP (10) MaSV, HoTen, TenMH, MaHK, DiemTK, KetQua FROM dbo.vw_BangDiem
WHERE KetQua = N'Không đạt' ORDER BY DiemTK;
GO
