# Hướng dẫn kiểm tra Linked Server (`database/12_linked_server.sql`)

## Chuẩn bị (một lần)

- Đã chạy `10_security.sql` (cần login `lg_daotao`).
- SQL Server bật chế độ đăng nhập hỗn hợp: `SELECT SERVERPROPERTY('IsIntegratedSecurityOnly');` phải trả 0.
  Nếu trả 1, xem mục 2 trong `HuongDan_DangNhap_SSMS.md`.
- Kết nối bằng tài khoản quản trị (cần quyền `sysadmin`).

## Chạy

1. Mở `12_linked_server.sql` trong SSMS, bấm F5 chạy cả file.
2. Xem tab **Messages** trước, rồi các tab kết quả.

## Kết quả mong đợi

| Chỗ xem | Mong đợi |
| --- | --- |
| Messages | Dòng `LS_LOCAL đã sẵn sàng, provider = ...`. Vài dòng `Provider ... không dùng được` trước đó là bình thường nếu máy thiếu provider đời mới. |
| Bảng sau phần 1 | 1 dòng `LS_LOCAL`, `is_rpc_out_enabled = 1` |
| Câu 1 | 5 sinh viên khoa CNTT |
| Câu 2 | `SoSV_QuaLinkedServer = SoSV_QuaViewToanCuc = 72` (hai số phải bằng nhau) |
| Câu 3 | Lớp học phần HK1-2627 của khoa Du lịch kèm tên môn |
| Câu 4 | Lớp học phần khoa Ngoại ngữ có từ 10 sinh viên trở lên |
| Câu 5 | 1 dòng: số đăng ký của khoa CNTT |
| Câu 6 | 3 dòng (CNTT, DL, NN) với điểm trung bình |
| Dòng cuối | Bảng ánh xạ đăng nhập của `LS_LOCAL` (`lg_daotao`) |

## Kiểm tra thủ công thêm

```sql
EXEC sp_testlinkedserver N'LS_LOCAL';                  -- không lỗi là kết nối được
SELECT COUNT(*) FROM LS_LOCAL.QLSV_CNTT.dbo.DangKy;    -- một câu tên 4 phần chạy tay
```

Với câu 3 và 4 bật **Actual Execution Plan** (Ctrl+M) trước khi chạy: trong plan phải có toán tử
**Remote Query** hoặc **Remote Scan**. Chụp ảnh làm bằng chứng demo (mục 7 của đề), đặt vào `images/`
theo tên như `12_linked_server.png`.

## Nếu lỗi

| Dấu hiệu | Nguyên nhân thường gặp |
| --- | --- |
| `Không tạo được LS_LOCAL` | Cả 3 provider thất bại; đọc các dòng `Provider ... không dùng được` ở Messages |
| `Login failed for user 'lg_daotao'` | Chưa chạy `10_security.sql`, hoặc chưa bật chế độ đăng nhập hỗn hợp |
| Lỗi chứng chỉ (certificate) | Chuỗi kết nối cần `TrustServerCertificate=yes` (script đã có); thử provider khác |
| Lỗi khác | Chép nguyên văn dòng đỏ ở Messages |
