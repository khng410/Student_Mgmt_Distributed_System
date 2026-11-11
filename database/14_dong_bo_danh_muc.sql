/* =====================================================================
   ĐỒ ÁN CSDL PHÂN TÁN – QUẢN LÝ SINH VIÊN NHIỀU KHOA
   File   : 14_dong_bo_danh_muc.sql
   Mục đích: ĐỒNG BỘ VÀ KIỂM THỬ ĐỒNG BỘ
             (1) tự đồng bộ danh mục nhân bản (Khoa, HocKy, MonHoc) từ điều phối xuống 3 node, có HÀNG ĐỢI
                 ghi bù cho node đang mất kết nối;
             (2) thủ tục quản lý danh mục cho ứng dụng (môn học, học kỳ, giảng viên, lớp);
             (3) kiểm thử: đổi dữ liệu ở MỘT nơi rồi đọc kết quả ở các nơi còn lại (điều phối + 3 node).
   Chạy sau : 12_linked_server.sql, trên instance điều phối (cổng 14330), tài khoản sysadmin.
   Chạy lại nhiều lần được (hàng đợi bị xóa và tạo lại). Mọi kịch bản kiểm thử, ví dụ đều ROLLBACK hoặc tự dọn.

   NỘI DUNG
     PHẦN 1-3  hàng đợi, trigger xếp hàng, dm_XuLyHangDoi, thủ tục quản lý danh mục
     PHẦN 4    hàm xem nhanh một sinh viên, một môn đang nằm ở đâu (ViTriSinhVien, ViTriMonHoc)
     PHẦN 5    7 kịch bản kiểm thử đồng bộ: thêm, sửa, chuyển khoa, xóa sinh viên; sửa, thêm danh mục; sửa tại node
     PHẦN 6    ví dụ hàng đợi và quản lý danh mục
     PHẦN 7    kết luận: bản sao khớp bản chính, hai mảnh dọc khớp nhau, hàng đợi rỗng

   CƠ CHẾ
   ---------------------------------------------------------------------
   * Bảng PHÂN MẢNH (SinhVien, GiangVien, Lop, LopHocPhan, DangKy): mỗi dòng chỉ có MỘT bản, nên không có gì để
     đồng bộ giữa các bản. Riêng SinhVien tách dọc thành 2 mảnh (học vụ ở node khoa, hồ sơ ở điều phối) nên
     sp_ThemSinhVien, sp_CapNhatSinhVien, sp_XoaSinhVien, sp_ChuyenKhoa ghi cả hai mảnh trong MỘT giao dịch phân tán.
   * Bảng NHÂN BẢN (Khoa, HocKy, MonHoc): bản chính ở điều phối, bản sao ở 3 node:
     - Mỗi lần thêm hoặc sửa một dòng danh mục ở điều phối, trigger trg_..._XepHangDoi ghi 3 mục vào bảng
       HangDoiDongBo (mỗi node một mục): "node này chưa có thay đổi đó".
       Trigger CHỈ xếp hàng, không gọi sang node: lỗi kết nối bên trong trigger sẽ hủy luôn lệnh sửa ở điều phối.
     - dm_XuLyHangDoi đi qua từng node còn mục chờ và gọi sp_DongBoDanhMuc cho node đó. Thành công: sp_DongBoDanhMuc
       xóa các mục của node. Thất bại (node mất kết nối): mục ở lại hàng đợi, ghi số lần thử và lỗi gần nhất;
       các node khác vẫn được đồng bộ. Khi node trở lại, chạy dm_XuLyHangDoi lần nữa là node đó nhận đủ thay đổi.
     - Các thủ tục dm_LuuMonHoc, dm_LuuHocKy sửa bản chính rồi gọi ngay dm_XuLyHangDoi, nên sửa qua thủ tục
       (ứng dụng dùng cách này) là tự đồng bộ. Sửa thẳng bằng UPDATE thì thay đổi nằm trong hàng đợi cho tới
       lần dm_XuLyHangDoi kế tiếp.
     - Không lan lệnh XÓA (như sp_DongBoDanhMuc): dòng danh mục ở node có thể đang được khóa ngoại tham chiếu.

   ĐỐI TƯỢNG TẠO Ở QLSV_TongHop (tiền tố dm_ để không lẫn vào 14 thủ tục sp_ của 07_procedures.sql)
     bảng      HangDoiDongBo
     trigger   trg_Khoa_XepHangDoi, trg_HocKy_XepHangDoi, trg_MonHoc_XepHangDoi
     thủ tục   dm_XuLyHangDoi     xử lý hàng đợi (tất cả node hoặc một node)
               dm_LuuMonHoc       thêm hoặc sửa môn học ở bản chính, rồi đồng bộ
               dm_LuuHocKy        thêm hoặc sửa học kỳ ở bản chính, rồi đồng bộ
               dm_LuuGiangVien    thêm hoặc sửa giảng viên ở node của khoa
               dm_LuuLop          thêm hoặc sửa lớp ở node của khoa
     hàm       ViTriSinhVien, ViTriMonHoc (tên không bắt đầu bằng fn_ để không lẫn vào 8 hàm của 08)
   Mã lỗi tự đặt: 501xx.
   ===================================================================== */

