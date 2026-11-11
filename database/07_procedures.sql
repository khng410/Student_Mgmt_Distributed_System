/* =====================================================================
   ĐỒ ÁN CSDL PHÂN TÁN – QUẢN LÝ SINH VIÊN NHIỀU KHOA
   File   : 07_procedures.sql
   Mục đích: 14 stored procedure ở node điều phối QLSV_TongHop (7 thủ tục lõi + 7 bổ sung). Ứng dụng chỉ gọi
             các thủ tục này; thủ tục tự tìm đúng node chứa dữ liệu.
   Người viết: ...............          Ngày: ..../11/2026
   Chạy sau : 06_queries_40.sql           Chạy lại nhiều lần được (CREATE OR ALTER).

   #  Thủ tục               Việc làm                                       Transaction
   1  sp_DongBoDanhMuc      đồng bộ Khoa/HocKy/MonHoc từ TongHop -> node   CÓ  (nhiều DB)
   2  sp_ThemSinhVien       thêm SV: học vụ -> node khoa, hồ sơ -> TongHop CÓ  (2 DB)
   3  sp_ChuyenKhoa         chuyển SV sang khoa khác: xóa node cũ, thêm mới CÓ  (2 node)
   4  sp_DangKyHocPhan      đăng ký lớp học phần, kiểm tra sĩ số/trùng      CÓ  (khóa UPDLOCK)
   5  sp_NhapDiem           nhập/sửa điểm quá trình, điểm thi
   6  sp_BangDiemSinhVien   bảng điểm + điểm TB tích lũy của 1 sinh viên
   7  sp_ThongKeKhoa        phân bố học lực theo khoa / học kỳ
   --- bổ sung cho ứng dụng và demo ---
   8  sp_CapNhatSinhVien    sửa SV ở cả 2 mảnh dọc (học vụ + hồ sơ)         CÓ  (2 DB)
   9  sp_XoaSinhVien        xóa SV khỏi cả 2 mảnh dọc, chặn nếu có đăng ký  CÓ  (2 DB)
   10 sp_HuyDangKy          hủy đăng ký khi chưa có điểm
   11 sp_TimSinhVien        tìm/lọc sinh viên toàn trường, không phân biệt dấu
   12 sp_MoLopHocPhan       mở lớp học phần ở node theo khoa của giảng viên
   13 sp_DemoGiaoDich       demo COMMIT / ROLLBACK phân tán (cho bảo vệ và app)  CÓ (2 DB)
   14 sp_PhanBoDuLieu       số dòng mỗi bảng ở từng node so với bản tập trung

   Mã lỗi tự đặt: 500xx (THROW). Mọi thủ tục có transaction đều dùng
   SET XACT_ABORT ON + TRY...CATCH: lỗi ở đâu cũng ROLLBACK rồi ném lỗi lên.
   Phần cuối file có ví dụ EXEC cho cả 14 thủ tục; ví dụ ghi dữ liệu nằm trong
   BEGIN TRAN ... ROLLBACK nên chạy bao nhiêu lần dữ liệu mẫu vẫn nguyên.
   ===================================================================== */

SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
USE QLSV_TongHop;
GO

/* ---------- Hàm phụ: tên database (đã đặt trong ngoặc vuông) của node giữ dữ liệu một khoa ----------
   Các thủ tục ghép tên này vào SQL động để chạy đúng node. Mã khoa lạ trả về NULL.
   (Không đặt tên bắt đầu bằng fn_ để không lẫn vào 8 hàm của 08_functions.sql.) */
CREATE OR ALTER FUNCTION dbo.DbCuaKhoa (@MaKhoa VARCHAR(10))
RETURNS SYSNAME
AS
BEGIN
    RETURN QUOTENAME(CASE @MaKhoa WHEN 'CNTT' THEN N'QLSV_CNTT' WHEN 'NN' THEN N'QLSV_NgoaiNgu' WHEN 'DL' THEN N'QLSV_DuLich' END);
END
GO

/* ---------- Thủ tục phụ: lớp này thuộc khoa nào ----------
   Hỏi lần lượt từng node và dừng ở node đầu tiên có lớp, nên một node KHÁC mất kết nối không chặn được việc
   thêm sinh viên cho các khoa còn lại (hàm UNION ALL 3 node trước đây lỗi ngay khi một node vắng).
   Không tìm thấy mà có node không trả lời: báo lỗi 50012 thay vì kết luận "không có lớp".
   Gọi TRƯỚC khi mở giao dịch: lỗi kết nối bắt được ở đây sẽ làm hỏng giao dịch đang mở (XACT_ABORT).
   (Không đặt tên bắt đầu bằng sp_ để không lẫn vào 14 thủ tục chính.) */
CREATE OR ALTER PROCEDURE dbo.TimKhoaCuaLop
    @MaLop   VARCHAR(15),
    @MaKhoa  VARCHAR(10) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @MaKhoa = NULL;
    DECLARE @db SYSNAME, @sql NVARCHAR(MAX), @nodeVang INT = 0;
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT db FROM (VALUES (1, N'QLSV_CNTT'), (2, N'QLSV_NgoaiNgu'), (3, N'QLSV_DuLich')) n(tt, db) ORDER BY tt;
    OPEN c;
    FETCH NEXT FROM c INTO @db;
    WHILE @@FETCH_STATUS = 0 AND @MaKhoa IS NULL
    BEGIN
        BEGIN TRY
            SET @sql = N'SELECT @k = MaKhoa FROM ' + QUOTENAME(@db) + N'.dbo.Lop WHERE MaLop = @MaLop;';
            EXEC sp_executesql @sql, N'@MaLop VARCHAR(15), @k VARCHAR(10) OUTPUT', @MaLop, @MaKhoa OUTPUT;
        END TRY
        BEGIN CATCH
            SET @nodeVang += 1;                      -- node này không trả lời: thử node kế tiếp
        END CATCH
        FETCH NEXT FROM c INTO @db;
    END
    CLOSE c;
    DEALLOCATE c;
    IF @MaKhoa IS NULL AND @nodeVang > 0
        THROW 50012, N'Chưa tìm thấy lớp ở các node đang hoạt động; có node mất kết nối nên chưa kết luận được.', 1;
END
GO


/* ---------- 1. sp_DongBoDanhMuc ----------
   Chép thay đổi của danh mục từ bản chính (TongHop) xuống node khoa:
   sửa dòng khác nhau, thêm dòng còn thiếu. KHÔNG xóa dòng ở node (có thể đang
   được khóa ngoại tham chiếu). @MaKhoa NULL = đồng bộ cả 3 node. */
