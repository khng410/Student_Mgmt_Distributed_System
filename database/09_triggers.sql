/* =====================================================================
   ĐỒ ÁN CSDL PHÂN TÁN – QUẢN LÝ SINH VIÊN NHIỀU KHOA
   File   : 09_triggers.sql
   Mục đích: 5 trigger kiểm soát dữ liệu và ghi log. Trigger là đối tượng của TỪNG database,
             nên 4 trigger của node khoa được cài vào cả 3 node (QLSV_CNTT, QLSV_NgoaiNgu,
             QLSV_DuLich) và 1 trigger cài ở QLSV_TongHop.
   Người viết: ...............          Ngày: ..../11/2026
   Chạy sau : 08_functions.sql            Chạy lại nhiều lần được (CREATE OR ALTER).

   #  Trigger                          Bảng (database)            Sự kiện            Việc làm
   1  trg_DangKy_GhiNhatKy             DangKy (3 node)            AFTER UPDATE,DELETE ghi NhatKy khi đổi điểm hoặc xóa đăng ký
   2  trg_SinhVien_ChanXoa             SinhVien (3 node)          INSTEAD OF DELETE   chặn xóa sinh viên đã có đăng ký/điểm
   3  trg_LopHocPhan_KiemTraMonHoc     LopHocPhan (3 node)        AFTER INSERT,UPDATE MaMH phải có ở danh mục GỐC (QLSV_TongHop)
   4  trg_HoSo_KiemTraSinhVien         SinhVien_HoSo (TongHop)    AFTER INSERT,UPDATE MaSV phải có ở một node khoa (thay cho FK
                                                                                      liên database, SQL Server không hỗ trợ)
   5  trg_DangKy_KiemTraDangKy         DangKy (3 node)            AFTER INSERT        chỉ SV đang học, không vượt sĩ số tối đa

   Trigger chặn lỗi dùng ROLLBACK TRANSACTION rồi THROW (mã 50901-50905). Khi bắt lỗi ở
   TRY...CATCH nhớ kiểm tra @@TRANCOUNT trước khi ROLLBACK, vì trigger đã hủy transaction.
   04_fragmentation.sql tắt/bật các trigger này khi nạp lại dữ liệu hàng loạt.
   LƯU Ý: bảng có trigger thì lệnh INSERT/UPDATE/DELETE ... OUTPUT phải dùng OUTPUT ... INTO
   (đã sửa trong 06_queries_40.sql câu 34 và 35).
   ===================================================================== */

SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
USE QLSV_TongHop;
GO

/* =====================================================================
   PHẦN 1. TRIGGER Ở NODE ĐIỀU PHỐI – QLSV_TongHop
   ===================================================================== */

CREATE OR ALTER TRIGGER dbo.trg_HoSo_KiemTraSinhVien
ON dbo.SinhVien_HoSo
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM inserted i
               WHERE NOT EXISTS (SELECT 1 FROM QLSV_CNTT.dbo.SinhVien     WHERE MaSV = i.MaSV)
                 AND NOT EXISTS (SELECT 1 FROM QLSV_NgoaiNgu.dbo.SinhVien WHERE MaSV = i.MaSV)
                 AND NOT EXISTS (SELECT 1 FROM QLSV_DuLich.dbo.SinhVien   WHERE MaSV = i.MaSV))
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50905, N'Mã sinh viên chưa có ở node khoa nào: hồ sơ phải đi cùng một sinh viên.', 1;
    END
END
GO


/* =====================================================================
   PHẦN 2. TRIGGER Ở 3 NODE KHOA – cài bằng vòng lặp qua từng database
   Trong nội dung trigger, dấu ~ được đổi thành dấu nháy đơn khi cài (để khỏi gấp đôi nháy).
   ===================================================================== */

DECLARE @trg TABLE (ten SYSNAME, noi NVARCHAR(MAX));

