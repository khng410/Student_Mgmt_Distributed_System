/* =====================================================================
   ĐỒ ÁN CSDL PHÂN TÁN – QUẢN LÝ SINH VIÊN NHIỀU KHOA
   File   : 14_demo_vai_tro.sql
   Mục đích: Demo sự khác nhau giữa các vai trò. Chạy NGUYÊN file này 4 lần, mỗi lần đăng nhập bằng
             một tài khoản khác (lg_admin, lg_daotao, lg_giaovu_cntt, lg_bgh), rồi so 4 bảng kết quả.
   Đăng nhập: server localhost, cổng 14330 (instance điều phối), SQL Server authentication,
              database QLSV_TongHop. Mật khẩu: docs/HuongDan.md, mục 1.
   Không thay đổi dữ liệu: mọi lệnh ghi nằm trong giao dịch rồi ROLLBACK.
   Không nằm trong scripts/trien_khai.py (file này phải chạy bằng từng tài khoản, không chạy bằng sa).
   ===================================================================== */

SET NOCOUNT ON;
SET XACT_ABORT ON;          -- ghi vào node khác instance trong giao dịch cần dòng này
GO
USE QLSV_TongHop;
GO

DECLARE @kq TABLE (STT INT, ThuLam NVARCHAR(120), KetQua NVARCHAR(200));
DECLARE @n INT;
DECLARE @bo TABLE (a NVARCHAR(4000) NULL, b NVARCHAR(4000) NULL, c NVARCHAR(4000) NULL,
                   d NVARCHAR(4000) NULL, e NVARCHAR(4000) NULL, f NVARCHAR(4000) NULL);   -- nuốt kết quả của thủ tục

-- 1. Danh sách sinh viên qua view toàn cục (3 node gộp lại)
BEGIN TRY
    SELECT @n = COUNT(*) FROM dbo.vw_SinhVien_ToanCuc;
    INSERT @kq VALUES (1, N'Xem danh sách sinh viên (vw_SinhVien_ToanCuc)', N'Được: ' + CAST(@n AS NVARCHAR) + N' sinh viên');
END TRY
BEGIN CATCH INSERT @kq VALUES (1, N'Xem danh sách sinh viên (vw_SinhVien_ToanCuc)', N'BỊ TỪ CHỐI (lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR) + N')'); END CATCH

-- 2. Thống kê theo khoa và học kỳ
BEGIN TRY
    SELECT @n = COUNT(DISTINCT MaKhoa) FROM dbo.vw_ThongKe_Khoa_HocKy;
    INSERT @kq VALUES (2, N'Xem thống kê (vw_ThongKe_Khoa_HocKy)', N'Được: thấy ' + CAST(@n AS NVARCHAR) + N' khoa');
END TRY
BEGIN CATCH INSERT @kq VALUES (2, N'Xem thống kê (vw_ThongKe_Khoa_HocKy)', N'BỊ TỪ CHỐI (lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR) + N')'); END CATCH

-- 3. Bảng điểm chi tiết từng sinh viên
BEGIN TRY
    SELECT @n = COUNT(*) FROM dbo.vw_BangDiem;
    INSERT @kq VALUES (3, N'Xem bảng điểm chi tiết (vw_BangDiem)', N'Được: ' + CAST(@n AS NVARCHAR) + N' lượt điểm');
END TRY
BEGIN CATCH INSERT @kq VALUES (3, N'Xem bảng điểm chi tiết (vw_BangDiem)', N'BỊ TỪ CHỐI (lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR) + N')'); END CATCH

-- 4. Hồ sơ nhạy cảm (CCCD, điện thoại, địa chỉ) qua view
BEGIN TRY
    SELECT @n = COUNT(CCCD) FROM dbo.vw_SinhVien_DayDu;
    INSERT @kq VALUES (4, N'Xem CCCD qua view (vw_SinhVien_DayDu)', N'Được: ' + CAST(@n AS NVARCHAR) + N' hồ sơ');
END TRY
BEGIN CATCH INSERT @kq VALUES (4, N'Xem CCCD qua view (vw_SinhVien_DayDu)', N'BỊ TỪ CHỐI (lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR) + N')'); END CATCH

-- 5. Đọc thẳng bảng nhạy cảm, không qua view
BEGIN TRY
    SELECT @n = COUNT(*) FROM dbo.SinhVien_HoSo;
    INSERT @kq VALUES (5, N'Đọc thẳng bảng SinhVien_HoSo', N'Được: ' + CAST(@n AS NVARCHAR) + N' dòng');
END TRY
BEGIN CATCH INSERT @kq VALUES (5, N'Đọc thẳng bảng SinhVien_HoSo', N'BỊ TỪ CHỐI (lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR) + N')'); END CATCH

-- 6. Nhập điểm cho sinh viên khoa CNTT (rồi hoàn tác)
BEGIN TRY
    BEGIN TRAN;
        INSERT @bo EXEC dbo.sp_NhapDiem @MaSV = '24010001', @MaLHP = 'CNTT110-HK1-2627-01', @DiemQT = 9;
    ROLLBACK;
    INSERT @kq VALUES (6, N'Nhập điểm sinh viên khoa CNTT (sp_NhapDiem)', N'Được (đã hoàn tác)');
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    INSERT @kq VALUES (6, N'Nhập điểm sinh viên khoa CNTT (sp_NhapDiem)', N'BỊ TỪ CHỐI (lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR) + N'): ' + LEFT(ERROR_MESSAGE(), 80));
END CATCH

-- 7. Nhập điểm cho sinh viên khoa Ngoại ngữ (rồi hoàn tác)
BEGIN TRY
    BEGIN TRAN;
        INSERT @bo EXEC dbo.sp_NhapDiem @MaSV = '24020001', @MaLHP = 'NN110-HK1-2627-01', @DiemQT = 9;
    ROLLBACK;
    INSERT @kq VALUES (7, N'Nhập điểm sinh viên khoa Ngoại ngữ (sp_NhapDiem)', N'Được (đã hoàn tác)');
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    INSERT @kq VALUES (7, N'Nhập điểm sinh viên khoa Ngoại ngữ (sp_NhapDiem)', N'BỊ TỪ CHỐI (lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR) + N'): ' + LEFT(ERROR_MESSAGE(), 80));
END CATCH

-- 8. Sửa cấu trúc CSDL: tạo một bảng (rồi hoàn tác)
BEGIN TRY
    BEGIN TRAN;
        EXEC (N'CREATE TABLE dbo.ThuQuyen (x INT)');
    ROLLBACK;
    INSERT @kq VALUES (8, N'Tạo bảng mới (sửa cấu trúc CSDL)', N'Được (đã hoàn tác)');
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    INSERT @kq VALUES (8, N'Tạo bảng mới (sửa cấu trúc CSDL)', N'BỊ TỪ CHỐI (lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR) + N')');
END CATCH

SELECT SUSER_SNAME() AS DangNhapBang, STT, ThuLam, KetQua FROM @kq ORDER BY STT;
GO
