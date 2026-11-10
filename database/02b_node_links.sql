/* =====================================================================
   ĐỒ ÁN CSDL PHÂN TÁN – QUẢN LÝ SINH VIÊN NHIỀU KHOA
   File   : 02b_node_links.sql
   Mục đích: Nối instance điều phối (qlsv_tonghop) với 3 instance node khoa bằng Linked Server,
             rồi tạo "database đại diện" để mọi script cũ (QLSV_CNTT.dbo.SinhVien ...) chạy nguyên.
   Chạy sau : 02_create_tables.sql và 02a_create_node.sql (3 node), trên instance ĐIỀU PHỐI (cổng 14330). Cần quyền sysadmin.

   CÁCH HOẠT ĐỘNG
   * LS_QLSV_CNTT / LS_QLSV_NgoaiNgu / LS_QLSV_DuLich : Linked Server tới 3 instance riêng
     (container qlsv_cntt, qlsv_ngoaingu, qlsv_dulich). Tên Linked Server = 'LS_' + tên database.
   * Trên instance điều phối, QLSV_CNTT / QLSV_NgoaiNgu / QLSV_DuLich chỉ là vỏ rỗng chứa SYNONYM
     trỏ về bảng thật ở instance node. Bảng thật, dữ liệu và trigger nằm ở instance node.
   * Vì vậy câu lệnh viết bằng tên 3 phần vẫn chạy, nhưng thực chất là truy vấn liên instance;
     ghi vào nhiều node trong một giao dịch dùng MSDTC (giao dịch phân tán).

   MẬT KHẨU sa không nằm trong file: scripts/chay_sql.py thay $(SA_MATKHAU) bằng MSSQL_SA_PASSWORD trong .env.
   Chạy tay bằng SSMS thì bật SQLCMD Mode và thêm dòng đầu :setvar SA_MATKHAU "<mật khẩu sa>".

   QUYỀN DÙNG: lúc này chỉ người chạy script được ánh xạ tới các Linked Server; 10_security.sql
   thêm ánh xạ cho từng tài khoản (mỗi login đi sang node bằng login cùng tên, nên quyền ở node
   vẫn do node quyết định). KHÔNG dùng @locallogin = NULL vì sẽ cho mọi login đi bằng một tài khoản.
   ===================================================================== */

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
USE master;
GO

DECLARE @nguoiChay SYSNAME = SUSER_SNAME(), @db SYSNAME, @host SYSNAME, @ls SYSNAME;
DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT db, host FROM (VALUES (N'QLSV_CNTT',     N'qlsv_cntt'),
                                 (N'QLSV_NgoaiNgu', N'qlsv_ngoaingu'),
                                 (N'QLSV_DuLich',   N'qlsv_dulich')) n(db, host);
OPEN c;
FETCH NEXT FROM c INTO @db, @host;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @ls = N'LS_' + @db;
    IF EXISTS (SELECT 1 FROM sys.servers WHERE name = @ls)
        EXEC sp_dropserver @server = @ls, @droplogins = 'droplogins';

    EXEC sp_addlinkedserver @server = @ls, @srvproduct = N'', @provider = N'MSOLEDBSQL',
         @datasrc = @host;            -- KHÔNG đặt @provstr: có chuỗi này thì login không phải sysadmin bị lỗi 7416
    EXEC sp_serveroption @ls, N'rpc out', N'true';                              -- gọi thủ tục / SQL động ở node
    EXEC sp_serveroption @ls, N'remote proc transaction promotion', N'true';    -- giao dịch phân tán (MSDTC)
    EXEC sp_serveroption @ls, N'collation compatible', N'true';                 -- cùng Vietnamese_CI_AS: đẩy lọc sang node
    EXEC sp_addlinkedsrvlogin @rmtsrvname = @ls, @useself = N'FALSE', @locallogin = @nguoiChay,
         @rmtuser = N'sa', @rmtpassword = N'$(SA_MATKHAU)';
    EXEC sp_testlinkedserver @ls;
    PRINT N'Linked Server ' + @ls + N' -> ' + @host + N' OK';
    FETCH NEXT FROM c INTO @db, @host;
END
CLOSE c;
DEALLOCATE c;
GO

/* Database đại diện: mỗi bảng của node là một synonym tới bảng thật ở instance node */
DECLARE @t TABLE (ten SYSNAME);
INSERT @t VALUES (N'Khoa'), (N'HocKy'), (N'MonHoc'), (N'GiangVien'), (N'Lop'), (N'SinhVien'),
                 (N'LopHocPhan'), (N'DangKy'), (N'NhatKy');
DECLARE @db SYSNAME, @sql NVARCHAR(MAX), @exec NVARCHAR(300);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT db FROM (VALUES (N'QLSV_CNTT'), (N'QLSV_NgoaiNgu'), (N'QLSV_DuLich')) n(db);
OPEN c;
FETCH NEXT FROM c INTO @db;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'';
    SELECT @sql += N'DROP SYNONYM IF EXISTS dbo.' + ten + N'; CREATE SYNONYM dbo.' + ten
                 + N' FOR LS_' + @db + N'.' + @db + N'.dbo.' + ten + N'; '
    FROM @t;
    SET @exec = QUOTENAME(@db) + N'.sys.sp_executesql';
    EXEC @exec @sql;
    FETCH NEXT FROM c INTO @db;
END
CLOSE c;
DEALLOCATE c;
GO

-- Kiểm tra: đếm bảng qua synonym (bảng còn rỗng vì chưa nạp dữ liệu), chứng minh đường đi tới đủ 3 node
SELECT N'CNTT' AS Node, COUNT(*) AS SoSinhVien FROM QLSV_CNTT.dbo.SinhVien
UNION ALL SELECT N'NN', COUNT(*) FROM QLSV_NgoaiNgu.dbo.SinhVien
UNION ALL SELECT N'DL', COUNT(*) FROM QLSV_DuLich.dbo.SinhVien;
GO
