/* =====================================================================
   ĐỒ ÁN CSDL PHÂN TÁN – QUẢN LÝ SINH VIÊN NHIỀU KHOA
   File   : 02_create_tables.sql
   Mục đích: Tạo bảng cho CSDL tập trung và cho từng node phân tán.
   Người viết: ...............          Ngày: ..../11/2026
   Chạy sau : 01_create_databases.sql

   THIẾT KẾ TẬP TRUNG (QLSV_TapTrung) – 9 bảng, đạt 3NF:
     Khoa, HocKy, MonHoc, GiangVien, Lop, SinhVien, LopHocPhan, DangKy, NhatKy

   PHÂN BỐ DỮ LIỆU
   ---------------------------------------------------------------------
   Bảng          | Cách phân bố                                  | Đặt tại
   --------------+-----------------------------------------------+-----------
   Khoa, HocKy,  | NHÂN BẢN TOÀN PHẦN (bảng danh mục nhỏ, ít đổi)| TongHop (bản chính)
   MonHoc        |   -> node khoa có FK cục bộ                    | + 3 node khoa
   GiangVien     | NGANG CHÍNH theo MaKhoa (CHECK MaKhoa = ...)   | 3 node khoa
   Lop           | NGANG CHÍNH theo MaKhoa (CHECK MaKhoa = ...)   | 3 node khoa
   SinhVien      | DỌC: (MaSV, HoTen, NgaySinh, GioiTinh, MaLop,  | 3 node khoa
                 |       TrangThai)                              |
                 |   + NGANG DẪN XUẤT theo Lop                    |
   SinhVien_HoSo | DỌC: (MaSV, CCCD, DienThoai, Email, DiaChi)    | TongHop
   LopHocPhan    | NGANG DẪN XUẤT theo GiangVien (khoa mở lớp)    | 3 node khoa
   DangKy        | NGANG DẪN XUẤT theo SinhVien                   | 3 node khoa
   NhatKy        | Mỗi node một bảng log riêng                    | mọi node

   Tái thiết:  SinhVien  = (SV_CNTT ∪ SV_NN ∪ SV_DL) ⋈ SinhVien_HoSo
               các bảng ngang khác = UNION ALL 3 node     (file 05_views.sql)
   ===================================================================== */

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;   -- bắt buộc cho cột tính toán PERSISTED
GO


/* =====================================================================
   PHẦN 1. CSDL TẬP TRUNG – QLSV_TapTrung
   ===================================================================== */

USE QLSV_TapTrung;
GO
DROP TABLE IF EXISTS dbo.DangKy, dbo.LopHocPhan, dbo.SinhVien,
                     dbo.Lop, dbo.GiangVien, dbo.MonHoc, dbo.HocKy, dbo.Khoa, dbo.NhatKy;
GO

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
    CONSTRAINT CK_Khoa_DienThoai    CHECK (DienThoai LIKE '0[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'),
    CONSTRAINT CK_Khoa_Email        CHECK (Email LIKE '%_@_%._%')
);
GO

CREATE TABLE dbo.HocKy (
    MaHK         VARCHAR(10)    NOT NULL,   -- vd: HK1-2526
    TenHK        NVARCHAR(20)   NOT NULL,
    NamHoc       CHAR(9)        NOT NULL,   -- vd: 2025-2026
    NgayBatDau   DATE           NOT NULL,
    NgayKetThuc  DATE           NOT NULL,
    CONSTRAINT PK_HocKy             PRIMARY KEY (MaHK),
    CONSTRAINT UQ_HocKy_Ten_Nam     UNIQUE (TenHK, NamHoc),
    CONSTRAINT CK_HocKy_TenHK       CHECK (TenHK IN (N'Học kỳ 1', N'Học kỳ 2', N'Học kỳ hè')),
    CONSTRAINT CK_HocKy_NamHoc      CHECK (NamHoc LIKE '[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]'),
    CONSTRAINT CK_HocKy_Ngay        CHECK (NgayKetThuc > NgayBatDau)
);
GO