SET NOCOUNT ON;
SET XACT_ABORT ON;      -- bắt buộc khi sửa bảng ở node khác instance trong BEGIN TRAN
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
   Có mã thì sửa, chưa có thì thêm. @ThemMoi = 1 (giao diện, khi chọn Thêm mới): mã đã có thì báo lỗi 50107.
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.dm_LuuMonHoc
    @MaMH      VARCHAR(10),
    @TenMH     NVARCHAR(100),
    @SoTinChi  TINYINT,
    @LoaiMH    NVARCHAR(20) = N'Bắt buộc',
    @MaKhoa    VARCHAR(10)  = NULL,             -- NULL = môn chung toàn trường
    @ThemMoi   BIT          = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF NULLIF(LTRIM(@MaMH), '') IS NULL OR NULLIF(LTRIM(@TenMH), N'') IS NULL
        THROW 50101, N'Phải nhập mã môn và tên môn.', 1;
    IF @ThemMoi = 1 AND EXISTS (SELECT 1 FROM dbo.MonHoc WHERE MaMH = @MaMH)
        THROW 50107, N'Mã môn học đã tồn tại. Muốn sửa thì chọn dòng đó trong danh sách.', 1;

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
    @NgayKetThuc  DATE,
    @ThemMoi      BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF NULLIF(LTRIM(@MaHK), '') IS NULL
        THROW 50102, N'Phải nhập mã học kỳ.', 1;
    IF @ThemMoi = 1 AND EXISTS (SELECT 1 FROM dbo.HocKy WHERE MaHK = @MaHK)
        THROW 50107, N'Mã học kỳ đã tồn tại. Muốn sửa thì chọn dòng đó trong danh sách.', 1;

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
    @DienThoai  VARCHAR(10) = NULL,
    @ThemMoi    BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @db SYSNAME = dbo.DbCuaKhoa(@MaKhoa), @sql NVARCHAR(MAX);
    IF @db IS NULL
        THROW 50103, N'MaKhoa phải là CNTT, NN hoặc DL.', 1;
    IF NULLIF(LTRIM(@MaGV), '') IS NULL OR NULLIF(LTRIM(@HoTen), N'') IS NULL
        THROW 50104, N'Phải nhập mã và họ tên giảng viên.', 1;

    -- Mã là duy nhất trên CẢ 3 node: @o = khoa đang giữ mã này (NULL = chưa có).
    -- ponytail: cần cả 3 node bật; hỏi lần lượt từng node như TimKhoaCuaLop nếu muốn lưu được khi node khác tắt
    DECLARE @o VARCHAR(10) = (SELECT k FROM (SELECT MaGV, 'CNTT' AS k FROM QLSV_CNTT.dbo.GiangVien
                                             UNION ALL SELECT MaGV, 'NN' FROM QLSV_NgoaiNgu.dbo.GiangVien
                                             UNION ALL SELECT MaGV, 'DL' FROM QLSV_DuLich.dbo.GiangVien) x WHERE MaGV = @MaGV);
    IF @o IS NOT NULL AND (@ThemMoi = 1 OR @o <> @MaKhoa)
        THROW 50107, N'Mã giảng viên đã tồn tại. Muốn sửa thì chọn dòng đó trong danh sách.', 1;

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
    @MaGVCN    VARCHAR(10) = NULL,
    @ThemMoi   BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @db SYSNAME = dbo.DbCuaKhoa(@MaKhoa), @sql NVARCHAR(MAX);
    IF @db IS NULL
        THROW 50105, N'MaKhoa phải là CNTT, NN hoặc DL.', 1;
    IF NULLIF(LTRIM(@MaLop), '') IS NULL OR NULLIF(LTRIM(@TenLop), N'') IS NULL
        THROW 50106, N'Phải nhập mã lớp và tên lớp.', 1;

    -- Mã là duy nhất trên cả 3 node (như dm_LuuGiangVien)
    DECLARE @o VARCHAR(10) = (SELECT k FROM (SELECT MaLop, 'CNTT' AS k FROM QLSV_CNTT.dbo.Lop
                                             UNION ALL SELECT MaLop, 'NN' FROM QLSV_NgoaiNgu.dbo.Lop
                                             UNION ALL SELECT MaLop, 'DL' FROM QLSV_DuLich.dbo.Lop) x WHERE MaLop = @MaLop);
    IF @o IS NOT NULL AND (@ThemMoi = 1 OR @o <> @MaKhoa)
        THROW 50107, N'Mã lớp đã tồn tại. Muốn sửa thì chọn dòng đó trong danh sách.', 1;

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
   PHẦN 4. HÀM XEM NHANH: dữ liệu đang nằm ở đâu
   ===================================================================== */
