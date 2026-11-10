/* =====================================================================
   ĐỒ ÁN CSDL PHÂN TÁN – QUẢN LÝ SINH VIÊN NHIỀU KHOA
   File   : 12_linked_server.sql
   Mục đích: Chạy thử truy vấn LIÊN NÚT và truy vấn TỔNG HỢP TOÀN HỆ THỐNG qua Linked Server,
             chứng minh dữ liệu thật sự lấy từ 4 instance SQL Server khác nhau.
   Người viết: ...............          Ngày: ..../11/2026
   Chạy sau : 11_transactions_concurrency.sql, trên instance điều phối (cổng 14330), tài khoản sysadmin.
   Chạy lại nhiều lần được; không sửa dữ liệu (mọi lệnh ghi đều ROLLBACK).

   Linked Server được tạo ở 02b_node_links.sql (LS_QLSV_CNTT, LS_QLSV_NgoaiNgu, LS_QLSV_DuLich), mỗi cái
   trỏ tới một instance riêng: qlsv_cntt, qlsv_ngoaingu, qlsv_dulich. Tên 4 phần:
       LinkedServer.Database.Schema.Table
   ===================================================================== */

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
USE QLSV_TongHop;
GO

/* =====================================================================
   PHẦN 1. CẤU HÌNH – 3 Linked Server và ánh xạ đăng nhập (bằng chứng cấu hình)
   ===================================================================== */
SELECT name AS LinkedServer, provider, data_source AS MayChuDich, is_rpc_out_enabled AS RpcOut,
       is_remote_proc_transaction_promotion_enabled AS GiaoDichPhanTan
FROM sys.servers WHERE name LIKE N'LS[_]QLSV[_]%' ORDER BY name;
GO

/* =====================================================================
   PHẦN 2. CHỨNG MINH DỮ LIỆU NẰM Ở 4 INSTANCE KHÁC NHAU
   Mỗi dòng do chính instance đó tự báo tên máy chủ và số dòng của nó (OPENQUERY chạy nguyên bên node).
   ===================================================================== */
SELECT N'Điều phối' AS Node, @@SERVERNAME AS MayChu,
       (SELECT COUNT(*) FROM dbo.SinhVien_HoSo) AS SoDong, N'SinhVien_HoSo (mảnh dọc nhạy cảm)' AS Bang
UNION ALL SELECT N'CNTT', MayChu, SoDong, N'SinhVien (mảnh học vụ)'
FROM OPENQUERY(LS_QLSV_CNTT, 'SELECT @@SERVERNAME AS MayChu, (SELECT COUNT(*) FROM QLSV_CNTT.dbo.SinhVien) AS SoDong FROM (SELECT 1 AS x) t')
UNION ALL SELECT N'Ngoại ngữ', MayChu, SoDong, N'SinhVien (mảnh học vụ)'
FROM OPENQUERY(LS_QLSV_NgoaiNgu, 'SELECT @@SERVERNAME AS MayChu, (SELECT COUNT(*) FROM QLSV_NgoaiNgu.dbo.SinhVien) AS SoDong FROM (SELECT 1 AS x) t')
UNION ALL SELECT N'Du lịch', MayChu, SoDong, N'SinhVien (mảnh học vụ)'
FROM OPENQUERY(LS_QLSV_DuLich, 'SELECT @@SERVERNAME AS MayChu, (SELECT COUNT(*) FROM QLSV_DuLich.dbo.SinhVien) AS SoDong FROM (SELECT 1 AS x) t');
GO

/* =====================================================================
   PHẦN 3. TRUY VẤN LIÊN NÚT
   Gợi ý: bật Actual Execution Plan (Ctrl+M) để thấy toán tử "Remote Query" cho chứng cứ.
   ===================================================================== */

-- Câu 1. Đọc một node qua tên 4 phần: 5 sinh viên đầu của khoa CNTT.
SELECT TOP (5) MaSV, HoTen, MaLop
FROM LS_QLSV_CNTT.QLSV_CNTT.dbo.SinhVien
ORDER BY MaSV;
GO