CREATE OR ALTER PROCEDURE dbo.sp_DongBoDanhMuc
    @MaKhoa VARCHAR(10) = NULL,
    @ImLang BIT = 0                 -- 1: không trả bảng kết quả (khi được gọi từ dm_XuLyHangDoi, 15_dong_bo_danh_muc.sql)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @MaKhoa IS NOT NULL AND @MaKhoa NOT IN ('CNTT', 'NN', 'DL')
        THROW 50001, N'MaKhoa phải là CNTT, NN hoặc DL (hoặc NULL để đồng bộ cả 3 node).', 1;

    DECLARE @node TABLE (db SYSNAME, k VARCHAR(10));
    INSERT @node VALUES (N'QLSV_CNTT', 'CNTT'), (N'QLSV_NgoaiNgu', 'NN'), (N'QLSV_DuLich', 'DL');

    CREATE TABLE #kq_DongBo (Node SYSNAME, Bang NVARCHAR(20), DaSua INT, DaThem INT);

    DECLARE @tpl NVARCHAR(MAX) = N'
    DECLARE @s INT, @t INT;

    UPDATE t SET TenKhoa = s.TenKhoa, NamThanhLap = s.NamThanhLap, DienThoai = s.DienThoai, Email = s.Email
    FROM {DB}.dbo.Khoa t JOIN QLSV_TongHop.dbo.Khoa s ON s.MaKhoa = t.MaKhoa
    WHERE NOT EXISTS (SELECT t.TenKhoa, t.NamThanhLap, t.DienThoai, t.Email
                      INTERSECT SELECT s.TenKhoa, s.NamThanhLap, s.DienThoai, s.Email);
    SET @s = @@ROWCOUNT;
    INSERT {DB}.dbo.Khoa SELECT * FROM QLSV_TongHop.dbo.Khoa s
    WHERE NOT EXISTS (SELECT 1 FROM {DB}.dbo.Khoa t WHERE t.MaKhoa = s.MaKhoa);
    SET @t = @@ROWCOUNT;
    INSERT #kq_DongBo VALUES (N''{DB}'', N''Khoa'', @s, @t);

    UPDATE t SET TenHK = s.TenHK, NamHoc = s.NamHoc, NgayBatDau = s.NgayBatDau, NgayKetThuc = s.NgayKetThuc
    FROM {DB}.dbo.HocKy t JOIN QLSV_TongHop.dbo.HocKy s ON s.MaHK = t.MaHK
    WHERE NOT EXISTS (SELECT t.TenHK, t.NamHoc, t.NgayBatDau, t.NgayKetThuc
                      INTERSECT SELECT s.TenHK, s.NamHoc, s.NgayBatDau, s.NgayKetThuc);
    SET @s = @@ROWCOUNT;
    INSERT {DB}.dbo.HocKy SELECT * FROM QLSV_TongHop.dbo.HocKy s
    WHERE NOT EXISTS (SELECT 1 FROM {DB}.dbo.HocKy t WHERE t.MaHK = s.MaHK);
    SET @t = @@ROWCOUNT;
    INSERT #kq_DongBo VALUES (N''{DB}'', N''HocKy'', @s, @t);

    UPDATE t SET TenMH = s.TenMH, SoTinChi = s.SoTinChi, LoaiMH = s.LoaiMH, MaKhoa = s.MaKhoa
    FROM {DB}.dbo.MonHoc t JOIN QLSV_TongHop.dbo.MonHoc s ON s.MaMH = t.MaMH
    WHERE NOT EXISTS (SELECT t.TenMH, t.SoTinChi, t.LoaiMH, t.MaKhoa
                      INTERSECT SELECT s.TenMH, s.SoTinChi, s.LoaiMH, s.MaKhoa);
    SET @s = @@ROWCOUNT;
    INSERT {DB}.dbo.MonHoc SELECT * FROM QLSV_TongHop.dbo.MonHoc s
    WHERE NOT EXISTS (SELECT 1 FROM {DB}.dbo.MonHoc t WHERE t.MaMH = s.MaMH);
    SET @t = @@ROWCOUNT;
    INSERT #kq_DongBo VALUES (N''{DB}'', N''MonHoc'', @s, @t);';

    DECLARE @db SYSNAME, @sql NVARCHAR(MAX);
    BEGIN TRY
        BEGIN TRAN;
        DECLARE c CURSOR LOCAL FAST_FORWARD FOR
            SELECT db FROM @node WHERE @MaKhoa IS NULL OR k = @MaKhoa;
        OPEN c;
        FETCH NEXT FROM c INTO @db;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @sql = REPLACE(@tpl, N'{DB}', @db);
            EXEC (@sql);
            FETCH NEXT FROM c INTO @db;
        END
        CLOSE c;
        DEALLOCATE c;
        -- node vừa đồng bộ xong thì không còn gì chờ trong hàng đợi (bảng tạo ở 15_dong_bo_danh_muc.sql)
        IF OBJECT_ID(N'dbo.HangDoiDongBo') IS NOT NULL
            DELETE dbo.HangDoiDongBo WHERE @MaKhoa IS NULL OR MaKhoa = @MaKhoa;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH

    IF @ImLang = 0
        SELECT Node, Bang, DaSua, DaThem FROM #kq_DongBo ORDER BY Node, Bang;
END
GO


/* ---------- 2. sp_ThemSinhVien ----------
   Một sinh viên nằm ở 2 database: học vụ ở node của khoa (tìm theo lớp),
   hồ sơ cá nhân ở TongHop. Hai lệnh INSERT phải cùng thành công hoặc cùng thất bại. */
CREATE OR ALTER PROCEDURE dbo.sp_ThemSinhVien
    @MaSV       CHAR(8),
    @HoTen      NVARCHAR(100),
    @NgaySinh   DATE,
    @GioiTinh   NVARCHAR(3),
    @MaLop      VARCHAR(15),
    @CCCD       CHAR(12),
    @Email      VARCHAR(100),
    @DienThoai  VARCHAR(10)   = NULL,
    @DiaChi     NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @k VARCHAR(10), @db SYSNAME, @sql NVARCHAR(MAX);

    EXEC dbo.TimKhoaCuaLop @MaLop, @k OUTPUT;

    IF @k IS NULL
        THROW 50010, N'Không tìm thấy lớp này ở node nào.', 1;
    IF EXISTS (SELECT 1 FROM dbo.SinhVien_HoSo WHERE MaSV = @MaSV)
        THROW 50011, N'Mã sinh viên đã tồn tại.', 1;

    SET @db = dbo.DbCuaKhoa(@k);
    -- Báo cho trigger trg_HoSo_KiemTraSinhVien biết sinh viên nằm ở node nào, để nó chỉ hỏi node đó (không cần cả 3 node sống)
    EXEC sp_set_session_context N'KhoaSV', @k;

    BEGIN TRY
        BEGIN TRAN;

        SET @sql = N'INSERT ' + @db + N'.dbo.SinhVien (MaSV, HoTen, NgaySinh, GioiTinh, MaLop)
                     VALUES (@MaSV, @HoTen, @NgaySinh, @GioiTinh, @MaLop);';
        EXEC sp_executesql @sql,
             N'@MaSV CHAR(8), @HoTen NVARCHAR(100), @NgaySinh DATE, @GioiTinh NVARCHAR(3), @MaLop VARCHAR(15)',
             @MaSV, @HoTen, @NgaySinh, @GioiTinh, @MaLop;

        INSERT dbo.SinhVien_HoSo (MaSV, CCCD, DienThoai, Email, DiaChi)
        VALUES (@MaSV, @CCCD, @DienThoai, @Email, @DiaChi);

        COMMIT;
        EXEC sp_set_session_context N'KhoaSV', NULL;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        EXEC sp_set_session_context N'KhoaSV', NULL;
        THROW;
    END CATCH

    -- Đọc lại từ đúng node của sinh viên (không qua view toàn cục, vì view cần cả 3 node đang sống)
    SET @sql = N'SELECT s.MaSV, s.HoTen, s.MaLop, k.TenKhoa, s.TrangThai
                 FROM ' + @db + N'.dbo.SinhVien s JOIN ' + @db + N'.dbo.Lop l ON l.MaLop = s.MaLop
                 JOIN dbo.Khoa k ON k.MaKhoa = l.MaKhoa WHERE s.MaSV = @MaSV;';
    EXEC sp_executesql @sql, N'@MaSV CHAR(8)', @MaSV;
