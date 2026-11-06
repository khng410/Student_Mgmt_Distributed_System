/* =====================================================================
   ĐỒ ÁN CSDL PHÂN TÁN – QUẢN LÝ SINH VIÊN NHIỀU KHOA
   File   : 06_queries_40.sql
   Mục đích: 40 câu truy vấn theo 8 nhóm a–h của đề, chạy ở node điều phối
             QLSV_TongHop. Mỗi câu có comment ghi câu hỏi.
   Người viết: ...............          Ngày: ..../11/2026
   Chạy sau : 05_views.sql                Chạy lại nhiều lần được.

   CƠ CẤU                       NHÓM  CÂU
   ---------------------------------------------------------------------
   a  Đơn giản                   5     1 – 5
   b  Hàm tổng hợp               7     6 – 12
   c  GROUP BY + HAVING          5     13 – 17
   d  Cực trị, top-N             4     18 – 21
   e  "Không/chưa có"            5     22 – 26
   f  UNION / INTERSECT / EXCEPT 3     27 – 29
   g  INSERT / UPDATE / DELETE   7     30 – 36   (mỗi câu trong 1 transaction, ROLLBACK cuối
                                                  để dữ liệu mẫu không đổi; có SELECT kiểm tra)
   h  Phép chia / lồng NOT EXISTS 4    37 – 40

   ĐÁNH DẤU  -- [PT]  = câu thể hiện đặc trưng phân tán, thuộc một trong các loại:
     * dùng VIEW toàn cục (vw_*)  * UNION ALL / truy vấn nhiều node
     * JOIN giữa các database      * tái thiết mảnh dọc (SinhVien_HoSo)
   Tổng cộng 30 câu đánh dấu [PT] (đề yêu cầu >= 15).

   Quy ước điểm: DiemTK = NULL (chưa đủ DiemQT, DiemThi) không tính vào AVG/MAX/MIN;
   điểm >= 4 là đạt.
   ===================================================================== */

SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
USE QLSV_TongHop;
GO


/* #####################################################################
   NHÓM a – TRUY VẤN ĐƠN GIẢN (SELECT / WHERE / ORDER BY / TOP)   5 câu
   ##################################################################### */

-- Câu 1 (a) [PT]: Liệt kê sinh viên nữ đang học của cả trường, sắp xếp theo khoa, lớp, mã SV.
--   Dữ liệu lấy từ 3 node qua VIEW toàn cục.
SELECT MaSV, HoTen, MaLop, TenKhoa
FROM dbo.vw_SinhVien_ToanCuc
WHERE GioiTinh = N'Nữ' AND TrangThai = N'Đang học'
ORDER BY TenKhoa, MaLop, MaSV;
GO

-- Câu 2 (a): Liệt kê các môn học bắt buộc có từ 3 tín chỉ trở lên, sắp xếp theo tên môn.
--   Danh mục môn học có bản chính ở TongHop.
SELECT MaMH, TenMH, SoTinChi, MaKhoa
FROM dbo.MonHoc
WHERE LoaiMH = N'Bắt buộc' AND SoTinChi >= 3
ORDER BY TenMH;
GO

-- Câu 3 (a) [PT]: Lấy 5 sinh viên trẻ tuổi nhất toàn trường.
SELECT TOP (5) MaSV, HoTen, NgaySinh, TenLop, TenKhoa
FROM dbo.vw_SinhVien_ToanCuc
ORDER BY NgaySinh DESC, MaSV;
GO

-- Câu 4 (a) [PT]: Liệt kê lớp học phần của khoa CNTT mở ở HK1-2627, kèm tên môn
--   (JOIN node QLSV_CNTT với danh mục ở QLSV_TongHop) và giảng viên phụ trách.
SELECT lp.MaLHP, m.TenMH, g.HoTen AS GiangVien, lp.PhongHoc, lp.SiSoToiDa
FROM QLSV_CNTT.dbo.LopHocPhan lp
JOIN QLSV_CNTT.dbo.GiangVien g ON g.MaGV = lp.MaGV
JOIN dbo.MonHoc m              ON m.MaMH = lp.MaMH
WHERE lp.MaHK = 'HK1-2627'
ORDER BY lp.MaLHP;
GO

