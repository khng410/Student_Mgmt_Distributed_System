/* =====================================================================
   ĐỒ ÁN CSDL PHÂN TÁN – QUẢN LÝ SINH VIÊN NHIỀU KHOA
   File   : 08_functions.sql
   Mục đích: 8 hàm (5 scalar + 3 table-valued) ở node điều phối QLSV_TongHop.
             Các hàm đọc dữ liệu qua VIEW toàn cục nên không cần biết dữ liệu ở node nào.
   Người viết: ...............          Ngày: ..../11/2026
   Chạy sau : 07_procedures.sql           Chạy lại nhiều lần được (CREATE OR ALTER).

   #  Hàm                      Loại            Việc làm
   1  fn_XepLoaiDiem           scalar          điểm 0-10 -> Giỏi/Khá/Trung bình/Yếu/Không đạt
   2  fn_DiemTBTichLuy         scalar          điểm TB tích lũy của 1 sinh viên (trọng số = tín chỉ)
   3  fn_TinChiTichLuy         scalar          số tín chỉ đã đạt (điểm >= 4) của 1 sinh viên
   4  fn_XepLoaiHocLuc         scalar          xếp loại học lực của 1 sinh viên (gọi hàm 1 và 2)
   5  fn_SiSoLopHocPhan        scalar          số sinh viên đã đăng ký 1 lớp học phần
   6  fn_BangDiemSinhVien      table-valued    bảng điểm 1 sinh viên (theo học kỳ hoặc tất cả)
   7  fn_DanhSachLop           table-valued    danh sách sinh viên 1 lớp kèm điểm TB tích lũy
   8  fn_TopSinhVien           table-valued    top N sinh viên điểm TB cao nhất (theo khoa hoặc toàn trường)

   Quy ước: DiemTK NULL = chưa có điểm, không tính vào trung bình/tín chỉ.
   Thang xếp loại (khớp sp_ThongKeKhoa): Giỏi >= 8; Khá >= 6,5; Trung bình >= 5;
   Yếu >= 4; Không đạt < 4.
   Hàm không thể dùng SQL động, nên các hàm đọc thẳng qua VIEW ở 05_views.sql.
   Phần cuối file có câu SELECT gọi thử cho cả 8 hàm.
   ===================================================================== */

SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
USE QLSV_TongHop;
GO


/* ---------- 1. fn_XepLoaiDiem (scalar) ---------- */
CREATE OR ALTER FUNCTION dbo.fn_XepLoaiDiem (@Diem DECIMAL(4,2))
RETURNS NVARCHAR(20)
AS
BEGIN
    RETURN CASE WHEN @Diem IS NULL THEN N'Chưa có điểm'
                WHEN @Diem >= 8    THEN N'Giỏi'
                WHEN @Diem >= 6.5  THEN N'Khá'
                WHEN @Diem >= 5    THEN N'Trung bình'
                WHEN @Diem >= 4    THEN N'Yếu'
                ELSE N'Không đạt' END;
END
GO

/* ---------- 2. fn_DiemTBTichLuy (scalar) ----------
   Điểm TB = tổng(điểm TK x tín chỉ) / tổng tín chỉ của các môn đã có điểm.
   Mỗi lượt đăng ký tính một lần (chưa xử lý học lại lấy điểm cao nhất). */
CREATE OR ALTER FUNCTION dbo.fn_DiemTBTichLuy (@MaSV CHAR(8))
RETURNS DECIMAL(4,2)
AS
BEGIN
    RETURN (SELECT CAST(SUM(DiemTK * SoTinChi)
                        / NULLIF(SUM(CASE WHEN DiemTK IS NOT NULL THEN SoTinChi END), 0) AS DECIMAL(4,2))
            FROM dbo.vw_BangDiem
            WHERE MaSV = @MaSV);
END
GO

