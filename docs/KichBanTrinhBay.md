# Kịch bản trình bày: Quản lý sinh viên nhiều khoa – CSDL phân tán

Thời lượng gợi ý: **20 phút trình bày + demo**, sau đó hỏi đáp. Mỗi phần ghi: **Nói** (ý chính), **Làm** (thao tác),
**Thấy** (kết quả đúng phải hiện ra). Mọi con số dưới đây đã chạy thử trên dữ liệu mẫu.

---

## 0. Chuẩn bị (tối nay và 15 phút trước giờ)

**Tối nay, tập một lần toàn bộ**, đặc biệt phần blocking/deadlock (mục 6) vì cần 2 cửa sổ.

**Trước giờ trình bày:**

```
docker compose up -d                  # đợi docker compose ps: 4 container (healthy), khoảng 1 phút
python3 -I scripts/trien_khai.py      # dữ liệu về đúng dữ liệu mẫu, cuối cùng in "XONG"
python3 -I scripts/kiem_tra_demo.py   # phải in "Tất cả đều đúng."
cd app && bash chay.sh                # ứng dụng ở http://localhost:8501
```

**Mở sẵn:**

| Cửa sổ | Nội dung |
| --- | --- |
| Trình duyệt tab 1 | `images/kien_truc_phan_tan.svg` (sơ đồ kiến trúc) |
| Trình duyệt tab 2 | Ứng dụng `http://localhost:8501`, chưa đăng nhập |
| Docker Desktop | Trang Containers (4 container `qlsv_*` màu xanh) |
| SQLPro / SSMS | 5 kết nối tới `localhost,14330`, database `QLSV_TongHop`: `sa`, `lg_admin`, `lg_daotao`, `lg_giaovu_cntt`, `lg_bgh` |
| SQLPro, kết nối `sa` | Mở sẵn các file `12_linked_server.sql`, `11_transactions_concurrency.sql`, `13_dong_bo_kiem_thu.sql`, `14_demo_vai_tro.sql` |
| Terminal | Ở thư mục gốc dự án |

**Phương án dự phòng:** nếu Docker hoặc máy gặp sự cố, dùng ảnh chụp trong `images/` và báo cáo Word. Không sửa lỗi trước mặt
giảng viên quá 1 phút; chuyển sang ảnh rồi giải thích.

---

## 1. Mở đầu (1 phút)

**Nói:**
- Đề tài: quản lý sinh viên của trường có 3 khoa (CNTT, Ngoại ngữ, Du lịch). Mỗi khoa tự quản lý giảng viên, lớp, sinh viên,
  lớp học phần, điểm; Phòng Đào tạo cần xem toàn trường và giữ hồ sơ cá nhân nhạy cảm.
- Vì vậy dữ liệu được **phân tán theo khoa**, đặt ở **4 SQL Server riêng biệt**, nối với nhau bằng **Linked Server**.
- Nhóm đi từ thiết kế **tập trung** (9 bảng, 3NF) rồi phân mảnh sang các node, và chứng minh ghép lại đúng bằng bản gốc.

---

## 2. Kiến trúc (3 phút)

**Làm:** mở sơ đồ `kien_truc_phan_tan.svg`, rồi Docker Desktop.

**Nói:**
- 4 instance SQL Server 2022, mỗi instance một container Docker: điều phối (cổng 14330) và 3 node khoa (14331–14333).
  Đây là instance thật, có tiến trình, bộ nhớ và dữ liệu riêng, không phải 4 database trên một máy chủ.
- **Node điều phối** giữ: bản chính danh mục (Khoa, HocKy, MonHoc), mảnh dọc nhạy cảm `SinhVien_HoSo`, 5 view toàn cục,
  14 thủ tục, 8 hàm, phân quyền. Ứng dụng chỉ nói chuyện với node này.
- **3 node khoa** giữ dữ liệu của khoa mình và bản sao danh mục.
- Điều phối có 3 Linked Server `LS_QLSV_CNTT`, `LS_QLSV_NgoaiNgu`, `LS_QLSV_DuLich`. Thêm **database đại diện** chứa synonym,
  nên câu lệnh viết `QLSV_CNTT.dbo.SinhVien` thực chất chạy sang instance khác. Ghi vào nhiều node trong một giao dịch dùng MSDTC.

