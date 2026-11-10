/* =====================================================================
   ĐỒ ÁN CSDL PHÂN TÁN – QUẢN LÝ SINH VIÊN NHIỀU KHOA
   File   : 13_dong_bo_kiem_thu.sql
   Mục đích: KIỂM THỬ ĐỒNG BỘ. Đổi dữ liệu ở MỘT nơi rồi đọc kết quả ở các nơi còn lại
             (điều phối + 3 node khoa, 4 instance khác nhau).
   Chạy sau : 12_linked_server.sql, trên instance điều phối (cổng 14330), tài khoản sysadmin.
   Chạy lại nhiều lần được; mọi thay đổi đều ROLLBACK, dữ liệu mẫu giữ nguyên.

   CƠ CHẾ ĐỒNG BỘ CỦA HỆ THỐNG (cái được kiểm thử ở đây)
   * Bảng PHÂN MẢNH (SinhVien, GiangVien, Lop, LopHocPhan, DangKy): mỗi dòng chỉ có MỘT bản, nên không có
     gì để đồng bộ giữa các bản. Riêng SinhVien tách dọc thành 2 mảnh (học vụ ở node khoa, hồ sơ ở điều phối)
     nên các thủ tục sp_ThemSinhVien, sp_CapNhatSinhVien, sp_XoaSinhVien, sp_ChuyenKhoa ghi cả hai mảnh
     trong MỘT giao dịch phân tán: hoặc cả hai đổi, hoặc không đổi gì.
   * Bảng NHÂN BẢN (Khoa, HocKy, MonHoc): bản chính ở điều phối, bản sao ở 3 node. Sửa ở điều phối KHÔNG
     tự lan xuống; sp_DongBoDanhMuc chép xuống (sửa dòng khác, thêm dòng thiếu, không xóa). Trigger
     trg_LopHocPhan_KiemTraMonHoc chặn giảng viên mở lớp cho môn của khoa khác (kiểm tra bằng dữ liệu của chính node).

   Mỗi kịch bản in 2 bảng: TRƯỚC và SAU, cột là các nơi lưu dữ liệu.
   ===================================================================== */

SET NOCOUNT ON;
SET XACT_ABORT ON;      -- bắt buộc khi sửa bảng ở node khác instance trong BEGIN TRAN
GO
USE QLSV_TongHop;
GO

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
    DECLARE @truoc TABLE (Noi NVARCHAR(30), DiemTong DECIMAL(12,2));
    INSERT @truoc
    SELECT N'CNTT', SUM(DiemThi) FROM QLSV_CNTT.dbo.DangKy
    UNION ALL SELECT N'Ngoại ngữ', SUM(DiemThi) FROM QLSV_NgoaiNgu.dbo.DangKy
    UNION ALL SELECT N'Du lịch',   SUM(DiemThi) FROM QLSV_DuLich.dbo.DangKy;

    UPDATE QLSV_CNTT.dbo.DangKy SET DiemThi = DiemThi + 0.5 WHERE MaSV = '24010001' AND MaLHP = 'CNTT101-HK1-2425-01';   -- sửa điểm tại node CNTT

    DECLARE @sau TABLE (Noi NVARCHAR(30), DiemTong DECIMAL(12,2));
    INSERT @sau
    SELECT N'CNTT', SUM(DiemThi) FROM QLSV_CNTT.dbo.DangKy
    UNION ALL SELECT N'Ngoại ngữ', SUM(DiemThi) FROM QLSV_NgoaiNgu.dbo.DangKy
    UNION ALL SELECT N'Du lịch',   SUM(DiemThi) FROM QLSV_DuLich.dbo.DangKy;

    SELECT t.Noi, t.DiemTong AS TongDiemThi_Truoc, s.DiemTong AS TongDiemThi_Sau,
           CASE WHEN t.DiemTong = s.DiemTong THEN N'không đổi' ELSE N'ĐÃ ĐỔI (+0.5)' END AS KetQua
    FROM @truoc t JOIN @sau s ON s.Noi = t.Noi;
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
   KẾT LUẬN: sau toàn bộ kiểm thử, kiểm tra lại tái thiết và bản sao khớp bản chính
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