/* ---------- 3. fn_TinChiTichLuy (scalar) ---------- */
CREATE OR ALTER FUNCTION dbo.fn_TinChiTichLuy (@MaSV CHAR(8))
RETURNS INT
AS
BEGIN
    RETURN (SELECT ISNULL(SUM(SoTinChi), 0)
            FROM dbo.vw_BangDiem
            WHERE MaSV = @MaSV AND DiemTK >= 4);
END
GO

/* ---------- 4. fn_XepLoaiHocLuc (scalar, gọi hàm 1 và 2) ---------- */
CREATE OR ALTER FUNCTION dbo.fn_XepLoaiHocLuc (@MaSV CHAR(8))
RETURNS NVARCHAR(20)
AS
BEGIN
    RETURN dbo.fn_XepLoaiDiem(dbo.fn_DiemTBTichLuy(@MaSV));
END
GO

/* ---------- 5. fn_SiSoLopHocPhan (scalar) ---------- */
CREATE OR ALTER FUNCTION dbo.fn_SiSoLopHocPhan (@MaLHP VARCHAR(20))
RETURNS INT
AS
BEGIN
    RETURN (SELECT COUNT(*) FROM dbo.vw_DangKy_ToanCuc WHERE MaLHP = @MaLHP);
END
GO

/* ---------- 6. fn_BangDiemSinhVien (inline table-valued) ----------
   @MaHK NULL = mọi học kỳ. */
CREATE OR ALTER FUNCTION dbo.fn_BangDiemSinhVien (@MaSV CHAR(8), @MaHK VARCHAR(10))
RETURNS TABLE
AS
RETURN
(
    SELECT MaHK, MaLHP, MaMH, TenMH, SoTinChi, DiemQT, DiemThi, DiemTK, KetQua
    FROM dbo.vw_BangDiem
    WHERE MaSV = @MaSV AND (@MaHK IS NULL OR MaHK = @MaHK)
);
GO

/* ---------- 7. fn_DanhSachLop (inline table-valued) ----------
   Mọi sinh viên của lớp, kể cả sinh viên chưa có điểm (LEFT JOIN). */
CREATE OR ALTER FUNCTION dbo.fn_DanhSachLop (@MaLop VARCHAR(15))
RETURNS TABLE
AS
RETURN
(
    SELECT s.MaSV, s.HoTen, s.GioiTinh, s.TrangThai,
           COUNT(b.DiemTK) AS SoMonCoDiem,
           CAST(SUM(b.DiemTK * b.SoTinChi)
                / NULLIF(SUM(CASE WHEN b.DiemTK IS NOT NULL THEN b.SoTinChi END), 0) AS DECIMAL(4,2)) AS DiemTBTichLuy
    FROM dbo.vw_SinhVien_ToanCuc s
    LEFT JOIN dbo.vw_BangDiem b ON b.MaSV = s.MaSV
    WHERE s.MaLop = @MaLop
    GROUP BY s.MaSV, s.HoTen, s.GioiTinh, s.TrangThai
);
GO

/* ---------- 8. fn_TopSinhVien (inline table-valued) ----------
   Top @N sinh viên có điểm TB tích lũy cao nhất, chỉ xét người có ít nhất @MinMon môn có điểm.
   @MaKhoa NULL = toàn trường. */
CREATE OR ALTER FUNCTION dbo.fn_TopSinhVien (@MaKhoa VARCHAR(10), @N INT, @MinMon INT)
RETURNS TABLE
AS
RETURN
(
    SELECT TOP (@N) MaSV, HoTen, TenKhoa, SoMon, DiemTB
    FROM (
        SELECT MaSV, HoTen, TenKhoa, COUNT(DiemTK) AS SoMon,
               CAST(SUM(DiemTK * SoTinChi)
                    / NULLIF(SUM(CASE WHEN DiemTK IS NOT NULL THEN SoTinChi END), 0) AS DECIMAL(4,2)) AS DiemTB
        FROM dbo.vw_BangDiem
        WHERE @MaKhoa IS NULL OR MaKhoa = @MaKhoa
        GROUP BY MaSV, HoTen, TenKhoa
        HAVING COUNT(DiemTK) >= @MinMon
    ) t
    ORDER BY DiemTB DESC, MaSV
);
GO


