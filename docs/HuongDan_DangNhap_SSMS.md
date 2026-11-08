# Hướng dẫn đăng nhập SSMS bằng tài khoản của hệ thống

Dùng để kiểm tra các tài khoản tạo trong `database/10_security.sql` có đăng nhập được và đúng quyền không.
Mật khẩu của từng tài khoản nằm trong phần 1 của `10_security.sql`.

| Login | Vai trò |
| --- | --- |
| `lg_admin` | Quản trị |
| `lg_daotao` | Phòng Đào tạo |
| `lg_giaovu_cntt`, `lg_giaovu_nn`, `lg_giaovu_dl` | Giáo vụ khoa CNTT, Ngoại ngữ, Du lịch |
| `lg_bgh` | Ban giám hiệu |

## 1. Đăng nhập

1. Trong SSMS bấm **Connect → Database Engine**.
2. Điền:
   - **Server name:** tên máy chủ bạn vẫn dùng (ví dụ `localhost` hoặc `localhost\SQLEXPRESS`).
   - **Authentication:** **SQL Server Authentication** (không chọn Windows Authentication).
   - **Login / Password:** tài khoản và mật khẩu cần thử.
3. Bấm **Connect**. Nên mở kết nối này tách riêng với kết nối quản trị của bạn.

Nếu SSMS báo `The certificate chain was issued by an authority that is not trusted`, bấm **Options >>** ở hộp thoại Connect và đánh dấu **Trust server certificate**.

## 2. Lỗi `Login failed` (18456, state 58): máy chủ chỉ cho Windows Authentication

Kiểm tra bằng kết nối quản trị:

```sql
SELECT SERVERPROPERTY('IsIntegratedSecurityOnly');   -- 1 = chỉ Windows, 0 = đã bật hỗn hợp
```

Nếu kết quả là 1, bật chế độ hỗn hợp:

1. Object Explorer: chuột phải tên máy chủ → **Properties → Security**.
2. Chọn **SQL Server and Windows Authentication mode** → OK.
3. Khởi động lại dịch vụ SQL Server (chuột phải tên máy chủ → **Restart**).

Các nguyên nhân khác: sai mật khẩu, login bị khóa (`is_disabled = 1`), chưa chạy `10_security.sql`.

## 3. Kiểm tra quyền sau khi vào được

Chạy trong cửa sổ Query của kết nối đó. `SELECT SUSER_NAME();` cho biết đang dùng tài khoản nào.

| Đăng nhập bằng | Chạy | Kết quả mong đợi |
| --- | --- | --- |
| `lg_giaovu_cntt` | `SELECT TOP 3 * FROM QLSV_TongHop.dbo.vw_SinhVien_ToanCuc;` | Có dữ liệu |
| `lg_giaovu_cntt` | `SELECT TOP 1 CCCD FROM QLSV_TongHop.dbo.vw_SinhVien_DayDu;` | Lỗi 229 (không có quyền) |
| `lg_daotao` | `SELECT TOP 3 MaSV, CCCD FROM QLSV_TongHop.dbo.vw_SinhVien_DayDu;` | Có dữ liệu |
| `lg_daotao` | `SELECT TOP 1 CCCD FROM QLSV_TongHop.dbo.SinhVien_HoSo;` | Lỗi 229 (chỉ được đọc qua VIEW) |
| `lg_bgh` | `SELECT * FROM QLSV_TongHop.dbo.vw_ThongKe_Khoa_HocKy;` | Có dữ liệu |
| `lg_bgh` | `SELECT TOP 1 * FROM QLSV_TongHop.dbo.vw_BangDiem;` | Lỗi 229 |

## 4. Lưu ý

- Tài khoản bị giới hạn có thể không thấy đầy đủ cây trong Object Explorer (ví dụ danh sách database). Bình thường; vẫn chạy được câu truy vấn trong cửa sổ Query.
- Khi chạy `11_transactions_concurrency.sql` (nhiều cửa sổ, mỗi cửa sổ một phiên) hãy dùng tài khoản quản trị của bạn. Các tài khoản `lg_*` chỉ để kiểm thử phân quyền và để ứng dụng đăng nhập.
- Mật khẩu trong `10_security.sql` chỉ để chạy thử trên máy cá nhân. Đổi trước khi dùng thật.
