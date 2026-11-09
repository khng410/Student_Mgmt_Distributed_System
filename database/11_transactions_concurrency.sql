/* =====================================================================
   ĐỒ ÁN CSDL PHÂN TÁN – QUẢN LÝ SINH VIÊN NHIỀU KHOA
   File   : 11_transactions_concurrency.sql
   Mục đích: Giao dịch (COMMIT, ROLLBACK có lỗi), đồng thời (blocking, deadlock) + DMV,
             và hiệu năng (execution plan, STATISTICS IO/TIME, index).
   Người viết: ...............          Ngày: ..../11/2026
   Chạy sau : 10_security.sql             Dùng tài khoản quản trị.

   PHẦN A  chạy cả file (F5).
   PHẦN B, C nằm trong comment: sao chép từng khối ra 2 cửa sổ SSMS và làm theo số bước.
   PHẦN D  truy vấn giám sát, chạy bất cứ lúc nào (không có blocking thì trả 0 dòng).
   PHẦN E  hiệu năng và index: chạy cả phần E (F5); đọc hướng dẫn xem bằng chứng ở đầu phần E.
   ===================================================================== */

SET NOCOUNT ON;
GO
USE QLSV_TongHop;
GO
SET XACT_ABORT ON;
GO

/* ========================= PHẦN A – GIAO DỊCH ========================= */

-- Dọn dữ liệu demo của lần chạy trước
DELETE FROM dbo.SinhVien_HoSo      WHERE MaSV = '99999998';
DELETE FROM QLSV_CNTT.dbo.SinhVien WHERE MaSV = '99999998';
GO

-- A1. COMMIT: thêm 1 sinh viên vào 2 database trong 1 giao dịch -> cả hai nơi đều có dòng.
BEGIN TRAN;
    INSERT QLSV_CNTT.dbo.SinhVien (MaSV, HoTen, NgaySinh, GioiTinh, MaLop)
    VALUES ('99999998', N'Sinh Viên Giao Dịch', '2006-01-01', N'Nam', '66.CNTT-1');
    INSERT dbo.SinhVien_HoSo (MaSV, CCCD, Email)
    VALUES ('99999998', '000000000098', 'gd99999998@sv.qlsv.edu.vn');
COMMIT TRAN;

SELECT N'Sau COMMIT' AS Buoc,
       (SELECT COUNT(*) FROM QLSV_CNTT.dbo.SinhVien WHERE MaSV = '99999998') AS DongOTNodeCNTT,   -- = 1
       (SELECT COUNT(*) FROM dbo.SinhVien_HoSo      WHERE MaSV = '99999998') AS DongOTongHop;     -- = 1

DELETE FROM dbo.SinhVien_HoSo      WHERE MaSV = '99999998';      -- dọn
DELETE FROM QLSV_CNTT.dbo.SinhVien WHERE MaSV = '99999998';
GO

-- A2. ROLLBACK do lỗi cố ý: lệnh thứ nhất (node CNTT) thành công, lệnh thứ hai (TongHop) trùng CCCD
--     nên lỗi -> cả giao dịch bị hủy, node CNTT cũng không còn dòng nào.
DECLARE @cccdTrung CHAR(12) = (SELECT TOP (1) CCCD FROM dbo.SinhVien_HoSo ORDER BY MaSV);
BEGIN TRY
    BEGIN TRAN;
        INSERT QLSV_CNTT.dbo.SinhVien (MaSV, HoTen, NgaySinh, GioiTinh, MaLop)
        VALUES ('99999998', N'Sinh Viên Giao Dịch', '2006-01-01', N'Nam', '66.CNTT-1');
        INSERT dbo.SinhVien_HoSo (MaSV, CCCD, Email)
        VALUES ('99999998', @cccdTrung, 'gd99999998@sv.qlsv.edu.vn');      -- lỗi: trùng CCCD
    COMMIT TRAN;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS MaLoi, ERROR_MESSAGE() AS ThongBao;
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;
END CATCH

SELECT N'Sau ROLLBACK' AS Buoc,
       (SELECT COUNT(*) FROM QLSV_CNTT.dbo.SinhVien WHERE MaSV = '99999998') AS DongOTNodeCNTT,   -- = 0
       (SELECT COUNT(*) FROM dbo.SinhVien_HoSo      WHERE MaSV = '99999998') AS DongOTongHop;     -- = 0
GO

