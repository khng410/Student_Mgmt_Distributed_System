/* =====================================================================
   ĐỒ ÁN CSDL PHÂN TÁN – QUẢN LÝ SINH VIÊN NHIỀU KHOA
   File   : 04_fragmentation.sql
   Mục đích: Chuyển dữ liệu từ CSDL TẬP TRUNG (QLSV_TapTrung) sang các mảnh
             ở 4 node, rồi KIỂM TRA ghép các mảnh lại = dữ liệu gốc.
   Người viết: ...............          Ngày: ..../11/2026
   Chạy sau : 03_seed_data.sql            Chạy lại nhiều lần được (xóa mảnh cũ rồi nạp lại).

   TIÊU CHÍ PHÂN MẢNH
   ---------------------------------------------------------------------
   NHÂN BẢN   Khoa, HocKy, MonHoc    : bản chính ở TongHop, chép nguyên xuống 3 node.
                                       Lý do: bảng nhỏ, ít đổi, đọc nhiều -> mọi khóa
                                       ngoại trong node khoa là khóa ngoại cục bộ.
   NGANG CHÍNH  GiangVien, Lop       : lọc trực tiếp theo MaKhoa.
   NGANG DẪN XUẤT
                SinhVien   <- theo Lop        (Lop.MaKhoa của lớp sinh viên đó)
                LopHocPhan <- theo GiangVien  (khoa của giảng viên mở lớp)
                DangKy     <- theo SinhVien   (khoa của sinh viên đăng ký)
   DỌC          SinhVien : học vụ  (MaSV, HoTen, NgaySinh, GioiTinh, MaLop, TrangThai)
                                                                  -> 3 node khoa
                SinhVien_HoSo : nhạy cảm (MaSV, CCCD, DienThoai, Email, DiaChi)
                                                                  -> TongHop
   Cả hai mảnh dọc giữ MaSV làm khóa chung để JOIN lại.

   TÁI THIẾT
     bảng ngang  = UNION ALL của 3 node
     SinhVien    = (SV_CNTT ∪ SV_NN ∪ SV_DL) JOIN SinhVien_HoSo ON MaSV
   Phần KIỂM TRA ở cuối file chứng minh: không thiếu, không thừa, không trùng.
   ===================================================================== */

SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
USE master;
GO

/* =====================================================================
   PHẦN 1. PHÂN MẢNH – tất cả trong 1 transaction: lỗi ở đâu cũng ROLLBACK
   ===================================================================== */

DECLARE @node TABLE (db SYSNAME, k VARCHAR(10));
INSERT @node VALUES (N'QLSV_CNTT', 'CNTT'), (N'QLSV_NgoaiNgu', 'NN'), (N'QLSV_DuLich', 'DL');

-- Khuôn lệnh cho 1 node khoa; {DB} và {K} được thay bằng từng dòng của @node.
DECLARE @tpl NVARCHAR(MAX) = N'
-- tắt trigger (09_triggers.sql) khi nạp hàng loạt: tránh ghi NhatKy rác và kiểm tra sai thứ tự
ALTER TABLE {DB}.dbo.DangKy     DISABLE TRIGGER ALL;
ALTER TABLE {DB}.dbo.LopHocPhan DISABLE TRIGGER ALL;
ALTER TABLE {DB}.dbo.SinhVien   DISABLE TRIGGER ALL;
ALTER TABLE {DB}.dbo.Lop        DISABLE TRIGGER ALL;
ALTER TABLE {DB}.dbo.GiangVien  DISABLE TRIGGER ALL;

DELETE {DB}.dbo.DangKy;  DELETE {DB}.dbo.LopHocPhan;  DELETE {DB}.dbo.SinhVien;
DELETE {DB}.dbo.Lop;     DELETE {DB}.dbo.GiangVien;
DELETE {DB}.dbo.MonHoc;  DELETE {DB}.dbo.HocKy;       DELETE {DB}.dbo.Khoa;

-- nhân bản danh mục từ bản chính ở TongHop
INSERT {DB}.dbo.Khoa   SELECT * FROM QLSV_TongHop.dbo.Khoa;
INSERT {DB}.dbo.HocKy  SELECT * FROM QLSV_TongHop.dbo.HocKy;
INSERT {DB}.dbo.MonHoc SELECT * FROM QLSV_TongHop.dbo.MonHoc;