**Làm:** chạy **phần 1 và 2** của `12_linked_server.sql` (kết nối `sa`).

**Thấy:** 3 Linked Server trỏ tới 3 máy chủ khác nhau; bảng phần 2 có **4 tên máy chủ khác nhau** (`qlsv_tonghop`, `qlsv_cntt`,
`qlsv_ngoaingu`, `qlsv_dulich`), số dòng 72 / 24 / 24 / 24.

**Nói:** mỗi dòng do chính instance đó tự báo tên của nó, đây là bằng chứng dữ liệu nằm ở 4 nơi.

---

## 3. Phân mảnh và tái thiết (3 phút)

**Làm:** mở bảng "Bảng phân mảnh, vị trí lưu trữ và nhân bản" trong README.

**Nói:**
- **Nhân bản toàn bộ**: Khoa, HocKy, MonHoc (nhỏ, ít đổi, đọc nhiều; node có khóa ngoại cục bộ).
- **Ngang chính** theo MaKhoa: GiangVien, Lop. **Ngang dẫn xuất**: SinhVien theo Lop, LopHocPhan theo GiangVien, DangKy theo SinhVien.
- **Dọc**: SinhVien tách thành học vụ (ở node khoa) và hồ sơ nhạy cảm CCCD, điện thoại, địa chỉ (ở điều phối), chung khóa MaSV.

**Làm:** ứng dụng → đăng nhập **Phòng Đào tạo** → trang **Phân tán** → mục "Dữ liệu nằm ở đâu".

**Thấy:** bảng số dòng từng node: GiangVien 8+8+8 = 24, SinhVien 24+24+24 = 72, DangKy 207×3 = 621, cột "Khớp" toàn **OK**.

**Nói:** ba tính chất của phân mảnh đều được kiểm tra trong `04_fragmentation.sql` phần 2: **đầy đủ** (Thiếu = 0),
**không trùng** (Thừa = 0, lệch số dòng = 0), **tái thiết** (UNION ALL các mảnh ngang, JOIN hai mảnh dọc = bản gốc).

**Làm:** mục "Một sinh viên, hai mảnh", chọn một sinh viên.

**Thấy:** sơ đồ tô đậm node của khoa; hai thẻ: học vụ ở `QLSV_CNTT`, hồ sơ CCCD ở `QLSV_TongHop`.

---

## 4. Truy vấn liên nút và tổng hợp toàn hệ thống (2 phút)

**Làm:** chạy câu 2, 4, 7, 9 của `12_linked_server.sql`.

**Thấy:**
- Câu 2: `72 | 72` – gộp 3 node bằng tên 4 phần bằng đúng view toàn cục.
- Câu 4: học vụ từ node CNTT ghép CCCD từ điều phối (JOIN giữa 2 instance).
- Câu 7: điểm trung bình từng khoa HK2-2526, mỗi khoa từ một instance.
- Câu 9: toàn trường 72 sinh viên, 621 lượt đăng ký.

**Nói:** `06_queries_40.sql` có 40 truy vấn theo 8 nhóm của đề, 30 câu đánh dấu `[PT]` là truy vấn phân tán.

---

## 5. Thủ tục, hàm, trigger (3 phút)

**Làm:** ứng dụng → đăng xuất → đăng nhập **Quản trị** → trang **Kiểm thử** → **Chạy cả 13 ca**.

**Thấy:** `13/13 ca đã chạy ĐÚNG`. Mở 1–2 ca cho xem "Mong đợi", "Thực tế", câu SQL.

**Nói:**
- 5 ca hàm so **hai cách tính độc lập** (ví dụ điểm TB tích lũy từ hàm và tính tay từ bảng điểm), không so với số viết sẵn.
- 5 trigger chặn lỗi (mã 50901–50905) chạy ngay trên node. Trên giao diện bình thường không chạy tới được vì thủ tục đã chặn trước:
  trigger là hàng rào thứ hai khi có người ghi thẳng vào bảng.

**Làm:** bật **Mô phỏng lỗi**, bấm **Chạy** ở ca `trg_SinhVien_ChanXoa`.

**Thấy:** ❌ SAI, Thực tế: lỗi 547 (khóa ngoại).