/* ========================= PHẦN B – BLOCKING (2 cửa sổ) =========================
-- BƯỚC 1 – CỬA SỔ 1: sửa 1 dòng ở node CNTT, KHÔNG commit.
USE QLSV_TongHop;
BEGIN TRAN;
    UPDATE QLSV_CNTT.dbo.DangKy SET DiemThi = 9
    WHERE MaSV = '24010001' AND MaLHP = 'CNTT101-HK1-2425-01';

-- BƯỚC 2 – CỬA SỔ 2: sửa CÙNG dòng đó -> bị chặn (con quay cứ chạy).
--   (Dùng lệnh ghi vì người ghi luôn bị chặn. Lệnh đọc có thể KHÔNG bị chặn nếu database bật
--    READ_COMMITTED_SNAPSHOT: người đọc khi đó thấy bản đã commit cũ.)
USE QLSV_TongHop;
SET LOCK_TIMEOUT 120000;     -- sau 120 giây tự báo lỗi thay vì chờ mãi
BEGIN TRAN;
    UPDATE QLSV_CNTT.dbo.DangKy SET DiemThi = 8
    WHERE MaSV = '24010001' AND MaLHP = 'CNTT101-HK1-2425-01';

-- BƯỚC 3 – CỬA SỔ 1: chạy truy vấn D1 và D2 ở PHẦN D.
--   D1 cho thấy SessionBiChan (cửa sổ 2), SessionGayChan (cửa sổ 1), wait_type = LCK_M_U.
--   D2 cho thấy phiên 1 giữ khóa X (GRANT), phiên 2 xin khóa U/X nhưng đang WAIT.

-- BƯỚC 4 – CỬA SỔ 1: hoàn tác -> cửa sổ 2 chạy tiếp ngay.
ROLLBACK TRAN;
-- BƯỚC 5 – CỬA SỔ 2: lệnh UPDATE đã chạy xong, hoàn tác nốt để dữ liệu mẫu nguyên.
ROLLBACK TRAN;
*/
GO

/* ========================= PHẦN C – DEADLOCK (2 cửa sổ) =========================
Hai giao dịch sửa 2 dòng ở 2 node theo thứ tự ngược nhau nên chờ nhau; SQL Server hủy một bên (lỗi 1205).

-- CỬA SỔ 1: chạy TRƯỚC, rồi sang cửa sổ 2 ngay (trong 15 giây).
USE QLSV_TongHop;
BEGIN TRAN;
    UPDATE QLSV_CNTT.dbo.DangKy SET DiemThi = 9
    WHERE MaSV = '24010001' AND MaLHP = 'CNTT101-HK1-2425-01';
    WAITFOR DELAY '00:00:15';
    UPDATE QLSV_NgoaiNgu.dbo.DangKy SET DiemThi = 9
    WHERE MaSV = '24020001' AND MaLHP = 'NN101-HK1-2425-01';
ROLLBACK TRAN;

-- CỬA SỔ 2: chạy ngay sau cửa sổ 1.
USE QLSV_TongHop;
SET DEADLOCK_PRIORITY LOW;   -- cửa sổ 2 là nạn nhân
BEGIN TRAN;
    UPDATE QLSV_NgoaiNgu.dbo.DangKy SET DiemThi = 8
    WHERE MaSV = '24020001' AND MaLHP = 'NN101-HK1-2425-01';
    WAITFOR DELAY '00:00:15';
    UPDATE QLSV_CNTT.dbo.DangKy SET DiemThi = 8
    WHERE MaSV = '24010001' AND MaLHP = 'CNTT101-HK1-2425-01';
ROLLBACK TRAN;

-- KẾT QUẢ: cửa sổ 2 báo "Msg 1205 ... chosen as the deadlock victim"; cửa sổ 1 chạy xong.
-- CÁCH TRÁNH: mọi giao dịch cùng sửa theo một thứ tự (CNTT trước, Ngoại ngữ sau) thì chỉ chờ, không deadlock.
*/
GO

/* ========================= PHẦN D – GIÁM SÁT (DMV) ========================= */

-- D1. Phiên nào đang bị chặn, bị phiên nào chặn?
SELECT r.session_id AS SessionBiChan, r.blocking_session_id AS SessionGayChan,
       r.wait_type, r.wait_time AS MsDaCho, DB_NAME(r.database_id) AS DB,
       SUBSTRING(t.text, 1, 150) AS CauLenhBiChan
FROM sys.dm_exec_requests r
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.blocking_session_id <> 0;
GO

-- D2. Khóa đang giữ (GRANT) hoặc đang chờ (WAIT) ở TongHop và 3 node
SELECT request_session_id AS Session, DB_NAME(resource_database_id) AS DB,
       resource_type, request_mode, request_status