/* Một sinh viên đang nằm ở đâu: hồ sơ ở điều phối, học vụ ở node nào (1 = có, 0 = không). */
CREATE OR ALTER FUNCTION dbo.ViTriSinhVien (@MaSV CHAR(8))
RETURNS TABLE
AS
RETURN
(
    SELECT @MaSV AS MaSV,
           (SELECT COUNT(*) FROM dbo.SinhVien_HoSo            WHERE MaSV = @MaSV) AS HoSo_DieuPhoi,
           (SELECT COUNT(*) FROM QLSV_CNTT.dbo.SinhVien       WHERE MaSV = @MaSV) AS HocVu_CNTT,
           (SELECT COUNT(*) FROM QLSV_NgoaiNgu.dbo.SinhVien   WHERE MaSV = @MaSV) AS HocVu_NN,
           (SELECT COUNT(*) FROM QLSV_DuLich.dbo.SinhVien     WHERE MaSV = @MaSV) AS HocVu_DL,
           (SELECT HoTen FROM dbo.vw_SinhVien_ToanCuc         WHERE MaSV = @MaSV) AS HoTen_QuaViewToanCuc,
           (SELECT DiaChi FROM dbo.SinhVien_HoSo              WHERE MaSV = @MaSV) AS DiaChi_HoSo
);
GO

/* Một môn học ở 4 nơi: bản chính và 3 bản sao. */
CREATE OR ALTER FUNCTION dbo.ViTriMonHoc (@MaMH VARCHAR(10))
RETURNS TABLE
AS
RETURN
(
    SELECT n.Noi, n.TenMH
    FROM (SELECT N'1. Điều phối (bản chính)' AS Noi, (SELECT TenMH FROM dbo.MonHoc WHERE MaMH = @MaMH) AS TenMH
          UNION ALL SELECT N'2. Node CNTT (bản sao)',     (SELECT TenMH FROM QLSV_CNTT.dbo.MonHoc     WHERE MaMH = @MaMH)
          UNION ALL SELECT N'3. Node Ngoại ngữ (bản sao)', (SELECT TenMH FROM QLSV_NgoaiNgu.dbo.MonHoc WHERE MaMH = @MaMH)
          UNION ALL SELECT N'4. Node Du lịch (bản sao)',   (SELECT TenMH FROM QLSV_DuLich.dbo.MonHoc   WHERE MaMH = @MaMH)) n
);
GO