-- Câu 2. Gộp 3 node bằng tên 4 phần rồi so với VIEW toàn cục: hai con số phải bằng nhau.
SELECT (SELECT COUNT(*) FROM (
            SELECT MaSV FROM LS_QLSV_CNTT.QLSV_CNTT.dbo.SinhVien
            UNION ALL SELECT MaSV FROM LS_QLSV_NgoaiNgu.QLSV_NgoaiNgu.dbo.SinhVien
            UNION ALL SELECT MaSV FROM LS_QLSV_DuLich.QLSV_DuLich.dbo.SinhVien) x) AS SoSV_QuaLinkedServer,
       (SELECT COUNT(*) FROM dbo.vw_SinhVien_ToanCuc)                              AS SoSV_QuaViewToanCuc;
GO

-- Câu 3. JOIN liên instance: bảng ở node Du lịch với danh mục MonHoc ở node điều phối.
SELECT lp.MaLHP, m.TenMH, lp.MaGV, lp.SiSoToiDa
FROM LS_QLSV_DuLich.QLSV_DuLich.dbo.LopHocPhan lp
JOIN dbo.MonHoc m ON m.MaMH = lp.MaMH
WHERE lp.MaHK = 'HK1-2627'
ORDER BY lp.MaLHP;
GO

-- Câu 4. JOIN mảnh dọc: học vụ ở node CNTT ghép với hồ sơ ở node điều phối (hai instance khác nhau).
SELECT TOP (3) s.MaSV, s.HoTen, s.MaLop, h.CCCD, h.Email
FROM LS_QLSV_CNTT.QLSV_CNTT.dbo.SinhVien s
JOIN dbo.SinhVien_HoSo h ON h.MaSV = s.MaSV
ORDER BY s.MaSV;
GO

