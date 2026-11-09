# Hướng dẫn đo hiệu năng và index (PHẦN E của `database/11_transactions_concurrency.sql`)

Mục đích: có bằng chứng cho yêu cầu kỹ thuật số 12 và demo mục 6 của đề (Actual Execution Plan + giải thích tác dụng của index).

## Chạy

1. Mở `11_transactions_concurrency.sql`, chạy từ dòng `PHẦN E` đến hết file (chọn đoạn rồi chạy). Các khối blocking và deadlock ở giữa nằm trong comment nên chạy cả file cũng an toàn.
2. **E1** (bảng thử 300.000 dòng ở tempdb): tự tạo, đo và xóa; không đụng dữ liệu thật.
3. **E2**: tạo index thật `IX_DangKy_MaLHP` trên `DangKy(MaLHP)` ở 3 node. Chạy lại `02_create_tables.sql` thì index mất, chạy lại E2.

## Kết quả mong đợi (đã đo trên SQL Server Docker)

| Truy vấn | Toán tử trong kế hoạch (cột `StmtText`) | Số trang đã đọc (`logical reads`) |
| --- | --- | --- |
| A. Lọc theo `MaLHP`, chưa có index | Clustered Index Scan | 1753 |
| B. Lọc theo `MaSV` (đầu khóa chính) | Clustered Index Seek | 3 |
| A. Lọc theo `MaLHP`, sau khi tạo index | Index Seek | 3 |

Số cụ thể có thể lệch vài đơn vị tùy máy; điều cần thấy là Scan → Seek và số trang giảm hàng trăm lần.
Trong tab Messages có thêm một dòng `logical reads` khi tạo index (đọc cả bảng để dựng index); đó là chi phí tạo, không phải của truy vấn.

## Cách chụp ảnh

- **SSMS:** bấm Ctrl+M (Include Actual Execution Plan) trước khi chạy E1. Tab "Execution plan" hiện sơ đồ: chụp sơ đồ truy vấn A trước và sau.
- **Công cụ khác (SQLPro...):** kế hoạch thực tế đã hiện dạng bảng chữ (STATISTICS PROFILE), chụp cột `StmtText` có "Clustered Index Scan" và "Index Seek". Số trang đọc ở tab Messages.
- Đặt ảnh vào `images/`, tên ví dụ `11_plan_truoc.png`, `11_plan_sau.png`, `11_logical_reads.png`.

## Giải thích ngắn khi vấn đáp

- Khóa chính `(MaSV, MaLHP)` sắp dữ liệu theo `MaSV` trước, nên lọc theo `MaLHP` không dùng được để tìm nhanh: phải quét cả bảng.
- Index trên `MaLHP` cho phép nhảy thẳng tới các dòng của lớp đó (Seek). `INCLUDE (DiemTK)` giúp truy vấn không phải quay lại bảng gốc.
- Truy vấn B không cần index mới vì đã seek bằng khóa chính. Index chỉ có ích khi khớp cách truy vấn thật sự dùng bảng.
- Cái giá: INSERT/UPDATE/DELETE chậm hơn một chút và tốn dung lượng.
- Trong hệ thống này, `MaLHP` được lọc ở `fn_SiSoLopHocPhan`, `sp_DangKyHocPhan` và trigger kiểm tra sĩ số; SQL Server không tự tạo index cho khóa ngoại.
