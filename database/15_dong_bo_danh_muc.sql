/* =====================================================================
   ĐỒ ÁN CSDL PHÂN TÁN – QUẢN LÝ SINH VIÊN NHIỀU KHOA
   File   : 15_dong_bo_danh_muc.sql
   Mục đích: (1) TỰ ĐỒNG BỘ danh mục nhân bản (Khoa, HocKy, MonHoc) từ điều phối xuống 3 node, có HÀNG ĐỢI
                 ghi bù cho node đang mất kết nối;
             (2) thủ tục quản lý danh mục cho ứng dụng (môn học, học kỳ, giảng viên, lớp).
   Chạy sau : 13_dong_bo_kiem_thu.sql, trên instance điều phối (cổng 14330), tài khoản sysadmin.
   Chạy lại nhiều lần được (hàng đợi bị xóa và tạo lại). Phần ví dụ cuối file đều ROLLBACK.

   CƠ CHẾ
   ---------------------------------------------------------------------
   * Mỗi lần thêm hoặc sửa một dòng danh mục ở điều phối, trigger trg_..._XepHangDoi ghi 3 mục vào bảng
     HangDoiDongBo (mỗi node một mục): "node này chưa có thay đổi đó".
     Trigger CHỈ xếp hàng, không gọi sang node: lỗi kết nối bên trong trigger sẽ hủy luôn lệnh sửa ở điều phối.
   * dm_XuLyHangDoi đi qua từng node còn mục chờ và gọi sp_DongBoDanhMuc cho node đó. Thành công: sp_DongBoDanhMuc
     xóa các mục của node. Thất bại (node mất kết nối): mục ở lại hàng đợi, ghi số lần thử và lỗi gần nhất;
     các node khác vẫn được đồng bộ. Khi node trở lại, chạy dm_XuLyHangDoi lần nữa là node đó nhận đủ thay đổi.
   * Các thủ tục dm_LuuMonHoc, dm_LuuHocKy sửa bản chính rồi gọi ngay dm_XuLyHangDoi, nên sửa qua thủ tục
     (ứng dụng dùng cách này) là tự đồng bộ. Sửa thẳng bằng UPDATE thì thay đổi nằm trong hàng đợi cho tới
     lần dm_XuLyHangDoi kế tiếp.
   * Không lan lệnh XÓA (như sp_DongBoDanhMuc): dòng danh mục ở node có thể đang được khóa ngoại tham chiếu.

   ĐỐI TƯỢNG TẠO Ở QLSV_TongHop (tiền tố dm_ để không lẫn vào 14 thủ tục sp_ của 07_procedures.sql)
     bảng      HangDoiDongBo
     trigger   trg_Khoa_XepHangDoi, trg_HocKy_XepHangDoi, trg_MonHoc_XepHangDoi
     thủ tục   dm_XuLyHangDoi     xử lý hàng đợi (tất cả node hoặc một node)
               dm_LuuMonHoc       thêm hoặc sửa môn học ở bản chính, rồi đồng bộ
               dm_LuuHocKy        thêm hoặc sửa học kỳ ở bản chính, rồi đồng bộ
               dm_LuuGiangVien    thêm hoặc sửa giảng viên ở node của khoa
               dm_LuuLop          thêm hoặc sửa lớp ở node của khoa
   Mã lỗi tự đặt: 501xx.
   ===================================================================== */

SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
USE QLSV_TongHop;
GO

/* =====================================================================
   PHẦN 1. HÀNG ĐỢI VÀ TRIGGER XẾP HÀNG
   ===================================================================== */
DROP TABLE IF EXISTS dbo.HangDoiDongBo;
CREATE TABLE dbo.HangDoiDongBo (
    MaHD        INT IDENTITY(1,1) NOT NULL,
    MaKhoa      VARCHAR(10)    NOT NULL,       -- node chưa nhận thay đổi
    Bang        SYSNAME        NOT NULL,       -- Khoa | HocKy | MonHoc
    KhoaChinh   NVARCHAR(50)   NOT NULL,       -- khóa của dòng danh mục đã đổi
    HanhDong    VARCHAR(10)    NOT NULL,
    ThoiGian    DATETIME2(0)   NOT NULL  CONSTRAINT DF_HangDoi_ThoiGian DEFAULT SYSDATETIME(),
    SoLanThu    INT            NOT NULL  CONSTRAINT DF_HangDoi_SoLanThu DEFAULT 0,
    LoiGanNhat  NVARCHAR(400)  NULL,
    CONSTRAINT PK_HangDoiDongBo        PRIMARY KEY (MaHD),
    CONSTRAINT CK_HangDoi_MaKhoa       CHECK (MaKhoa IN ('CNTT', 'NN', 'DL')),
    CONSTRAINT CK_HangDoi_HanhDong     CHECK (HanhDong IN ('INSERT', 'UPDATE'))
);
GO

