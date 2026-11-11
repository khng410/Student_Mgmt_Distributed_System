/* =====================================================================
   ĐỒ ÁN CSDL PHÂN TÁN – QUẢN LÝ SINH VIÊN NHIỀU KHOA
   File   : 02_node_va_linked_server.sql
   Mục đích: Nối instance điều phối với 3 instance node bằng Linked Server, dựng database và bảng ở cả 3 node
             TỪ XA, rồi tạo database đại diện (synonym) để các file sau dùng tên 3 phần như cũ.
   Người viết: ...............          Ngày: ..../11/2026
   Chạy sau : 01_create_tables.sql, trên instance ĐIỀU PHỐI (localhost,14330) bằng tài khoản sa.
              Chạy được trực tiếp trong SQLPro, SSMS, Azure Data Studio: không có biến, không cần script Python.
              Chạy lại nhiều lần được (database của node bị xóa và tạo lại).

   NODE                 INSTANCE (container)   DATABASE        ĐIỀU KIỆN PHÂN MẢNH NGANG
   Khoa CNTT            qlsv_cntt              QLSV_CNTT       MaKhoa = 'CNTT'
   Khoa Ngoại ngữ       qlsv_ngoaingu          QLSV_NgoaiNgu   MaKhoa = 'NN'
   Khoa Du lịch         qlsv_dulich            QLSV_DuLich     MaKhoa = 'DL'

   CÁCH HOẠT ĐỘNG
   * PHẦN 1. LS_QLSV_CNTT / LS_QLSV_NgoaiNgu / LS_QLSV_DuLich (tên = 'LS_' + tên database). Người chạy file được
     ánh xạ sang node bằng CHÍNH login và mật khẩu của mình (@useself = TRUE): 4 instance dùng chung mật khẩu sa
     (file .env) nên không phải ghi mật khẩu vào file. 10_security.sql thêm ánh xạ cho từng tài khoản lg_*.
     KHÔNG dùng @locallogin = NULL vì sẽ cho mọi login đi bằng một tài khoản.
   * PHẦN 2. Ba node có cấu trúc giống hệt nhau, chỉ khác tên database và mã khoa, nên DDL viết MỘT lần dưới dạng
     khuôn ({K} = mã khoa) rồi gửi sang từng node qua <LinkedServer>.<db>.sys.sp_executesql.
   * PHẦN 3. Trên instance điều phối, QLSV_CNTT / QLSV_NgoaiNgu / QLSV_DuLich (tạo ở 02) chỉ là vỏ rỗng chứa
     SYNONYM trỏ về bảng thật ở node: QLSV_CNTT.dbo.SinhVien thực chất là truy vấn liên instance.
   ===================================================================== */

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
USE master;
GO

/* =====================================================================
   PHẦN 1. LINKED SERVER TỚI 3 NODE
   ===================================================================== */
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
         @datasrc = @host;            
    EXEC sp_serveroption @ls, N'rpc out', N'true';                              
    EXEC sp_serveroption @ls, N'remote proc transaction promotion', N'true';    
    EXEC sp_serveroption @ls, N'collation compatible', N'true';                 
    EXEC sp_addlinkedsrvlogin @rmtsrvname = @ls, @useself = N'TRUE', @locallogin = @nguoiChay; 
    EXEC sp_testlinkedserver @ls;
    PRINT N'Linked Server ' + @ls + N' -> ' + @host + N' OK';
    FETCH NEXT FROM c INTO @db, @host;
END
CLOSE c;
DEALLOCATE c;
GO


/* =====================================================================
   PHẦN 2. DATABASE VÀ BẢNG Ở 3 NODE (chạy từ xa)
   Khuôn DDL của một node: {K} được thay bằng mã khoa. Dấu nháy trong khuôn viết đôi ('') vì nằm trong chuỗi.
   ===================================================================== */
DECLARE @ddl NVARCHAR(MAX) = N'
-- Bản sao danh mục (nhân bản từ QLSV_TongHop)