-- Câu 5 (a) [PT]: Liệt kê sinh viên đang bảo lưu hoặc đã thôi học trên toàn trường.
SELECT MaSV, HoTen, TenLop, TenKhoa, TrangThai
FROM dbo.vw_SinhVien_ToanCuc
WHERE TrangThai IN (N'Bảo lưu', N'Thôi học')
ORDER BY TenKhoa, TrangThai, MaSV;
GO


/* #####################################################################
   NHÓM b – HÀM TỔNG HỢP (COUNT, SUM, AVG, MIN, MAX)   7 câu
   ##################################################################### */

-- Câu 6 (b) [PT]: Toàn trường có bao nhiêu sinh viên? So với số sinh viên ở CSDL tập trung.
SELECT (SELECT COUNT(*) FROM dbo.vw_SinhVien_ToanCuc)        AS SoSV_QuaViewToanCuc,
       (SELECT COUNT(*) FROM QLSV_TapTrung.dbo.SinhVien)     AS SoSV_TapTrung;
GO

-- Câu 7 (b) [PT]: Có bao nhiêu lượt đăng ký học phần, và bao nhiêu sinh viên đã đăng ký ít nhất một lớp?
SELECT COUNT(*)                AS SoLuotDangKy,
       COUNT(DISTINCT MaSV)    AS SoSinhVienDaDangKy
FROM dbo.vw_DangKy_ToanCuc;
GO

-- Câu 8 (b): Tổng số tín chỉ của các môn bắt buộc (danh mục) là bao nhiêu?
SELECT SUM(SoTinChi) AS TongTinChiBatBuoc, COUNT(*) AS SoMon
FROM dbo.MonHoc
WHERE LoaiMH = N'Bắt buộc';
GO

-- Câu 9 (b) [PT]: Điểm tổng kết trung bình toàn trường ở học kỳ HK2-2526 là bao nhiêu?
SELECT CAST(AVG(DiemTK) AS DECIMAL(4,2)) AS DiemTBToanTruong, COUNT(DiemTK) AS SoLuotCoDiem
FROM dbo.vw_DangKy_ToanCuc
WHERE MaHK = 'HK2-2526';
GO

-- Câu 10 (b) [PT]: Điểm tổng kết cao nhất, thấp nhất và số lượt chưa có điểm của toàn trường.
SELECT MAX(DiemTK) AS DiemCaoNhat,
       MIN(DiemTK) AS DiemThapNhat,
       SUM(CASE WHEN DiemTK IS NULL THEN 1 ELSE 0 END) AS SoLuotChuaCoDiem
FROM dbo.vw_DangKy_ToanCuc;
GO

-- Câu 11 (b): Khoa Ngoại ngữ có bao nhiêu giảng viên và tuổi trung bình là bao nhiêu?
SELECT COUNT(*) AS SoGiangVien,
       CAST(AVG(CAST(DATEDIFF(YEAR, NgaySinh, GETDATE()) AS DECIMAL(5,2))) AS DECIMAL(5,1)) AS TuoiTrungBinh
FROM QLSV_NgoaiNgu.dbo.GiangVien;
GO

-- Câu 12 (b) [PT]: Toàn trường có bao nhiêu lớp học phần mở ở HK1-2627? (gộp 3 node)
SELECT COUNT(*) AS SoLopHocPhan
FROM (
    SELECT MaLHP FROM QLSV_CNTT.dbo.LopHocPhan     WHERE MaHK = 'HK1-2627'
    UNION ALL
    SELECT MaLHP FROM QLSV_NgoaiNgu.dbo.LopHocPhan WHERE MaHK = 'HK1-2627'
    UNION ALL
    SELECT MaLHP FROM QLSV_DuLich.dbo.LopHocPhan   WHERE MaHK = 'HK1-2627'
) x;
GO


/* #####################################################################
   NHÓM c – GROUP BY VÀ HAVING   5 câu
   ##################################################################### */

-- Câu 13 (c) [PT]: Khoa nào có từ 20 sinh viên trở lên? Hiển thị sĩ số và số sinh viên đang học.
SELECT TenKhoa, COUNT(*) AS SiSo,
       SUM(CASE WHEN TrangThai = N'Đang học' THEN 1 ELSE 0 END) AS DangHoc
FROM dbo.vw_SinhVien_ToanCuc
GROUP BY TenKhoa
HAVING COUNT(*) >= 20;
GO

