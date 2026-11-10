/* =====================================================================
   ĐỒ ÁN CSDL PHÂN TÁN – QUẢN LÝ SINH VIÊN NHIỀU KHOA
   File   : 09_triggers.sql
   Mục đích: 7 trigger kiểm soát dữ liệu và ghi log. Trigger là đối tượng của TỪNG database,
             nên 5 trigger của node khoa được cài vào cả 3 node (QLSV_CNTT, QLSV_NgoaiNgu,
             QLSV_DuLich) và 2 trigger cài ở QLSV_TongHop.
   Người viết: ...............          Ngày: ..../11/2026
   Chạy sau : 08_functions.sql            Chạy lại nhiều lần được (CREATE OR ALTER).

   #  Trigger                          Bảng (database)            Sự kiện            Việc làm
   1  trg_DangKy_GhiNhatKy             DangKy (3 node)            AFTER UPDATE,DELETE ghi NhatKy khi đổi điểm hoặc xóa đăng ký
   2  trg_SinhVien_ChanXoa             SinhVien (3 node)          INSTEAD OF DELETE   chặn xóa sinh viên đã có đăng ký/điểm
   3  trg_LopHocPhan_KiemTraMonHoc     LopHocPhan (3 node)        AFTER INSERT,UPDATE môn phải của khoa giảng viên (hoặc môn chung)
   4  trg_HoSo_KiemTraSinhVien         SinhVien_HoSo (TongHop)    AFTER INSERT,UPDATE MaSV phải có ở một node khoa (thay cho FK
                                                                                      liên database, SQL Server không hỗ trợ)
   5  trg_DangKy_KiemTraDangKy         DangKy (3 node)            AFTER INSERT        chỉ SV đang học, không vượt sĩ số tối đa
   6  trg_SinhVien_GhiNhatKy           SinhVien (3 node)          AFTER INSERT,UPDATE,DELETE
                                                                                      ghi NhatKy khi thêm / sửa / xóa / chuyển khoa
   7  trg_HoSo_GhiNhatKy               SinhVien_HoSo (TongHop)    AFTER INSERT,UPDATE,DELETE
                                                                                      ghi NhatKy hồ sơ cá nhân (CCCD, điện thoại chỉ
                                                                                      ghi 4 / 3 số cuối)
   Trigger 6 và 7 bỏ qua mã sinh viên 99999999, mã dành riêng cho sp_DemoGiaoDich, để dữ liệu demo không
   làm rối nhật ký (cố định theo mã, không có cờ nào để người dùng tự tắt nhật ký).
   Chuyển khoa hiện thành DELETE ở node cũ + INSERT ở node mới.

   Trigger chặn lỗi dùng ROLLBACK TRANSACTION rồi THROW (mã 50901-50905). Khi bắt lỗi ở
   TRY...CATCH nhớ kiểm tra @@TRANCOUNT trước khi ROLLBACK, vì trigger đã hủy transaction.
   04_fragmentation.sql tắt/bật các trigger này khi nạp lại dữ liệu hàng loạt.
   LƯU Ý: bảng có trigger thì lệnh INSERT/UPDATE/DELETE ... OUTPUT phải dùng OUTPUT ... INTO
   (đã sửa trong 06_queries_40.sql câu 34 và 35).
   ===================================================================== */

SET NOCOUNT ON;
SET XACT_ABORT ON;          -- bắt buộc khi sửa bảng ở node khác instance trong BEGIN TRAN
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


CREATE OR ALTER TRIGGER dbo.trg_HoSo_GhiNhatKy
ON dbo.SinhVien_HoSo
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.NhatKy (TenBang, HanhDong, KhoaChinh, NoiDungCu, NoiDungMoi)
    SELECT N'SinhVien_HoSo',
           CASE WHEN d.MaSV IS NULL THEN 'INSERT' WHEN i.MaSV IS NULL THEN 'DELETE' ELSE 'UPDATE' END,
           COALESCE(i.MaSV, d.MaSV),
           CASE WHEN d.MaSV IS NULL THEN NULL
                ELSE CONCAT(N'CCCD=***', RIGHT(d.CCCD, 4), N'; DienThoai=***', RIGHT(d.DienThoai, 3),
                            N'; Email=', d.Email, N'; DiaChi=', d.DiaChi) END,
           CASE WHEN i.MaSV IS NULL THEN NULL
                ELSE CONCAT(N'CCCD=***', RIGHT(i.CCCD, 4), N'; DienThoai=***', RIGHT(i.DienThoai, 3),
                            N'; Email=', i.Email, N'; DiaChi=', i.DiaChi) END
    FROM inserted i
    FULL OUTER JOIN deleted d ON d.MaSV = i.MaSV
    WHERE COALESCE(i.MaSV, d.MaSV) <> '99999999'                 -- mã dành riêng cho sp_DemoGiaoDich
      AND (i.MaSV IS NULL OR d.MaSV IS NULL
           OR NOT EXISTS (SELECT d.CCCD, d.DienThoai, d.Email, d.DiaChi
                          INTERSECT SELECT i.CCCD, i.DienThoai, i.Email, i.DiaChi));
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
    -- Chỉ dùng dữ liệu của chính node (bản sao MonHoc và GiangVien): không gọi sang instance khác, nên chạy được
    -- cả trong giao dịch phân tán mà điều phối đang giữ.
    IF EXISTS (SELECT 1 FROM inserted i
               JOIN dbo.GiangVien g ON g.MaGV = i.MaGV
               JOIN dbo.MonHoc m ON m.MaMH = i.MaMH
               WHERE m.MaKhoa IS NOT NULL AND m.MaKhoa <> g.MaKhoa)
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50902, N~Môn học thuộc khoa khác, giảng viên này không được mở lớp.~, 1;
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
END'),

