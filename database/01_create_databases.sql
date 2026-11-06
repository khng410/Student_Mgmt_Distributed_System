/* =====================================================================
   ĐỒ ÁN CSDL PHÂN TÁN – QUẢN LÝ SINH VIÊN NHIỀU KHOA
   File   : 01_create_databases.sql
   Mục đích: Tạo 5 database mô phỏng hệ thống phân tán trên 1 SQL Server
             instance.
   Người viết: ...............          Ngày: ..../11/2026

   KIẾN TRÚC
   ---------------------------------------------------------------------
   QLSV_TapTrung : CSDL TẬP TRUNG (thiết kế gốc, trước khi phân tán).
                   Dùng để minh họa bước "tập trung -> phân tán" và để
                   kiểm tra tái thiết (dữ liệu ghép lại = dữ liệu gốc).
   QLSV_TongHop  : NODE ĐIỀU PHỐI (Phòng Đào tạo). Giữ bản chính của các
                   bảng danh mục, mảnh dọc hồ sơ sinh viên, VIEW toàn cục.
   QLSV_CNTT     : NODE 1 – Khoa Công nghệ Thông tin   (MaKhoa = 'CNTT')
   QLSV_NgoaiNgu : NODE 2 – Khoa Ngoại ngữ             (MaKhoa = 'NN')
   QLSV_DuLich   : NODE 3 – Khoa Du lịch               (MaKhoa = 'DL')

   - Collation Vietnamese_CI_AS để sắp xếp / so sánh tiếng Việt đúng.
   - Script chạy lại nhiều lần được: database cũ bị xóa rồi tạo mới.
   ===================================================================== */

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
USE master;
GO

/* ---------- 1. Xóa database cũ (nếu có) ---------- */
DECLARE @db SYSNAME, @sql NVARCHAR(MAX);
DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM (VALUES (N'QLSV_TapTrung'), (N'QLSV_TongHop'),
                             (N'QLSV_CNTT'), (N'QLSV_NgoaiNgu'),
                             (N'QLSV_DuLich')) AS d(name);
OPEN cur;
FETCH NEXT FROM cur INTO @db;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF DB_ID(@db) IS NOT NULL
    BEGIN
        -- Ngắt mọi kết nối đang mở tới database rồi mới xóa
        SET @sql = N'ALTER DATABASE ' + QUOTENAME(@db)
                 + N' SET SINGLE_USER WITH ROLLBACK IMMEDIATE; '
                 + N'DROP DATABASE ' + QUOTENAME(@db) + N';';
        EXEC (@sql);
        PRINT N'Đã xóa database ' + @db;
    END
    FETCH NEXT FROM cur INTO @db;
END
CLOSE cur;
DEALLOCATE cur;
GO

/* ---------- 2. Tạo database ---------- */
CREATE DATABASE QLSV_TapTrung COLLATE Vietnamese_CI_AS;
GO
CREATE DATABASE QLSV_TongHop  COLLATE Vietnamese_CI_AS;
GO
CREATE DATABASE QLSV_CNTT     COLLATE Vietnamese_CI_AS;
GO
CREATE DATABASE QLSV_NgoaiNgu COLLATE Vietnamese_CI_AS;
GO
CREATE DATABASE QLSV_DuLich   COLLATE Vietnamese_CI_AS;
GO

/* ---------- 3. Kiểm tra kết quả ---------- */
SELECT name            AS TenDatabase,
       collation_name  AS Collation,
       create_date     AS NgayTao
FROM sys.databases
WHERE name LIKE N'QLSV[_]%'
ORDER BY create_date;
GO
