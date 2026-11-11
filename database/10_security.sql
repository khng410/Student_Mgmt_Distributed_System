/* =====================================================================
   ĐỒ ÁN CSDL PHÂN TÁN – QUẢN LÝ SINH VIÊN NHIỀU KHOA
   File   : 10_security.sql
   Mục đích: Người dùng, vai trò và phân quyền cho hệ thống phân tán.
   Người viết: ...............          Ngày: ..../11/2026
   Chạy sau : 09_triggers.sql             Chạy lại nhiều lần được. Cần quyền sysadmin.

   6 TÀI KHOẢN (LOGIN -> USER ở cả 5 database)           ROLE
   ---------------------------------------------------------------------
   lg_admin        Quản trị hệ thống                      db_owner ở 5 database
   lg_daotao       Phòng Đào tạo (toàn trường)            rl_DaoTao  (TongHop + 3 node)
   lg_giaovu_cntt  Giáo vụ khoa CNTT                      rl_GiaoVu  (TongHop + node CNTT)
   lg_giaovu_nn    Giáo vụ khoa Ngoại ngữ                 rl_GiaoVu  (TongHop + node NN)
   lg_giaovu_dl    Giáo vụ khoa Du lịch                   rl_GiaoVu  (TongHop + node DL)
   lg_bgh          Ban giám hiệu (chỉ xem thống kê)       rl_BGH     (TongHop)

   NGUYÊN TẮC
   * Cấp quyền qua VIEW và thủ tục, không cấp trực tiếp bảng nhạy cảm: hồ sơ cá nhân
     (CCCD, điện thoại, địa chỉ) nằm ở bảng SinhVien_HoSo, chỉ Phòng Đào tạo xem được qua
     vw_SinhVien_DayDu; DENY SELECT trên chính bảng.
   * Giáo vụ chỉ được SỬA ĐIỂM sinh viên của khoa mình: quyền UPDATE(DiemQT, DiemThi) chỉ
     cấp ở node của khoa. sp_NhapDiem chạy SQL động, nên bị từ chối khi sinh viên thuộc
     node khoa khác.
   * VIEW và thủ tục ở TongHop đọc node khoa qua database đại diện (synonym -> Linked Server): chuỗi sở hữu
     chỉ đi được đến database đại diện; sang instance node, quyền do node kiểm tra bằng login cùng tên
     (Linked Server ánh xạ từng login). Vì vậy login và quyền phải có ở cả 4 instance, và mọi giáo vụ cần SELECT
     ở cả 3 node để view toàn cục chạy; chỉ UPDATE điểm là riêng từng khoa. Hạn chế: xem README, mục "Giới hạn đã biết".
   * SQL động không đi theo chuỗi sở hữu: quyền trên bảng của node được kiểm tra riêng.

   MẬT KHẨU dưới đây chỉ để chạy thử trên máy cá nhân, hãy đổi trước khi dùng thật.
   Demo dùng EXECUTE AS LOGIN nên không cần SQL Server bật chế độ đăng nhập hỗn hợp.
   ===================================================================== */

SET NOCOUNT ON;
SET XACT_ABORT ON;          -- bắt buộc khi sửa bảng ở node khác instance trong BEGIN TRAN
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
USE master;
GO

/* =====================================================================
   PHẦN 1. LOGIN (cấp máy chủ)
   ===================================================================== */
DECLARE @lg TABLE (ten SYSNAME, mk NVARCHAR(50));
INSERT @lg VALUES (N'lg_admin',       N'Tr0ng#Zq81!2026'),  (N'lg_daotao',      N'Xe9$Lm47#2026p'),
                  (N'lg_giaovu_cntt', N'Bv3@Rt62$2026k'),   (N'lg_giaovu_nn',   N'Hw7#Ny15@2026c'),
                  (N'lg_giaovu_dl',   N'Pk4$Jd88#2026m'),   (N'lg_bgh',         N'Fz2@Qs59$2026t');