END
GO


/* ---------- 3. sp_ChuyenKhoa ----------
   Chuyển sinh viên sang lớp thuộc khoa khác: thêm dòng ở node mới rồi xóa dòng ở
   node cũ. Hồ sơ ở TongHop giữ nguyên (cùng MaSV) - đây là lợi ích của mảnh dọc.
   Không cho chuyển nếu sinh viên đã có đăng ký học phần, vì lớp học phần cũ
   chỉ tồn tại ở node cũ. */
CREATE OR ALTER PROCEDURE dbo.sp_ChuyenKhoa
    @MaSV      CHAR(8),
    @MaLopMoi  VARCHAR(15)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @kCu VARCHAR(10), @kMoi VARCHAR(10), @dbCu SYSNAME, @dbMoi SYSNAME,
            @sql NVARCHAR(MAX), @soDK INT;

    SELECT @kCu = MaKhoa FROM dbo.vw_SinhVien_ToanCuc WHERE MaSV = @MaSV;
    IF @kCu IS NULL
        THROW 50020, N'Không tìm thấy sinh viên.', 1;

    EXEC dbo.TimKhoaCuaLop @MaLopMoi, @kMoi OUTPUT;
    IF @kMoi IS NULL
        THROW 50021, N'Không tìm thấy lớp mới.', 1;
    IF @kMoi = @kCu
        THROW 50022, N'Lớp mới cùng khoa với khoa hiện tại, không cần chuyển node.', 1;

    SET @dbCu  = dbo.DbCuaKhoa(@kCu);
    SET @dbMoi = dbo.DbCuaKhoa(@kMoi);

    SET @sql = N'SELECT @soDK = COUNT(*) FROM ' + @dbCu + N'.dbo.DangKy WHERE MaSV = @MaSV;';
    EXEC sp_executesql @sql, N'@MaSV CHAR(8), @soDK INT OUTPUT', @MaSV, @soDK OUTPUT;
    IF @soDK > 0
        THROW 50023, N'Sinh viên đã có đăng ký học phần ở khoa cũ, không thể chuyển khoa.', 1;

    BEGIN TRY
        BEGIN TRAN;

        SET @sql = N'INSERT ' + @dbMoi + N'.dbo.SinhVien (MaSV, HoTen, NgaySinh, GioiTinh, MaLop, TrangThai)
                     SELECT MaSV, HoTen, NgaySinh, GioiTinh, @MaLopMoi, TrangThai
                     FROM ' + @dbCu + N'.dbo.SinhVien WHERE MaSV = @MaSV;
                     DELETE FROM ' + @dbCu + N'.dbo.SinhVien WHERE MaSV = @MaSV;';
        EXEC sp_executesql @sql, N'@MaSV CHAR(8), @MaLopMoi VARCHAR(15)', @MaSV, @MaLopMoi;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH

    SELECT MaSV, HoTen, MaLop, TenKhoa FROM dbo.vw_SinhVien_ToanCuc WHERE MaSV = @MaSV;
END
GO


/* ---------- 4. sp_DangKyHocPhan ----------
   Kiểm tra: sinh viên đang học, lớp học phần có ở khoa của sinh viên, chưa đăng ký,
   chưa đủ sĩ số. UPDLOCK + HOLDLOCK giữ khóa trên dòng lớp học phần trong transaction
   để hai người cùng đăng ký chỗ cuối không cùng thành công. */
CREATE OR ALTER PROCEDURE dbo.sp_DangKyHocPhan
    @MaSV   CHAR(8),
    @MaLHP  VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @k VARCHAR(10), @tt NVARCHAR(20), @db SYSNAME, @sql NVARCHAR(MAX),
            @siso INT, @daDK INT, @trung INT;

    SELECT @k = MaKhoa, @tt = TrangThai FROM dbo.vw_SinhVien_ToanCuc WHERE MaSV = @MaSV;
    IF @k IS NULL
        THROW 50030, N'Không tìm thấy sinh viên.', 1;
    IF @tt <> N'Đang học'
        THROW 50031, N'Chỉ sinh viên đang học mới được đăng ký học phần.', 1;

    SET @db = dbo.DbCuaKhoa(@k);

    BEGIN TRY
        BEGIN TRAN;

        SET @sql = N'SELECT @siso = SiSoToiDa FROM ' + @db + N'.dbo.LopHocPhan WITH (UPDLOCK, HOLDLOCK) WHERE MaLHP = @MaLHP;
                     SELECT @daDK = COUNT(*) FROM ' + @db + N'.dbo.DangKy WHERE MaLHP = @MaLHP;
                     SELECT @trung = COUNT(*) FROM ' + @db + N'.dbo.DangKy WHERE MaSV = @MaSV AND MaLHP = @MaLHP;';
        EXEC sp_executesql @sql,
             N'@MaSV CHAR(8), @MaLHP VARCHAR(20), @siso INT OUTPUT, @daDK INT OUTPUT, @trung INT OUTPUT',
             @MaSV, @MaLHP, @siso OUTPUT, @daDK OUTPUT, @trung OUTPUT;

        IF @siso IS NULL
            THROW 50032, N'Lớp học phần không tồn tại ở khoa của sinh viên.', 1;
        IF @trung > 0
            THROW 50033, N'Sinh viên đã đăng ký lớp học phần này.', 1;
        IF @daDK >= @siso
            THROW 50034, N'Lớp học phần đã đủ sĩ số.', 1;

        SET @sql = N'INSERT ' + @db + N'.dbo.DangKy (MaSV, MaLHP) VALUES (@MaSV, @MaLHP);';
        EXEC sp_executesql @sql, N'@MaSV CHAR(8), @MaLHP VARCHAR(20)', @MaSV, @MaLHP;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH

    SELECT MaSV, MaLHP, TenMH, MaHK, NgayDangKy FROM dbo.vw_DangKy_ToanCuc WHERE MaSV = @MaSV AND MaLHP = @MaLHP;