CREATE TABLE dbo.MonHoc (
    MaMH         VARCHAR(10)    NOT NULL,
    TenMH        NVARCHAR(100)  NOT NULL,
    SoTinChi     TINYINT        NOT NULL,
    LoaiMH       NVARCHAR(20)   NOT NULL  CONSTRAINT DF_MonHoc_LoaiMH DEFAULT N'Bắt buộc',
    MaKhoa       VARCHAR(10)    NULL,       -- khoa phụ trách; NULL = môn chung toàn trường
    CONSTRAINT PK_MonHoc            PRIMARY KEY (MaMH),
    CONSTRAINT UQ_MonHoc_TenMH      UNIQUE (TenMH),
    CONSTRAINT CK_MonHoc_SoTinChi   CHECK (SoTinChi BETWEEN 1 AND 6),
    CONSTRAINT CK_MonHoc_LoaiMH     CHECK (LoaiMH IN (N'Bắt buộc', N'Tự chọn')),
    CONSTRAINT FK_MonHoc_Khoa       FOREIGN KEY (MaKhoa) REFERENCES dbo.Khoa (MaKhoa)
);
GO

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
    CONSTRAINT CK_GiangVien_GioiTinh CHECK (GioiTinh IN (N'Nam', N'Nữ')),
    CONSTRAINT CK_GiangVien_NgaySinh CHECK (NgaySinh BETWEEN '1950-01-01' AND '2003-12-31'),
    CONSTRAINT CK_GiangVien_HocVi   CHECK (HocVi IN (N'Thạc sĩ', N'Tiến sĩ', N'PGS.TS', N'GS.TS')),
    CONSTRAINT CK_GiangVien_Email   CHECK (Email LIKE '%_@_%._%'),
    CONSTRAINT CK_GiangVien_DienThoai CHECK (DienThoai LIKE '0[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'),
    CONSTRAINT FK_GiangVien_Khoa    FOREIGN KEY (MaKhoa) REFERENCES dbo.Khoa (MaKhoa)
);
GO

CREATE TABLE dbo.Lop (
    MaLop        VARCHAR(15)    NOT NULL,   -- vd: 65.CNTT-1
    TenLop       NVARCHAR(100)  NOT NULL,
    NienKhoa     CHAR(9)        NOT NULL,   -- vd: 2023-2027
    MaKhoa       VARCHAR(10)    NOT NULL,
    MaGVCN       VARCHAR(10)    NULL,       -- giảng viên chủ nhiệm
    CONSTRAINT PK_Lop               PRIMARY KEY (MaLop),
    CONSTRAINT UQ_Lop_TenLop        UNIQUE (TenLop),
    CONSTRAINT CK_Lop_NienKhoa      CHECK (NienKhoa LIKE '[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]'),
    CONSTRAINT FK_Lop_Khoa          FOREIGN KEY (MaKhoa) REFERENCES dbo.Khoa (MaKhoa),
    CONSTRAINT FK_Lop_GiangVien     FOREIGN KEY (MaGVCN) REFERENCES dbo.GiangVien (MaGV)
);
GO

CREATE TABLE dbo.SinhVien (
    MaSV         CHAR(8)        NOT NULL,
    HoTen        NVARCHAR(100)  NOT NULL,
    NgaySinh     DATE           NOT NULL,
    GioiTinh     NVARCHAR(3)    NOT NULL,
    MaLop        VARCHAR(15)    NOT NULL,
    TrangThai    NVARCHAR(20)   NOT NULL  CONSTRAINT DF_SinhVien_TrangThai DEFAULT N'Đang học',
    CCCD         CHAR(12)       NOT NULL,
    DienThoai    VARCHAR(10)    NULL,
    Email        VARCHAR(100)   NOT NULL,
    DiaChi       NVARCHAR(200)  NULL,
    CONSTRAINT PK_SinhVien          PRIMARY KEY (MaSV),
    CONSTRAINT CK_SinhVien_MaSV     CHECK (MaSV NOT LIKE '%[^0-9]%'),
    CONSTRAINT CK_SinhVien_GioiTinh CHECK (GioiTinh IN (N'Nam', N'Nữ')),
    CONSTRAINT CK_SinhVien_NgaySinh CHECK (NgaySinh BETWEEN '1990-01-01' AND '2010-12-31'),
    CONSTRAINT CK_SinhVien_TrangThai CHECK (TrangThai IN (N'Đang học', N'Bảo lưu', N'Thôi học', N'Đã tốt nghiệp')),
    CONSTRAINT UQ_SinhVien_CCCD          UNIQUE (CCCD),
    CONSTRAINT UQ_SinhVien_Email         UNIQUE (Email),
    CONSTRAINT CK_SinhVien_CCCD          CHECK (CCCD NOT LIKE '%[^0-9]%'),
    CONSTRAINT CK_SinhVien_DienThoai     CHECK (DienThoai LIKE '0[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'),
    CONSTRAINT CK_SinhVien_Email         CHECK (Email LIKE '%_@_%._%'),
    CONSTRAINT FK_SinhVien_Lop      FOREIGN KEY (MaLop) REFERENCES dbo.Lop (MaLop)
);
GO

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
GO

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
GO

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
    CONSTRAINT CK_NhatKy_HanhDong   CHECK (HanhDong IN ('INSERT', 'UPDATE', 'DELETE'))
);
GO