/* #####################################################################
   PHẦN 5. KIỂM THỬ ĐỒNG BỘ – đổi ở một nơi, kiểm tra ở cả 4 nơi
   Mỗi kịch bản in 2 bảng: TRƯỚC và SAU, cột là các nơi lưu dữ liệu.
   ##################################################################### */

/* =====================================================================
   KỊCH BẢN 1. THÊM sinh viên ở điều phối -> kiểm tra ở cả 4 nơi
   Kỳ vọng: hồ sơ ở điều phối = 1, học vụ ở node CNTT = 1, hai node còn lại = 0, view toàn cục thấy ngay.
   ===================================================================== */
BEGIN TRAN;
    SELECT N'TRƯỚC thêm' AS Buoc, * FROM dbo.ViTriSinhVien('24019001');
    EXEC dbo.sp_ThemSinhVien @MaSV = '24019001', @HoTen = N'Kiểm Thử Đồng Bộ', @NgaySinh = '2006-02-02',
         @GioiTinh = N'Nữ', @MaLop = '66.CNTT-1', @CCCD = '001306009001', @Email = '24019001@sv.qlsv.edu.vn',
         @DiaChi = N'Hà Nội';
    SELECT N'SAU thêm' AS Buoc, * FROM dbo.ViTriSinhVien('24019001');
ROLLBACK TRAN;
SELECT N'SAU ROLLBACK (về như trước)' AS Buoc, * FROM dbo.ViTriSinhVien('24019001');
GO

/* =====================================================================
   KỊCH BẢN 2. SỬA sinh viên (họ tên ở node, địa chỉ ở điều phối) bằng một thủ tục
   Kỳ vọng: HoTen mới thấy qua view toàn cục (đọc từ node CNTT) và DiaChi mới ở hồ sơ điều phối, cùng lúc.
   ===================================================================== */
BEGIN TRAN;
    SELECT N'TRƯỚC sửa' AS Buoc, * FROM dbo.ViTriSinhVien('24010001');
    EXEC dbo.sp_CapNhatSinhVien @MaSV = '24010001', @HoTen = N'Tên Đã Sửa', @DiaChi = N'Địa chỉ đã sửa';
    SELECT N'SAU sửa' AS Buoc, * FROM dbo.ViTriSinhVien('24010001');
ROLLBACK TRAN;
SELECT N'SAU ROLLBACK' AS Buoc, * FROM dbo.ViTriSinhVien('24010001');
GO

/* =====================================================================
   KỊCH BẢN 3. CHUYỂN KHOA CNTT -> Ngoại ngữ (sinh viên chưa có đăng ký học phần)
   Kỳ vọng: học vụ rời node CNTT sang node Ngoại ngữ; hồ sơ ở điều phối không đổi (cùng MaSV).
   ===================================================================== */
BEGIN TRAN;
    SELECT N'TRƯỚC chuyển' AS Buoc, * FROM dbo.ViTriSinhVien('24010016');
    EXEC dbo.sp_ChuyenKhoa @MaSV = '24010016', @MaLopMoi = '66.NN-1';
    SELECT N'SAU chuyển' AS Buoc, * FROM dbo.ViTriSinhVien('24010016');
ROLLBACK TRAN;
SELECT N'SAU ROLLBACK' AS Buoc, * FROM dbo.ViTriSinhVien('24010016');
GO

/* =====================================================================
   KỊCH BẢN 4. XÓA sinh viên chưa có đăng ký: biến mất khỏi CẢ HAI mảnh
   ===================================================================== */
BEGIN TRAN;
    SELECT N'TRƯỚC xóa' AS Buoc, * FROM dbo.ViTriSinhVien('24010016');
    EXEC dbo.sp_XoaSinhVien @MaSV = '24010016';
    SELECT N'SAU xóa' AS Buoc, * FROM dbo.ViTriSinhVien('24010016');