INSERT @trg VALUES
(N'trg_DangKy_GhiNhatKy', N'
CREATE OR ALTER TRIGGER dbo.trg_DangKy_GhiNhatKy
ON dbo.DangKy
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.NhatKy (TenBang, HanhDong, KhoaChinh, NoiDungCu, NoiDungMoi)
    SELECT N~DangKy~,
           CASE WHEN i.MaSV IS NULL THEN ~DELETE~ ELSE ~UPDATE~ END,
           d.MaSV + ~|~ + d.MaLHP,
           N~DiemQT=~ + ISNULL(CONVERT(NVARCHAR(10), d.DiemQT), N~NULL~)
             + N~; DiemThi=~ + ISNULL(CONVERT(NVARCHAR(10), d.DiemThi), N~NULL~)
             + N~; DiemTK=~  + ISNULL(CONVERT(NVARCHAR(10), d.DiemTK), N~NULL~),
           CASE WHEN i.MaSV IS NULL THEN NULL
                ELSE N~DiemQT=~ + ISNULL(CONVERT(NVARCHAR(10), i.DiemQT), N~NULL~)
                     + N~; DiemThi=~ + ISNULL(CONVERT(NVARCHAR(10), i.DiemThi), N~NULL~)
                     + N~; DiemTK=~  + ISNULL(CONVERT(NVARCHAR(10), i.DiemTK), N~NULL~) END
    FROM deleted d
    LEFT JOIN inserted i ON i.MaSV = d.MaSV AND i.MaLHP = d.MaLHP
    WHERE i.MaSV IS NULL
       OR NOT EXISTS (SELECT d.DiemQT, d.DiemThi INTERSECT SELECT i.DiemQT, i.DiemThi);
END'),

(N'trg_SinhVien_ChanXoa', N'
CREATE OR ALTER TRIGGER dbo.trg_SinhVien_ChanXoa
ON dbo.SinhVien
INSTEAD OF DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM deleted d JOIN dbo.DangKy k ON k.MaSV = d.MaSV)
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50901, N~Không thể xóa sinh viên đã có đăng ký học phần hoặc điểm.~, 1;
    END
    DELETE s FROM dbo.SinhVien s JOIN deleted d ON d.MaSV = s.MaSV;
END'),

(N'trg_LopHocPhan_KiemTraMonHoc', N'
CREATE OR ALTER TRIGGER dbo.trg_LopHocPhan_KiemTraMonHoc
ON dbo.LopHocPhan
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM inserted i
               WHERE NOT EXISTS (SELECT 1 FROM QLSV_TongHop.dbo.MonHoc m WHERE m.MaMH = i.MaMH))
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50902, N~Môn học không có trong danh mục gốc ở QLSV_TongHop (bản sao ở node có thể đã cũ).~, 1;
    END
END'),

(N'trg_DangKy_KiemTraDangKy', N'
CREATE OR ALTER TRIGGER dbo.trg_DangKy_KiemTraDangKy
ON dbo.DangKy
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM inserted i JOIN dbo.SinhVien s ON s.MaSV = i.MaSV
               WHERE s.TrangThai <> N~Đang học~)
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50903, N~Chỉ sinh viên đang học mới được đăng ký học phần.~, 1;
    END
    IF EXISTS (SELECT 1 FROM inserted i JOIN dbo.LopHocPhan lp ON lp.MaLHP = i.MaLHP
               WHERE (SELECT COUNT(*) FROM dbo.DangKy k WHERE k.MaLHP = lp.MaLHP) > lp.SiSoToiDa)
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50904, N~Lớp học phần đã vượt sĩ số tối đa.~, 1;
    END
END');

DECLARE @db SYSNAME, @noi NVARCHAR(MAX), @sql NVARCHAR(MAX), @exec NVARCHAR(300);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT n.db, t.noi
    FROM (VALUES (N'QLSV_CNTT'), (N'QLSV_NgoaiNgu'), (N'QLSV_DuLich')) n(db)
    CROSS JOIN @trg t;
OPEN c;
FETCH NEXT FROM c INTO @db, @noi;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql  = REPLACE(@noi, N'~', N'''');
    SET @exec = QUOTENAME(@db) + N'.sys.sp_executesql';     -- chạy trong ngữ cảnh database của node
    EXEC @exec @sql;                                        -- mỗi lần 1 trigger (CREATE TRIGGER phải đứng đầu batch)
    FETCH NEXT FROM c INTO @db, @noi;
END
CLOSE c;
DEALLOCATE c;
GO

-- Kiểm tra cài đặt: 1 trigger ở TongHop + 4 trigger x 3 node = 13 đối tượng, 5 loại trigger
SELECT db, ten AS Trigger_, bang AS TrenBang
FROM (
    SELECT N'QLSV_TongHop' AS db, name AS ten, OBJECT_NAME(parent_id, DB_ID(N'QLSV_TongHop')) AS bang FROM QLSV_TongHop.sys.triggers
    UNION ALL SELECT N'QLSV_CNTT',     name, OBJECT_NAME(parent_id, DB_ID(N'QLSV_CNTT'))     FROM QLSV_CNTT.sys.triggers
    UNION ALL SELECT N'QLSV_NgoaiNgu', name, OBJECT_NAME(parent_id, DB_ID(N'QLSV_NgoaiNgu')) FROM QLSV_NgoaiNgu.sys.triggers
    UNION ALL SELECT N'QLSV_DuLich',   name, OBJECT_NAME(parent_id, DB_ID(N'QLSV_DuLich'))   FROM QLSV_DuLich.sys.triggers
) x
ORDER BY ten, db;
GO


/* =====================================================================
   PHẦN 3. MINH HỌA – INSERT / UPDATE / DELETE làm trigger chạy (mọi ví dụ đều ROLLBACK)
   ===================================================================== */

-- Trigger 1: trg_DangKy_GhiNhatKy. UPDATE điểm thi và DELETE một đăng ký -> NhatKy có 2 dòng mới.
BEGIN TRAN;
    UPDATE QLSV_CNTT.dbo.DangKy SET DiemThi = 9.5
    WHERE MaSV = '24010001' AND MaLHP = 'CNTT101-HK1-2425-01';
    DELETE FROM QLSV_CNTT.dbo.DangKy
    WHERE MaSV = '24010001' AND MaLHP = 'CNTT102-HK1-2425-01';

    SELECT TOP (2) MaNK, HanhDong, KhoaChinh, NoiDungCu, NoiDungMoi, NguoiThucHien
    FROM QLSV_CNTT.dbo.NhatKy ORDER BY MaNK DESC;
ROLLBACK TRAN;
GO

-- Trigger 2: trg_SinhVien_ChanXoa. Xóa sinh viên đã có đăng ký -> bị chặn; sinh viên chưa đăng ký -> xóa được.
BEGIN TRY
    DELETE FROM QLSV_CNTT.dbo.SinhVien WHERE MaSV = '24010001';
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS MaLoi, ERROR_MESSAGE() AS ThongBao;
    IF @@TRANCOUNT > 0 ROLLBACK;
END CATCH
BEGIN TRAN;
    DELETE FROM QLSV_CNTT.dbo.SinhVien WHERE MaSV = '24010016';
    SELECT N'Sau DELETE (24010016 chưa đăng ký môn nào)' AS Buoc, COUNT(*) AS SoDong
    FROM QLSV_CNTT.dbo.SinhVien WHERE MaSV = '24010016';          -- = 0
ROLLBACK TRAN;
GO

-- Trigger 3: trg_LopHocPhan_KiemTraMonHoc. Môn CNTT999 chỉ có ở bản sao của node, không có ở bản gốc TongHop.
--   Khóa ngoại cục bộ cho qua, trigger chặn lại.
BEGIN TRY
    BEGIN TRAN;
        INSERT QLSV_CNTT.dbo.MonHoc (MaMH, TenMH, SoTinChi, MaKhoa)
        VALUES ('CNTT999', N'Môn chỉ có ở bản sao', 3, 'CNTT');
        INSERT QLSV_CNTT.dbo.LopHocPhan (MaLHP, MaMH, MaHK, Nhom, MaGV, SiSoToiDa)
        VALUES ('CNTT999-HK1-2627-01', 'CNTT999', 'HK1-2627', 1, 'GVCNTT01', 50);
    COMMIT;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS MaLoi, ERROR_MESSAGE() AS ThongBao;
    IF @@TRANCOUNT > 0 ROLLBACK;
END CATCH
SELECT N'Sau lỗi: môn CNTT999 còn ở node không?' AS KiemTra, COUNT(*) AS SoDong
FROM QLSV_CNTT.dbo.MonHoc WHERE MaMH = 'CNTT999';                -- = 0 (transaction đã bị hủy)
GO

-- Trigger 4: trg_HoSo_KiemTraSinhVien. Thêm hồ sơ cho mã sinh viên chưa có ở node nào -> bị chặn.
BEGIN TRY
    INSERT dbo.SinhVien_HoSo (MaSV, CCCD, Email)
    VALUES ('77777777', '001306007777', 'khongcosv@sv.qlsv.edu.vn');
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS MaLoi, ERROR_MESSAGE() AS ThongBao;
    IF @@TRANCOUNT > 0 ROLLBACK;
END CATCH
GO

-- Trigger 5: trg_DangKy_KiemTraDangKy. (a) sinh viên đang bảo lưu đăng ký -> bị chặn;
--            (b) thử đặt sĩ số tối đa còn 10 rồi đăng ký thêm khi lớp đã có hơn 10 người -> bị chặn.
BEGIN TRY
    INSERT QLSV_CNTT.dbo.DangKy (MaSV, MaLHP) VALUES ('24010008', 'CNTT110-HK1-2627-01');   -- 24010008 đang bảo lưu
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS MaLoi, ERROR_MESSAGE() AS ThongBao;
    IF @@TRANCOUNT > 0 ROLLBACK;
END CATCH
BEGIN TRY
    BEGIN TRAN;
        UPDATE QLSV_CNTT.dbo.LopHocPhan SET SiSoToiDa = 10 WHERE MaLHP = 'CNTT110-HK1-2627-01';
        INSERT QLSV_CNTT.dbo.DangKy (MaSV, MaLHP) VALUES ('24010016', 'CNTT110-HK1-2627-01');
    COMMIT;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS MaLoi, ERROR_MESSAGE() AS ThongBao;
    IF @@TRANCOUNT > 0 ROLLBACK;
END CATCH
SELECT N'Sau lỗi: sĩ số tối đa đã trở lại' AS KiemTra, SiSoToiDa
FROM QLSV_CNTT.dbo.LopHocPhan WHERE MaLHP = 'CNTT110-HK1-2627-01';   -- không còn là 10
GO
