# Tài khoản, quyền hạn và đổi mật khẩu

Nguồn quyền: `database/10_security.sql`. Đăng nhập thử: xem `HuongDan_DangNhap_SSMS.md`.

## 1. Quyền của từng tài khoản

| Tài khoản | Ở `QLSV_TongHop` | Ở 3 node khoa | Trang trong app |
| --- | --- | --- | --- |
| `lg_admin` | `db_owner` | `db_owner` | Tất cả 9 trang |
| `lg_daotao` | Xem mọi view và hàm; chạy mọi thủ tục; **không** đọc thẳng bảng `SinhVien_HoSo` (chỉ qua `vw_SinhVien_DayDu`); không ghi trực tiếp | Đọc/ghi mọi bảng | Tất cả 9 trang |
| `lg_giaovu_cntt`, `_nn`, `_dl` | Chỉ 4 view không nhạy cảm + 2 hàm bảng, **và chỉ thấy dữ liệu khoa mình**; chạy 4 thủ tục (tìm sinh viên, bảng điểm, thống kê, nhập điểm); **không** xem `vw_SinhVien_DayDu`; không ghi | **Chỉ node khoa mình**: đọc mọi bảng, sửa riêng `DiemQT` và `DiemThi`, không xóa. Node khoa khác: không có quyền | Thống kê, Tìm kiếm, Bảng điểm, Nhập điểm (tất cả chỉ với khoa mình) |
| `lg_bgh` | Chỉ `vw_ThongKe_Khoa_HocKy` và `sp_ThongKeKhoa`; không ghi | Không có quyền | Thống kê |

Lưu ý:
- `lg_admin` **không** phải `sysadmin` của máy chủ: là chủ 5 database nhưng không tạo, sửa, xóa được login khác.
- Giáo vụ chỉ thấy dữ liệu khoa mình ở mọi nơi, ngay trong SQL Server: `vw_SinhVien_ToanCuc` và `vw_DangKy_ToanCuc` lọc theo hàm `dbo.PhamViKhoaCuaToi()` (xem `05_views.sql`); `vw_BangDiem`, `vw_ThongKe_Khoa_HocKy`, các hàm và thủ tục đều đọc qua hai view đó nên tự bị lọc. Giáo vụ CNTT gọi `sp_NhapDiem` hay `sp_BangDiemSinhVien` cho sinh viên khoa khác sẽ nhận "Không tìm thấy sinh viên", tìm kiếm và thống kê khoa khác trả rỗng. Quyền `UPDATE` điểm chỉ ở node khoa mình là lớp bảo vệ thứ hai.
- Thêm giáo vụ mới: thêm một dòng vào hàm `dbo.PhamViKhoaCuaToi()` trong `05_views.sql`, rồi cấp quyền như các giáo vụ khác ở `10_security.sql`.
- Tên các trang trong app chỉ là lớp ẩn bớt chức năng; quyền thật do SQL Server kiểm soát.

Xem lại quyền đang có: chạy PHẦN 7 trong `10_security.sql` (thành viên role và danh sách GRANT/DENY).

## 2. Đổi mật khẩu

Dùng tài khoản `sysadmin` (trong Docker thường là `sa`, tài khoản dùng trong SQLPro):

```sql
ALTER LOGIN lg_giaovu_cntt WITH PASSWORD = N'MatKhauMoi#2026a';
```

Mật khẩu mới phải đạt chính sách: ít nhất 8 ký tự, có ít nhất 3 trong 4 loại (hoa, thường, số, ký hiệu), không chứa tên đăng nhập.

Chính tài khoản đó tự đổi được, kèm mật khẩu cũ:

```sql
ALTER LOGIN lg_giaovu_cntt WITH PASSWORD = N'MatKhauMoi#2026a', OLD_PASSWORD = N'MatKhauCu';
```

Việc đi kèm sau khi đổi:

- **Sửa mật khẩu trong `10_security.sql`.** Chạy lại file này không đặt lại mật khẩu cho login đã tồn tại, nên file chỉ là ghi chép; nên sửa cho khớp.
- **Nếu đổi mật khẩu `lg_daotao`**, Linked Server `LS_LOCAL` sẽ không đăng nhập được vì `12_linked_server.sql` lưu mật khẩu cũ. Cập nhật:

  ```sql
  EXEC sp_addlinkedsrvlogin @rmtsrvname = N'LS_LOCAL', @useself = N'FALSE', @locallogin = NULL,
       @rmtuser = N'lg_daotao', @rmtpassword = N'MatKhauMoi#2026a';
  ```

  hoặc sửa mật khẩu trong `12_linked_server.sql` rồi chạy lại file.

## 3. Kiểm tra thay đổi đã được lưu

Mật khẩu nằm trong database hệ thống `master` dưới dạng băm một chiều (không xem lại được bản gốc), không nằm trong các database `QLSV_*`. Kiểm tra bằng tài khoản `sysadmin`:

```sql
-- (a) Mật khẩu được đặt lại lúc nào
SELECT name, LOGINPROPERTY(name, 'PasswordLastSetTime') AS DoiMatKhauLuc, modify_date
FROM sys.sql_logins WHERE name LIKE N'lg[_]%';

-- (b) Mật khẩu mới có khớp bản băm đang lưu không (1 = khớp)
SELECT name, PWDCOMPARE(N'MatKhauMoi#2026a', password_hash) AS Khop
FROM sys.sql_logins WHERE name = N'lg_giaovu_cntt';
```

(c) Cách thuyết phục nhất: đăng nhập thử bằng mật khẩu mới (SQLPro hoặc màn hình đăng nhập của app); mật khẩu cũ phải bị từ chối với lỗi `Login failed`.