-- Câu 14 (c) [PT]: Điểm tổng kết trung bình theo khoa và học kỳ; chỉ xét nhóm có từ 20 lượt có điểm.
SELECT TenKhoa, MaHK, COUNT(DiemTK) AS SoLuotCoDiem,
       CAST(AVG(DiemTK) AS DECIMAL(4,2)) AS DiemTB
FROM dbo.vw_BangDiem
GROUP BY TenKhoa, MaHK
HAVING COUNT(DiemTK) >= 20
ORDER BY TenKhoa, MaHK;
GO

-- Câu 15 (c) [PT]: Những lớp nào có từ 8 sinh viên trở lên? (tất cả trạng thái)
SELECT MaLop, TenLop, TenKhoa, COUNT(*) AS SiSo
FROM dbo.vw_SinhVien_ToanCuc
GROUP BY MaLop, TenLop, TenKhoa
HAVING COUNT(*) >= 8
ORDER BY TenKhoa, MaLop;
GO

-- Câu 16 (c): Ở khoa CNTT, những lớp học phần nào có từ 10 sinh viên đăng ký trở lên?
SELECT dk.MaLHP, COUNT(*) AS SoSVDangKy
FROM QLSV_CNTT.dbo.DangKy dk
GROUP BY dk.MaLHP
HAVING COUNT(*) >= 10
ORDER BY SoSVDangKy DESC, dk.MaLHP;
GO

-- Câu 17 (c) [PT]: Những môn học nào có điểm tổng kết trung bình dưới 7 (xét môn có ít nhất 10 lượt có điểm)?
SELECT MaMH, TenMH, COUNT(DiemTK) AS SoLuotCoDiem, CAST(AVG(DiemTK) AS DECIMAL(4,2)) AS DiemTB
FROM dbo.vw_BangDiem
GROUP BY MaMH, TenMH
HAVING COUNT(DiemTK) >= 10 AND AVG(DiemTK) < 7
ORDER BY DiemTB;
GO


/* #####################################################################
   NHÓM d – CỰC TRỊ, TOP-N   4 câu
   ##################################################################### */

-- Câu 18 (d) [PT]: Sinh viên nào đạt điểm tổng kết cao nhất toàn trường (kể cả đồng hạng)?
SELECT MaSV, HoTen, TenKhoa, TenMH, MaHK, DiemTK
FROM dbo.vw_BangDiem
WHERE DiemTK = (SELECT MAX(DiemTK) FROM dbo.vw_BangDiem);
GO

-- Câu 19 (d) [PT]: 5 sinh viên có điểm trung bình tất cả các môn cao nhất (cần ít nhất 8 môn có điểm).
SELECT TOP (5) WITH TIES MaSV, HoTen, TenKhoa,
       COUNT(DiemTK) AS SoMon, CAST(AVG(DiemTK) AS DECIMAL(4,2)) AS DiemTB
FROM dbo.vw_BangDiem
GROUP BY MaSV, HoTen, TenKhoa
HAVING COUNT(DiemTK) >= 8
ORDER BY AVG(DiemTK) DESC;
GO

-- Câu 20 (d): Môn học nào có số tín chỉ nhiều nhất?
SELECT MaMH, TenMH, SoTinChi
FROM dbo.MonHoc
WHERE SoTinChi = (SELECT MAX(SoTinChi) FROM dbo.MonHoc);
GO

-- Câu 21 (d) [PT]: Khoa nào có điểm tổng kết trung bình thấp nhất?
SELECT TOP (1) TenKhoa, CAST(AVG(DiemTK) AS DECIMAL(4,2)) AS DiemTB
FROM dbo.vw_BangDiem
GROUP BY TenKhoa
ORDER BY AVG(DiemTK) ASC;
GO


/* #####################################################################
   NHÓM e – "KHÔNG / CHƯA CÓ" (NOT IN, NOT EXISTS, LEFT / RIGHT JOIN)   5 câu
   ##################################################################### */

-- Câu 22 (e) [PT]: Sinh viên nào chưa đăng ký bất kỳ lớp học phần nào?  (NOT EXISTS)
SELECT s.MaSV, s.HoTen, s.TenLop, s.TenKhoa, s.TrangThai
FROM dbo.vw_SinhVien_ToanCuc s
WHERE NOT EXISTS (SELECT 1 FROM dbo.vw_DangKy_ToanCuc d WHERE d.MaSV = s.MaSV)
ORDER BY s.MaSV;
GO