-- ngang chính
INSERT {DB}.dbo.GiangVien SELECT * FROM QLSV_TapTrung.dbo.GiangVien WHERE MaKhoa = ''{K}'';
INSERT {DB}.dbo.Lop       SELECT * FROM QLSV_TapTrung.dbo.Lop       WHERE MaKhoa = ''{K}'';

-- ngang dẫn xuất + dọc (mảnh học vụ)
INSERT {DB}.dbo.SinhVien (MaSV, HoTen, NgaySinh, GioiTinh, MaLop, TrangThai)
SELECT sv.MaSV, sv.HoTen, sv.NgaySinh, sv.GioiTinh, sv.MaLop, sv.TrangThai
FROM QLSV_TapTrung.dbo.SinhVien sv
JOIN QLSV_TapTrung.dbo.Lop l ON l.MaLop = sv.MaLop
WHERE l.MaKhoa = ''{K}'';

INSERT {DB}.dbo.LopHocPhan
SELECT lp.*
FROM QLSV_TapTrung.dbo.LopHocPhan lp
JOIN QLSV_TapTrung.dbo.GiangVien g ON g.MaGV = lp.MaGV
WHERE g.MaKhoa = ''{K}'';

-- DiemTK là cột tính toán nên không chép
INSERT {DB}.dbo.DangKy (MaSV, MaLHP, NgayDangKy, DiemQT, DiemThi)
SELECT dk.MaSV, dk.MaLHP, dk.NgayDangKy, dk.DiemQT, dk.DiemThi
FROM QLSV_TapTrung.dbo.DangKy dk
JOIN QLSV_TapTrung.dbo.SinhVien sv ON sv.MaSV = dk.MaSV
JOIN QLSV_TapTrung.dbo.Lop l       ON l.MaLop = sv.MaLop
WHERE l.MaKhoa = ''{K}'';

ALTER TABLE {DB}.dbo.DangKy     ENABLE TRIGGER ALL;
ALTER TABLE {DB}.dbo.LopHocPhan ENABLE TRIGGER ALL;
ALTER TABLE {DB}.dbo.SinhVien   ENABLE TRIGGER ALL;
ALTER TABLE {DB}.dbo.Lop        ENABLE TRIGGER ALL;
ALTER TABLE {DB}.dbo.GiangVien  ENABLE TRIGGER ALL;
';
DECLARE @db SYSNAME, @k VARCHAR(10), @sql NVARCHAR(MAX);

IF NOT EXISTS (SELECT 1 FROM QLSV_TapTrung.dbo.SinhVien)
    THROW 50000, N'QLSV_TapTrung chưa có dữ liệu: hãy chạy 03_seed_data.sql trước.', 1;

BEGIN TRY
    BEGIN TRAN;

    /* --- Node điều phối TongHop: bản chính danh mục (mảnh dọc hồ sơ nạp SAU 3 node khoa) --- */
    ALTER TABLE QLSV_TongHop.dbo.SinhVien_HoSo DISABLE TRIGGER ALL;
    DELETE QLSV_TongHop.dbo.SinhVien_HoSo;
    DELETE QLSV_TongHop.dbo.MonHoc;
    DELETE QLSV_TongHop.dbo.HocKy;
    DELETE QLSV_TongHop.dbo.Khoa;

    INSERT QLSV_TongHop.dbo.Khoa   SELECT * FROM QLSV_TapTrung.dbo.Khoa;
    INSERT QLSV_TongHop.dbo.HocKy  SELECT * FROM QLSV_TapTrung.dbo.HocKy;
    INSERT QLSV_TongHop.dbo.MonHoc SELECT * FROM QLSV_TapTrung.dbo.MonHoc;

    PRINT N'Đã nạp QLSV_TongHop (danh mục)';

    /* --- 3 node khoa --- */
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT db, k FROM @node;
    OPEN c;
    FETCH NEXT FROM c INTO @db, @k;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @sql = REPLACE(REPLACE(@tpl, N'{DB}', @db), N'{K}', @k);
        EXEC (@sql);
        PRINT N'Đã phân mảnh sang ' + @db + N' (MaKhoa = ' + @k + N')';
        FETCH NEXT FROM c INTO @db, @k;
    END
    CLOSE c;
    DEALLOCATE c;

    /* --- Mảnh dọc hồ sơ: nạp sau khi SinhVien ở 3 node đã có (trigger kiểm tra MaSV cần điều này) --- */
    INSERT QLSV_TongHop.dbo.SinhVien_HoSo (MaSV, CCCD, DienThoai, Email, DiaChi)
    SELECT MaSV, CCCD, DienThoai, Email, DiaChi FROM QLSV_TapTrung.dbo.SinhVien;
    ALTER TABLE QLSV_TongHop.dbo.SinhVien_HoSo ENABLE TRIGGER ALL;
    PRINT N'Đã nạp QLSV_TongHop.SinhVien_HoSo';

    COMMIT;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    THROW;