ROLLBACK TRAN;
SELECT N'SAU ROLLBACK' AS Buoc, * FROM dbo.ViTriSinhVien('24010016');
GO

/* =====================================================================
   KỊCH BẢN 5. CẬP NHẬT DANH MỤC TẠI TRUNG TÂM (bảng nhân bản MonHoc)
   Kỳ vọng: sau UPDATE ở điều phối, 3 bản sao CHƯA đổi (nhân bản không tự lan);
            sau sp_DongBoDanhMuc, cả 4 nơi giống nhau.
   ===================================================================== */
BEGIN TRAN;
    SELECT N'TRƯỚC khi sửa' AS Buoc, * FROM dbo.ViTriMonHoc('CNTT101');
    UPDATE dbo.MonHoc SET TenMH = TenMH + N' (đã đổi tên)' WHERE MaMH = 'CNTT101';
    SELECT N'SAU UPDATE ở điều phối, CHƯA đồng bộ' AS Buoc, * FROM dbo.ViTriMonHoc('CNTT101');
    EXEC dbo.sp_DongBoDanhMuc;
    SELECT N'SAU sp_DongBoDanhMuc' AS Buoc, * FROM dbo.ViTriMonHoc('CNTT101');
ROLLBACK TRAN;
SELECT N'SAU ROLLBACK (4 nơi về như cũ)' AS Buoc, * FROM dbo.ViTriMonHoc('CNTT101');
GO

/* =====================================================================
   KỊCH BẢN 6. THÊM môn MỚI ở điều phối -> thử mở lớp -> đồng bộ -> mở lớp lại
   Trước khi đồng bộ, node CNTT chưa có môn: khóa ngoại cục bộ chặn việc mở lớp.
   Sau sp_DongBoDanhMuc, node có môn và mở được lớp.
   Kịch bản này không dùng BEGIN TRAN vì sp_MoLopHocPhan và sp_DongBoDanhMuc là thao tác thật; nó tự dọn ở cuối.
   ===================================================================== */
BEGIN TRY
    INSERT dbo.MonHoc (MaMH, TenMH, SoTinChi, LoaiMH, MaKhoa) VALUES ('CNTT998', N'Môn mới để kiểm thử', 3, N'Tự chọn', 'CNTT');
    SELECT N'SAU INSERT ở điều phối, CHƯA đồng bộ' AS Buoc, * FROM dbo.ViTriMonHoc('CNTT998');

    BEGIN TRY
        EXEC dbo.sp_MoLopHocPhan @MaMH = 'CNTT998', @MaHK = 'HK1-2627', @MaGV = 'GVCNTT01', @Nhom = 1;
        SELECT N'LỖI KIỂM THỬ: mở được lớp khi node chưa có môn' AS KetQua;
    END TRY
    BEGIN CATCH
        SELECT N'Mở lớp TRƯỚC đồng bộ: bị chặn (đúng)' AS Buoc, ERROR_NUMBER() AS MaLoi, ERROR_MESSAGE() AS ThongBao;
    END CATCH

    EXEC dbo.sp_DongBoDanhMuc @MaKhoa = 'CNTT';
    SELECT N'SAU sp_DongBoDanhMuc (chỉ khoa CNTT)' AS Buoc, * FROM dbo.ViTriMonHoc('CNTT998');

    EXEC dbo.sp_MoLopHocPhan @MaMH = 'CNTT998', @MaHK = 'HK1-2627', @MaGV = 'GVCNTT01', @Nhom = 1;     -- mở lớp SAU đồng bộ
    SELECT N'Mở lớp SAU đồng bộ: lớp có ở node CNTT' AS Buoc, MaLHP, MaMH, MaGV
    FROM QLSV_CNTT.dbo.LopHocPhan WHERE MaMH = 'CNTT998';
END TRY
BEGIN CATCH
    SELECT N'LỖI KIỂM THỬ' AS KetQua, ERROR_NUMBER() AS MaLoi, ERROR_MESSAGE() AS ThongBao;
END CATCH