FROM sys.dm_tran_locks
WHERE resource_type <> 'DATABASE'
  AND resource_database_id IN (DB_ID(N'QLSV_TongHop'), DB_ID(N'QLSV_CNTT'), DB_ID(N'QLSV_NgoaiNgu'), DB_ID(N'QLSV_DuLich'))
ORDER BY request_session_id, request_status DESC;
GO

/* #####################################################################
   PHẦN E – HIỆU NĂNG: Actual Execution Plan, STATISTICS IO/TIME, index
   VÌ SAO CẦN BẢNG THỬ: dữ liệu mẫu chỉ có vài trăm dòng (vài trang dữ liệu), quá nhỏ để thấy
   khác biệt. E1 tạo bảng tạm #PerfDangKy 300.000 dòng, cấu trúc giống DangKy
   (khóa chính MaSV, MaLHP). Bảng tạm nằm ở tempdb, tự mất khi đóng cửa sổ và không đụng tới
   dữ liệu thật. E2 mới tạo index thật cho các node.

   CÁCH XEM BẰNG CHỨNG (chụp ảnh cho báo cáo và demo mục 6 của đề)
   * SSMS: bấm Ctrl+M (Include Actual Execution Plan) trước khi chạy E1. Tab "Execution plan"
           hiện sơ đồ; xem toán tử Clustered Index Scan (trước) và Index Seek (sau). Tab Messages
           có dòng "logical reads" của STATISTICS IO và "elapsed time" của STATISTICS TIME.
   * Công cụ khác (SQLPro...): STATISTICS PROFILE đã bật sẵn nên kế hoạch thực tế hiện thành bảng
     chữ, cột StmtText ghi tên toán tử (Clustered Index Scan / Index Seek). Số trang đã đọc xem ở tab
     Messages (dòng "logical reads" của STATISTICS IO); ghi 3 con số: A trước, B, A sau.
   ##################################################################### */
GO

/* =====================================================================
   E1. Bảng thử, đo TRƯỚC, tạo index, đo SAU (cùng một batch)
   ===================================================================== */
DROP TABLE IF EXISTS #PerfDangKy;

CREATE TABLE #PerfDangKy (
    MaSV        CHAR(8)       NOT NULL,
    MaLHP       VARCHAR(20)   NOT NULL,
    NgayDangKy  DATE          NOT NULL,
    DiemQT      DECIMAL(4,2)  NULL,
    DiemThi     DECIMAL(4,2)  NULL,
    DiemTK      DECIMAL(4,2)  NULL,
    CONSTRAINT PK_PerfDangKy PRIMARY KEY (MaSV, MaLHP)      -- giống bảng DangKy thật
);