-- Câu 5. OPENQUERY: câu truy vấn chạy NGUYÊN BÊN node (lọc ở xa, chỉ trả về kết quả) - nhanh hơn tên 4 phần.
SELECT * FROM OPENQUERY(LS_QLSV_NgoaiNgu,
    'SELECT MaLHP, COUNT(*) AS SoSVDangKy
     FROM QLSV_NgoaiNgu.dbo.DangKy
     GROUP BY MaLHP
     HAVING COUNT(*) >= 10');
GO

-- Câu 6. Chạy lệnh từ xa bằng EXEC ... AT (cần tùy chọn rpc out).
EXEC (N'SELECT @@SERVERNAME AS MayChu, COUNT(*) AS SoDangKyOKhoaCNTT FROM QLSV_CNTT.dbo.DangKy') AT LS_QLSV_CNTT;
GO

/* =====================================================================
   PHẦN 4. TRUY VẤN TỔNG HỢP TOÀN HỆ THỐNG (lấy dữ liệu từ cả 3 node trong một câu)
   ===================================================================== */

-- Câu 7. Điểm tổng kết trung bình của mỗi khoa ở HK2-2526, ghép từ 3 instance.
SELECT x.TenKhoa, CAST(AVG(x.DiemTK) AS DECIMAL(4,2)) AS DiemTB, COUNT(x.DiemTK) AS SoLuotCoDiem
FROM (
    SELECT N'CNTT' AS TenKhoa, dk.DiemTK
    FROM LS_QLSV_CNTT.QLSV_CNTT.dbo.DangKy dk JOIN LS_QLSV_CNTT.QLSV_CNTT.dbo.LopHocPhan lp ON lp.MaLHP = dk.MaLHP
    WHERE lp.MaHK = 'HK2-2526'
    UNION ALL
    SELECT N'NN', dk.DiemTK
    FROM LS_QLSV_NgoaiNgu.QLSV_NgoaiNgu.dbo.DangKy dk JOIN LS_QLSV_NgoaiNgu.QLSV_NgoaiNgu.dbo.LopHocPhan lp ON lp.MaLHP = dk.MaLHP
    WHERE lp.MaHK = 'HK2-2526'
    UNION ALL
    SELECT N'DL', dk.DiemTK
    FROM LS_QLSV_DuLich.QLSV_DuLich.dbo.DangKy dk JOIN LS_QLSV_DuLich.QLSV_DuLich.dbo.LopHocPhan lp ON lp.MaLHP = dk.MaLHP
    WHERE lp.MaHK = 'HK2-2526'
) x
GROUP BY x.TenKhoa
ORDER BY x.TenKhoa;
GO

-- Câu 8. Cùng bài toán qua VIEW toàn cục (view đọc 3 node bằng synonym): kết quả phải khớp câu 7 về số lượt.
SELECT TenKhoa, COUNT(DiemTK) AS SoLuotCoDiem
FROM dbo.vw_BangDiem WHERE MaHK = 'HK2-2526'
GROUP BY TenKhoa ORDER BY TenKhoa;
GO

-- Câu 9. Tổng số sinh viên và số đăng ký của cả trường, mỗi con số do một instance trả về.
SELECT n.Khoa, n.SoSV, n.SoDangKy, SUM(n.SoSV) OVER () AS TongSVToanTruong, SUM(n.SoDangKy) OVER () AS TongDangKy
FROM (
    SELECT N'CNTT' AS Khoa, (SELECT COUNT(*) FROM LS_QLSV_CNTT.QLSV_CNTT.dbo.SinhVien) AS SoSV,
           (SELECT COUNT(*) FROM LS_QLSV_CNTT.QLSV_CNTT.dbo.DangKy) AS SoDangKy
    UNION ALL SELECT N'NN', (SELECT COUNT(*) FROM LS_QLSV_NgoaiNgu.QLSV_NgoaiNgu.dbo.SinhVien),
                            (SELECT COUNT(*) FROM LS_QLSV_NgoaiNgu.QLSV_NgoaiNgu.dbo.DangKy)
    UNION ALL SELECT N'DL', (SELECT COUNT(*) FROM LS_QLSV_DuLich.QLSV_DuLich.dbo.SinhVien),
                            (SELECT COUNT(*) FROM LS_QLSV_DuLich.QLSV_DuLich.dbo.DangKy)
) n;
GO

/* =====================================================================
   PHẦN 5. GIAO DỊCH PHÂN TÁN (MSDTC): sửa 2 node trong một giao dịch rồi ROLLBACK
   ===================================================================== */
BEGIN DISTRIBUTED TRANSACTION;
    UPDATE LS_QLSV_CNTT.QLSV_CNTT.dbo.DangKy       SET DiemThi = 9 WHERE MaSV = '24010001' AND MaLHP = 'CNTT101-HK1-2425-01';
    UPDATE LS_QLSV_NgoaiNgu.QLSV_NgoaiNgu.dbo.DangKy SET DiemThi = 9 WHERE MaSV = '24020001' AND MaLHP = 'NN101-HK1-2425-01';
    SELECT N'Trong giao dịch' AS Buoc,
           (SELECT DiemThi FROM LS_QLSV_CNTT.QLSV_CNTT.dbo.DangKy WHERE MaSV = '24010001' AND MaLHP = 'CNTT101-HK1-2425-01') AS DiemThiCNTT,
           (SELECT DiemThi FROM LS_QLSV_NgoaiNgu.QLSV_NgoaiNgu.dbo.DangKy WHERE MaSV = '24020001' AND MaLHP = 'NN101-HK1-2425-01') AS DiemThiNN;
ROLLBACK TRANSACTION;
SELECT N'Sau ROLLBACK' AS Buoc,
       (SELECT DiemThi FROM LS_QLSV_CNTT.QLSV_CNTT.dbo.DangKy WHERE MaSV = '24010001' AND MaLHP = 'CNTT101-HK1-2425-01') AS DiemThiCNTT,
       (SELECT DiemThi FROM LS_QLSV_NgoaiNgu.QLSV_NgoaiNgu.dbo.DangKy WHERE MaSV = '24020001' AND MaLHP = 'NN101-HK1-2425-01') AS DiemThiNN;
GO

/* =====================================================================
   PHẦN 6. KIỂM TRA BẢO MẬT: quyền ở node do node quyết định
   lg_bgh (Ban giám hiệu) đi sang node bằng login cùng tên lg_bgh, không có quyền ghi: node từ chối.
   ===================================================================== */
EXECUTE AS LOGIN = 'lg_bgh';
BEGIN TRY
    DELETE FROM LS_QLSV_CNTT.QLSV_CNTT.dbo.DangKy WHERE MaSV = '00000000';
    SELECT N'LỖI BẢO MẬT: lg_bgh ghi được vào node CNTT' AS KetQua;
END TRY
BEGIN CATCH
    SELECT N'Đúng: node CNTT từ chối lg_bgh' AS KetQua, ERROR_NUMBER() AS MaLoi, ERROR_MESSAGE() AS ThongBao;
END CATCH
REVERT;
GO