/* =====================================================================
   GỌI THỬ (SELECT) cho cả 8 hàm
   ===================================================================== */

-- 1. fn_XepLoaiDiem: thử mọi ngưỡng
SELECT d AS Diem, dbo.fn_XepLoaiDiem(d) AS XepLoai
FROM (VALUES (CAST(9.5 AS DECIMAL(4,2))), (8.00), (7.00), (5.50), (4.00), (3.90), (NULL)) v(d);
GO

-- 2, 3, 4. Điểm TB tích lũy, tín chỉ tích lũy, xếp loại của từng sinh viên lớp 66.CNTT-1
SELECT MaSV, HoTen,
       dbo.fn_DiemTBTichLuy(MaSV) AS DiemTBTichLuy,
       dbo.fn_TinChiTichLuy(MaSV) AS TinChiTichLuy,
       dbo.fn_XepLoaiHocLuc(MaSV) AS XepLoai
FROM dbo.vw_SinhVien_ToanCuc
WHERE MaLop = '66.CNTT-1'
ORDER BY MaSV;
GO

-- 4 (dùng trong WHERE). Sinh viên khoa Du lịch xếp loại Giỏi
SELECT MaSV, HoTen, dbo.fn_DiemTBTichLuy(MaSV) AS DiemTBTichLuy
FROM dbo.vw_SinhVien_ToanCuc
WHERE MaKhoa = 'DL' AND dbo.fn_XepLoaiHocLuc(MaSV) = N'Giỏi'
ORDER BY MaSV;
GO

-- 5. fn_SiSoLopHocPhan: sĩ số các lớp học phần HK1-2627 của khoa CNTT so với sĩ số tối đa
SELECT lp.MaLHP, dbo.fn_SiSoLopHocPhan(lp.MaLHP) AS SiSoHienTai, lp.SiSoToiDa
FROM QLSV_CNTT.dbo.LopHocPhan lp
WHERE lp.MaHK = 'HK1-2627'
ORDER BY lp.MaLHP;
GO

-- 6. fn_BangDiemSinhVien: tất cả học kỳ rồi riêng HK2-2526
SELECT * FROM dbo.fn_BangDiemSinhVien('24010001', NULL)       ORDER BY MaHK, MaMH;
SELECT * FROM dbo.fn_BangDiemSinhVien('24010001', 'HK2-2526') ORDER BY MaMH;
GO

-- 7. fn_DanhSachLop: lớp 66.NN-1, có cả sinh viên chưa có điểm
SELECT * FROM dbo.fn_DanhSachLop('66.NN-1') ORDER BY MaSV;
GO

-- 8. fn_TopSinhVien: top 5 khoa CNTT và top 5 toàn trường (cần >= 8 môn có điểm)
SELECT * FROM dbo.fn_TopSinhVien('CNTT', 5, 8);
SELECT * FROM dbo.fn_TopSinhVien(NULL,   5, 8);
GO

-- Kiểm tra nhất quán: điểm TB tích lũy từ hàm phải bằng điểm tính trực tiếp từ VIEW (kết quả mong đợi: 0 dòng)
SELECT s.MaSV
FROM dbo.vw_SinhVien_ToanCuc s
CROSS APPLY (SELECT CAST(SUM(DiemTK * SoTinChi)
                         / NULLIF(SUM(CASE WHEN DiemTK IS NOT NULL THEN SoTinChi END), 0) AS DECIMAL(4,2)) AS TB
             FROM dbo.vw_BangDiem b WHERE b.MaSV = s.MaSV) x
WHERE ISNULL(x.TB, -1) <> ISNULL(dbo.fn_DiemTBTichLuy(s.MaSV), -1);
GO

-- Đếm: phải đúng 8 hàm do file này tạo (5 scalar FN + 3 inline table-valued IF)
SELECT COUNT(*) AS SoHam FROM sys.objects WHERE type IN ('FN', 'IF', 'TF') AND name LIKE N'fn[_]%';
GO