/* =====================================================================
   PHẦN 2. NODE ĐIỀU PHỐI – QLSV_TongHop
   Bản chính của danh mục + mảnh dọc hồ sơ sinh viên + log
   ===================================================================== */

USE QLSV_TongHop;
GO
DROP TABLE IF EXISTS dbo.DangKy, dbo.LopHocPhan, dbo.SinhVien, dbo.SinhVien_HoSo,
                     dbo.Lop, dbo.GiangVien, dbo.MonHoc, dbo.HocKy, dbo.Khoa, dbo.NhatKy;
GO

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
    CONSTRAINT CK_Khoa_DienThoai    CHECK (DienThoai LIKE '0[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'),
    CONSTRAINT CK_Khoa_Email        CHECK (Email LIKE '%_@_%._%')
);
GO

CREATE TABLE dbo.HocKy (
    MaHK         VARCHAR(10)    NOT NULL,   -- vd: HK1-2526
    TenHK        NVARCHAR(20)   NOT NULL,
    NamHoc       CHAR(9)        NOT NULL,   -- vd: 2025-2026
    NgayBatDau   DATE           NOT NULL,
    NgayKetThuc  DATE           NOT NULL,
    CONSTRAINT PK_HocKy             PRIMARY KEY (MaHK),
    CONSTRAINT UQ_HocKy_Ten_Nam     UNIQUE (TenHK, NamHoc),
    CONSTRAINT CK_HocKy_TenHK       CHECK (TenHK IN (N'Học kỳ 1', N'Học kỳ 2', N'Học kỳ hè')),
    CONSTRAINT CK_HocKy_NamHoc      CHECK (NamHoc LIKE '[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]'),
    CONSTRAINT CK_HocKy_Ngay        CHECK (NgayKetThuc > NgayBatDau)
);
GO

CREATE TABLE dbo.MonHoc (
    MaMH         VARCHAR(10)    NOT NULL,
    TenMH        NVARCHAR(100)  NOT NULL,
    SoTinChi     TINYINT        NOT NULL,
    LoaiMH       NVARCHAR(20)   NOT NULL  CONSTRAINT DF_MonHoc_LoaiMH DEFAULT N'Bắt buộc',
    MaKhoa       VARCHAR(10)    NULL,       -- khoa phụ trách; NULL = môn chung toàn trường
    CONSTRAINT PK_MonHoc            PRIMARY KEY (MaMH),
    CONSTRAINT UQ_MonHoc_TenMH      UNIQUE (TenMH),
    CONSTRAINT CK_MonHoc_SoTinChi   CHECK (SoTinChi BETWEEN 1 AND 6),
    CONSTRAINT CK_MonHoc_LoaiMH     CHECK (LoaiMH IN (N'Bắt buộc', N'Tự chọn')),
    CONSTRAINT FK_MonHoc_Khoa       FOREIGN KEY (MaKhoa) REFERENCES dbo.Khoa (MaKhoa)
);
GO

-- Mảnh dọc 2 của SinhVien (thông tin cá nhân nhạy cảm), do Phòng Đào tạo quản lý.
-- Không thể tạo FK tới SinhVien ở database khác (SQL Server không hỗ trợ FK
-- giữa 2 database) -> ràng buộc MaSV phải tồn tại ở 1 node khoa được kiểm tra
-- bằng trigger (file 09_triggers.sql).
CREATE TABLE dbo.SinhVien_HoSo (
    MaSV         CHAR(8)        NOT NULL,
    CCCD         CHAR(12)       NOT NULL,
    DienThoai    VARCHAR(10)    NULL,
    Email        VARCHAR(100)   NOT NULL,
    DiaChi       NVARCHAR(200)  NULL,
    CONSTRAINT PK_SinhVien_HoSo     PRIMARY KEY (MaSV),
    CONSTRAINT UQ_SinhVien_HoSo_CCCD          UNIQUE (CCCD),
    CONSTRAINT UQ_SinhVien_HoSo_Email         UNIQUE (Email),
    CONSTRAINT CK_SinhVien_HoSo_CCCD          CHECK (CCCD NOT LIKE '%[^0-9]%'),
    CONSTRAINT CK_SinhVien_HoSo_DienThoai     CHECK (DienThoai LIKE '0[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'),
    CONSTRAINT CK_SinhVien_HoSo_Email         CHECK (Email LIKE '%_@_%._%')
);
GO

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
    CONSTRAINT CK_NhatKy_HanhDong   CHECK (HanhDong IN ('INSERT', 'UPDATE', 'DELETE'))
);
GO