CREATE OR ALTER TRIGGER dbo.trg_Khoa_XepHangDoi ON dbo.Khoa AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.HangDoiDongBo (MaKhoa, Bang, KhoaChinh, HanhDong)
    SELECT n.k, N'Khoa', i.MaKhoa, CASE WHEN EXISTS (SELECT 1 FROM deleted) THEN 'UPDATE' ELSE 'INSERT' END
    FROM inserted i CROSS JOIN (VALUES ('CNTT'), ('NN'), ('DL')) n(k);
END
GO
CREATE OR ALTER TRIGGER dbo.trg_HocKy_XepHangDoi ON dbo.HocKy AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.HangDoiDongBo (MaKhoa, Bang, KhoaChinh, HanhDong)
    SELECT n.k, N'HocKy', i.MaHK, CASE WHEN EXISTS (SELECT 1 FROM deleted) THEN 'UPDATE' ELSE 'INSERT' END
    FROM inserted i CROSS JOIN (VALUES ('CNTT'), ('NN'), ('DL')) n(k);
END
GO
CREATE OR ALTER TRIGGER dbo.trg_MonHoc_XepHangDoi ON dbo.MonHoc AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.HangDoiDongBo (MaKhoa, Bang, KhoaChinh, HanhDong)
    SELECT n.k, N'MonHoc', i.MaMH, CASE WHEN EXISTS (SELECT 1 FROM deleted) THEN 'UPDATE' ELSE 'INSERT' END
    FROM inserted i CROSS JOIN (VALUES ('CNTT'), ('NN'), ('DL')) n(k);
END
GO