-- Câu 23 (e) [PT]: Sinh viên nào chưa đăng ký lớp nào ở học kỳ hiện tại HK1-2627?  (NOT IN)
SELECT MaSV, HoTen, TenKhoa, TrangThai
FROM dbo.vw_SinhVien_ToanCuc
WHERE MaSV NOT IN (SELECT MaSV FROM dbo.vw_DangKy_ToanCuc WHERE MaHK = 'HK1-2627')
ORDER BY TenKhoa, MaSV;
GO

-- Câu 24 (e) [PT]: Môn học nào chưa được khoa nào mở lớp học phần?  (NOT EXISTS trên 3 node)
WITH lhp AS (
    SELECT MaMH FROM QLSV_CNTT.dbo.LopHocPhan
    UNION ALL SELECT MaMH FROM QLSV_NgoaiNgu.dbo.LopHocPhan
    UNION ALL SELECT MaMH FROM QLSV_DuLich.dbo.LopHocPhan
)
SELECT m.MaMH, m.TenMH
FROM dbo.MonHoc m
WHERE NOT EXISTS (SELECT 1 FROM lhp WHERE lhp.MaMH = m.MaMH);
GO

-- Câu 25 (e) [PT]: Giảng viên nào chưa dạy lớp học phần nào?  (LEFT JOIN, gộp 3 node)
WITH gv AS (
    SELECT MaGV, HoTen, MaKhoa FROM QLSV_CNTT.dbo.GiangVien
    UNION ALL SELECT MaGV, HoTen, MaKhoa FROM QLSV_NgoaiNgu.dbo.GiangVien
    UNION ALL SELECT MaGV, HoTen, MaKhoa FROM QLSV_DuLich.dbo.GiangVien
), lhp AS (
    SELECT MaLHP, MaGV FROM QLSV_CNTT.dbo.LopHocPhan
    UNION ALL SELECT MaLHP, MaGV FROM QLSV_NgoaiNgu.dbo.LopHocPhan
    UNION ALL SELECT MaLHP, MaGV FROM QLSV_DuLich.dbo.LopHocPhan
)
SELECT g.MaGV, g.HoTen, g.MaKhoa
FROM gv g
LEFT JOIN lhp ON lhp.MaGV = g.MaGV
WHERE lhp.MaLHP IS NULL
ORDER BY g.MaKhoa, g.MaGV;
GO

-- Câu 26 (e): Ở khoa Ngoại ngữ, lớp học phần nào chưa có sinh viên đăng ký?  (RIGHT JOIN)
SELECT lp.MaLHP, lp.MaMH, lp.MaHK
FROM QLSV_NgoaiNgu.dbo.DangKy dk
RIGHT JOIN QLSV_NgoaiNgu.dbo.LopHocPhan lp ON lp.MaLHP = dk.MaLHP
WHERE dk.MaLHP IS NULL
ORDER BY lp.MaLHP;
GO


/* #####################################################################
   NHÓM f – HỢP / GIAO / TRỪ (UNION, INTERSECT, EXCEPT)   3 câu
   ##################################################################### */

-- Câu 27 (f) [PT]: Những khoa nào có sinh viên bảo lưu HOẶC có sinh viên thôi học?  (UNION)
SELECT TenKhoa FROM dbo.vw_SinhVien_ToanCuc WHERE TrangThai = N'Bảo lưu'
UNION
SELECT TenKhoa FROM dbo.vw_SinhVien_ToanCuc WHERE TrangThai = N'Thôi học';
GO

-- Câu 28 (f) [PT]: Sinh viên nào đã đăng ký học ở CẢ HAI học kỳ HK1-2425 và HK1-2627?  (INTERSECT)
SELECT x.MaSV, s.HoTen, s.TenKhoa
FROM (
    SELECT MaSV FROM dbo.vw_DangKy_ToanCuc WHERE MaHK = 'HK1-2425'
    INTERSECT
    SELECT MaSV FROM dbo.vw_DangKy_ToanCuc WHERE MaHK = 'HK1-2627'
) x
JOIN dbo.vw_SinhVien_ToanCuc s ON s.MaSV = x.MaSV
ORDER BY s.TenKhoa, x.MaSV;
GO