/* =====================================================================
   PHẦN 3. NODE KHOA CÔNG NGHỆ THÔNG TIN – QLSV_CNTT
   Điều kiện phân mảnh: MaKhoa = 'CNTT'
   ===================================================================== */

USE QLSV_CNTT;
GO
DROP TABLE IF EXISTS dbo.DangKy, dbo.LopHocPhan, dbo.SinhVien,
                     dbo.Lop, dbo.GiangVien, dbo.MonHoc, dbo.HocKy, dbo.Khoa, dbo.NhatKy;
GO

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
    CONSTRAINT CK_Khoa_DienThoai    CHECK (DienThoai LIKE '0[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'),
    CONSTRAINT CK_Khoa_Email        CHECK (Email LIKE '%_@_%._%')
);
GO

CREATE TABLE dbo.HocKy (
    MaHK         VARCHAR(10)    NOT NULL,   -- vd: HK1-2526
    TenHK        NVARCHAR(20)   NOT NULL,
    NamHoc       CHAR(9)        NOT NULL,   -- vd: 2025-2026
    NgayBatDau   DATE           NOT NULL,
    NgayKetThuc  DATE           NOT NULL,
    CONSTRAINT PK_HocKy             PRIMARY KEY (MaHK),
    CONSTRAINT UQ_HocKy_Ten_Nam     UNIQUE (TenHK, NamHoc),
    CONSTRAINT CK_HocKy_TenHK       CHECK (TenHK IN (N'Học kỳ 1', N'Học kỳ 2', N'Học kỳ hè')),
    CONSTRAINT CK_HocKy_NamHoc      CHECK (NamHoc LIKE '[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]'),
    CONSTRAINT CK_HocKy_Ngay        CHECK (NgayKetThuc > NgayBatDau)
);
GO

CREATE TABLE dbo.MonHoc (
    MaMH         VARCHAR(10)    NOT NULL,
    TenMH        NVARCHAR(100)  NOT NULL,
    SoTinChi     TINYINT        NOT NULL,
    LoaiMH       NVARCHAR(20)   NOT NULL  CONSTRAINT DF_MonHoc_LoaiMH DEFAULT N'Bắt buộc',
    MaKhoa       VARCHAR(10)    NULL,       -- khoa phụ trách; NULL = môn chung toàn trường
    CONSTRAINT PK_MonHoc            PRIMARY KEY (MaMH),
    CONSTRAINT UQ_MonHoc_TenMH      UNIQUE (TenMH),
    CONSTRAINT CK_MonHoc_SoTinChi   CHECK (SoTinChi BETWEEN 1 AND 6),
    CONSTRAINT CK_MonHoc_LoaiMH     CHECK (LoaiMH IN (N'Bắt buộc', N'Tự chọn')),
    CONSTRAINT FK_MonHoc_Khoa       FOREIGN KEY (MaKhoa) REFERENCES dbo.Khoa (MaKhoa)
);
GO

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
    CONSTRAINT CK_GiangVien_GioiTinh CHECK (GioiTinh IN (N'Nam', N'Nữ')),
    CONSTRAINT CK_GiangVien_NgaySinh CHECK (NgaySinh BETWEEN '1950-01-01' AND '2003-12-31'),
    CONSTRAINT CK_GiangVien_HocVi   CHECK (HocVi IN (N'Thạc sĩ', N'Tiến sĩ', N'PGS.TS', N'GS.TS')),
    CONSTRAINT CK_GiangVien_Email   CHECK (Email LIKE '%_@_%._%'),
    CONSTRAINT CK_GiangVien_DienThoai CHECK (DienThoai LIKE '0[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'),
    CONSTRAINT CK_GiangVien_MaKhoa_CNTT CHECK (MaKhoa = 'CNTT'),   -- điều kiện phân mảnh ngang
    CONSTRAINT FK_GiangVien_Khoa    FOREIGN KEY (MaKhoa) REFERENCES dbo.Khoa (MaKhoa)
);
GO

CREATE TABLE dbo.Lop (
    MaLop        VARCHAR(15)    NOT NULL,   -- vd: 65.CNTT-1
    TenLop       NVARCHAR(100)  NOT NULL,
    NienKhoa     CHAR(9)        NOT NULL,   -- vd: 2023-2027
    MaKhoa       VARCHAR(10)    NOT NULL,
    MaGVCN       VARCHAR(10)    NULL,       -- giảng viên chủ nhiệm
    CONSTRAINT PK_Lop               PRIMARY KEY (MaLop),
    CONSTRAINT UQ_Lop_TenLop        UNIQUE (TenLop),
    CONSTRAINT CK_Lop_NienKhoa      CHECK (NienKhoa LIKE '[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]'),
    CONSTRAINT CK_Lop_MaKhoa_CNTT CHECK (MaKhoa = 'CNTT'),   -- điều kiện phân mảnh ngang
    CONSTRAINT FK_Lop_Khoa          FOREIGN KEY (MaKhoa) REFERENCES dbo.Khoa (MaKhoa),
    CONSTRAINT FK_Lop_GiangVien     FOREIGN KEY (MaGVCN) REFERENCES dbo.GiangVien (MaGV)
);
GO