**Nói:** khi tắt trigger, phép kiểm tra phát hiện ngay, nên kết quả ĐÚNG là đáng tin. Lỗi 547 cho thấy còn lớp bảo vệ thứ hai là
khóa ngoại. Trigger được tắt trong giao dịch thử nên ROLLBACK bật lại, dữ liệu không đổi.

**Làm:** tắt Mô phỏng lỗi, chạy lại ca đó → ✅.

---

## 6. Giao dịch và đồng thời (4 phút)

**Làm:** `12_linked_server.sql` **phần 5**.

**Thấy:** `Trong giao dịch | 9.00 | 9.00` rồi `Sau ROLLBACK | 8.10 | 5.70`.

**Nói:** một giao dịch sửa 2 instance (CNTT và Ngoại ngữ), MSDTC điều phối; ROLLBACK hủy cả hai.

**Làm:** `11_transactions_concurrency.sql` **phần A**.

**Thấy:** A1 `Sau COMMIT | 1 | 1`; A2 lỗi 2627 (trùng CCCD) rồi `Sau ROLLBACK | 0 | 0`.

**Nói:** lệnh thứ nhất ở node CNTT đã chạy xong nhưng vẫn bị hủy vì lệnh thứ hai ở điều phối lỗi: tính nguyên tử.

**Làm (blocking, 2 cửa sổ):** phần B trong comment: cửa sổ 1 UPDATE không commit; cửa sổ 2 UPDATE cùng dòng → bị treo;
cửa sổ 1 chạy phần **D**.

**Thấy:** D1: phiên bị chặn chờ `LCK_M_U`, cột Node = `qlsv_cntt`; D2: khóa `X` GRANT và `U` WAIT. Cửa sổ 1 ROLLBACK → cửa sổ 2 chạy tiếp.

**Nói (deadlock, phần C):** hai instance mỗi bên chỉ thấy khóa của mình nên **không tự phát hiện deadlock phân tán** (không có lỗi
1205 như khi cùng một máy chủ); dùng `LOCK_TIMEOUT` để phiên chờ tự báo lỗi 1222. (Chỉ demo nếu tối nay đã tập thành công.)

**Làm:** phần **E** (index).

**Thấy:** trước index `Clustered Index Scan`, 1753 trang; sau index `Index Seek`, 3 trang.

---

## 7. Đồng bộ và khi một node mất kết nối (3 phút)

**Làm:** `13_dong_bo_kiem_thu.sql` **kịch bản 5** (sửa danh mục ở trung tâm).

**Thấy:** sau UPDATE ở điều phối, 3 bản sao **chưa đổi**; sau `sp_DongBoDanhMuc`, cả 4 nơi giống nhau; ROLLBACK về như cũ.

**Nói:** dữ liệu phân mảnh mỗi dòng chỉ có một bản nên không cần đồng bộ; thêm, sửa, xóa, chuyển khoa sinh viên ghi cả hai mảnh
dọc trong một giao dịch (kịch bản 1–4). Chỉ danh mục nhân bản cần đồng bộ, làm bằng `sp_DongBoDanhMuc`.

**Làm (nếu còn thời gian, khoảng 2 phút):** terminal `python3 -I scripts/thu_mat_ket_noi.py`.

**Thấy:** dừng node Du lịch: đọc node còn sống vẫn được; view toàn cục, thêm sinh viên, giao dịch chạm node vắng **lỗi và bị hủy,
không ghi dở**; bật lại node, đồng bộ lại, bản sao khớp (`0` dòng lệch), view trả lại 72 sinh viên.

**Nói (nếu không chạy):** bảng "Khi một node mất kết nối" trong README tóm tắt kết quả đã đo.

---

## 8. Phân quyền (2 phút)

**Làm:** chạy `14_demo_vai_tro.sql` ở 4 kết nối `lg_admin`, `lg_daotao`, `lg_giaovu_cntt`, `lg_bgh`; xếp 4 bảng cạnh nhau.

**Thấy:**

| Thử làm | Quản trị | Đào tạo | Giáo vụ CNTT | Ban giám hiệu |
| --- | --- | --- | --- | --- |
| Xem danh sách sinh viên | 72 | 72 | **24** | từ chối |
| Xem thống kê | 3 khoa | 3 khoa | **1 khoa** | 3 khoa |
| Đọc thẳng `SinhVien_HoSo` | được | **từ chối** | từ chối | từ chối |
| Nhập điểm SV Ngoại ngữ | được | được | **từ chối** | từ chối |
| Tạo bảng mới | **được** | từ chối | từ chối | từ chối |