CREATE TABLE dbo.Khoa (
    MaKhoa       VARCHAR(10)    NOT NULL,
    TenKhoa      NVARCHAR(100)  NOT NULL,
    NamThanhLap  SMALLINT       NULL,
    DienThoai    VARCHAR(10)    NULL,
    Email        VARCHAR(100)   NOT NULL,
    CONSTRAINT PK_Khoa              PRIMARY KEY (MaKhoa),
    CONSTRAINT UQ_Khoa_TenKhoa      UNIQUE (TenKhoa),
    CONSTRAINT UQ_Khoa_Email        UNIQUE (Email),
    CONSTRAINT CK_Khoa_NamThanhLap  CHECK (NamThanhLap BETWEEN 1950 AND 2100),
    CONSTRAINT CK_Khoa_DienThoai    CHECK (DienThoai LIKE ''0[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]''),
    CONSTRAINT CK_Khoa_Email        CHECK (Email LIKE ''%_@_%._%'')
);
CREATE TABLE dbo.HocKy (
    MaHK         VARCHAR(10)    NOT NULL,   -- vd: HK1-2526
    TenHK        NVARCHAR(20)   NOT NULL,
    NamHoc       CHAR(9)        NOT NULL,   -- vd: 2025-2026
    NgayBatDau   DATE           NOT NULL,
    NgayKetThuc  DATE           NOT NULL,
    CONSTRAINT PK_HocKy             PRIMARY KEY (MaHK),
    CONSTRAINT UQ_HocKy_Ten_Nam     UNIQUE (TenHK, NamHoc),
    CONSTRAINT CK_HocKy_TenHK       CHECK (TenHK IN (N''Học kỳ 1'', N''Học kỳ 2'', N''Học kỳ hè'')),
    CONSTRAINT CK_HocKy_NamHoc      CHECK (NamHoc LIKE ''[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]''),
    CONSTRAINT CK_HocKy_Ngay        CHECK (NgayKetThuc > NgayBatDau)
);
CREATE TABLE dbo.MonHoc (
    MaMH         VARCHAR(10)    NOT NULL,
    TenMH        NVARCHAR(100)  NOT NULL,
    SoTinChi     TINYINT        NOT NULL,
    LoaiMH       NVARCHAR(20)   NOT NULL  CONSTRAINT DF_MonHoc_LoaiMH DEFAULT N''Bắt buộc'',
    MaKhoa       VARCHAR(10)    NULL,       -- khoa phụ trách; NULL = môn chung toàn trường
    CONSTRAINT PK_MonHoc            PRIMARY KEY (MaMH),
    CONSTRAINT UQ_MonHoc_TenMH      UNIQUE (TenMH),
    CONSTRAINT CK_MonHoc_SoTinChi   CHECK (SoTinChi BETWEEN 1 AND 6),
    CONSTRAINT CK_MonHoc_LoaiMH     CHECK (LoaiMH IN (N''Bắt buộc'', N''Tự chọn'')),
    CONSTRAINT FK_MonHoc_Khoa       FOREIGN KEY (MaKhoa) REFERENCES dbo.Khoa (MaKhoa)
);
CREATE TABLE dbo.GiangVien (
    MaGV         VARCHAR(10)    NOT NULL,
    HoTen        NVARCHAR(100)  NOT NULL,
    GioiTinh     NVARCHAR(3)    NOT NULL,
    NgaySinh     DATE           NOT NULL,
    HocVi        NVARCHAR(20)   NOT NULL,
    Email        VARCHAR(100)   NOT NULL,
    DienThoai    VARCHAR(10)    NULL,
    MaKhoa       VARCHAR(10)    NOT NULL,
    CONSTRAINT PK_GiangVien         PRIMARY KEY (MaGV),
    CONSTRAINT UQ_GiangVien_Email   UNIQUE (Email),
    CONSTRAINT CK_GiangVien_GioiTinh CHECK (GioiTinh IN (N''Nam'', N''Nữ'')),
    CONSTRAINT CK_GiangVien_NgaySinh CHECK (NgaySinh BETWEEN ''1950-01-01'' AND ''2003-12-31''),
    CONSTRAINT CK_GiangVien_HocVi   CHECK (HocVi IN (N''Thạc sĩ'', N''Tiến sĩ'', N''PGS.TS'', N''GS.TS'')),
    CONSTRAINT CK_GiangVien_Email   CHECK (Email LIKE ''%_@_%._%''),
    CONSTRAINT CK_GiangVien_DienThoai CHECK (DienThoai LIKE ''0[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]''),
    CONSTRAINT CK_GiangVien_MaKhoa_{K} CHECK (MaKhoa = ''{K}''),   -- điều kiện phân mảnh ngang
    CONSTRAINT FK_GiangVien_Khoa    FOREIGN KEY (MaKhoa) REFERENCES dbo.Khoa (MaKhoa)
);
CREATE TABLE dbo.Lop (
    MaLop        VARCHAR(15)    NOT NULL,   -- vd: 65.CNTT-1
    TenLop       NVARCHAR(100)  NOT NULL,
    NienKhoa     CHAR(9)        NOT NULL,   -- vd: 2023-2027
    MaKhoa       VARCHAR(10)    NOT NULL,
    MaGVCN       VARCHAR(10)    NULL,       -- giảng viên chủ nhiệm
    CONSTRAINT PK_Lop               PRIMARY KEY (MaLop),
    CONSTRAINT UQ_Lop_TenLop        UNIQUE (TenLop),
    CONSTRAINT CK_Lop_NienKhoa      CHECK (NienKhoa LIKE ''[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]''),
    CONSTRAINT CK_Lop_MaKhoa_{K} CHECK (MaKhoa = ''{K}''),   -- điều kiện phân mảnh ngang
    CONSTRAINT FK_Lop_Khoa          FOREIGN KEY (MaKhoa) REFERENCES dbo.Khoa (MaKhoa),
    CONSTRAINT FK_Lop_GiangVien     FOREIGN KEY (MaGVCN) REFERENCES dbo.GiangVien (MaGV)
);
-- Mảnh dọc 1 của SinhVien (thông tin học vụ) + phân mảnh ngang DẪN XUẤT theo Lop:
-- FK tới Lop cục bộ bảo đảm sinh viên chỉ thuộc lớp của khoa này.
CREATE TABLE dbo.SinhVien (
    MaSV         CHAR(8)        NOT NULL,
    HoTen        NVARCHAR(100)  NOT NULL,
    NgaySinh     DATE           NOT NULL,
    GioiTinh     NVARCHAR(3)    NOT NULL,
    MaLop        VARCHAR(15)    NOT NULL,
    TrangThai    NVARCHAR(20)   NOT NULL  CONSTRAINT DF_SinhVien_TrangThai DEFAULT N''Đang học'',
    CONSTRAINT PK_SinhVien          PRIMARY KEY (MaSV),
    CONSTRAINT CK_SinhVien_MaSV     CHECK (MaSV NOT LIKE ''%[^0-9]%''),
    CONSTRAINT CK_SinhVien_GioiTinh CHECK (GioiTinh IN (N''Nam'', N''Nữ'')),
    CONSTRAINT CK_SinhVien_NgaySinh CHECK (NgaySinh BETWEEN ''1990-01-01'' AND ''2010-12-31''),
    CONSTRAINT CK_SinhVien_TrangThai CHECK (TrangThai IN (N''Đang học'', N''Bảo lưu'', N''Thôi học'', N''Đã tốt nghiệp'')),
    CONSTRAINT FK_SinhVien_Lop      FOREIGN KEY (MaLop) REFERENCES dbo.Lop (MaLop)
);
-- Phân mảnh ngang dẫn xuất: FK tới GiangVien cục bộ -> lớp học phần do khoa này mở.