/* =====================================================================
   PHẦN 2. XỬ LÝ HÀNG ĐỢI
   Mỗi node một lần thử riêng: node mất kết nối không cản node khác. @MaKhoa NULL = mọi node còn mục chờ.
   Trả về một dòng cho mỗi node đã thử: số mục chờ, kết quả, lỗi (nếu có).
   Nếu được gọi bên trong một giao dịch đang mở mà một node lỗi, giao dịch đó đã hỏng (XACT_ABORT) nên lỗi được ném lên.
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.dm_XuLyHangDoi
    @MaKhoa VARCHAR(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @kq TABLE (Node VARCHAR(10), SoMucCho INT, KetQua NVARCHAR(30), Loi NVARCHAR(400));
    DECLARE @k VARCHAR(10), @n INT;
    DECLARE c CURSOR LOCAL STATIC FOR
        SELECT MaKhoa, COUNT(*) FROM dbo.HangDoiDongBo WHERE @MaKhoa IS NULL OR MaKhoa = @MaKhoa GROUP BY MaKhoa ORDER BY MaKhoa;
    OPEN c;
    FETCH NEXT FROM c INTO @k, @n;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            EXEC dbo.sp_DongBoDanhMuc @MaKhoa = @k, @ImLang = 1;        -- thành công thì chính nó xóa mục chờ của node
            INSERT @kq VALUES (@k, @n, N'Đã đồng bộ', NULL);
        END TRY
        BEGIN CATCH
            IF XACT_STATE() = -1 THROW;                                 -- đang ở trong giao dịch của người gọi: không tiếp tục được
            UPDATE dbo.HangDoiDongBo SET SoLanThu += 1, LoiGanNhat = LEFT(ERROR_MESSAGE(), 400) WHERE MaKhoa = @k;
            INSERT @kq VALUES (@k, @n, N'Còn chờ (node không trả lời)', LEFT(ERROR_MESSAGE(), 400));
        END CATCH
        FETCH NEXT FROM c INTO @k, @n;
    END
    CLOSE c;
    DEALLOCATE c;

    SELECT Node, SoMucCho, KetQua, Loi FROM @kq ORDER BY Node;
END
GO


/* =====================================================================
   PHẦN 3. QUẢN LÝ DANH MỤC
   Danh mục nhân bản (môn học, học kỳ): ghi bản chính ở điều phối rồi đồng bộ ngay.
   Danh mục phân mảnh (giảng viên, lớp): ghi thẳng vào node của khoa.
   Có mã thì sửa, chưa có thì thêm.
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.dm_LuuMonHoc
    @MaMH      VARCHAR(10),
    @TenMH     NVARCHAR(100),
    @SoTinChi  TINYINT,
    @LoaiMH    NVARCHAR(20) = N'Bắt buộc',
    @MaKhoa    VARCHAR(10)  = NULL              -- NULL = môn chung toàn trường
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF NULLIF(LTRIM(@MaMH), '') IS NULL OR NULLIF(LTRIM(@TenMH), N'') IS NULL
        THROW 50101, N'Phải nhập mã môn và tên môn.', 1;

    IF EXISTS (SELECT 1 FROM dbo.MonHoc WHERE MaMH = @MaMH)
        UPDATE dbo.MonHoc SET TenMH = @TenMH, SoTinChi = @SoTinChi, LoaiMH = @LoaiMH, MaKhoa = @MaKhoa WHERE MaMH = @MaMH;
    ELSE
        INSERT dbo.MonHoc (MaMH, TenMH, SoTinChi, LoaiMH, MaKhoa) VALUES (@MaMH, @TenMH, @SoTinChi, @LoaiMH, @MaKhoa);

    EXEC dbo.dm_XuLyHangDoi;                    -- trigger vừa xếp 3 mục: đẩy ngay xuống các node đang hoạt động
END
GO

CREATE OR ALTER PROCEDURE dbo.dm_LuuHocKy
    @MaHK         VARCHAR(10),
    @TenHK        NVARCHAR(20),
    @NamHoc       CHAR(9),
    @NgayBatDau   DATE,
    @NgayKetThuc  DATE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF NULLIF(LTRIM(@MaHK), '') IS NULL
        THROW 50102, N'Phải nhập mã học kỳ.', 1;

    IF EXISTS (SELECT 1 FROM dbo.HocKy WHERE MaHK = @MaHK)
        UPDATE dbo.HocKy SET TenHK = @TenHK, NamHoc = @NamHoc, NgayBatDau = @NgayBatDau, NgayKetThuc = @NgayKetThuc WHERE MaHK = @MaHK;
    ELSE
        INSERT dbo.HocKy (MaHK, TenHK, NamHoc, NgayBatDau, NgayKetThuc) VALUES (@MaHK, @TenHK, @NamHoc, @NgayBatDau, @NgayKetThuc);

    EXEC dbo.dm_XuLyHangDoi;
END
GO

/* Giảng viên nằm ở node của khoa (phân mảnh ngang theo MaKhoa). Không đổi khoa của giảng viên đã có. */
CREATE OR ALTER PROCEDURE dbo.dm_LuuGiangVien
    @MaGV       VARCHAR(10),
    @HoTen      NVARCHAR(100),
    @GioiTinh   NVARCHAR(3),
    @NgaySinh   DATE,
    @HocVi      NVARCHAR(20),
    @Email      VARCHAR(100),
    @MaKhoa     VARCHAR(10),
    @DienThoai  VARCHAR(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @db SYSNAME = dbo.DbCuaKhoa(@MaKhoa), @sql NVARCHAR(MAX);
    IF @db IS NULL
        THROW 50103, N'MaKhoa phải là CNTT, NN hoặc DL.', 1;
    IF NULLIF(LTRIM(@MaGV), '') IS NULL OR NULLIF(LTRIM(@HoTen), N'') IS NULL
        THROW 50104, N'Phải nhập mã và họ tên giảng viên.', 1;

    SET @sql = N'
    IF EXISTS (SELECT 1 FROM ' + @db + N'.dbo.GiangVien WHERE MaGV = @MaGV)
        UPDATE ' + @db + N'.dbo.GiangVien SET HoTen = @HoTen, GioiTinh = @GioiTinh, NgaySinh = @NgaySinh, HocVi = @HocVi,
               Email = @Email, DienThoai = @DienThoai WHERE MaGV = @MaGV;
    ELSE
        INSERT ' + @db + N'.dbo.GiangVien (MaGV, HoTen, GioiTinh, NgaySinh, HocVi, Email, DienThoai, MaKhoa)
        VALUES (@MaGV, @HoTen, @GioiTinh, @NgaySinh, @HocVi, @Email, @DienThoai, @MaKhoa);
    SELECT MaGV, HoTen, GioiTinh, NgaySinh, HocVi, Email, DienThoai, MaKhoa FROM ' + @db + N'.dbo.GiangVien WHERE MaGV = @MaGV;';
    EXEC sp_executesql @sql,
         N'@MaGV VARCHAR(10), @HoTen NVARCHAR(100), @GioiTinh NVARCHAR(3), @NgaySinh DATE, @HocVi NVARCHAR(20),
           @Email VARCHAR(100), @DienThoai VARCHAR(10), @MaKhoa VARCHAR(10)',
         @MaGV, @HoTen, @GioiTinh, @NgaySinh, @HocVi, @Email, @DienThoai, @MaKhoa;
END
GO

/* Lớp nằm ở node của khoa. Giảng viên chủ nhiệm (nếu có) phải thuộc cùng khoa: khóa ngoại cục bộ ở node kiểm tra. */
CREATE OR ALTER PROCEDURE dbo.dm_LuuLop
    @MaLop     VARCHAR(15),
    @TenLop    NVARCHAR(100),
    @NienKhoa  CHAR(9),
    @MaKhoa    VARCHAR(10),
    @MaGVCN    VARCHAR(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @db SYSNAME = dbo.DbCuaKhoa(@MaKhoa), @sql NVARCHAR(MAX);
    IF @db IS NULL
        THROW 50105, N'MaKhoa phải là CNTT, NN hoặc DL.', 1;
    IF NULLIF(LTRIM(@MaLop), '') IS NULL OR NULLIF(LTRIM(@TenLop), N'') IS NULL
        THROW 50106, N'Phải nhập mã lớp và tên lớp.', 1;

    SET @sql = N'
    IF EXISTS (SELECT 1 FROM ' + @db + N'.dbo.Lop WHERE MaLop = @MaLop)
        UPDATE ' + @db + N'.dbo.Lop SET TenLop = @TenLop, NienKhoa = @NienKhoa, MaGVCN = @MaGVCN WHERE MaLop = @MaLop;
    ELSE
        INSERT ' + @db + N'.dbo.Lop (MaLop, TenLop, NienKhoa, MaKhoa, MaGVCN) VALUES (@MaLop, @TenLop, @NienKhoa, @MaKhoa, @MaGVCN);
    SELECT MaLop, TenLop, NienKhoa, MaKhoa, MaGVCN FROM ' + @db + N'.dbo.Lop WHERE MaLop = @MaLop;';
    EXEC sp_executesql @sql,
         N'@MaLop VARCHAR(15), @TenLop NVARCHAR(100), @NienKhoa CHAR(9), @MaKhoa VARCHAR(10), @MaGVCN VARCHAR(10)',
         @MaLop, @TenLop, @NienKhoa, @MaKhoa, @MaGVCN;
END
GO


/* =====================================================================
   PHẦN 4. VÍ DỤ – mọi thay đổi đều ROLLBACK (dbo.ViTriMonHoc tạo ở 13_dong_bo_kiem_thu.sql)
   ===================================================================== */

-- 1. Sửa qua thủ tục: bản chính và cả 3 bản sao đổi ngay, hàng đợi rỗng.
BEGIN TRAN;
    EXEC dbo.dm_LuuMonHoc @MaMH = 'CNTT101', @TenMH = N'Nhập môn lập trình (sửa qua thủ tục)', @SoTinChi = 3, @MaKhoa = 'CNTT';
    SELECT N'Sau dm_LuuMonHoc' AS Buoc, * FROM dbo.ViTriMonHoc('CNTT101');
    SELECT N'Sau dm_LuuMonHoc: số mục còn chờ' AS KiemTra, COUNT(*) AS SoMuc FROM dbo.HangDoiDongBo;      -- = 0
ROLLBACK TRAN;
GO

-- 2. Sửa thẳng bằng UPDATE: trigger xếp 3 mục, bản sao chưa đổi; dm_XuLyHangDoi đẩy xuống, hàng đợi rỗng.
BEGIN TRAN;
    UPDATE dbo.MonHoc SET TenMH = TenMH + N' (sửa thẳng)' WHERE MaMH = 'NN101';
    SELECT N'Sau UPDATE thẳng: hàng đợi' AS Buoc, MaKhoa AS Node, Bang, KhoaChinh, HanhDong FROM dbo.HangDoiDongBo ORDER BY MaKhoa;
    SELECT N'Sau UPDATE thẳng' AS Buoc, * FROM dbo.ViTriMonHoc('NN101');
    EXEC dbo.dm_XuLyHangDoi;
    SELECT N'Sau dm_XuLyHangDoi' AS Buoc, * FROM dbo.ViTriMonHoc('NN101');
    SELECT N'Sau dm_XuLyHangDoi: số mục còn chờ' AS KiemTra, COUNT(*) AS SoMuc FROM dbo.HangDoiDongBo;    -- = 0
ROLLBACK TRAN;
GO

-- 3. Thêm môn mới và học kỳ mới qua thủ tục: có ngay ở cả 3 node.
BEGIN TRAN;
    EXEC dbo.dm_LuuMonHoc @MaMH = 'CHUNG05', @TenMH = N'Kỹ năng mềm', @SoTinChi = 2, @LoaiMH = N'Tự chọn';
    EXEC dbo.dm_LuuHocKy  @MaHK = 'HK2-2627', @TenHK = N'Học kỳ 2', @NamHoc = '2026-2027', @NgayBatDau = '2027-02-08', @NgayKetThuc = '2027-06-30';
    SELECT N'Môn CHUNG05' AS KiemTra, * FROM dbo.ViTriMonHoc('CHUNG05');
    SELECT N'Học kỳ HK2-2627 có ở số node' AS KiemTra,
           (SELECT COUNT(*) FROM QLSV_CNTT.dbo.HocKy WHERE MaHK = 'HK2-2627')
         + (SELECT COUNT(*) FROM QLSV_NgoaiNgu.dbo.HocKy WHERE MaHK = 'HK2-2627')
         + (SELECT COUNT(*) FROM QLSV_DuLich.dbo.HocKy WHERE MaHK = 'HK2-2627') AS SoNode;                -- = 3
ROLLBACK TRAN;
GO

-- 4. Giảng viên và lớp: ghi vào node của khoa; mã khoa sai thì bị từ chối.
BEGIN TRAN;
    EXEC dbo.dm_LuuGiangVien @MaGV = 'GVDL09', @HoTen = N'Trần Thị Thử', @GioiTinh = N'Nữ', @NgaySinh = '1990-05-05',
         @HocVi = N'Thạc sĩ', @Email = 'gvdl09@gv.qlsv.edu.vn', @MaKhoa = 'DL';
    EXEC dbo.dm_LuuLop @MaLop = '67.DL-1', @TenLop = N'DL K67-1', @NienKhoa = '2025-2029', @MaKhoa = 'DL', @MaGVCN = 'GVDL09';
    SELECT N'Chỉ node Du lịch có giảng viên mới' AS KiemTra,
           (SELECT COUNT(*) FROM QLSV_CNTT.dbo.GiangVien WHERE MaGV = 'GVDL09')   AS CNTT,
           (SELECT COUNT(*) FROM QLSV_DuLich.dbo.GiangVien WHERE MaGV = 'GVDL09') AS DuLich;              -- 0 | 1
ROLLBACK TRAN;
GO
BEGIN TRY
    EXEC dbo.dm_LuuLop @MaLop = '67.XX-1', @TenLop = N'Lớp khoa lạ', @NienKhoa = '2025-2029', @MaKhoa = 'XX';
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS MaLoi, ERROR_MESSAGE() AS ThongBao;                                        -- 50105
END CATCH
GO

-- Sau các ví dụ: hàng đợi phải rỗng và bản sao khớp bản chính
SELECT N'Hàng đợi sau ví dụ' AS KiemTra, COUNT(*) AS SoMuc FROM dbo.HangDoiDongBo;
GO