END CATCH
GO


/* =====================================================================
   PHẦN 2. KIỂM TRA TÁI THIẾT: ghép các mảnh phải bằng dữ liệu tập trung
     Thieu      = dòng có ở bản tập trung nhưng mất ở các mảnh
     Thua       = dòng có ở các mảnh nhưng không có ở bản tập trung
     LechSoDong = (số dòng gốc) - (số dòng sau khi ghép); khác 0 nghĩa là trùng/thiếu
   Cả 3 cột phải = 0 thì KetQua = OK.
   ===================================================================== */

DROP TABLE IF EXISTS #kq;
CREATE TABLE #kq (KiemTra NVARCHAR(100), Thieu INT, Thua INT, LechSoDong INT);

DECLARE @chk TABLE (nhan NVARCHAR(100), goc NVARCHAR(MAX), ghep NVARCHAR(MAX));

-- Bản sao danh mục ở cả 4 node phải giống bản gốc
INSERT @chk
SELECT t.n + N' @ ' + d.db,
       N'SELECT * FROM QLSV_TapTrung.dbo.' + t.n,
       N'SELECT * FROM ' + d.db + N'.dbo.' + t.n
FROM (VALUES (N'Khoa'), (N'HocKy'), (N'MonHoc')) t(n)
CROSS JOIN (VALUES (N'QLSV_TongHop'), (N'QLSV_CNTT'), (N'QLSV_NgoaiNgu'), (N'QLSV_DuLich')) d(db);

-- Mảnh ngang: UNION ALL 3 node = bảng gốc
INSERT @chk
SELECT t.n + N' = CNTT ∪ NN ∪ DL',
       N'SELECT * FROM QLSV_TapTrung.dbo.' + t.n,
       N'SELECT * FROM QLSV_CNTT.dbo.' + t.n
     + N' UNION ALL SELECT * FROM QLSV_NgoaiNgu.dbo.' + t.n
     + N' UNION ALL SELECT * FROM QLSV_DuLich.dbo.' + t.n
FROM (VALUES (N'GiangVien'), (N'Lop'), (N'LopHocPhan'), (N'DangKy')) t(n);