-- Dọn dữ liệu kiểm thử (node trước, điều phối sau; sp_DongBoDanhMuc không xóa dòng nên phải xóa bản sao tay)
DELETE QLSV_CNTT.dbo.LopHocPhan WHERE MaMH = 'CNTT998';
DELETE QLSV_CNTT.dbo.MonHoc     WHERE MaMH = 'CNTT998';
DELETE dbo.MonHoc               WHERE MaMH = 'CNTT998';
DELETE dbo.HangDoiDongBo        WHERE KhoaChinh = 'CNTT998';   -- trigger đã xếp hàng cho 2 node chưa đồng bộ
SELECT N'Đã dọn: môn CNTT998 còn lại ở 4 nơi' AS KiemTra, COUNT(*) AS SoDong FROM (
    SELECT MaMH FROM dbo.MonHoc UNION ALL SELECT MaMH FROM QLSV_CNTT.dbo.MonHoc
    UNION ALL SELECT MaMH FROM QLSV_NgoaiNgu.dbo.MonHoc UNION ALL SELECT MaMH FROM QLSV_DuLich.dbo.MonHoc) x
WHERE MaMH = 'CNTT998';     -- = 0
GO

/* =====================================================================
   KỊCH BẢN 7. SỬA TẠI MỘT NÚT (node CNTT) -> kiểm tra ở các nút còn lại
   7a. Sửa dữ liệu phân mảnh ở node (điểm thi): chỉ node đó đổi, node khác không đổi.
   ===================================================================== */
BEGIN TRAN;
    DECLARE @truoc TABLE (Noi NVARCHAR(30), Tong DECIMAL(12,2));
    INSERT @truoc
    SELECT N'CNTT', SUM(DiemThi) FROM QLSV_CNTT.dbo.DangKy
    UNION ALL SELECT N'Ngoại ngữ', SUM(DiemThi) FROM QLSV_NgoaiNgu.dbo.DangKy
    UNION ALL SELECT N'Du lịch',   SUM(DiemThi) FROM QLSV_DuLich.dbo.DangKy;

    UPDATE QLSV_CNTT.dbo.DangKy SET DiemThi = DiemThi + 0.5 WHERE MaSV = '24010001' AND MaLHP = 'CNTT101-HK1-2425-01';   -- sửa điểm tại node CNTT

    SELECT t.Noi, t.Tong AS TongDiemThi_Truoc, s.Tong AS TongDiemThi_Sau,
           CASE WHEN t.Tong = s.Tong THEN N'không đổi' ELSE N'ĐÃ ĐỔI (+0.5)' END AS KetQua
    FROM @truoc t
    JOIN (SELECT N'CNTT' AS Noi, SUM(DiemThi) AS Tong FROM QLSV_CNTT.dbo.DangKy
          UNION ALL SELECT N'Ngoại ngữ', SUM(DiemThi) FROM QLSV_NgoaiNgu.dbo.DangKy
          UNION ALL SELECT N'Du lịch',   SUM(DiemThi) FROM QLSV_DuLich.dbo.DangKy) s ON s.Noi = t.Noi;
ROLLBACK TRAN;
GO

/* 7b. Sửa trực tiếp BẢN SAO danh mục ở node (làm bản sao lệch bản chính): sp_DongBoDanhMuc kéo về đúng bản chính. */
BEGIN TRAN;
    EXEC LS_QLSV_NgoaiNgu.QLSV_NgoaiNgu.sys.sp_executesql N'UPDATE dbo.MonHoc SET TenMH = N''SỬA LẠC Ở NODE'' WHERE MaMH = ''NN101'';';
    SELECT N'Sau khi sửa lạc ở node Ngoại ngữ' AS Buoc, * FROM dbo.ViTriMonHoc('NN101');
    EXEC dbo.sp_DongBoDanhMuc @MaKhoa = 'NN';
    SELECT N'Sau sp_DongBoDanhMuc' AS Buoc, * FROM dbo.ViTriMonHoc('NN101');
ROLLBACK TRAN;
GO

/* =====================================================================
   PHẦN 6. HÀNG ĐỢI VÀ QUẢN LÝ DANH MỤC – ví dụ, mọi thay đổi đều ROLLBACK
   ===================================================================== */