-- Mảnh dọc 1 của SinhVien (thông tin học vụ) + phân mảnh ngang DẪN XUẤT theo Lop:
-- FK tới Lop cục bộ bảo đảm sinh viên chỉ thuộc lớp của khoa này.
CREATE TABLE dbo.SinhVien (
    MaSV         CHAR(8)        NOT NULL,
    HoTen        NVARCHAR(100)  NOT NULL,
    NgaySinh     DATE           NOT NULL,
    GioiTinh     NVARCHAR(3)    NOT NULL,
    MaLop        VARCHAR(15)    NOT NULL,
    TrangThai    NVARCHAR(20)   NOT NULL  CONSTRAINT DF_SinhVien_TrangThai DEFAULT N'Đang học',
    CONSTRAINT PK_SinhVien          PRIMARY KEY (MaSV),
    CONSTRAINT CK_SinhVien_MaSV     CHECK (MaSV NOT LIKE '%[^0-9]%'),
    CONSTRAINT CK_SinhVien_GioiTinh CHECK (GioiTinh IN (N'Nam', N'Nữ')),
    CONSTRAINT CK_SinhVien_NgaySinh CHECK (NgaySinh BETWEEN '1990-01-01' AND '2010-12-31'),
    CONSTRAINT CK_SinhVien_TrangThai CHECK (TrangThai IN (N'Đang học', N'Bảo lưu', N'Thôi học', N'Đã tốt nghiệp')),
    CONSTRAINT FK_SinhVien_Lop      FOREIGN KEY (MaLop) REFERENCES dbo.Lop (MaLop)
);
GO

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
GO

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
GO

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
    CONSTRAINT CK_NhatKy_HanhDong   CHECK (HanhDong IN ('INSERT', 'UPDATE', 'DELETE'))
);
GO


/* =====================================================================
   PHẦN 4. NODE KHOA NGOẠI NGỮ – QLSV_NgoaiNgu
   Điều kiện phân mảnh: MaKhoa = 'NN'
   ===================================================================== */

USE QLSV_NgoaiNgu;
GO
DROP TABLE IF EXISTS dbo.DangKy, dbo.LopHocPhan, dbo.SinhVien,
                     dbo.Lop, dbo.GiangVien, dbo.MonHoc, dbo.HocKy, dbo.Khoa, dbo.NhatKy;
GO

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
    CONSTRAINT CK_Khoa_DienThoai    CHECK (DienThoai LIKE '0[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'),
    CONSTRAINT CK_Khoa_Email        CHECK (Email LIKE '%_@_%._%')
);
GO

CREATE TABLE dbo.HocKy (
    MaHK         VARCHAR(10)    NOT NULL,   -- vd: HK1-2526
    TenHK        NVARCHAR(20)   NOT NULL,
    NamHoc       CHAR(9)        NOT NULL,   -- vd: 2025-2026
    NgayBatDau   DATE           NOT NULL,
    NgayKetThuc  DATE           NOT NULL,
    CONSTRAINT PK_HocKy             PRIMARY KEY (MaHK),
    CONSTRAINT UQ_HocKy_Ten_Nam     UNIQUE (TenHK, NamHoc),
    CONSTRAINT CK_HocKy_TenHK       CHECK (TenHK IN (N'Học kỳ 1', N'Học kỳ 2', N'Học kỳ hè')),
    CONSTRAINT CK_HocKy_NamHoc      CHECK (NamHoc LIKE '[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]'),
    CONSTRAINT CK_HocKy_Ngay        CHECK (NgayKetThuc > NgayBatDau)
);
GO