-- Câu 29 (f) [PT]: Sinh viên nào có đăng ký ở HK1-2526 nhưng KHÔNG đăng ký ở HK2-2526?  (EXCEPT)
SELECT x.MaSV, s.HoTen, s.TenKhoa, s.TrangThai
FROM (
    SELECT MaSV FROM dbo.vw_DangKy_ToanCuc WHERE MaHK = 'HK1-2526'
    EXCEPT
    SELECT MaSV FROM dbo.vw_DangKy_ToanCuc WHERE MaHK = 'HK2-2526'
) x
JOIN dbo.vw_SinhVien_ToanCuc s ON s.MaSV = x.MaSV
ORDER BY s.TenKhoa, x.MaSV;
GO


/* #####################################################################
   NHÓM g – INSERT / UPDATE / DELETE CÓ ĐIỀU KIỆN   7 câu
   Mỗi câu: BEGIN TRAN -> thao tác -> SELECT kiểm tra -> ROLLBACK -> SELECT chứng minh đã hoàn tác.
   ##################################################################### */

-- Câu 30 (g) [PT]: THÊM sinh viên mới: học vụ vào node CNTT, hồ sơ cá nhân vào TongHop (2 database, 1 transaction).
BEGIN TRAN;
    INSERT QLSV_CNTT.dbo.SinhVien (MaSV, HoTen, NgaySinh, GioiTinh, MaLop)
    VALUES ('24019999', N'Nguyễn Thị Kiểm Thử', '2006-05-10', N'Nữ', '66.CNTT-1');
    INSERT dbo.SinhVien_HoSo (MaSV, CCCD, DienThoai, Email, DiaChi)
    VALUES ('24019999', '001306009999', '0912345678', '24019999@sv.qlsv.edu.vn', N'Số 1 đường Lê Lợi, Hà Nội');

    SELECT N'Sau INSERT' AS Buoc, MaSV, HoTen, TenKhoa, CCCD
    FROM dbo.vw_SinhVien_DayDu WHERE MaSV = '24019999';
ROLLBACK TRAN;
SELECT N'Sau ROLLBACK' AS Buoc, COUNT(*) AS SoDong FROM dbo.vw_SinhVien_DayDu WHERE MaSV = '24019999';
GO

-- Câu 31 (g): THÊM bằng INSERT ... SELECT: đăng ký sinh viên 24010016 (chưa học môn nào)
--   vào mọi lớp học phần HK1-2627 của khoa CNTT mà em chưa đăng ký.
BEGIN TRAN;
    INSERT QLSV_CNTT.dbo.DangKy (MaSV, MaLHP, NgayDangKy)
    SELECT '24010016', lp.MaLHP, '2026-09-10'
    FROM QLSV_CNTT.dbo.LopHocPhan lp
    WHERE lp.MaHK = 'HK1-2627'
      AND NOT EXISTS (SELECT 1 FROM QLSV_CNTT.dbo.DangKy d
                      WHERE d.MaSV = '24010016' AND d.MaLHP = lp.MaLHP);

    SELECT N'Sau INSERT' AS Buoc, COUNT(*) AS SoLopDaDangKy
    FROM QLSV_CNTT.dbo.DangKy WHERE MaSV = '24010016';
ROLLBACK TRAN;
SELECT N'Sau ROLLBACK' AS Buoc, COUNT(*) AS SoLopDaDangKy
FROM QLSV_CNTT.dbo.DangKy WHERE MaSV = '24010016';
GO

