/* =====================================================================
   ĐỒ ÁN CSDL PHÂN TÁN – QUẢN LÝ SINH VIÊN NHIỀU KHOA
   File   : 02a_create_node.sql
   Mục đích: Tạo database và bảng cho MỘT node khoa (xóa bản cũ nếu có). Ba node (CNTT, Ngoại ngữ, Du lịch)
             có cấu trúc giống hệt nhau, chỉ khác tên database và điều kiện phân mảnh ngang MaKhoa = ...,
             nên dùng chung file này.
   Chạy trên TỪNG instance node (cổng 14331, 14332, 14333), với 2 biến:

       $(NODE_DB)   tên database của node   QLSV_CNTT | QLSV_NgoaiNgu | QLSV_DuLich
       $(MA_KHOA)   mã khoa của node        CNTT      | NN            | DL

   scripts/trien_khai.py tự điền 2 biến này. Chạy tay bằng SSMS: bật SQLCMD Mode rồi thêm ở đầu file
       :setvar NODE_DB QLSV_CNTT
       :setvar MA_KHOA CNTT

   Node giữ: bản sao danh mục (Khoa, HocKy, MonHoc), các mảnh ngang (GiangVien, Lop, SinhVien học vụ,
   LopHocPhan, DangKy) và bảng NhatKy riêng. Xem bảng phân bố ở đầu 02_create_tables.sql.
   ===================================================================== */

USE master;
GO
IF DB_ID(N'$(NODE_DB)') IS NOT NULL
BEGIN
    ALTER DATABASE $(NODE_DB) SET SINGLE_USER WITH ROLLBACK IMMEDIATE;      -- ngắt kết nối đang mở rồi xóa
    DROP DATABASE $(NODE_DB);
END
GO
CREATE DATABASE $(NODE_DB) COLLATE Vietnamese_CI_AS;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;   -- bắt buộc cho cột tính toán PERSISTED
GO

USE $(NODE_DB);
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
    CONSTRAINT CK_GiangVien_MaKhoa_$(MA_KHOA) CHECK (MaKhoa = '$(MA_KHOA)'),   -- điều kiện phân mảnh ngang
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
    CONSTRAINT CK_Lop_MaKhoa_$(MA_KHOA) CHECK (MaKhoa = '$(MA_KHOA)'),   -- điều kiện phân mảnh ngang
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

-- Kiểm tra: 9 bảng của node, kèm số ràng buộc CHECK và khóa ngoại
SELECT DB_NAME() AS Node, t.name AS TenBang,
       (SELECT COUNT(*) FROM sys.check_constraints c WHERE c.parent_object_id = t.object_id) AS SoCHECK,
       (SELECT COUNT(*) FROM sys.foreign_keys f      WHERE f.parent_object_id = t.object_id) AS SoFK
FROM sys.tables t
ORDER BY t.name;
GO