(N'trg_SinhVien_GhiNhatKy', N'
CREATE OR ALTER TRIGGER dbo.trg_SinhVien_GhiNhatKy
ON dbo.SinhVien
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.NhatKy (TenBang, HanhDong, KhoaChinh, NoiDungCu, NoiDungMoi)
    SELECT N~SinhVien~,
           CASE WHEN d.MaSV IS NULL THEN ~INSERT~ WHEN i.MaSV IS NULL THEN ~DELETE~ ELSE ~UPDATE~ END,
           COALESCE(i.MaSV, d.MaSV),
           CASE WHEN d.MaSV IS NULL THEN NULL
                ELSE CONCAT(N~HoTen=~, d.HoTen, N~; NgaySinh=~, CONVERT(NVARCHAR(10), d.NgaySinh, 23),
                            N~; GioiTinh=~, d.GioiTinh, N~; MaLop=~, d.MaLop, N~; TrangThai=~, d.TrangThai) END,
           CASE WHEN i.MaSV IS NULL THEN NULL
                ELSE CONCAT(N~HoTen=~, i.HoTen, N~; NgaySinh=~, CONVERT(NVARCHAR(10), i.NgaySinh, 23),
                            N~; GioiTinh=~, i.GioiTinh, N~; MaLop=~, i.MaLop, N~; TrangThai=~, i.TrangThai) END
    FROM inserted i
    FULL OUTER JOIN deleted d ON d.MaSV = i.MaSV
    WHERE COALESCE(i.MaSV, d.MaSV) <> ~99999999~                 -- mã dành riêng cho sp_DemoGiaoDich
      AND (i.MaSV IS NULL OR d.MaSV IS NULL
           OR NOT EXISTS (SELECT d.HoTen, d.NgaySinh, d.GioiTinh, d.MaLop, d.TrangThai
                          INTERSECT SELECT i.HoTen, i.NgaySinh, i.GioiTinh, i.MaLop, i.TrangThai));
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
    SET @exec = N'LS_' + @db + N'.' + QUOTENAME(@db) + N'.sys.sp_executesql';   -- chạy ở instance của node (Linked Server)
    EXEC @exec @sql;                                        -- mỗi lần 1 trigger (CREATE TRIGGER phải đứng đầu batch)
    FETCH NEXT FROM c INTO @db, @noi;
END
CLOSE c;
DEALLOCATE c;
GO

-- Kiểm tra cài đặt: 2 trigger ở TongHop + 5 trigger x 3 node = 17 đối tượng, 7 loại trigger
SELECT db, ten AS Trigger_, bang AS TrenBang
FROM (
    SELECT N'QLSV_TongHop' AS db, name AS ten, OBJECT_NAME(parent_id) AS bang FROM sys.triggers
    UNION ALL SELECT N'QLSV_CNTT', t.name, b.name FROM LS_QLSV_CNTT.QLSV_CNTT.sys.triggers t JOIN LS_QLSV_CNTT.QLSV_CNTT.sys.tables b ON b.object_id = t.parent_id
    UNION ALL SELECT N'QLSV_NgoaiNgu', t.name, b.name FROM LS_QLSV_NgoaiNgu.QLSV_NgoaiNgu.sys.triggers t JOIN LS_QLSV_NgoaiNgu.QLSV_NgoaiNgu.sys.tables b ON b.object_id = t.parent_id
    UNION ALL SELECT N'QLSV_DuLich', t.name, b.name FROM LS_QLSV_DuLich.QLSV_DuLich.sys.triggers t JOIN LS_QLSV_DuLich.QLSV_DuLich.sys.tables b ON b.object_id = t.parent_id
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

-- Trigger 3: trg_LopHocPhan_KiemTraMonHoc. Giảng viên khoa CNTT mở lớp cho môn NN101 của khoa Ngoại ngữ (bản sao
--   của môn này có ở node CNTT nên khóa ngoại cục bộ cho qua, trigger chặn lại).
--   Khối TRY...CATCH chạy NGAY TRÊN node (EXEC ... sp_executesql từ xa): trigger tự ROLLBACK giao dịch, nếu
--   chạy trong giao dịch phân tán thì MSDTC báo lỗi 1206 và mất mã lỗi 50902 của trigger.
EXEC LS_QLSV_CNTT.QLSV_CNTT.sys.sp_executesql N'
BEGIN TRY
    BEGIN TRAN;
        INSERT dbo.LopHocPhan (MaLHP, MaMH, MaHK, Nhom, MaGV, SiSoToiDa)
        VALUES (''NN101-HK1-2627-09'', ''NN101'', ''HK1-2627'', 9, ''GVCNTT01'', 50);
    COMMIT;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS MaLoi, ERROR_MESSAGE() AS ThongBao;
    IF @@TRANCOUNT > 0 ROLLBACK;
END CATCH';
SELECT N'Sau lỗi: lớp NN101-HK1-2627-09 còn ở node không?' AS KiemTra, COUNT(*) AS SoDong
FROM QLSV_CNTT.dbo.LopHocPhan WHERE MaLHP = 'NN101-HK1-2627-09';   -- = 0 (transaction đã bị hủy)
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
EXEC LS_QLSV_CNTT.QLSV_CNTT.sys.sp_executesql N'                          -- chạy trên node, lý do như ở Trigger 3
BEGIN TRY
    BEGIN TRAN;
        UPDATE dbo.LopHocPhan SET SiSoToiDa = 10 WHERE MaLHP = ''CNTT110-HK1-2627-01'';
        INSERT dbo.DangKy (MaSV, MaLHP) VALUES (''24010016'', ''CNTT110-HK1-2627-01'');
    COMMIT;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS MaLoi, ERROR_MESSAGE() AS ThongBao;
    IF @@TRANCOUNT > 0 ROLLBACK;
END CATCH';
SELECT N'Sau lỗi: sĩ số tối đa đã trở lại' AS KiemTra, SiSoToiDa
FROM QLSV_CNTT.dbo.LopHocPhan WHERE MaLHP = 'CNTT110-HK1-2627-01';   -- không còn là 10
GO

-- Trigger 6 và 7: trg_SinhVien_GhiNhatKy + trg_HoSo_GhiNhatKy. Thêm, sửa, chuyển khoa, xóa một sinh viên thử:
--   NhatKy ở node CNTT, node Ngoại ngữ và TongHop mỗi nơi có các dòng tương ứng (rồi ROLLBACK).
--   Chuyển khoa = DELETE ở node cũ (CNTT) + INSERT ở node mới (NN); CCCD và điện thoại trong nhật ký chỉ có số cuối.
BEGIN TRAN;
    INSERT QLSV_CNTT.dbo.SinhVien (MaSV, HoTen, NgaySinh, GioiTinh, MaLop)
    VALUES ('99999996', N'Sinh Viên Nhật Ký', '2006-01-01', N'Nam', '66.CNTT-1');
    INSERT dbo.SinhVien_HoSo (MaSV, CCCD, DienThoai, Email, DiaChi)
    VALUES ('99999996', '000000000096', '0987654321', 'nk99999996@sv.qlsv.edu.vn', N'Hà Nội');
    UPDATE QLSV_CNTT.dbo.SinhVien SET HoTen = N'Sinh Viên Nhật Ký (sửa)' WHERE MaSV = '99999996';
    UPDATE dbo.SinhVien_HoSo SET DiaChi = N'Hải Phòng' WHERE MaSV = '99999996';
    EXEC dbo.sp_ChuyenKhoa @MaSV = '99999996', @MaLopMoi = '66.NN-1';
    DELETE FROM dbo.SinhVien_HoSo WHERE MaSV = '99999996';
    DELETE FROM QLSV_NgoaiNgu.dbo.SinhVien WHERE MaSV = '99999996';

    SELECT Node, MaNK, TenBang, HanhDong, NoiDungCu, NoiDungMoi FROM (
        SELECT N'QLSV_CNTT' AS Node, MaNK, TenBang, HanhDong, NoiDungCu, NoiDungMoi FROM QLSV_CNTT.dbo.NhatKy WHERE KhoaChinh = '99999996'
        UNION ALL SELECT N'QLSV_NgoaiNgu', MaNK, TenBang, HanhDong, NoiDungCu, NoiDungMoi FROM QLSV_NgoaiNgu.dbo.NhatKy WHERE KhoaChinh = '99999996'
        UNION ALL SELECT N'QLSV_TongHop', MaNK, TenBang, HanhDong, NoiDungCu, NoiDungMoi FROM dbo.NhatKy WHERE KhoaChinh = '99999996'
    ) x ORDER BY Node, MaNK;
ROLLBACK TRAN;
SELECT N'Sau ROLLBACK: số dòng nhật ký của sinh viên thử' AS KiemTra,
       (SELECT COUNT(*) FROM QLSV_CNTT.dbo.NhatKy WHERE KhoaChinh = '99999996')
     + (SELECT COUNT(*) FROM QLSV_NgoaiNgu.dbo.NhatKy WHERE KhoaChinh = '99999996')
     + (SELECT COUNT(*) FROM dbo.NhatKy WHERE KhoaChinh = '99999996') AS SoDong;   -- = 0
GO