-- Câu 32 (g): SỬA có điều kiện: cộng 0,5 điểm quá trình (tối đa 10) cho mọi đăng ký HK2-2526 ở khoa Ngoại ngữ.
BEGIN TRAN;
    DECLARE @truoc DECIMAL(5,3) =
        (SELECT AVG(dk.DiemTK) FROM QLSV_NgoaiNgu.dbo.DangKy dk
         JOIN QLSV_NgoaiNgu.dbo.LopHocPhan lp ON lp.MaLHP = dk.MaLHP WHERE lp.MaHK = 'HK2-2526');

    UPDATE dk
    SET DiemQT = CASE WHEN dk.DiemQT + 0.5 > 10 THEN 10 ELSE dk.DiemQT + 0.5 END
    FROM QLSV_NgoaiNgu.dbo.DangKy dk
    JOIN QLSV_NgoaiNgu.dbo.LopHocPhan lp ON lp.MaLHP = dk.MaLHP
    WHERE lp.MaHK = 'HK2-2526' AND dk.DiemQT IS NOT NULL;

    SELECT @truoc AS DiemTBTruoc, CAST(AVG(dk.DiemTK) AS DECIMAL(5,3)) AS DiemTBSau
    FROM QLSV_NgoaiNgu.dbo.DangKy dk
    JOIN QLSV_NgoaiNgu.dbo.LopHocPhan lp ON lp.MaLHP = dk.MaLHP WHERE lp.MaHK = 'HK2-2526';
ROLLBACK TRAN;
GO

-- Câu 33 (g) [PT]: SỬA trên 3 node trong 1 transaction: cho sinh viên đang bảo lưu quay lại học.
BEGIN TRAN;
    SELECT N'Trước' AS Buoc, TrangThai, COUNT(*) AS SoSV FROM dbo.vw_SinhVien_ToanCuc GROUP BY TrangThai;

    UPDATE QLSV_CNTT.dbo.SinhVien     SET TrangThai = N'Đang học' WHERE TrangThai = N'Bảo lưu';
    UPDATE QLSV_NgoaiNgu.dbo.SinhVien SET TrangThai = N'Đang học' WHERE TrangThai = N'Bảo lưu';
    UPDATE QLSV_DuLich.dbo.SinhVien   SET TrangThai = N'Đang học' WHERE TrangThai = N'Bảo lưu';

    SELECT N'Sau UPDATE' AS Buoc, TrangThai, COUNT(*) AS SoSV FROM dbo.vw_SinhVien_ToanCuc GROUP BY TrangThai;
ROLLBACK TRAN;
SELECT N'Sau ROLLBACK' AS Buoc, TrangThai, COUNT(*) AS SoSV FROM dbo.vw_SinhVien_ToanCuc GROUP BY TrangThai;
GO

-- Câu 34 (g): SỬA kèm truy vấn con: tăng thêm 10 chỗ cho lớp học phần CNTT đã đầy từ một nửa trở lên.
--   OUTPUT cho thấy sĩ số tối đa cũ và mới của từng lớp bị đổi.
BEGIN TRAN;
    UPDATE lp
    SET SiSoToiDa = lp.SiSoToiDa + 10
    OUTPUT inserted.MaLHP, deleted.SiSoToiDa AS SiSoCu, inserted.SiSoToiDa AS SiSoMoi
    FROM QLSV_CNTT.dbo.LopHocPhan lp
    WHERE (SELECT COUNT(*) FROM QLSV_CNTT.dbo.DangKy d WHERE d.MaLHP = lp.MaLHP) * 2 >= lp.SiSoToiDa;
ROLLBACK TRAN;
GO

-- Câu 35 (g): XÓA có điều kiện: xóa các đăng ký HK1-2627 của khoa Du lịch chưa có điểm nào.
BEGIN TRAN;
    DECLARE @truoc2 INT = (SELECT COUNT(*) FROM QLSV_DuLich.dbo.DangKy);

    DELETE dk
    OUTPUT deleted.MaSV, deleted.MaLHP
    FROM QLSV_DuLich.dbo.DangKy dk
    JOIN QLSV_DuLich.dbo.LopHocPhan lp ON lp.MaLHP = dk.MaLHP
    WHERE lp.MaHK = 'HK1-2627' AND dk.DiemQT IS NULL AND dk.DiemThi IS NULL;

    SELECT @truoc2 AS SoDongTruoc, COUNT(*) AS SoDongSau FROM QLSV_DuLich.dbo.DangKy;
ROLLBACK TRAN;
GO