CREATE TABLE dbo.LopHocPhan (
    MaLHP        VARCHAR(20)    NOT NULL,   -- vd: CNTT101-HK1-2526-01
    MaMH         VARCHAR(10)    NOT NULL,
    MaHK         VARCHAR(10)    NOT NULL,
    Nhom         TINYINT        NOT NULL  CONSTRAINT DF_LopHocPhan_Nhom DEFAULT 1,
    MaGV         VARCHAR(10)    NOT NULL,
    SiSoToiDa    SMALLINT       NOT NULL  CONSTRAINT DF_LopHocPhan_SiSo DEFAULT 60,
    PhongHoc     VARCHAR(10)    NULL,
    CONSTRAINT PK_LopHocPhan        PRIMARY KEY (MaLHP),
    CONSTRAINT UQ_LopHocPhan_MH_HK_Nhom UNIQUE (MaMH, MaHK, Nhom),
    CONSTRAINT CK_LopHocPhan_Nhom   CHECK (Nhom BETWEEN 1 AND 20),
    CONSTRAINT CK_LopHocPhan_SiSo   CHECK (SiSoToiDa BETWEEN 10 AND 200),
    CONSTRAINT FK_LopHocPhan_MonHoc FOREIGN KEY (MaMH) REFERENCES dbo.MonHoc (MaMH),
    CONSTRAINT FK_LopHocPhan_HocKy  FOREIGN KEY (MaHK) REFERENCES dbo.HocKy (MaHK),
    CONSTRAINT FK_LopHocPhan_GiangVien FOREIGN KEY (MaGV) REFERENCES dbo.GiangVien (MaGV)
);
-- Phân mảnh ngang dẫn xuất: FK tới SinhVien cục bộ -> đăng ký của sinh viên khoa này.