CREATE TABLE dbo.MonHoc (
    MaMH         VARCHAR(10)    NOT NULL,
    TenMH        NVARCHAR(100)  NOT NULL,
    SoTinChi     TINYINT        NOT NULL,
    LoaiMH       NVARCHAR(20)   NOT NULL  CONSTRAINT DF_MonHoc_LoaiMH DEFAULT N'Bắt buộc',
    MaKhoa       VARCHAR(10)    NULL,       -- khoa phụ trách; NULL = môn chung toàn trường
    CONSTRAINT PK_MonHoc            PRIMARY KEY (MaMH),
    CONSTRAINT UQ_MonHoc_TenMH      UNIQUE (TenMH),
    CONSTRAINT CK_MonHoc_SoTinChi   CHECK (SoTinChi BETWEEN 1 AND 6),
    CONSTRAINT CK_MonHoc_LoaiMH     CHECK (LoaiMH IN (N'Bắt buộc', N'Tự chọn')),
    CONSTRAINT FK_MonHoc_Khoa       FOREIGN KEY (MaKhoa) REFERENCES dbo.Khoa (MaKhoa)
);
GO

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
    CONSTRAINT CK_GiangVien_GioiTinh CHECK (GioiTinh IN (N'Nam', N'Nữ')),
    CONSTRAINT CK_GiangVien_NgaySinh CHECK (NgaySinh BETWEEN '1950-01-01' AND '2003-12-31'),
    CONSTRAINT CK_GiangVien_HocVi   CHECK (HocVi IN (N'Thạc sĩ', N'Tiến sĩ', N'PGS.TS', N'GS.TS')),
    CONSTRAINT CK_GiangVien_Email   CHECK (Email LIKE '%_@_%._%'),
    CONSTRAINT CK_GiangVien_DienThoai CHECK (DienThoai LIKE '0[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'),
    CONSTRAINT CK_GiangVien_MaKhoa_NN CHECK (MaKhoa = 'NN'),   -- điều kiện phân mảnh ngang
    CONSTRAINT FK_GiangVien_Khoa    FOREIGN KEY (MaKhoa) REFERENCES dbo.Khoa (MaKhoa)
);
GO

CREATE TABLE dbo.Lop (
    MaLop        VARCHAR(15)    NOT NULL,   -- vd: 65.CNTT-1
    TenLop       NVARCHAR(100)  NOT NULL,
    NienKhoa     CHAR(9)        NOT NULL,   -- vd: 2023-2027
    MaKhoa       VARCHAR(10)    NOT NULL,
    MaGVCN       VARCHAR(10)    NULL,       -- giảng viên chủ nhiệm
    CONSTRAINT PK_Lop               PRIMARY KEY (MaLop),
    CONSTRAINT UQ_Lop_TenLop        UNIQUE (TenLop),
    CONSTRAINT CK_Lop_NienKhoa      CHECK (NienKhoa LIKE '[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]'),
    CONSTRAINT CK_Lop_MaKhoa_NN CHECK (MaKhoa = 'NN'),   -- điều kiện phân mảnh ngang
    CONSTRAINT FK_Lop_Khoa          FOREIGN KEY (MaKhoa) REFERENCES dbo.Khoa (MaKhoa),
    CONSTRAINT FK_Lop_GiangVien     FOREIGN KEY (MaGVCN) REFERENCES dbo.GiangVien (MaGV)
);
GO

-- Mảnh dọc 1 của SinhVien (thông tin học vụ) + phân mảnh ngang DẪN XUẤT theo Lop:
-- FK tới Lop cục bộ bảo đảm sinh viên chỉ thuộc lớp của khoa này.
CREATE TABLE dbo.SinhVien (
    MaSV         CHAR(8)        NOT NULL,
    HoTen        NVARCHAR(100)  NOT NULL,
    NgaySinh     DATE           NOT NULL,
    GioiTinh     NVARCHAR(3)    NOT NULL,
    MaLop        VARCHAR(15)    NOT NULL,
    TrangThai    NVARCHAR(20)   NOT NULL  CONSTRAINT DF_SinhVien_TrangThai DEFAULT N'Đang học',
    CONSTRAINT PK_SinhVien          PRIMARY KEY (MaSV),
    CONSTRAINT CK_SinhVien_MaSV     CHECK (MaSV NOT LIKE '%[^0-9]%'),
    CONSTRAINT CK_SinhVien_GioiTinh CHECK (GioiTinh IN (N'Nam', N'Nữ')),
    CONSTRAINT CK_SinhVien_NgaySinh CHECK (NgaySinh BETWEEN '1990-01-01' AND '2010-12-31'),
    CONSTRAINT CK_SinhVien_TrangThai CHECK (TrangThai IN (N'Đang học', N'Bảo lưu', N'Thôi học', N'Đã tốt nghiệp')),
    CONSTRAINT FK_SinhVien_Lop      FOREIGN KEY (MaLop) REFERENCES dbo.Lop (MaLop)
);
GO

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
GO

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
GO

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
    CONSTRAINT CK_NhatKy_HanhDong   CHECK (HanhDong IN ('INSERT', 'UPDATE', 'DELETE'))
);
GO


/* =====================================================================
   PHẦN 5. NODE KHOA DU LỊCH – QLSV_DuLich
   Điều kiện phân mảnh: MaKhoa = 'DL'
   ===================================================================== */