-- Câu 36 (g) [PT]: XÓA phân tán: xóa sinh viên 24010016 (chưa đăng ký môn nào) khỏi cả hai mảnh dọc:
--   hồ sơ ở TongHop trước, học vụ ở node CNTT sau (2 database, 1 transaction).
BEGIN TRAN;
    SELECT N'Trước' AS Buoc, COUNT(*) AS SoSVToanTruong FROM dbo.vw_SinhVien_ToanCuc;

    DELETE FROM dbo.SinhVien_HoSo        WHERE MaSV = '24010016';
    DELETE FROM QLSV_CNTT.dbo.SinhVien   WHERE MaSV = '24010016'
        AND NOT EXISTS (SELECT 1 FROM QLSV_CNTT.dbo.DangKy d WHERE d.MaSV = '24010016');

    SELECT N'Sau DELETE' AS Buoc, COUNT(*) AS SoSVToanTruong FROM dbo.vw_SinhVien_ToanCuc;
ROLLBACK TRAN;
SELECT N'Sau ROLLBACK' AS Buoc, COUNT(*) AS SoSVToanTruong FROM dbo.vw_SinhVien_ToanCuc;
GO


/* #####################################################################
   NHÓM h – PHÉP CHIA QUAN HỆ / NOT EXISTS LỒNG   4 câu
   ##################################################################### */

-- Câu 37 (h) [PT]: Sinh viên nào đã đăng ký TẤT CẢ lớp học phần HK1-2425 của khoa mình?
--   (không tồn tại lớp của khoa mình mà em chưa đăng ký)
SELECT s.MaSV, s.HoTen, s.TenKhoa
FROM dbo.vw_SinhVien_ToanCuc s
WHERE NOT EXISTS (
    SELECT 1
    FROM (SELECT DISTINCT MaLHP, MaKhoa FROM dbo.vw_DangKy_ToanCuc WHERE MaHK = 'HK1-2425') l
    WHERE l.MaKhoa = s.MaKhoa
      AND NOT EXISTS (SELECT 1 FROM dbo.vw_DangKy_ToanCuc d
                      WHERE d.MaSV = s.MaSV AND d.MaLHP = l.MaLHP))
ORDER BY s.TenKhoa, s.MaSV;
GO

-- Câu 38 (h) [PT]: Sinh viên nào đã học đủ cả 3 môn chung CHUNG01, CHUNG02, CHUNG03?
SELECT s.MaSV, s.HoTen, s.TenKhoa
FROM dbo.vw_SinhVien_ToanCuc s
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.MonHoc m
    WHERE m.MaMH IN ('CHUNG01', 'CHUNG02', 'CHUNG03')
      AND NOT EXISTS (SELECT 1 FROM dbo.vw_DangKy_ToanCuc d
                      WHERE d.MaSV = s.MaSV AND d.MaMH = m.MaMH))
ORDER BY s.TenKhoa, s.MaSV;
GO

-- Câu 39 (h) [PT]: Sinh viên nào đã học ở HK2-2526 và TẤT CẢ các môn em học kỳ đó đều đạt (>= 4)?
--   Môn chưa có điểm (DiemTK NULL) không bị coi là rớt.
SELECT s.MaSV, s.HoTen, s.TenKhoa
FROM dbo.vw_SinhVien_ToanCuc s
WHERE EXISTS (SELECT 1 FROM dbo.vw_DangKy_ToanCuc d
              WHERE d.MaSV = s.MaSV AND d.MaHK = 'HK2-2526')
  AND NOT EXISTS (SELECT 1 FROM dbo.vw_DangKy_ToanCuc d
                  WHERE d.MaSV = s.MaSV AND d.MaHK = 'HK2-2526' AND d.DiemTK < 4)
ORDER BY s.TenKhoa, s.MaSV;
GO

-- Câu 40 (h) [PT]: Môn học nào được TẤT CẢ các khoa cùng mở lớp học phần?
--   (không tồn tại khoa nào chưa mở lớp cho môn đó)
WITH lhp AS (
    SELECT MaMH, 'CNTT' AS MaKhoa FROM QLSV_CNTT.dbo.LopHocPhan
    UNION ALL SELECT MaMH, 'NN' FROM QLSV_NgoaiNgu.dbo.LopHocPhan
    UNION ALL SELECT MaMH, 'DL' FROM QLSV_DuLich.dbo.LopHocPhan
)
SELECT m.MaMH, m.TenMH
FROM dbo.MonHoc m
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.Khoa k
    WHERE NOT EXISTS (SELECT 1 FROM lhp WHERE lhp.MaMH = m.MaMH AND lhp.MaKhoa = k.MaKhoa))
ORDER BY m.MaMH;
GO