-- Mảnh dọc: (UNION ALL 3 node) JOIN SinhVien_HoSo = SinhVien gốc
INSERT @chk VALUES (
    N'SinhVien = (CNTT ∪ NN ∪ DL) JOIN SinhVien_HoSo',
    N'SELECT MaSV, HoTen, NgaySinh, GioiTinh, MaLop, TrangThai, CCCD, DienThoai, Email, DiaChi
      FROM QLSV_TapTrung.dbo.SinhVien',
    N'SELECT s.MaSV, s.HoTen, s.NgaySinh, s.GioiTinh, s.MaLop, s.TrangThai,
             h.CCCD, h.DienThoai, h.Email, h.DiaChi
      FROM (SELECT * FROM QLSV_CNTT.dbo.SinhVien
            UNION ALL SELECT * FROM QLSV_NgoaiNgu.dbo.SinhVien
            UNION ALL SELECT * FROM QLSV_DuLich.dbo.SinhVien) s
      JOIN QLSV_TongHop.dbo.SinhVien_HoSo h ON h.MaSV = s.MaSV');

DECLARE @nhan NVARCHAR(100), @goc NVARCHAR(MAX), @ghep NVARCHAR(MAX), @q NVARCHAR(MAX);
DECLARE c2 CURSOR LOCAL FAST_FORWARD FOR SELECT nhan, goc, ghep FROM @chk;
OPEN c2;
FETCH NEXT FROM c2 INTO @nhan, @goc, @ghep;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @q = N'INSERT #kq SELECT N''' + @nhan + N''',
        (SELECT COUNT(*) FROM (' + @goc + N' EXCEPT SELECT * FROM (' + @ghep + N') r) a),
        (SELECT COUNT(*) FROM (SELECT * FROM (' + @ghep + N') r EXCEPT ' + @goc + N') b),
        (SELECT COUNT(*) FROM (' + @goc + N') g) - (SELECT COUNT(*) FROM (' + @ghep + N') h)';
    EXEC (@q);
    FETCH NEXT FROM c2 INTO @nhan, @goc, @ghep;
END
CLOSE c2;
DEALLOCATE c2;

SELECT KiemTra, Thieu, Thua, LechSoDong,
       CASE WHEN Thieu = 0 AND Thua = 0 AND LechSoDong = 0 THEN N'OK' ELSE N'LOI' END AS KetQua
FROM #kq;

IF EXISTS (SELECT 1 FROM #kq WHERE Thieu <> 0 OR Thua <> 0 OR LechSoDong <> 0)
    THROW 50001, N'Phân mảnh sai: có dòng thiếu/thừa/trùng, xem bảng KiemTra phía trên.', 1;
GO


/* =====================================================================
   PHẦN 3. MINH HỌA – dữ liệu nằm ở node nào (dùng cho báo cáo và demo)
   ===================================================================== */

SELECT N'GiangVien' AS Bang,
       (SELECT COUNT(*) FROM QLSV_TapTrung.dbo.GiangVien) AS TapTrung, NULL AS TongHop,
       (SELECT COUNT(*) FROM QLSV_CNTT.dbo.GiangVien)     AS CNTT,
       (SELECT COUNT(*) FROM QLSV_NgoaiNgu.dbo.GiangVien) AS NgoaiNgu,
       (SELECT COUNT(*) FROM QLSV_DuLich.dbo.GiangVien)   AS DuLich
UNION ALL SELECT N'Lop',
       (SELECT COUNT(*) FROM QLSV_TapTrung.dbo.Lop), NULL,
       (SELECT COUNT(*) FROM QLSV_CNTT.dbo.Lop),
       (SELECT COUNT(*) FROM QLSV_NgoaiNgu.dbo.Lop),
       (SELECT COUNT(*) FROM QLSV_DuLich.dbo.Lop)
UNION ALL SELECT N'SinhVien (mảnh học vụ)',
       (SELECT COUNT(*) FROM QLSV_TapTrung.dbo.SinhVien), NULL,
       (SELECT COUNT(*) FROM QLSV_CNTT.dbo.SinhVien),
       (SELECT COUNT(*) FROM QLSV_NgoaiNgu.dbo.SinhVien),
       (SELECT COUNT(*) FROM QLSV_DuLich.dbo.SinhVien)
UNION ALL SELECT N'SinhVien_HoSo (mảnh dọc nhạy cảm)',
       NULL, (SELECT COUNT(*) FROM QLSV_TongHop.dbo.SinhVien_HoSo), NULL, NULL, NULL
UNION ALL SELECT N'LopHocPhan',
       (SELECT COUNT(*) FROM QLSV_TapTrung.dbo.LopHocPhan), NULL,
       (SELECT COUNT(*) FROM QLSV_CNTT.dbo.LopHocPhan),
       (SELECT COUNT(*) FROM QLSV_NgoaiNgu.dbo.LopHocPhan),
       (SELECT COUNT(*) FROM QLSV_DuLich.dbo.LopHocPhan)
UNION ALL SELECT N'DangKy',
       (SELECT COUNT(*) FROM QLSV_TapTrung.dbo.DangKy), NULL,
       (SELECT COUNT(*) FROM QLSV_CNTT.dbo.DangKy),
       (SELECT COUNT(*) FROM QLSV_NgoaiNgu.dbo.DangKy),
       (SELECT COUNT(*) FROM QLSV_DuLich.dbo.DangKy);
GO

-- Một sinh viên được ghép lại từ 2 mảnh dọc ở 2 database khác nhau
SELECT TOP (3) s.MaSV, s.HoTen, s.MaLop, h.CCCD, h.Email
FROM QLSV_CNTT.dbo.SinhVien s
JOIN QLSV_TongHop.dbo.SinhVien_HoSo h ON h.MaSV = s.MaSV
ORDER BY s.MaSV;
GO