**Nói:** quản trị khác đào tạo ở quyền sửa cấu trúc; đào tạo xem CCCD qua view nhưng bị DENY đọc thẳng bảng; giáo vụ bị lọc theo
khoa; Ban giám hiệu chỉ xem thống kê. Quyền do SQL Server kiểm soát, ứng dụng chỉ ẩn bớt menu.

---

## 9. Ứng dụng (1–2 phút, có thể gộp vào các phần trên)

**Làm:** đăng nhập **Giáo vụ khoa CNTT** → menu chỉ còn 4 chức năng; Thống kê chỉ có khoa CNTT. Trang **Nhập điểm** sửa một điểm →
trang Nhật ký (đăng nhập Đào tạo) thấy dòng UPDATE do trigger ghi, có điểm cũ, điểm mới và người sửa.

---

## 10. Kết luận và giới hạn (1 phút)

**Nói:**
- Đã đáp ứng: 3 node trên instance riêng, Linked Server, sơ đồ kiến trúc, truy vấn liên nút và tổng hợp, phân mảnh và tái thiết
  có kiểm chứng, đồng bộ, xử lý mất kết nối, thủ tục, hàm, trigger, giao dịch phân tán, đồng thời, hiệu năng, phân quyền, ứng dụng.
- Giới hạn tự nhận (README, "Giới hạn đã biết"):
  - Không có chuỗi sở hữu giữa các instance nên người dùng cần quyền đọc ở node; nối thẳng vào cổng node sẽ bỏ qua lọc theo khoa.
    Hướng sửa: chỉ mở cổng điều phối cho người dùng, hoặc chuyển view thành thủ tục `EXECUTE AS`.
  - Deadlock giữa các instance không tự phát hiện; dùng `LOCK_TIMEOUT`.
  - Đồng bộ danh mục chạy tay; chưa có hàng đợi ghi bù khi node vắng.

---

## Hỏi đáp: câu hỏi có thể gặp

| Câu hỏi | Trả lời ngắn |
| --- | --- |
| Sao không đặt 4 database trên 1 máy chủ cho đơn giản? | Đề yêu cầu instance riêng; 4 container là 4 tiến trình SQL Server độc lập, giao tiếp qua mạng như máy thật. |
| Synonym và database đại diện để làm gì? | Để view, thủ tục viết bằng tên 3 phần chạy được với node ở instance khác; synonym trỏ tới `LS_x.QLSV_x.dbo.Bang`. |
| Khóa ngoại giữa `SinhVien_HoSo` và `SinhVien` thế nào? | SQL Server không có khóa ngoại giữa database/instance; thay bằng trigger `trg_HoSo_KiemTraSinhVien` (lỗi 50905). |
| Vì sao chọn nhân bản cho Khoa, HocKy, MonHoc? | Bảng nhỏ, ít đổi, đọc nhiều; node có khóa ngoại cục bộ, không phải truy vấn liên nút khi kiểm tra. |
| Ghi vào 2 node làm sao đảm bảo cả hai cùng thành công? | `SET XACT_ABORT ON` + giao dịch phân tán qua MSDTC; một bên lỗi thì cả giao dịch ROLLBACK (demo phần 6). |
| Một node chết thì sao? | Phần dữ liệu ở node khác vẫn đọc được; thao tác chạm node chết lỗi và bị hủy, không ghi dở; bật lại rồi đồng bộ danh mục (mục 7). |
| Làm sao biết kết quả demo là đúng? | `scripts/kiem_tra_demo.py` đối chiếu 52 điểm; trang Kiểm thử có chế độ mô phỏng lỗi chứng minh phép kiểm tra bắt được sai. |
| Vì sao Azure SQL Edge không dùng được? | Không hỗ trợ Linked Server; dùng image `mssql/server:2022` (trên Mac Apple Silicon chạy qua giả lập amd64). |
| Chuyển khoa sinh viên thì dữ liệu đi đâu? | Học vụ xóa ở node cũ, thêm ở node mới trong một giao dịch; hồ sơ ở điều phối giữ nguyên MaSV. Chặn nếu đã có đăng ký. |
