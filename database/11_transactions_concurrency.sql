/* =====================================================================
   ĐỒ ÁN CSDL PHÂN TÁN – QUẢN LÝ SINH VIÊN NHIỀU KHOA
   File   : 11_transactions_concurrency.sql
   Mục đích: Giao dịch (COMMIT, ROLLBACK có lỗi) và đồng thời (blocking, deadlock) + DMV.
   Người viết: ...............          Ngày: ..../11/2026
   Chạy sau : 10_security.sql             Dùng tài khoản quản trị.

   PHẦN A  chạy cả file (F5).
   PHẦN B, C nằm trong comment: sao chép từng khối ra 2 cửa sổ SSMS và làm theo số bước.
   PHẦN D  truy vấn giám sát, chạy bất cứ lúc nào (không có blocking thì trả 0 dòng).
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