END
GO


/* ---------- 5. sp_NhapDiem ----------
   Nhập hoặc sửa điểm. Tham số để NULL nghĩa là giữ nguyên điểm cũ. */
CREATE OR ALTER PROCEDURE dbo.sp_NhapDiem
    @MaSV     CHAR(8),
    @MaLHP    VARCHAR(20),
    @DiemQT   DECIMAL(4,2) = NULL,
    @DiemThi  DECIMAL(4,2) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @k VARCHAR(10), @db SYSNAME, @sql NVARCHAR(MAX), @n INT;

    IF @DiemQT IS NULL AND @DiemThi IS NULL
        THROW 50040, N'Phải nhập ít nhất một trong hai điểm: DiemQT hoặc DiemThi.', 1;
    IF @DiemQT < 0 OR @DiemQT > 10 OR @DiemThi < 0 OR @DiemThi > 10
        THROW 50041, N'Điểm phải nằm trong khoảng 0 đến 10.', 1;

    SELECT @k = MaKhoa FROM dbo.vw_SinhVien_ToanCuc WHERE MaSV = @MaSV;
    IF @k IS NULL
        THROW 50042, N'Không tìm thấy sinh viên.', 1;

    SET @db = dbo.DbCuaKhoa(@k);
    SET @sql = N'UPDATE ' + @db + N'.dbo.DangKy
                 SET DiemQT = ISNULL(@DiemQT, DiemQT), DiemThi = ISNULL(@DiemThi, DiemThi)
                 WHERE MaSV = @MaSV AND MaLHP = @MaLHP;
                 SET @n = @@ROWCOUNT;';
    EXEC sp_executesql @sql,
         N'@MaSV CHAR(8), @MaLHP VARCHAR(20), @DiemQT DECIMAL(4,2), @DiemThi DECIMAL(4,2), @n INT OUTPUT',
         @MaSV, @MaLHP, @DiemQT, @DiemThi, @n OUTPUT;

    IF @n = 0
        THROW 50043, N'Sinh viên chưa đăng ký lớp học phần này.', 1;

    SELECT MaSV, MaLHP, TenMH, DiemQT, DiemThi, DiemTK FROM dbo.vw_DangKy_ToanCuc
    WHERE MaSV = @MaSV AND MaLHP = @MaLHP;
END
GO


/* ---------- 6. sp_BangDiemSinhVien ----------
   Kết quả 1: bảng điểm. Kết quả 2: tổng hợp (điểm TB tích lũy tính theo tín chỉ).
   @MaHK NULL = mọi học kỳ. */
CREATE OR ALTER PROCEDURE dbo.sp_BangDiemSinhVien
    @MaSV  CHAR(8),
    @MaHK  VARCHAR(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.vw_SinhVien_ToanCuc WHERE MaSV = @MaSV)
        THROW 50050, N'Không tìm thấy sinh viên.', 1;

    SELECT MaHK, MaMH, TenMH, SoTinChi, DiemQT, DiemThi, DiemTK, KetQua
    FROM dbo.vw_BangDiem
    WHERE MaSV = @MaSV AND (@MaHK IS NULL OR MaHK = @MaHK)
    ORDER BY MaHK, MaMH;

    SELECT COUNT(DiemTK) AS SoMonCoDiem,
           SUM(CASE WHEN DiemTK >= 4 THEN SoTinChi ELSE 0 END) AS TinChiTichLuy,
           CAST(SUM(DiemTK * SoTinChi)
                / NULLIF(SUM(CASE WHEN DiemTK IS NOT NULL THEN SoTinChi END), 0) AS DECIMAL(4,2)) AS DiemTBTichLuy
    FROM dbo.vw_BangDiem
    WHERE MaSV = @MaSV AND (@MaHK IS NULL OR MaHK = @MaHK);
END
GO


/* ---------- 7. sp_ThongKeKhoa ----------
   Phân bố học lực theo khoa. Cả hai tham số NULL = toàn trường, mọi học kỳ.
   Giáo vụ chỉ thấy khoa của mình dù truyền @MaKhoa nào: vw_BangDiem đã lọc theo dbo.PhamViKhoaCuaToi (05_views.sql).
   Thang: Giỏi >= 8; Khá >= 6,5; Trung bình >= 5; Yếu >= 4; Không đạt < 4. */
