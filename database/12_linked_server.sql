/* =====================================================================
   ĐỒ ÁN CSDL PHÂN TÁN – QUẢN LÝ SINH VIÊN NHIỀU KHOA
   File   : 12_linked_server.sql
   Mục đích: Tạo Linked Server LS_LOCAL (loopback: trỏ về chính máy chủ này) để minh họa
             truy vấn tên 4 phần  LinkedServer.Database.Schema.Table.
   Người viết: ...............          Ngày: ..../11/2026
   Chạy sau : 10_security.sql (cần tài khoản lg_daotao)     Chạy lại nhiều lần được.
   Cần quyền sysadmin.

   VÌ SAO LOOPBACK: cả 4 node đang là 4 database trên cùng một instance, nên Linked Server
   trỏ về chính nó. Với instance thứ hai thật, chỉ cần đổi @datasrc trong phần 1.

   KẾT NỐI: LS_LOCAL đăng nhập lại bằng SQL login lg_daotao (Phòng Đào tạo) nên cần SQL Server
   bật chế độ đăng nhập hỗn hợp (xem docs/HuongDan.md, mục 1.2). Nếu không bật được,
   dùng thay thế: sp_addlinkedsrvlogin @rmtsrvname = N'LS_LOCAL', @useself = N'TRUE'
   (đi bằng chính Windows login đang chạy; không cần mật khẩu).

   GIAO DỊCH: lệnh GHI qua Linked Server trong BEGIN TRAN sẽ cần MSDTC (dịch vụ điều phối giao
   dịch phân tán), dễ lỗi khi demo. Vì vậy file này chỉ ĐỌC qua Linked Server; demo
   COMMIT/ROLLBACK dùng tên 3 phần (11_transactions_concurrency.sql).
   ===================================================================== */

SET NOCOUNT ON;
GO
USE master;
GO

/* =====================================================================
   PHẦN 1. TẠO LINKED SERVER – thử lần lượt các provider cho đến khi kết nối được
   ===================================================================== */
DECLARE @srv SYSNAME = @@SERVERNAME, @prov SYSNAME, @ok BIT = 0;
DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT prov FROM (VALUES (1, N'MSOLEDBSQL19'), (2, N'MSOLEDBSQL'), (3, N'SQLNCLI11')) v(thu_tu, prov)
    ORDER BY thu_tu;
OPEN c;
FETCH NEXT FROM c INTO @prov;
WHILE @@FETCH_STATUS = 0 AND @ok = 0
BEGIN
    BEGIN TRY
        IF EXISTS (SELECT 1 FROM sys.servers WHERE name = N'LS_LOCAL')
            EXEC sp_dropserver @server = N'LS_LOCAL', @droplogins = 'droplogins';

        EXEC sp_addlinkedserver @server = N'LS_LOCAL', @srvproduct = N'', @provider = @prov,
             @datasrc = @srv, @provstr = N'TrustServerCertificate=yes';
        EXEC sp_serveroption @server = N'LS_LOCAL', @optname = N'rpc out', @optvalue = N'true';
        EXEC sp_addlinkedsrvlogin @rmtsrvname = N'LS_LOCAL', @useself = N'FALSE', @locallogin = NULL,
             @rmtuser = N'lg_daotao', @rmtpassword = N'Xe9$Lm47#2026p';

        EXEC sp_testlinkedserver N'LS_LOCAL';       -- lỗi nếu provider thiếu hoặc đăng nhập sai
        SET @ok = 1;
        PRINT N'LS_LOCAL đã sẵn sàng, provider = ' + @prov;
    END TRY
    BEGIN CATCH
        PRINT N'Provider ' + @prov + N' không dùng được: ' + ERROR_MESSAGE();
    END CATCH
    FETCH NEXT FROM c INTO @prov;
END
CLOSE c;
DEALLOCATE c;

IF @ok = 0
BEGIN
    IF EXISTS (SELECT 1 FROM sys.servers WHERE name = N'LS_LOCAL')
        EXEC sp_dropserver @server = N'LS_LOCAL', @droplogins = 'droplogins';
    THROW 50120, N'Không tạo được LS_LOCAL: kiểm tra đã chạy 10_security.sql (login lg_daotao), SQL Server bật đăng nhập hỗn hợp và đã cài OLE DB provider.', 1;
END
GO

SELECT name AS LinkedServer, provider, data_source, is_rpc_out_enabled
FROM sys.servers WHERE name = N'LS_LOCAL';
GO