-- Điểm tổng kết = 40% quá trình + 60% thi, làm tròn 1 chữ số (cột tính toán).
CREATE TABLE dbo.DangKy (
    MaSV         CHAR(8)        NOT NULL,
    MaLHP        VARCHAR(20)    NOT NULL,
    NgayDangKy   DATE           NOT NULL  CONSTRAINT DF_DangKy_NgayDangKy DEFAULT CAST(GETDATE() AS DATE),
    DiemQT       DECIMAL(4,2)   NULL,
    DiemThi      DECIMAL(4,2)   NULL,
    DiemTK       AS CAST(ROUND(DiemQT * 0.4 + DiemThi * 0.6, 1) AS DECIMAL(4,2)) PERSISTED,
    CONSTRAINT PK_DangKy            PRIMARY KEY (MaSV, MaLHP),
    CONSTRAINT CK_DangKy_DiemQT     CHECK (DiemQT BETWEEN 0 AND 10),
    CONSTRAINT CK_DangKy_DiemThi    CHECK (DiemThi BETWEEN 0 AND 10),
    CONSTRAINT FK_DangKy_SinhVien   FOREIGN KEY (MaSV)  REFERENCES dbo.SinhVien (MaSV),
    CONSTRAINT FK_DangKy_LopHocPhan FOREIGN KEY (MaLHP) REFERENCES dbo.LopHocPhan (MaLHP)
);
-- Bảng log, được ghi bởi trigger (file 09_triggers.sql).
CREATE TABLE dbo.NhatKy (
    MaNK         INT IDENTITY(1,1) NOT NULL,
    TenBang      SYSNAME        NOT NULL,
    HanhDong     VARCHAR(10)    NOT NULL,
    KhoaChinh    NVARCHAR(100)  NOT NULL,
    NoiDungCu    NVARCHAR(MAX)  NULL,
    NoiDungMoi   NVARCHAR(MAX)  NULL,
    NguoiThucHien SYSNAME       NOT NULL  CONSTRAINT DF_NhatKy_Nguoi DEFAULT SUSER_SNAME(),
    ThoiGian     DATETIME2(0)   NOT NULL  CONSTRAINT DF_NhatKy_ThoiGian DEFAULT SYSDATETIME(),
    CONSTRAINT PK_NhatKy            PRIMARY KEY (MaNK),
    CONSTRAINT CK_NhatKy_HanhDong   CHECK (HanhDong IN (''INSERT'', ''UPDATE'', ''DELETE''))
);
';