-- 6.1. Sửa qua thủ tục: bản chính và cả 3 bản sao đổi ngay, hàng đợi rỗng.
BEGIN TRAN;
    EXEC dbo.dm_LuuMonHoc @MaMH = 'CNTT101', @TenMH = N'Nhập môn lập trình (sửa qua thủ tục)', @SoTinChi = 3, @MaKhoa = 'CNTT';
    SELECT N'Sau dm_LuuMonHoc' AS Buoc, * FROM dbo.ViTriMonHoc('CNTT101');
    SELECT N'Sau dm_LuuMonHoc: số mục còn chờ' AS KiemTra, COUNT(*) AS SoMuc FROM dbo.HangDoiDongBo;      -- = 0
ROLLBACK TRAN;
GO

-- 6.2. Sửa thẳng bằng UPDATE: trigger xếp 3 mục, bản sao chưa đổi; dm_XuLyHangDoi đẩy xuống, hàng đợi rỗng.
BEGIN TRAN;
    UPDATE dbo.MonHoc SET TenMH = TenMH + N' (sửa thẳng)' WHERE MaMH = 'NN101';
    SELECT N'Sau UPDATE thẳng: hàng đợi' AS Buoc, MaKhoa AS Node, Bang, KhoaChinh, HanhDong FROM dbo.HangDoiDongBo ORDER BY MaKhoa;
    SELECT N'Sau UPDATE thẳng' AS Buoc, * FROM dbo.ViTriMonHoc('NN101');
    EXEC dbo.dm_XuLyHangDoi;
    SELECT N'Sau dm_XuLyHangDoi' AS Buoc, * FROM dbo.ViTriMonHoc('NN101');
    SELECT N'Sau dm_XuLyHangDoi: số mục còn chờ' AS KiemTra, COUNT(*) AS SoMuc FROM dbo.HangDoiDongBo;    -- = 0
ROLLBACK TRAN;
GO

-- 6.3. Thêm môn mới và học kỳ mới qua thủ tục: có ngay ở cả 3 node.
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

-- 6.4. Giảng viên và lớp: ghi vào node của khoa; mã khoa sai thì bị từ chối.
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

/* =====================================================================
   PHẦN 7. KẾT LUẬN: bản sao khớp bản chính, hai mảnh dọc khớp nhau, hàng đợi rỗng
   ===================================================================== */
SELECT N'Bản sao danh mục khớp bản chính ở cả 3 node' AS KiemTra,
       (SELECT COUNT(*) FROM (SELECT MaMH, TenMH, SoTinChi, LoaiMH, MaKhoa FROM dbo.MonHoc
                              EXCEPT SELECT MaMH, TenMH, SoTinChi, LoaiMH, MaKhoa FROM QLSV_CNTT.dbo.MonHoc) a)
     + (SELECT COUNT(*) FROM (SELECT MaMH, TenMH, SoTinChi, LoaiMH, MaKhoa FROM dbo.MonHoc
                              EXCEPT SELECT MaMH, TenMH, SoTinChi, LoaiMH, MaKhoa FROM QLSV_NgoaiNgu.dbo.MonHoc) b)
     + (SELECT COUNT(*) FROM (SELECT MaMH, TenMH, SoTinChi, LoaiMH, MaKhoa FROM dbo.MonHoc
                              EXCEPT SELECT MaMH, TenMH, SoTinChi, LoaiMH, MaKhoa FROM QLSV_DuLich.dbo.MonHoc) c) AS SoDongLech;   -- = 0
SELECT N'Số sinh viên: hồ sơ ở điều phối = học vụ ở 3 node' AS KiemTra,
       (SELECT COUNT(*) FROM dbo.SinhVien_HoSo) AS HoSo,
       (SELECT COUNT(*) FROM dbo.vw_SinhVien_ToanCuc) AS HocVu;                                   -- 72 = 72
GO
SELECT N'Hàng đợi sau ví dụ' AS KiemTra, COUNT(*) AS SoMuc FROM dbo.HangDoiDongBo;     -- = 0
GO