/* =====================================================================
   PHẦN 2. TRUY VẤN TÊN 4 PHẦN
   Gợi ý: bật Actual Execution Plan (Ctrl+M) để thấy toán tử "Remote Query" cho chứng cứ.
   ===================================================================== */
USE QLSV_TongHop;
GO

-- Câu 1. Đọc một node qua tên 4 phần: 5 sinh viên đầu của khoa CNTT.
SELECT TOP (5) MaSV, HoTen, MaLop
FROM LS_LOCAL.QLSV_CNTT.dbo.SinhVien
ORDER BY MaSV;
GO

-- Câu 2. Gộp 3 node bằng tên 4 phần rồi so với VIEW toàn cục: hai con số phải bằng nhau.
SELECT (SELECT COUNT(*) FROM (
            SELECT MaSV FROM LS_LOCAL.QLSV_CNTT.dbo.SinhVien
            UNION ALL SELECT MaSV FROM LS_LOCAL.QLSV_NgoaiNgu.dbo.SinhVien
            UNION ALL SELECT MaSV FROM LS_LOCAL.QLSV_DuLich.dbo.SinhVien) x) AS SoSV_QuaLinkedServer,
       (SELECT COUNT(*) FROM dbo.vw_SinhVien_ToanCuc)                          AS SoSV_QuaViewToanCuc;
GO

-- Câu 3. JOIN bảng ở Linked Server với bảng cục bộ ở TongHop: lớp học phần HK1-2627 của khoa Du lịch kèm tên môn.
SELECT lp.MaLHP, m.TenMH, lp.MaGV, lp.SiSoToiDa
FROM LS_LOCAL.QLSV_DuLich.dbo.LopHocPhan lp
JOIN dbo.MonHoc m ON m.MaMH = lp.MaMH
WHERE lp.MaHK = 'HK1-2627'
ORDER BY lp.MaLHP;
GO

-- Câu 4. OPENQUERY: câu truy vấn chạy NGUYÊN BÊN node (lọc ở xa, chỉ trả về kết quả) - thường nhanh hơn tên 4 phần.
SELECT * FROM OPENQUERY(LS_LOCAL,
    'SELECT MaLHP, COUNT(*) AS SoSVDangKy
     FROM QLSV_NgoaiNgu.dbo.DangKy
     GROUP BY MaLHP
     HAVING COUNT(*) >= 10');
GO

-- Câu 5. Chạy lệnh từ xa bằng EXEC ... AT (cần tùy chọn rpc out đã bật ở trên).
EXEC (N'SELECT COUNT(*) AS SoDangKyOKhoaCNTT FROM QLSV_CNTT.dbo.DangKy') AT LS_LOCAL;
GO

-- Câu 6. Thống kê toàn trường qua Linked Server: điểm tổng kết trung bình của mỗi khoa ở HK2-2526.
SELECT x.TenKhoa, CAST(AVG(x.DiemTK) AS DECIMAL(4,2)) AS DiemTB, COUNT(x.DiemTK) AS SoLuotCoDiem
FROM (
    SELECT N'CNTT' AS TenKhoa, dk.DiemTK
    FROM LS_LOCAL.QLSV_CNTT.dbo.DangKy dk JOIN LS_LOCAL.QLSV_CNTT.dbo.LopHocPhan lp ON lp.MaLHP = dk.MaLHP
    WHERE lp.MaHK = 'HK2-2526'
    UNION ALL
    SELECT N'NN', dk.DiemTK
    FROM LS_LOCAL.QLSV_NgoaiNgu.dbo.DangKy dk JOIN LS_LOCAL.QLSV_NgoaiNgu.dbo.LopHocPhan lp ON lp.MaLHP = dk.MaLHP
    WHERE lp.MaHK = 'HK2-2526'
    UNION ALL
    SELECT N'DL', dk.DiemTK
    FROM LS_LOCAL.QLSV_DuLich.dbo.DangKy dk JOIN LS_LOCAL.QLSV_DuLich.dbo.LopHocPhan lp ON lp.MaLHP = dk.MaLHP
    WHERE lp.MaHK = 'HK2-2526'
) x
GROUP BY x.TenKhoa
ORDER BY x.TenKhoa;
GO

-- Thông tin đăng nhập của Linked Server (bằng chứng cấu hình)
EXEC sp_helplinkedsrvlogin @rmtsrvname = N'LS_LOCAL';
GO