-- Câu lệnh tạo login; {DB} là database mặc định (ở node khoa chưa có QLSV_TongHop nên để master)
DECLARE @tao NVARCHAR(MAX) = N'';
SELECT @tao += N'IF SUSER_ID(N''' + ten + N''') IS NULL CREATE LOGIN ' + ten + N' WITH PASSWORD = N''' + mk
             + N''', DEFAULT_DATABASE = {DB}, CHECK_POLICY = ON, CHECK_EXPIRATION = OFF; '
FROM @lg;

DECLARE @sql NVARCHAR(MAX) = REPLACE(@tao, N'{DB}', N'QLSV_TongHop');
EXEC sp_executesql @sql;                                                  -- instance điều phối

/* Mỗi node khoa là một instance riêng nên cần có login cùng tên, và Linked Server ánh xạ từng login của
   điều phối sang login cùng tên ở node: quyền ở node vẫn do node quyết định (không dùng một tài khoản chung). */
DECLARE @ls SYSNAME, @exec NVARCHAR(300);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT name FROM sys.servers WHERE name LIKE N'LS[_]QLSV[_]%';
OPEN c;
FETCH NEXT FROM c INTO @ls;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @exec = @ls + N'.master.sys.sp_executesql';
    SET @sql = REPLACE(@tao, N'{DB}', N'master');
    EXEC @exec @sql;                                                        -- tạo login ở node
    SELECT @sql = N'';
    SELECT @sql += N'EXEC sp_addlinkedsrvlogin @rmtsrvname = N''' + @ls + N''', @useself = N''FALSE'', @locallogin = N'''
                 + ten + N''', @rmtuser = N''' + ten + N''', @rmtpassword = N''' + mk + N'''; '
    FROM @lg;
    EXEC sp_executesql @sql;                                                -- ánh xạ login điều phối -> login node
    FETCH NEXT FROM c INTO @ls;
END
CLOSE c;
DEALLOCATE c;

-- Quản trị được đóng vai (EXECUTE AS LOGIN) 5 tài khoản còn lại ở instance điều phối: trang "Phân quyền" của ứng dụng
-- dùng quyền này để thử cùng một việc dưới từng vai trò. Không cấp cho tài khoản nào khác.
SET @sql = N'';
SELECT @sql += N'GRANT IMPERSONATE ON LOGIN::' + ten + N' TO lg_admin; ' FROM @lg WHERE ten <> N'lg_admin';
EXEC sp_executesql @sql;
GO

/* =====================================================================
   PHẦN 2. CHUỖI SỞ HỮU GIỮA CÁC DATABASE
   ===================================================================== */
ALTER DATABASE QLSV_TapTrung SET DB_CHAINING ON;
ALTER DATABASE QLSV_TongHop  SET DB_CHAINING ON;
ALTER DATABASE QLSV_CNTT     SET DB_CHAINING ON;
ALTER DATABASE QLSV_NgoaiNgu SET DB_CHAINING ON;
ALTER DATABASE QLSV_DuLich   SET DB_CHAINING ON;
GO

/* =====================================================================
   PHẦN 3. USER ở cả 8 database (5 ở điều phối, 3 ở node) + dọn role cũ (để chạy lại được)
   ===================================================================== */
DECLARE @tpl NVARCHAR(MAX) = N'
DROP USER IF EXISTS lg_admin;       DROP USER IF EXISTS lg_daotao;
DROP USER IF EXISTS lg_giaovu_cntt; DROP USER IF EXISTS lg_giaovu_nn;
DROP USER IF EXISTS lg_giaovu_dl;   DROP USER IF EXISTS lg_bgh;
DROP ROLE IF EXISTS rl_DaoTao;      DROP ROLE IF EXISTS rl_GiaoVu;      DROP ROLE IF EXISTS rl_BGH;

CREATE USER lg_admin       FOR LOGIN lg_admin;
CREATE USER lg_daotao      FOR LOGIN lg_daotao;
CREATE USER lg_giaovu_cntt FOR LOGIN lg_giaovu_cntt;
CREATE USER lg_giaovu_nn   FOR LOGIN lg_giaovu_nn;
CREATE USER lg_giaovu_dl   FOR LOGIN lg_giaovu_dl;
CREATE USER lg_bgh         FOR LOGIN lg_bgh;

ALTER ROLE db_owner ADD MEMBER lg_admin;';

-- Chạy khuôn lệnh trên trong từng database: EXEC <database>.sys.sp_executesql chạy trong ngữ cảnh database đó
DECLARE @exec NVARCHAR(300);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT noi FROM (VALUES
        (N'QLSV_TapTrung.sys.sp_executesql'), (N'QLSV_TongHop.sys.sp_executesql'),            -- 2 database thật ở điều phối
        (N'QLSV_CNTT.sys.sp_executesql'), (N'QLSV_NgoaiNgu.sys.sp_executesql'),
        (N'QLSV_DuLich.sys.sp_executesql'),                                                   -- 3 database đại diện ở điều phối
        (N'LS_QLSV_CNTT.QLSV_CNTT.sys.sp_executesql'), (N'LS_QLSV_NgoaiNgu.QLSV_NgoaiNgu.sys.sp_executesql'),
        (N'LS_QLSV_DuLich.QLSV_DuLich.sys.sp_executesql')) d(noi);                            -- 3 database thật ở instance node
OPEN c;
FETCH NEXT FROM c INTO @exec;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC @exec @tpl;
    FETCH NEXT FROM c INTO @exec;
END
CLOSE c;
DEALLOCATE c;
GO

/* =====================================================================
   PHẦN 4. ROLE VÀ QUYỀN Ở 3 NODE KHOA
     rl_DaoTao : đọc/ghi mọi bảng (các thủ tục dùng SQL động nên cần quyền trực tiếp)
     rl_GiaoVu : cả 3 giáo vụ, đọc mọi bảng của node (dữ liệu học vụ không nhạy cảm), không xóa.
                 Sửa DiemQT, DiemThi cấp riêng cho giáo vụ của khoa đó.
     rl_BGH    : chỉ đọc.
   Phải có TRƯỚC phần 5: view ở TongHop đọc node bằng chính login của người dùng (không có chuỗi sở hữu
   giữa các instance), nên giáo vụ và Ban giám hiệu cần SELECT ở cả 3 node.
   ===================================================================== */
DECLARE @tpl NVARCHAR(MAX) = N'
CREATE ROLE rl_DaoTao;
CREATE ROLE rl_GiaoVu;
CREATE ROLE rl_BGH;
ALTER ROLE rl_DaoTao ADD MEMBER lg_daotao;
ALTER ROLE rl_GiaoVu ADD MEMBER lg_giaovu_cntt;
ALTER ROLE rl_GiaoVu ADD MEMBER lg_giaovu_nn;
ALTER ROLE rl_GiaoVu ADD MEMBER lg_giaovu_dl;
ALTER ROLE rl_BGH    ADD MEMBER lg_bgh;

GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::dbo TO rl_DaoTao;
GRANT SELECT ON SCHEMA::dbo TO rl_GiaoVu, rl_BGH;
GRANT UPDATE ON dbo.DangKy (DiemQT, DiemThi) TO {GV};      -- chỉ giáo vụ của khoa này được sửa điểm
DENY  DELETE ON SCHEMA::dbo TO rl_GiaoVu;
DENY  INSERT, UPDATE, DELETE ON SCHEMA::dbo TO rl_BGH;';

DECLARE @db SYSNAME, @gv SYSNAME, @sql NVARCHAR(MAX), @exec NVARCHAR(300);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT db, gv FROM (VALUES (N'QLSV_CNTT',     N'lg_giaovu_cntt'),
                               (N'QLSV_NgoaiNgu', N'lg_giaovu_nn'),
                               (N'QLSV_DuLich',   N'lg_giaovu_dl')) n(db, gv);
OPEN c;
FETCH NEXT FROM c INTO @db, @gv;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql  = REPLACE(@tpl, N'{GV}', @gv);
    SET @exec = N'LS_' + @db + N'.' + QUOTENAME(@db) + N'.sys.sp_executesql';
    EXEC @exec @sql;                                        -- quyền thật, do instance node kiểm tra

    -- Database đại diện ở điều phối cũng cần quyền (SQL động không đi theo chuỗi sở hữu). Quyền cột
    -- không đặt được trên synonym nên cấp UPDATE cả schema; node vẫn chỉ cho sửa DiemQT, DiemThi của khoa mình.
    SET @sql  = REPLACE(@sql, N'GRANT UPDATE ON dbo.DangKy (DiemQT, DiemThi) TO ' + @gv + N';',
                              N'GRANT UPDATE ON SCHEMA::dbo TO rl_GiaoVu;');
    SET @exec = QUOTENAME(@db) + N'.sys.sp_executesql';
    EXEC @exec @sql;
    FETCH NEXT FROM c INTO @db, @gv;
END
CLOSE c;
DEALLOCATE c;
GO

/* =====================================================================
   PHẦN 5. ROLE VÀ QUYỀN Ở NODE ĐIỀU PHỐI – QLSV_TongHop
   ===================================================================== */
USE QLSV_TongHop;
GO

CREATE ROLE rl_DaoTao;
CREATE ROLE rl_GiaoVu;
CREATE ROLE rl_BGH;

ALTER ROLE rl_DaoTao ADD MEMBER lg_daotao;
ALTER ROLE rl_GiaoVu ADD MEMBER lg_giaovu_cntt;
ALTER ROLE rl_GiaoVu ADD MEMBER lg_giaovu_nn;
ALTER ROLE rl_GiaoVu ADD MEMBER lg_giaovu_dl;
ALTER ROLE rl_BGH    ADD MEMBER lg_bgh;

-- Phòng Đào tạo: xem mọi VIEW, chạy mọi thủ tục/hàm; ghi dữ liệu chỉ qua thủ tục.
GRANT SELECT  ON SCHEMA::dbo TO rl_DaoTao;
GRANT EXECUTE ON SCHEMA::dbo TO rl_DaoTao;
DENY  SELECT  ON dbo.SinhVien_HoSo TO rl_DaoTao;      -- không đọc thẳng bảng nhạy cảm, chỉ qua vw_SinhVien_DayDu

-- Giáo vụ: chỉ các VIEW không có thông tin nhạy cảm và vài thủ tục.
GRANT SELECT ON dbo.vw_SinhVien_ToanCuc     TO rl_GiaoVu;
GRANT SELECT ON dbo.vw_DangKy_ToanCuc       TO rl_GiaoVu;
GRANT SELECT ON dbo.vw_BangDiem             TO rl_GiaoVu;
GRANT SELECT ON dbo.vw_ThongKe_Khoa_HocKy   TO rl_GiaoVu;
GRANT SELECT ON dbo.fn_DanhSachLop          TO rl_GiaoVu;
GRANT SELECT ON dbo.fn_BangDiemSinhVien     TO rl_GiaoVu;
GRANT EXECUTE ON dbo.sp_TimSinhVien         TO rl_GiaoVu;
GRANT EXECUTE ON dbo.sp_BangDiemSinhVien    TO rl_GiaoVu;
GRANT EXECUTE ON dbo.sp_ThongKeKhoa         TO rl_GiaoVu;
GRANT EXECUTE ON dbo.sp_NhapDiem            TO rl_GiaoVu;
DENY  INSERT, UPDATE, DELETE ON SCHEMA::dbo TO rl_GiaoVu;   -- không sửa trực tiếp bảng ở TongHop

-- Ban giám hiệu: chỉ xem thống kê tổng hợp.
GRANT SELECT  ON dbo.vw_ThongKe_Khoa_HocKy TO rl_BGH;
GRANT EXECUTE ON dbo.sp_ThongKeKhoa        TO rl_BGH;
DENY  INSERT, UPDATE, DELETE ON SCHEMA::dbo TO rl_BGH;
GO

/* ---------- GRANT nhầm -> REVOKE -> DENY ----------
   Bước 1: lỡ cấp quyền xem hồ sơ đầy đủ cho giáo vụ -> giáo vụ thấy CCCD (sai).
   Bước 2: REVOKE thu hồi quyền đã cấp (về trạng thái "chưa cấp", chưa phải "từ chối").
   Bước 3: DENY để khóa hẳn, kể cả khi sau này giáo vụ thuộc role khác có quyền này. */
GRANT SELECT ON dbo.vw_SinhVien_DayDu TO rl_GiaoVu;          -- (1) cấp nhầm
GO
EXECUTE AS LOGIN = 'lg_giaovu_cntt';
    SELECT TOP (1) N'(1) Sau GRANT nhầm: giáo vụ đọc được CCCD' AS Buoc, MaSV, CCCD FROM dbo.vw_SinhVien_DayDu;
REVERT;
GO
REVOKE SELECT ON dbo.vw_SinhVien_DayDu FROM rl_GiaoVu;       -- (2) thu hồi
DENY   SELECT ON dbo.vw_SinhVien_DayDu TO   rl_GiaoVu;       -- (3) khóa hẳn
DENY   SELECT ON dbo.SinhVien_HoSo     TO   rl_GiaoVu;
DENY   SELECT ON dbo.SinhVien_HoSo     TO   rl_BGH;
DENY   SELECT ON dbo.vw_SinhVien_DayDu TO   rl_BGH;
GO

/* =====================================================================
   PHẦN 6. MINH HỌA – mỗi ca dùng EXECUTE AS LOGIN rồi REVERT
   Ca "ĐƯỢC PHÉP" trả dữ liệu; ca "BỊ TỪ CHỐI" in ra mã lỗi 229/230/297 (permission denied).
   Mọi ca ghi dữ liệu nằm trong BEGIN TRAN ... ROLLBACK.
   ===================================================================== */

-- Ca 1 (ĐƯỢC PHÉP): giáo vụ CNTT xem danh sách sinh viên qua VIEW toàn cục.
EXECUTE AS LOGIN = 'lg_giaovu_cntt';
BEGIN TRY
    SELECT SUSER_NAME() AS DangNhapVoi;
    SELECT TOP (3) MaSV, HoTen, TenKhoa FROM dbo.vw_SinhVien_ToanCuc ORDER BY MaSV;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS MaLoi, ERROR_MESSAGE() AS ThongBao;
END CATCH
REVERT;
GO

-- Ca 2 (BỊ TỪ CHỐI): cũng giáo vụ đó đọc hồ sơ cá nhân (CCCD) - qua VIEW đầy đủ và qua bảng gốc.
EXECUTE AS LOGIN = 'lg_giaovu_cntt';
BEGIN TRY
    SELECT TOP (1) MaSV, CCCD FROM dbo.vw_SinhVien_DayDu;
END TRY
BEGIN CATCH
    SELECT N'vw_SinhVien_DayDu' AS DoiTuong, ERROR_NUMBER() AS MaLoi, ERROR_MESSAGE() AS ThongBao;
END CATCH
BEGIN TRY
    SELECT TOP (1) MaSV, CCCD FROM dbo.SinhVien_HoSo;
END TRY
BEGIN CATCH
    SELECT N'SinhVien_HoSo' AS DoiTuong, ERROR_NUMBER() AS MaLoi, ERROR_MESSAGE() AS ThongBao;
END CATCH
REVERT;
GO

-- Ca 3 (ĐƯỢC PHÉP): giáo vụ CNTT nhập điểm cho sinh viên CNTT (rồi hoàn tác).
EXECUTE AS LOGIN = 'lg_giaovu_cntt';
BEGIN TRY
    BEGIN TRAN;
        EXEC dbo.sp_NhapDiem @MaSV = '24010001', @MaLHP = 'CNTT110-HK1-2627-01', @DiemQT = 8.5;
    ROLLBACK TRAN;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS MaLoi, ERROR_MESSAGE() AS ThongBao;
    IF @@TRANCOUNT > 0 ROLLBACK;
END CATCH
REVERT;
GO

-- Ca 4 (BỊ TỪ CHỐI): giáo vụ CNTT nhập điểm cho sinh viên khoa Ngoại ngữ -> không thấy sinh viên đó (lọc theo khoa);
--   nếu vượt được lớp lọc này vẫn bị chặn tiếp vì không có quyền UPDATE ở node NN.
EXECUTE AS LOGIN = 'lg_giaovu_cntt';
BEGIN TRY
    BEGIN TRAN;
        EXEC dbo.sp_NhapDiem @MaSV = '24020001', @MaLHP = 'NN110-HK1-2627-01', @DiemQT = 8.5;
    ROLLBACK TRAN;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS MaLoi, ERROR_MESSAGE() AS ThongBao;
    IF @@TRANCOUNT > 0 ROLLBACK;
END CATCH
REVERT;
GO

-- Ca 5 (BỊ TỪ CHỐI): giáo vụ CNTT xóa trực tiếp một đăng ký ở node CNTT.
EXECUTE AS LOGIN = 'lg_giaovu_cntt';
BEGIN TRY
    BEGIN TRAN;
        DELETE FROM QLSV_CNTT.dbo.DangKy WHERE MaSV = '24010001' AND MaLHP = 'CNTT101-HK1-2425-01';
    ROLLBACK TRAN;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS MaLoi, ERROR_MESSAGE() AS ThongBao;
    IF @@TRANCOUNT > 0 ROLLBACK;
END CATCH
REVERT;
GO

-- Ca 6 (ĐƯỢC PHÉP): Phòng Đào tạo xem hồ sơ đầy đủ qua VIEW.
-- Ca 7 (BỊ TỪ CHỐI): cùng người đó đọc thẳng bảng SinhVien_HoSo (chỉ được đi qua VIEW).
EXECUTE AS LOGIN = 'lg_daotao';
BEGIN TRY
    SELECT TOP (3) MaSV, HoTen, CCCD, DienThoai FROM dbo.vw_SinhVien_DayDu ORDER BY MaSV;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS MaLoi, ERROR_MESSAGE() AS ThongBao;
END CATCH
BEGIN TRY
    SELECT TOP (1) MaSV, CCCD FROM dbo.SinhVien_HoSo;
END TRY
BEGIN CATCH
    SELECT N'SinhVien_HoSo' AS DoiTuong, ERROR_NUMBER() AS MaLoi, ERROR_MESSAGE() AS ThongBao;
END CATCH
REVERT;
GO

-- Ca 8 (ĐƯỢC PHÉP): Phòng Đào tạo thêm sinh viên mới bằng thủ tục (ghi vào 2 database; rồi hoàn tác).
EXECUTE AS LOGIN = 'lg_daotao';
BEGIN TRY
    BEGIN TRAN;
        EXEC dbo.sp_ThemSinhVien @MaSV = '24019999', @HoTen = N'Nguyễn Thị Kiểm Thử', @NgaySinh = '2006-05-10',
             @GioiTinh = N'Nữ', @MaLop = '66.CNTT-1', @CCCD = '001306009999',
             @Email = '24019999@sv.qlsv.edu.vn';
    ROLLBACK TRAN;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS MaLoi, ERROR_MESSAGE() AS ThongBao;
    IF @@TRANCOUNT > 0 ROLLBACK;
END CATCH
REVERT;
GO

-- Ca 9 (ĐƯỢC PHÉP): Ban giám hiệu xem thống kê.
-- Ca 10 (BỊ TỪ CHỐI): Ban giám hiệu xem bảng điểm chi tiết từng sinh viên.
EXECUTE AS LOGIN = 'lg_bgh';
BEGIN TRY
    SELECT TenKhoa, MaHK, DiemTB, TyLeDat FROM dbo.vw_ThongKe_Khoa_HocKy ORDER BY TenKhoa, MaHK;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS MaLoi, ERROR_MESSAGE() AS ThongBao;
END CATCH
BEGIN TRY
    SELECT TOP (1) MaSV, TenMH, DiemTK FROM dbo.vw_BangDiem;
END TRY
BEGIN CATCH
    SELECT N'vw_BangDiem' AS DoiTuong, ERROR_NUMBER() AS MaLoi, ERROR_MESSAGE() AS ThongBao;
END CATCH
REVERT;
GO

-- Ca 11 (PHẠM VI KHOA): giáo vụ CNTT chỉ thấy dữ liệu khoa CNTT ở mọi view, hàm và thủ tục.
EXECUTE AS LOGIN = 'lg_giaovu_cntt';
BEGIN TRY
    SELECT N'vw_SinhVien_ToanCuc' AS Nguon, MaKhoa, COUNT(*) AS SoDong FROM dbo.vw_SinhVien_ToanCuc GROUP BY MaKhoa;    -- chỉ CNTT
    SELECT N'vw_ThongKe_Khoa_HocKy' AS Nguon, MaKhoa, COUNT(*) AS SoDong FROM dbo.vw_ThongKe_Khoa_HocKy GROUP BY MaKhoa; -- chỉ CNTT
    EXEC dbo.sp_ThongKeKhoa @MaKhoa = 'NN';                     -- khoa khác -> rỗng
    EXEC dbo.sp_TimSinhVien @MaKhoa = 'NN';                     -- khoa khác -> rỗng
    EXEC dbo.sp_BangDiemSinhVien @MaSV = '24020001';            -- sinh viên khoa khác -> lỗi "Không tìm thấy sinh viên"
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS MaLoi, ERROR_MESSAGE() AS ThongBao;
END CATCH
REVERT;
GO

-- Ca 12 (ĐƯỢC PHÉP): quản trị viên xem mọi thứ.
EXECUTE AS LOGIN = 'lg_admin';
    SELECT SUSER_NAME() AS DangNhapVoi, COUNT(*) AS SoSinhVienCoHoSo FROM dbo.vw_SinhVien_DayDu;
REVERT;
GO

/* =====================================================================
   PHẦN 7. TỔNG KẾT QUYỀN (chụp ảnh cho báo cáo)
   ===================================================================== */

-- Thành viên các role ở 4 database thật: cùng một câu hỏi, chạy ở điều phối và ở từng instance node
DECLARE @q NVARCHAR(MAX) = N'
SELECT DB_NAME(), r.name, m.name
FROM sys.database_role_members rm
JOIN sys.database_principals r ON r.principal_id = rm.role_principal_id
JOIN sys.database_principals m ON m.principal_id = rm.member_principal_id
WHERE r.name LIKE N''rl[_]%'';';
CREATE TABLE #tv (db SYSNAME, role_name SYSNAME, member_name SYSNAME);
INSERT #tv EXEC (@q);
INSERT #tv EXEC (N'USE QLSV_CNTT; '     + @q) AT LS_QLSV_CNTT;
INSERT #tv EXEC (N'USE QLSV_NgoaiNgu; ' + @q) AT LS_QLSV_NgoaiNgu;
INSERT #tv EXEC (N'USE QLSV_DuLich; '   + @q) AT LS_QLSV_DuLich;
SELECT db, role_name, member_name FROM #tv ORDER BY db, role_name, member_name;
DROP TABLE #tv;
GO

-- Quyền đã GRANT / DENY ở QLSV_TongHop
SELECT pr.name AS Role, pe.state_desc AS TrangThai, pe.permission_name AS Quyen,
       CASE pe.class WHEN 1 THEN OBJECT_NAME(pe.major_id) WHEN 3 THEN N'SCHEMA ' + SCHEMA_NAME(pe.major_id) END AS DoiTuong
FROM sys.database_permissions pe
JOIN sys.database_principals pr ON pr.principal_id = pe.grantee_principal_id
WHERE pr.name LIKE N'rl[_]%'
ORDER BY pr.name, pe.state_desc, DoiTuong, pe.permission_name;
GO

-- Quyền ở các node khoa (xem node CNTT; NN và DL tương tự, chỉ khác giáo vụ được sửa điểm). Chạy ngay trên node.
EXEC (N'USE QLSV_CNTT;
SELECT pr.name AS NguoiNhan, pe.state_desc AS TrangThai, pe.permission_name AS Quyen,
       CASE pe.class WHEN 1 THEN OBJECT_NAME(pe.major_id) WHEN 3 THEN N''SCHEMA '' + SCHEMA_NAME(pe.major_id) END AS DoiTuong
FROM sys.database_permissions pe
JOIN sys.database_principals pr ON pr.principal_id = pe.grantee_principal_id
WHERE pr.name LIKE N''rl[_]%'' OR (pr.name LIKE N''lg[_]giaovu%'' AND pe.permission_name = ''UPDATE'')
ORDER BY pr.name, pe.state_desc, pe.permission_name;') AT LS_QLSV_CNTT;
GO

-- 6 login của hệ thống
SELECT name AS Login, type_desc, is_disabled FROM sys.server_principals WHERE name LIKE N'lg[_]%' ORDER BY name;
GO