CREATE OR ALTER PROCEDURE dbo.sp_ThongKeKhoa
    @MaKhoa  VARCHAR(10) = NULL,
    @MaHK    VARCHAR(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TenKhoa,
           COUNT(DiemTK) AS SoLuotCoDiem,
           CAST(AVG(DiemTK) AS DECIMAL(4,2)) AS DiemTB,
           SUM(CASE WHEN DiemTK >= 8                  THEN 1 ELSE 0 END) AS Gioi,
           SUM(CASE WHEN DiemTK >= 6.5 AND DiemTK < 8 THEN 1 ELSE 0 END) AS Kha,
           SUM(CASE WHEN DiemTK >= 5   AND DiemTK < 6.5 THEN 1 ELSE 0 END) AS TrungBinh,
           SUM(CASE WHEN DiemTK >= 4   AND DiemTK < 5 THEN 1 ELSE 0 END) AS Yeu,
           SUM(CASE WHEN DiemTK < 4                   THEN 1 ELSE 0 END) AS KhongDat
    FROM dbo.vw_BangDiem
    WHERE (@MaKhoa IS NULL OR MaKhoa = @MaKhoa)
      AND (@MaHK   IS NULL OR MaHK   = @MaHK)
    GROUP BY TenKhoa
    ORDER BY TenKhoa;
END
GO


/* =====================================================================
   PHẦN BỔ SUNG – 7 thủ tục cho ứng dụng và demo (ngoài 7 thủ tục lõi ở trên)
   ===================================================================== */

/* ---------- 8. sp_CapNhatSinhVien ----------
   Sửa thông tin sinh viên ở cả 2 mảnh dọc trong 1 transaction.
   Tham số NULL = giữ nguyên (nên không thể xóa trắng một trường; CCCD và lớp không sửa ở đây:
   đổi khoa dùng sp_ChuyenKhoa). */
CREATE OR ALTER PROCEDURE dbo.sp_CapNhatSinhVien
    @MaSV       CHAR(8),
    @HoTen      NVARCHAR(100) = NULL,
    @NgaySinh   DATE          = NULL,
    @GioiTinh   NVARCHAR(3)   = NULL,
    @TrangThai  NVARCHAR(20)  = NULL,
    @Email      VARCHAR(100)  = NULL,
    @DienThoai  VARCHAR(10)   = NULL,
    @DiaChi     NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @k VARCHAR(10), @db SYSNAME, @sql NVARCHAR(MAX);
    SELECT @k = MaKhoa FROM dbo.vw_SinhVien_ToanCuc WHERE MaSV = @MaSV;
    IF @k IS NULL
        THROW 50060, N'Không tìm thấy sinh viên.', 1;

    SET @db = dbo.DbCuaKhoa(@k);

    BEGIN TRY
        BEGIN TRAN;

        SET @sql = N'UPDATE ' + @db + N'.dbo.SinhVien
                     SET HoTen = ISNULL(@HoTen, HoTen), NgaySinh = ISNULL(@NgaySinh, NgaySinh),
                         GioiTinh = ISNULL(@GioiTinh, GioiTinh), TrangThai = ISNULL(@TrangThai, TrangThai)
                     WHERE MaSV = @MaSV;';
        EXEC sp_executesql @sql,
             N'@MaSV CHAR(8), @HoTen NVARCHAR(100), @NgaySinh DATE, @GioiTinh NVARCHAR(3), @TrangThai NVARCHAR(20)',
             @MaSV, @HoTen, @NgaySinh, @GioiTinh, @TrangThai;

        UPDATE dbo.SinhVien_HoSo
        SET Email = ISNULL(@Email, Email), DienThoai = ISNULL(@DienThoai, DienThoai), DiaChi = ISNULL(@DiaChi, DiaChi)
        WHERE MaSV = @MaSV;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH

    SELECT MaSV, HoTen, NgaySinh, GioiTinh, TrangThai, Email, DienThoai, DiaChi
    FROM dbo.vw_SinhVien_DayDu WHERE MaSV = @MaSV;
END
GO


/* ---------- 9. sp_XoaSinhVien ----------
   Xóa sinh viên khỏi cả 2 mảnh dọc (hồ sơ trước, học vụ sau). Chỉ xóa được khi chưa có
   đăng ký học phần nào, để không mất lịch sử điểm. */
CREATE OR ALTER PROCEDURE dbo.sp_XoaSinhVien
    @MaSV CHAR(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @k VARCHAR(10), @db SYSNAME, @sql NVARCHAR(MAX), @soDK INT;
    SELECT @k = MaKhoa FROM dbo.vw_SinhVien_ToanCuc WHERE MaSV = @MaSV;
    IF @k IS NULL
        THROW 50061, N'Không tìm thấy sinh viên.', 1;

    SET @db = dbo.DbCuaKhoa(@k);
    SET @sql = N'SELECT @soDK = COUNT(*) FROM ' + @db + N'.dbo.DangKy WHERE MaSV = @MaSV;';
    EXEC sp_executesql @sql, N'@MaSV CHAR(8), @soDK INT OUTPUT', @MaSV, @soDK OUTPUT;
    IF @soDK > 0
        THROW 50062, N'Sinh viên đã có đăng ký học phần, không thể xóa.', 1;

    BEGIN TRY
        BEGIN TRAN;
        DELETE FROM dbo.SinhVien_HoSo WHERE MaSV = @MaSV;
        SET @sql = N'DELETE FROM ' + @db + N'.dbo.SinhVien WHERE MaSV = @MaSV;';
        EXEC sp_executesql @sql, N'@MaSV CHAR(8)', @MaSV;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH

    SELECT N'Đã xóa sinh viên' AS KetQua, @MaSV AS MaSV;
END
GO


/* ---------- 10. sp_HuyDangKy ----------
   Hủy đăng ký học phần. Chỉ hủy được khi chưa có điểm nào. */
CREATE OR ALTER PROCEDURE dbo.sp_HuyDangKy
    @MaSV   CHAR(8),
    @MaLHP  VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @k VARCHAR(10), @db SYSNAME, @sql NVARCHAR(MAX), @ton INT, @coDiem INT;
    SELECT @k = MaKhoa FROM dbo.vw_SinhVien_ToanCuc WHERE MaSV = @MaSV;
    IF @k IS NULL
        THROW 50070, N'Không tìm thấy sinh viên.', 1;

    SET @db = dbo.DbCuaKhoa(@k);
    SET @sql = N'SELECT @ton = COUNT(*),
                        @coDiem = COUNT(CASE WHEN DiemQT IS NOT NULL OR DiemThi IS NOT NULL THEN 1 END)
                 FROM ' + @db + N'.dbo.DangKy WHERE MaSV = @MaSV AND MaLHP = @MaLHP;';
    EXEC sp_executesql @sql, N'@MaSV CHAR(8), @MaLHP VARCHAR(20), @ton INT OUTPUT, @coDiem INT OUTPUT',
         @MaSV, @MaLHP, @ton OUTPUT, @coDiem OUTPUT;

    IF @ton = 0
        THROW 50071, N'Sinh viên chưa đăng ký lớp học phần này.', 1;
    IF @coDiem > 0
        THROW 50072, N'Đăng ký đã có điểm, không thể hủy.', 1;

    SET @sql = N'DELETE FROM ' + @db + N'.dbo.DangKy WHERE MaSV = @MaSV AND MaLHP = @MaLHP;';
    EXEC sp_executesql @sql, N'@MaSV CHAR(8), @MaLHP VARCHAR(20)', @MaSV, @MaLHP;

    SELECT N'Đã hủy đăng ký' AS KetQua, @MaSV AS MaSV, @MaLHP AS MaLHP;
END
GO


/* ---------- 11. sp_TimSinhVien ----------
   Tìm sinh viên toàn trường (qua VIEW toàn cục). Mọi tham số NULL = không lọc.
   @TuKhoa khớp một phần mã SV hoặc họ tên, KHÔNG phân biệt dấu ("nguyen" tìm ra "Nguyễn"). */
CREATE OR ALTER PROCEDURE dbo.sp_TimSinhVien
    @TuKhoa     NVARCHAR(100) = NULL,
    @MaKhoa     VARCHAR(10)   = NULL,
    @MaLop      VARCHAR(15)   = NULL,
    @TrangThai  NVARCHAR(20)  = NULL,
    @Top        INT           = 100
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (@Top) MaSV, HoTen, NgaySinh, GioiTinh, MaLop, TenLop, TenKhoa, TrangThai
    FROM dbo.vw_SinhVien_ToanCuc
    WHERE (@TuKhoa IS NULL
           OR MaSV LIKE N'%' + @TuKhoa + N'%'
           OR HoTen COLLATE Vietnamese_CI_AI LIKE N'%' + @TuKhoa + N'%')
      AND (@MaKhoa    IS NULL OR MaKhoa    = @MaKhoa)
      AND (@MaLop     IS NULL OR MaLop     = @MaLop)
      AND (@TrangThai IS NULL OR TrangThai = @TrangThai)
    ORDER BY MaKhoa, MaLop, MaSV;
END
GO


/* ---------- 12. sp_MoLopHocPhan ----------
   Mở lớp học phần mới. Node được chọn theo khoa của giảng viên. Mã lớp học phần tự sinh
   dạng MaMH-MaHK-Nhom và phải duy nhất trên toàn hệ thống (không chỉ trong 1 node). */
CREATE OR ALTER PROCEDURE dbo.sp_MoLopHocPhan
    @MaMH       VARCHAR(10),
    @MaHK       VARCHAR(10),
    @MaGV       VARCHAR(10),
    @Nhom       TINYINT      = 1,
    @SiSoToiDa  SMALLINT     = 60,
    @PhongHoc   VARCHAR(10)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @k VARCHAR(10), @khoaMon VARCHAR(10), @coMon BIT = 0, @db SYSNAME, @sql NVARCHAR(MAX),
            @MaLHP VARCHAR(20);

    SELECT @k = MaKhoa FROM (
        SELECT MaGV, MaKhoa FROM QLSV_CNTT.dbo.GiangVien
        UNION ALL SELECT MaGV, MaKhoa FROM QLSV_NgoaiNgu.dbo.GiangVien
        UNION ALL SELECT MaGV, MaKhoa FROM QLSV_DuLich.dbo.GiangVien) g
    WHERE g.MaGV = @MaGV;
    IF @k IS NULL
        THROW 50080, N'Không tìm thấy giảng viên.', 1;

    SELECT @khoaMon = MaKhoa, @coMon = 1 FROM dbo.MonHoc WHERE MaMH = @MaMH;
    IF @coMon = 0
        THROW 50081, N'Không tìm thấy môn học.', 1;
    IF @khoaMon IS NOT NULL AND @khoaMon <> @k
        THROW 50082, N'Môn học thuộc khoa khác, giảng viên này không được mở lớp.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.HocKy WHERE MaHK = @MaHK)
        THROW 50083, N'Không tìm thấy học kỳ.', 1;

    SET @MaLHP = @MaMH + '-' + @MaHK + '-' + RIGHT('0' + CAST(@Nhom AS VARCHAR(3)), 2);
    IF EXISTS (SELECT 1 FROM (
                   SELECT MaLHP FROM QLSV_CNTT.dbo.LopHocPhan
                   UNION ALL SELECT MaLHP FROM QLSV_NgoaiNgu.dbo.LopHocPhan
                   UNION ALL SELECT MaLHP FROM QLSV_DuLich.dbo.LopHocPhan) x WHERE x.MaLHP = @MaLHP)
        THROW 50084, N'Mã lớp học phần đã tồn tại ở một node; hãy đổi Nhom.', 1;

    SET @db = dbo.DbCuaKhoa(@k);
    SET @sql = N'INSERT ' + @db + N'.dbo.LopHocPhan (MaLHP, MaMH, MaHK, Nhom, MaGV, SiSoToiDa, PhongHoc)
                 VALUES (@MaLHP, @MaMH, @MaHK, @Nhom, @MaGV, @SiSoToiDa, @PhongHoc);';
    EXEC sp_executesql @sql,
         N'@MaLHP VARCHAR(20), @MaMH VARCHAR(10), @MaHK VARCHAR(10), @Nhom TINYINT, @MaGV VARCHAR(10), @SiSoToiDa SMALLINT, @PhongHoc VARCHAR(10)',
         @MaLHP, @MaMH, @MaHK, @Nhom, @MaGV, @SiSoToiDa, @PhongHoc;

    SELECT @MaLHP AS MaLHP, @k AS NodeKhoa, @MaMH AS MaMH, @MaHK AS MaHK, @MaGV AS MaGV, @SiSoToiDa AS SiSoToiDa;
END
GO


/* ---------- 13. sp_DemoGiaoDich ----------
   Demo giao dịch phân tán cho buổi bảo vệ / trang "Phân tán" của ứng dụng.
   Thêm 1 sinh viên demo (99999999) vào 2 database trong 1 transaction.
     @GayLoi = 0 : cả hai lệnh thành công -> COMMIT, thấy dữ liệu ở cả node CNTT lẫn TongHop.
     @GayLoi = 1 : lệnh thứ hai cố ý lỗi (trùng CCCD) -> ROLLBACK, lệnh thứ nhất cũng bị hủy.
   @DonDep = 1 : xóa sinh viên demo sau khi đã ghi kết quả, để dữ liệu mẫu không đổi.
   Mã 99999999 được dành riêng cho demo: trg_SinhVien_GhiNhatKy và trg_HoSo_GhiNhatKy (09) bỏ qua mã này. */
CREATE OR ALTER PROCEDURE dbo.sp_DemoGiaoDich
    @GayLoi  BIT = 0,
    @DonDep  BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ma CHAR(8) = '99999999', @cccd CHAR(12) = '000000000099', @cccdTrung CHAR(12),
            @ketQua NVARCHAR(200), @loi NVARCHAR(4000) = NULL, @soNode INT, @soHoSo INT;

    DELETE FROM dbo.SinhVien_HoSo        WHERE MaSV = @ma;      -- dọn lần chạy trước (nếu có)
    DELETE FROM QLSV_CNTT.dbo.SinhVien   WHERE MaSV = @ma;
    SELECT TOP (1) @cccdTrung = CCCD FROM dbo.SinhVien_HoSo ORDER BY MaSV;

    BEGIN TRY
        BEGIN TRAN;
        INSERT QLSV_CNTT.dbo.SinhVien (MaSV, HoTen, NgaySinh, GioiTinh, MaLop)
        VALUES (@ma, N'Sinh Viên Demo', '2006-01-01', N'Nam', '66.CNTT-1');

        INSERT dbo.SinhVien_HoSo (MaSV, CCCD, Email)
        VALUES (@ma, CASE WHEN @GayLoi = 1 THEN @cccdTrung ELSE @cccd END, 'demo99999999@sv.qlsv.edu.vn');
        COMMIT;
        SET @ketQua = N'COMMIT: cả hai lệnh INSERT (node CNTT và TongHop) đều được ghi.';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SET @loi = ERROR_MESSAGE();
        SET @ketQua = N'ROLLBACK: lệnh thứ hai lỗi nên lệnh INSERT thứ nhất ở node CNTT cũng bị hủy.';
    END CATCH

    SELECT @soNode  = COUNT(*) FROM QLSV_CNTT.dbo.SinhVien WHERE MaSV = @ma;
    SELECT @soHoSo  = COUNT(*) FROM dbo.SinhVien_HoSo      WHERE MaSV = @ma;

    SELECT @ketQua AS KetQua, @soNode AS DongOTNodeCNTT, @soHoSo AS DongOTongHop, @loi AS ThongBaoLoi;

    IF @DonDep = 1 AND (@soNode > 0 OR @soHoSo > 0)
    BEGIN
        DELETE FROM dbo.SinhVien_HoSo      WHERE MaSV = @ma;
        DELETE FROM QLSV_CNTT.dbo.SinhVien WHERE MaSV = @ma;
    END
END
GO


/* ---------- 14. sp_PhanBoDuLieu ----------
   Số dòng của từng bảng ở từng node, so với CSDL tập trung gốc (QLSV_TapTrung).
   Dùng cho trang "Phân tán" của ứng dụng và demo "dữ liệu nằm ở đâu".
   KhopTapTrung = OK khi tổng các node bằng bản gốc (sẽ LECH sau khi thêm/xóa dữ liệu mới). */
CREATE OR ALTER PROCEDURE dbo.sp_PhanBoDuLieu
AS
BEGIN
    SET NOCOUNT ON;

    SELECT Bang, CNTT, NgoaiNgu, DuLich, CNTT + NgoaiNgu + DuLich AS TongCacNode, TapTrung,
           CASE WHEN CNTT + NgoaiNgu + DuLich = TapTrung THEN N'OK' ELSE N'LECH' END AS KhopTapTrung
    FROM (
        SELECT N'GiangVien' AS Bang,
               (SELECT COUNT(*) FROM QLSV_CNTT.dbo.GiangVien)     AS CNTT,
               (SELECT COUNT(*) FROM QLSV_NgoaiNgu.dbo.GiangVien) AS NgoaiNgu,
               (SELECT COUNT(*) FROM QLSV_DuLich.dbo.GiangVien)   AS DuLich,
               (SELECT COUNT(*) FROM QLSV_TapTrung.dbo.GiangVien) AS TapTrung
        UNION ALL SELECT N'Lop',
               (SELECT COUNT(*) FROM QLSV_CNTT.dbo.Lop), (SELECT COUNT(*) FROM QLSV_NgoaiNgu.dbo.Lop),
               (SELECT COUNT(*) FROM QLSV_DuLich.dbo.Lop), (SELECT COUNT(*) FROM QLSV_TapTrung.dbo.Lop)
        UNION ALL SELECT N'SinhVien (mảnh học vụ)',
               (SELECT COUNT(*) FROM QLSV_CNTT.dbo.SinhVien), (SELECT COUNT(*) FROM QLSV_NgoaiNgu.dbo.SinhVien),
               (SELECT COUNT(*) FROM QLSV_DuLich.dbo.SinhVien), (SELECT COUNT(*) FROM QLSV_TapTrung.dbo.SinhVien)
        UNION ALL SELECT N'LopHocPhan',
               (SELECT COUNT(*) FROM QLSV_CNTT.dbo.LopHocPhan), (SELECT COUNT(*) FROM QLSV_NgoaiNgu.dbo.LopHocPhan),
               (SELECT COUNT(*) FROM QLSV_DuLich.dbo.LopHocPhan), (SELECT COUNT(*) FROM QLSV_TapTrung.dbo.LopHocPhan)
        UNION ALL SELECT N'DangKy',
               (SELECT COUNT(*) FROM QLSV_CNTT.dbo.DangKy), (SELECT COUNT(*) FROM QLSV_NgoaiNgu.dbo.DangKy),
               (SELECT COUNT(*) FROM QLSV_DuLich.dbo.DangKy), (SELECT COUNT(*) FROM QLSV_TapTrung.dbo.DangKy)
    ) t;

    -- Mảnh dọc nhạy cảm: nằm tập trung ở TongHop, phải bằng số sinh viên gốc
    SELECT N'SinhVien_HoSo (mảnh dọc, ở TongHop)' AS Bang,
           (SELECT COUNT(*) FROM dbo.SinhVien_HoSo)             AS SoDongTongHop,
           (SELECT COUNT(*) FROM QLSV_TapTrung.dbo.SinhVien)    AS TapTrung,
           CASE WHEN (SELECT COUNT(*) FROM dbo.SinhVien_HoSo) = (SELECT COUNT(*) FROM QLSV_TapTrung.dbo.SinhVien)
                THEN N'OK' ELSE N'LECH' END AS KhopTapTrung;
END
GO


/* =====================================================================
   VÍ DỤ GỌI (EXEC) – mỗi ví dụ ghi dữ liệu nằm trong BEGIN TRAN ... ROLLBACK
   ===================================================================== */
SET XACT_ABORT ON;
GO

-- 1. sp_DongBoDanhMuc: sau 04_fragmentation.sql các node đã khớp nên mọi số = 0
EXEC dbo.sp_DongBoDanhMuc;                      -- cả 3 node
EXEC dbo.sp_DongBoDanhMuc @MaKhoa = 'CNTT';     -- chỉ node CNTT
-- Sửa danh mục ở TongHop rồi đồng bộ: chỉ node CNTT nhận thay đổi, sau đó hoàn tác.
BEGIN TRAN;
    UPDATE dbo.MonHoc SET SoTinChi = 4 WHERE MaMH = 'CNTT101';
    EXEC dbo.sp_DongBoDanhMuc @MaKhoa = 'CNTT';
    SELECT N'Node CNTT sau đồng bộ' AS Buoc, MaMH, SoTinChi FROM QLSV_CNTT.dbo.MonHoc WHERE MaMH = 'CNTT101';
    SELECT N'Node NN chưa đồng bộ'   AS Buoc, MaMH, SoTinChi FROM QLSV_NgoaiNgu.dbo.MonHoc WHERE MaMH = 'CNTT101';
ROLLBACK TRAN;
GO

-- 2. sp_ThemSinhVien: thành công (rồi hoàn tác)
BEGIN TRAN;
    EXEC dbo.sp_ThemSinhVien @MaSV = '24019999', @HoTen = N'Nguyễn Thị Kiểm Thử', @NgaySinh = '2006-05-10',
         @GioiTinh = N'Nữ', @MaLop = '66.CNTT-1', @CCCD = '001306009999',
         @Email = '24019999@sv.qlsv.edu.vn', @DienThoai = '0912345678', @DiaChi = N'Số 1 đường Lê Lợi, Hà Nội';
ROLLBACK TRAN;
GO
-- 2b. sp_ThemSinhVien: lỗi do trùng CCCD -> hồ sơ không thêm được -> ROLLBACK cả phần học vụ ở node CNTT
DECLARE @cccd CHAR(12) = (SELECT TOP (1) CCCD FROM dbo.SinhVien_HoSo ORDER BY MaSV);
BEGIN TRY
    EXEC dbo.sp_ThemSinhVien @MaSV = '24019998', @HoTen = N'Trần Văn Trùng CCCD', @NgaySinh = '2006-01-01',
         @GioiTinh = N'Nam', @MaLop = '66.CNTT-1', @CCCD = @cccd, @Email = '24019998@sv.qlsv.edu.vn';
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS MaLoi, ERROR_MESSAGE() AS ThongBao;
END CATCH
SELECT N'Sau lỗi: node CNTT còn dòng này không?' AS KiemTra, COUNT(*) AS SoDong
FROM QLSV_CNTT.dbo.SinhVien WHERE MaSV = '24019998';      -- phải = 0
GO

-- 3. sp_ChuyenKhoa: sinh viên 24010016 (chưa đăng ký môn nào) chuyển từ CNTT sang lớp NN (rồi hoàn tác)
BEGIN TRAN;
    EXEC dbo.sp_ChuyenKhoa @MaSV = '24010016', @MaLopMoi = '66.NN-2';
    SELECT N'Node CNTT' AS Node, COUNT(*) AS SoDong FROM QLSV_CNTT.dbo.SinhVien WHERE MaSV = '24010016'
    UNION ALL SELECT N'Node NN', COUNT(*) FROM QLSV_NgoaiNgu.dbo.SinhVien WHERE MaSV = '24010016'
    UNION ALL SELECT N'Hồ sơ ở TongHop', COUNT(*) FROM dbo.SinhVien_HoSo WHERE MaSV = '24010016';
ROLLBACK TRAN;
GO
-- 3b. sp_ChuyenKhoa bị từ chối: sinh viên 24010001 đã có đăng ký học phần
BEGIN TRY
    EXEC dbo.sp_ChuyenKhoa @MaSV = '24010001', @MaLopMoi = '66.NN-1';
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS MaLoi, ERROR_MESSAGE() AS ThongBao;
END CATCH
GO

-- 4. sp_DangKyHocPhan: thành công (rồi hoàn tác) và 2 trường hợp bị từ chối
BEGIN TRAN;
    EXEC dbo.sp_DangKyHocPhan @MaSV = '24010016', @MaLHP = 'CNTT110-HK1-2627-01';
ROLLBACK TRAN;
GO
BEGIN TRY   -- đã đăng ký rồi
    EXEC dbo.sp_DangKyHocPhan @MaSV = '24010001', @MaLHP = 'CNTT101-HK1-2425-01';
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS MaLoi, ERROR_MESSAGE() AS ThongBao;
END CATCH
BEGIN TRY   -- lớp học phần của khoa khác
    EXEC dbo.sp_DangKyHocPhan @MaSV = '24010016', @MaLHP = 'NN110-HK1-2627-01';
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS MaLoi, ERROR_MESSAGE() AS ThongBao;
END CATCH
GO

-- 5. sp_NhapDiem: nhập điểm hợp lệ (rồi hoàn tác) và điểm sai
BEGIN TRAN;
    EXEC dbo.sp_NhapDiem @MaSV = '24010001', @MaLHP = 'CNTT110-HK1-2627-01', @DiemQT = 8.5, @DiemThi = 9;
ROLLBACK TRAN;
GO
BEGIN TRY
    EXEC dbo.sp_NhapDiem @MaSV = '24010001', @MaLHP = 'CNTT110-HK1-2627-01', @DiemThi = 11;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS MaLoi, ERROR_MESSAGE() AS ThongBao;
END CATCH
GO

-- 6. sp_BangDiemSinhVien
EXEC dbo.sp_BangDiemSinhVien @MaSV = '24010001';
EXEC dbo.sp_BangDiemSinhVien @MaSV = '24010001', @MaHK = 'HK2-2526';
GO

-- 7. sp_ThongKeKhoa
EXEC dbo.sp_ThongKeKhoa;
EXEC dbo.sp_ThongKeKhoa @MaKhoa = 'CNTT', @MaHK = 'HK2-2526';
GO

-- 8. sp_CapNhatSinhVien: sửa họ tên (node CNTT) và địa chỉ (hồ sơ ở TongHop) trong 1 transaction, rồi hoàn tác
BEGIN TRAN;
    EXEC dbo.sp_CapNhatSinhVien @MaSV = '24010001', @HoTen = N'Họ Tên Đã Sửa', @DiaChi = N'Địa chỉ mới, Hà Nội';
ROLLBACK TRAN;
GO
BEGIN TRY   -- mã sinh viên không tồn tại
    EXEC dbo.sp_CapNhatSinhVien @MaSV = '00000000', @HoTen = N'Không có';
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS MaLoi, ERROR_MESSAGE() AS ThongBao;
END CATCH
GO

-- 9. sp_XoaSinhVien: xóa được sinh viên chưa đăng ký môn nào (rồi hoàn tác); bị từ chối nếu đã có đăng ký
BEGIN TRAN;
    EXEC dbo.sp_XoaSinhVien @MaSV = '24010016';
ROLLBACK TRAN;
GO
BEGIN TRY
    EXEC dbo.sp_XoaSinhVien @MaSV = '24010001';
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS MaLoi, ERROR_MESSAGE() AS ThongBao;
END CATCH
GO

-- 10. sp_HuyDangKy: đăng ký rồi hủy ngay khi chưa có điểm (hoàn tác); bị từ chối nếu đã có điểm
BEGIN TRAN;
    EXEC dbo.sp_DangKyHocPhan @MaSV = '24010016', @MaLHP = 'CNTT110-HK1-2627-01';
    EXEC dbo.sp_HuyDangKy     @MaSV = '24010016', @MaLHP = 'CNTT110-HK1-2627-01';
ROLLBACK TRAN;
GO
BEGIN TRY
    EXEC dbo.sp_HuyDangKy @MaSV = '24010001', @MaLHP = 'CNTT101-HK1-2425-01';
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS MaLoi, ERROR_MESSAGE() AS ThongBao;
END CATCH
GO

-- 11. sp_TimSinhVien
EXEC dbo.sp_TimSinhVien @TuKhoa = N'nguyen';                                 -- tìm không dấu
EXEC dbo.sp_TimSinhVien @MaKhoa = 'NN', @TrangThai = N'Đang học', @Top = 10;  -- lọc theo khoa và trạng thái
GO

-- 12. sp_MoLopHocPhan: mở lớp CNTT109 cho giảng viên chưa dạy lớp nào (rồi hoàn tác) và 1 trường hợp bị từ chối
BEGIN TRAN;
    EXEC dbo.sp_MoLopHocPhan @MaMH = 'CNTT109', @MaHK = 'HK1-2627', @MaGV = 'GVCNTT08', @PhongHoc = 'A101';
ROLLBACK TRAN;
GO
BEGIN TRY   -- giảng viên CNTT mở môn của khoa Ngoại ngữ
    EXEC dbo.sp_MoLopHocPhan @MaMH = 'NN101', @MaHK = 'HK1-2627', @MaGV = 'GVCNTT08';
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS MaLoi, ERROR_MESSAGE() AS ThongBao;
END CATCH
GO

-- 13. sp_DemoGiaoDich: COMMIT rồi ROLLBACK (mỗi lần chạy tự dọn dữ liệu demo)
EXEC dbo.sp_DemoGiaoDich @GayLoi = 0;   -- thấy 1 dòng ở node CNTT và 1 dòng ở TongHop
EXEC dbo.sp_DemoGiaoDich @GayLoi = 1;   -- lỗi trùng CCCD -> cả hai nơi đều 0 dòng
GO

-- 14. sp_PhanBoDuLieu
EXEC dbo.sp_PhanBoDuLieu;
GO

-- Đếm: phải đúng 14 thủ tục do file này tạo
SELECT COUNT(*) AS SoThuTuc FROM sys.procedures WHERE name LIKE N'sp[_]%';
GO