DECLARE @db SYSNAME, @k VARCHAR(10), @ls SYSNAME, @exec NVARCHAR(300), @sql NVARCHAR(MAX);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT db, k FROM (VALUES (N'QLSV_CNTT', 'CNTT'), (N'QLSV_NgoaiNgu', 'NN'), (N'QLSV_DuLich', 'DL')) n(db, k);
OPEN c;
FETCH NEXT FROM c INTO @db, @k;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @ls = N'LS_' + @db;
    -- (a) xóa database cũ của node (ngắt kết nối đang mở trước), tạo mới
    SET @exec = @ls + N'.master.sys.sp_executesql';
    SET @sql = N'IF DB_ID(N''' + @db + N''') IS NOT NULL
                 BEGIN
                     ALTER DATABASE ' + QUOTENAME(@db) + N' SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
                     DROP DATABASE ' + QUOTENAME(@db) + N';
                 END';
    EXEC @exec @sql;
    SET @sql = N'CREATE DATABASE ' + QUOTENAME(@db) + N' COLLATE Vietnamese_CI_AS;';
    EXEC @exec @sql;
    -- (b) tạo 9 bảng trong database vừa tạo (chạy trong ngữ cảnh database đó)
    SET @exec = @ls + N'.' + QUOTENAME(@db) + N'.sys.sp_executesql';
    SET @sql = N'SET QUOTED_IDENTIFIER ON; SET ANSI_NULLS ON;' + REPLACE(@ddl, N'{K}', @k);   -- bắt buộc cho cột tính toán PERSISTED
    EXEC @exec @sql;
    PRINT N'Đã dựng ' + @db + N' ở node ' + @ls + N' (MaKhoa = ' + @k + N')';
    FETCH NEXT FROM c INTO @db, @k;
END
CLOSE c;
DEALLOCATE c;
GO


/* =====================================================================
   PHẦN 3. DATABASE ĐẠI DIỆN: mỗi bảng của node là một synonym tới bảng thật ở instance node
   ===================================================================== */
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


/* =====================================================================
   PHẦN 4. KIỂM TRA
   ===================================================================== */
-- Mỗi node có đủ 9 bảng; số ràng buộc CHECK và khóa ngoại đọc thẳng từ catalog của node
SELECT N'QLSV_CNTT' AS Node, t.name AS TenBang,
       (SELECT COUNT(*) FROM LS_QLSV_CNTT.QLSV_CNTT.sys.check_constraints c WHERE c.parent_object_id = t.object_id) AS SoCHECK,
       (SELECT COUNT(*) FROM LS_QLSV_CNTT.QLSV_CNTT.sys.foreign_keys f WHERE f.parent_object_id = t.object_id) AS SoFK
FROM LS_QLSV_CNTT.QLSV_CNTT.sys.tables t
UNION ALL
SELECT N'QLSV_NgoaiNgu', t.name,
       (SELECT COUNT(*) FROM LS_QLSV_NgoaiNgu.QLSV_NgoaiNgu.sys.check_constraints c WHERE c.parent_object_id = t.object_id),
       (SELECT COUNT(*) FROM LS_QLSV_NgoaiNgu.QLSV_NgoaiNgu.sys.foreign_keys f WHERE f.parent_object_id = t.object_id)
FROM LS_QLSV_NgoaiNgu.QLSV_NgoaiNgu.sys.tables t
UNION ALL
SELECT N'QLSV_DuLich', t.name,
       (SELECT COUNT(*) FROM LS_QLSV_DuLich.QLSV_DuLich.sys.check_constraints c WHERE c.parent_object_id = t.object_id),
       (SELECT COUNT(*) FROM LS_QLSV_DuLich.QLSV_DuLich.sys.foreign_keys f WHERE f.parent_object_id = t.object_id)
FROM LS_QLSV_DuLich.QLSV_DuLich.sys.tables t
ORDER BY Node, TenBang;
GO

-- Đi qua synonym tới đủ 3 node (bảng còn rỗng vì chưa nạp dữ liệu ở 03, 04)
SELECT N'CNTT' AS Node, COUNT(*) AS SoSinhVien FROM QLSV_CNTT.dbo.SinhVien
UNION ALL SELECT N'NN', COUNT(*) FROM QLSV_NgoaiNgu.dbo.SinhVien
UNION ALL SELECT N'DL', COUNT(*) FROM QLSV_DuLich.dbo.SinhVien;
GO