USE QLSV_DuLich;
GO
DROP TABLE IF EXISTS dbo.DangKy, dbo.LopHocPhan, dbo.SinhVien,
                     dbo.Lop, dbo.GiangVien, dbo.MonHoc, dbo.HocKy, dbo.Khoa, dbo.NhatKy;
GO

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
    CONSTRAINT CK_Khoa_DienThoai    CHECK (DienThoai LIKE '0[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'),
    CONSTRAINT CK_Khoa_Email        CHECK (Email LIKE '%_@_%._%')
);
GO

CREATE TABLE dbo.HocKy (
    MaHK         VARCHAR(10)    NOT NULL,   -- vd: HK1-2526
    TenHK        NVARCHAR(20)   NOT NULL,
    NamHoc       CHAR(9)        NOT NULL,   -- vd: 2025-2026
    NgayBatDau   DATE           NOT NULL,
    NgayKetThuc  DATE           NOT NULL,
    CONSTRAINT PK_HocKy             PRIMARY KEY (MaHK),
    CONSTRAINT UQ_HocKy_Ten_Nam     UNIQUE (TenHK, NamHoc),
    CONSTRAINT CK_HocKy_TenHK       CHECK (TenHK IN (N'Học kỳ 1', N'Học kỳ 2', N'Học kỳ hè')),
    CONSTRAINT CK_HocKy_NamHoc      CHECK (NamHoc LIKE '[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]'),
    CONSTRAINT CK_HocKy_Ngay        CHECK (NgayKetThuc > NgayBatDau)
);
GO

CREATE TABLE dbo.MonHoc (
    MaMH         VARCHAR(10)    NOT NULL,
    TenMH        NVARCHAR(100)  NOT NULL,
    SoTinChi     TINYINT        NOT NULL,
    LoaiMH       NVARCHAR(20)   NOT NULL  CONSTRAINT DF_MonHoc_LoaiMH DEFAULT N'Bắt buộc',
    MaKhoa       VARCHAR(10)    NULL,       -- khoa phụ trách; NULL = môn chung toàn trường
    CONSTRAINT PK_MonHoc            PRIMARY KEY (MaMH),
    CONSTRAINT UQ_MonHoc_TenMH      UNIQUE (TenMH),
    CONSTRAINT CK_MonHoc_SoTinChi   CHECK (SoTinChi BETWEEN 1 AND 6),
    CONSTRAINT CK_MonHoc_LoaiMH     CHECK (LoaiMH IN (N'Bắt buộc', N'Tự chọn')),
    CONSTRAINT FK_MonHoc_Khoa       FOREIGN KEY (MaKhoa) REFERENCES dbo.Khoa (MaKhoa)
);
GO

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
    CONSTRAINT CK_GiangVien_GioiTinh CHECK (GioiTinh IN (N'Nam', N'Nữ')),
    CONSTRAINT CK_GiangVien_NgaySinh CHECK (NgaySinh BETWEEN '1950-01-01' AND '2003-12-31'),
    CONSTRAINT CK_GiangVien_HocVi   CHECK (HocVi IN (N'Thạc sĩ', N'Tiến sĩ', N'PGS.TS', N'GS.TS')),
    CONSTRAINT CK_GiangVien_Email   CHECK (Email LIKE '%_@_%._%'),
    CONSTRAINT CK_GiangVien_DienThoai CHECK (DienThoai LIKE '0[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'),
    CONSTRAINT CK_GiangVien_MaKhoa_DL CHECK (MaKhoa = 'DL'),   -- điều kiện phân mảnh ngang
    CONSTRAINT FK_GiangVien_Khoa    FOREIGN KEY (MaKhoa) REFERENCES dbo.Khoa (MaKhoa)
);
GO

CREATE TABLE dbo.Lop (
    MaLop        VARCHAR(15)    NOT NULL,   -- vd: 65.CNTT-1
    TenLop       NVARCHAR(100)  NOT NULL,
    NienKhoa     CHAR(9)        NOT NULL,   -- vd: 2023-2027
    MaKhoa       VARCHAR(10)    NOT NULL,
    MaGVCN       VARCHAR(10)    NULL,       -- giảng viên chủ nhiệm
    CONSTRAINT PK_Lop               PRIMARY KEY (MaLop),
    CONSTRAINT UQ_Lop_TenLop        UNIQUE (TenLop),
    CONSTRAINT CK_Lop_NienKhoa      CHECK (NienKhoa LIKE '[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]'),
    CONSTRAINT CK_Lop_MaKhoa_DL CHECK (MaKhoa = 'DL'),   -- điều kiện phân mảnh ngang
    CONSTRAINT FK_Lop_Khoa          FOREIGN KEY (MaKhoa) REFERENCES dbo.Khoa (MaKhoa),
    CONSTRAINT FK_Lop_GiangVien     FOREIGN KEY (MaGVCN) REFERENCES dbo.GiangVien (MaGV)
);
GO