-- 10.000 lớp học phần x 30 sinh viên = 300.000 dòng
;WITH n AS (
    SELECT TOP (300000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS i
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
INSERT #PerfDangKy (MaSV, MaLHP, NgayDangKy, DiemQT, DiemThi, DiemTK)
SELECT RIGHT('00000000' + CAST(((i % 30) + (i / 30) * 7) % 20000 AS VARCHAR(8)), 8),
       'LHP' + RIGHT('00000' + CAST(i / 30 + 1 AS VARCHAR(5)), 5),
       DATEADD(DAY, i % 365, '2025-09-01'),
       4 + (i % 61) / 10.0, 4 + (i % 53) / 10.0, 4 + (i % 57) / 10.0
FROM n;

SELECT COUNT(*) AS SoDong FROM #PerfDangKy;

SET STATISTICS IO ON;
SET STATISTICS TIME ON;
SET STATISTICS PROFILE ON;          -- kế hoạch thực tế dạng bảng chữ (cột StmtText)

/* ---- đo TRƯỚC khi có index ---- */

-- Truy vấn A: tìm theo MaLHP (cột KHÔNG đứng đầu khóa chính) -> phải quét cả bảng
SELECT COUNT(*) AS SoSV, AVG(DiemTK) AS DiemTB FROM #PerfDangKy WHERE MaLHP = 'LHP05000';

-- Truy vấn B: tìm theo MaSV (cột đứng đầu khóa chính) -> đã có Index Seek nhờ khóa chính
SELECT COUNT(*) AS SoLop, AVG(DiemTK) AS DiemTB FROM #PerfDangKy WHERE MaSV = '00001234';

SET STATISTICS PROFILE OFF;

/* ---- Tạo index cho truy vấn A ---- */
CREATE NONCLUSTERED INDEX IX_PerfDangKy_MaLHP ON #PerfDangKy (MaLHP) INCLUDE (DiemTK);

/* ---- đo SAU khi có index: cùng truy vấn A ---- */
SET STATISTICS PROFILE ON;
SELECT COUNT(*) AS SoSV, AVG(DiemTK) AS DiemTB FROM #PerfDangKy WHERE MaLHP = 'LHP05000';
SET STATISTICS PROFILE OFF;

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;

DROP TABLE #PerfDangKy;
GO

/* =====================================================================
   NHẬN XÉT (viết lại theo số liệu của bạn khi đưa vào báo cáo, mục 10)
   Ví dụ đã đo: A trước = 1753 logical reads (Clustered Index Scan); B = 3; A sau = 3 (Index Seek).
   ---------------------------------------------------------------------
   1. Truy vấn A lọc theo MaLHP. Khóa chính (MaSV, MaLHP) sắp xếp theo MaSV trước, nên MaLHP không
      dùng được để tìm nhanh: SQL Server phải quét toàn bộ bảng (Clustered Index Scan), số trang
      đọc xấp xỉ số trang của cả bảng.
   2. Sau khi tạo index không cụm trên MaLHP, kế hoạch chuyển sang Index Seek: chỉ đọc vài trang để
      đi từ gốc cây tới các dòng của lớp đó. Số trang đọc giảm hàng trăm lần.
   3. INCLUDE (DiemTK) làm index "phủ" truy vấn: không cần quay lại bảng gốc (không có Key Lookup).
   4. Truy vấn B lọc theo MaSV, đứng đầu khóa chính nên đã Seek từ trước: tạo thêm index là thừa.
      Index chỉ có ích khi khớp cách truy vấn thật sự dùng bảng.
   5. Cái giá: mỗi index làm INSERT/UPDATE/DELETE chậm hơn một chút và tốn dung lượng, nên chỉ
      tạo cho truy vấn chạy thường xuyên. Ở hệ thống này, MaLHP được lọc trong sĩ số lớp học
      phần (fn_SiSoLopHocPhan, sp_DangKyHocPhan, trigger kiểm tra sĩ số) và khóa ngoại tới
      LopHocPhan, nên index này đáng giá.
   6. SQL Server không tự tạo index cho cột khóa ngoại; index trên MaLHP còn giúp tránh quét
      DangKy khi xóa hoặc sửa một lớp học phần.
   ===================================================================== */

/* =====================================================================
   E2. Tạo index thật cho bảng DangKy ở 3 node khoa
   (chạy lại 02_create_tables.sql sẽ xóa bảng và index này -> chạy lại phần E2)
   ===================================================================== */
DECLARE @tpl NVARCHAR(MAX) = N'
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N''IX_DangKy_MaLHP'' AND object_id = OBJECT_ID(N''dbo.DangKy''))
    CREATE NONCLUSTERED INDEX IX_DangKy_MaLHP ON dbo.DangKy (MaLHP) INCLUDE (DiemQT, DiemThi, DiemTK);';
DECLARE @db SYSNAME, @exec NVARCHAR(300);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT db FROM (VALUES (N'QLSV_CNTT'), (N'QLSV_NgoaiNgu'), (N'QLSV_DuLich')) d(db);
OPEN c;
FETCH NEXT FROM c INTO @db;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @exec = QUOTENAME(@db) + N'.sys.sp_executesql';
    EXEC @exec @tpl;
    FETCH NEXT FROM c INTO @db;
END
CLOSE c;
DEALLOCATE c;
GO

-- Kiểm tra: mỗi node có index mới trên DangKy(MaLHP)
SELECT N'QLSV_CNTT' AS DB, name AS TenIndex, type_desc FROM QLSV_CNTT.sys.indexes
WHERE object_id = OBJECT_ID(N'QLSV_CNTT.dbo.DangKy') AND name = N'IX_DangKy_MaLHP'
UNION ALL
SELECT N'QLSV_NgoaiNgu', name, type_desc FROM QLSV_NgoaiNgu.sys.indexes
WHERE object_id = OBJECT_ID(N'QLSV_NgoaiNgu.dbo.DangKy') AND name = N'IX_DangKy_MaLHP'
UNION ALL
SELECT N'QLSV_DuLich', name, type_desc FROM QLSV_DuLich.sys.indexes
WHERE object_id = OBJECT_ID(N'QLSV_DuLich.dbo.DangKy') AND name = N'IX_DangKy_MaLHP';
GO