-- Mảnh dọc 1 của SinhVien (thông tin học vụ) + phân mảnh ngang DẪN XUẤT theo Lop:
-- FK tới Lop cục bộ bảo đảm sinh viên chỉ thuộc lớp của khoa này.
CREATE TABLE dbo.SinhVien (
    MaSV         CHAR(8)        NOT NULL,
    HoTen        NVARCHAR(100)  NOT NULL,
    NgaySinh     DATE           NOT NULL,
    GioiTinh     NVARCHAR(3)    NOT NULL,
    MaLop        VARCHAR(15)    NOT NULL,
    TrangThai    NVARCHAR(20)   NOT NULL  CONSTRAINT DF_SinhVien_TrangThai DEFAULT N'Đang học',
    CONSTRAINT PK_SinhVien          PRIMARY KEY (MaSV),
    CONSTRAINT CK_SinhVien_MaSV     CHECK (MaSV NOT LIKE '%[^0-9]%'),
    CONSTRAINT CK_SinhVien_GioiTinh CHECK (GioiTinh IN (N'Nam', N'Nữ')),
    CONSTRAINT CK_SinhVien_NgaySinh CHECK (NgaySinh BETWEEN '1990-01-01' AND '2010-12-31'),
    CONSTRAINT CK_SinhVien_TrangThai CHECK (TrangThai IN (N'Đang học', N'Bảo lưu', N'Thôi học', N'Đã tốt nghiệp')),
    CONSTRAINT FK_SinhVien_Lop      FOREIGN KEY (MaLop) REFERENCES dbo.Lop (MaLop)
);
GO

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
GO

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
GO

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
    CONSTRAINT CK_NhatKy_HanhDong   CHECK (HanhDong IN ('INSERT', 'UPDATE', 'DELETE'))
);
GO


/* =====================================================================
   PHẦN 6. KIỂM TRA – liệt kê bảng ở từng node (truy vấn 3 phần)
   ===================================================================== */

USE master;
GO
SELECT N'QLSV_TapTrung' AS Node, t.name AS TenBang,
       (SELECT COUNT(*) FROM QLSV_TapTrung.sys.check_constraints c WHERE c.parent_object_id = t.object_id) AS SoCHECK,
       (SELECT COUNT(*) FROM QLSV_TapTrung.sys.foreign_keys f WHERE f.parent_object_id = t.object_id)      AS SoFK
FROM QLSV_TapTrung.sys.tables t
UNION ALL
SELECT N'QLSV_TongHop' AS Node, t.name AS TenBang,
       (SELECT COUNT(*) FROM QLSV_TongHop.sys.check_constraints c WHERE c.parent_object_id = t.object_id) AS SoCHECK,
       (SELECT COUNT(*) FROM QLSV_TongHop.sys.foreign_keys f WHERE f.parent_object_id = t.object_id)      AS SoFK
FROM QLSV_TongHop.sys.tables t
UNION ALL
SELECT N'QLSV_CNTT' AS Node, t.name AS TenBang,
       (SELECT COUNT(*) FROM QLSV_CNTT.sys.check_constraints c WHERE c.parent_object_id = t.object_id) AS SoCHECK,
       (SELECT COUNT(*) FROM QLSV_CNTT.sys.foreign_keys f WHERE f.parent_object_id = t.object_id)      AS SoFK
FROM QLSV_CNTT.sys.tables t
UNION ALL
SELECT N'QLSV_NgoaiNgu' AS Node, t.name AS TenBang,
       (SELECT COUNT(*) FROM QLSV_NgoaiNgu.sys.check_constraints c WHERE c.parent_object_id = t.object_id) AS SoCHECK,
       (SELECT COUNT(*) FROM QLSV_NgoaiNgu.sys.foreign_keys f WHERE f.parent_object_id = t.object_id)      AS SoFK
FROM QLSV_NgoaiNgu.sys.tables t
UNION ALL
SELECT N'QLSV_DuLich' AS Node, t.name AS TenBang,
       (SELECT COUNT(*) FROM QLSV_DuLich.sys.check_constraints c WHERE c.parent_object_id = t.object_id) AS SoCHECK,
       (SELECT COUNT(*) FROM QLSV_DuLich.sys.foreign_keys f WHERE f.parent_object_id = t.object_id)      AS SoFK
FROM QLSV_DuLich.sys.tables t
ORDER BY Node, TenBang;
GO
