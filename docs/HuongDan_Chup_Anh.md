# Hướng dẫn chụp 60 ảnh cho báo cáo

Số hình (1–60) trùng với các khung vàng `[CHỤP ẢNH n]` trong `report/CSDLPT_DoAn_65131461.docx` và Phụ lục A của báo cáo.
Làm theo **thứ tự các giai đoạn dưới đây** (không theo thứ tự số hình) để đỡ chuyển qua lại giữa các công cụ.

## 0. Chuẩn bị chung

**Công cụ**
- Công cụ SQL (SQLPro for MSSQL) nối SQL Server bằng **tài khoản quản trị** (`sa` hoặc tài khoản bạn dùng khi chạy các script).
- Ứng dụng: `cd app && bash chay.sh`, mở `http://localhost:8501`.
- Chụp màn hình trên Mac: `Cmd + Shift + 4` (kéo chọn vùng), `Cmd + Shift + 4` rồi nhấn `Space` (chụp nguyên một cửa sổ), `Cmd + Shift + 5` (thanh công cụ chụp/quay). Ảnh mặc định nằm ở Desktop; đổi tên theo cột "Lưu" rồi chuyển vào thư mục `images/`.

**Dữ liệu sạch (khuyến nghị làm trước khi chụp)**
Các con số mong đợi (72 sinh viên, 621 đăng ký, nhật ký rỗng, mọi dòng `KhopTapTrung = OK`) chỉ đúng khi dữ liệu chưa bị thay đổi bởi các lần thử của bạn (thêm Nguyễn Gia Khánh, sửa điểm...). Nên chạy lại **lần lượt `01` → `10`** (cả `11` phần A và phần E2, và `12`) trước khi bắt đầu. Việc này tạo lại 5 database, nên nhật ký (`NhatKy`) sẽ trống: các thao tác tạo nhật ký để chụp hình 24 và 54 làm **sau** bước này.

**Quy tắc chụp**
1. Chụp **cả câu lệnh lẫn kết quả** khi gọn; kết quả dài thì chụp phần đầu và chừng 10 dòng.
2. Phóng to cửa sổ để thấy đủ các cột, không để thanh cuộn che dữ liệu.
3. **Không để lộ mật khẩu** (ô đăng nhập chỉ hiện dấu chấm, che thanh trạng thái nếu có).
4. Với ảnh chụp **ứng dụng web**: nhớ **cắt bỏ thanh địa chỉ của trình duyệt**, vì địa chỉ chứa mã phiên đăng nhập (`?phien=...`).
5. Dùng cùng một cỡ chữ và kích thước cửa sổ cho các ảnh cùng loại để báo cáo đều.

**Cách chạy một đoạn trong SQLPro:** bôi đen đúng đoạn cần chạy rồi bấm nút Execute (nếu không bôi đen, công cụ chạy cả file). Mỗi kết quả (bảng) có một tab riêng; chuyển tab để chụp từng bảng.
**Mỗi ảnh ghi chú:** "Chạy" = làm gì, "Chụp" = trong khung hình phải có gì, "Mong đợi" = kết quả đúng.

---

## Giai đoạn 1. Chạy các file SQL bằng tài khoản quản trị (hình 1–33)

### Hình 1 – `05_phan_bo_du_lieu.png`
- **Chạy:** mở kết nối `QLSV_TongHop`, chạy `EXEC dbo.sp_PhanBoDuLieu;`
- **Chụp:** cả hai bảng kết quả (bảng số dòng 5 bảng × 3 node + bảng `SinhVien_HoSo`).
- **Mong đợi:** mọi dòng cột `KhopTapTrung = OK`; DangKy 207/207/207, SinhVien 24/24/24.

### Hình 2 – `05_nam_database.png`
- **Chạy:** `SELECT name, collation_name FROM sys.databases WHERE name LIKE 'QLSV%';`
- **Chụp:** bảng 5 dòng (`QLSV_TapTrung`, `QLSV_TongHop`, `QLSV_CNTT`, `QLSV_NgoaiNgu`, `QLSV_DuLich`) cùng collation `Vietnamese_CI_AS`. Có thể thêm danh sách database ở thanh bên của SQLPro.

### Hình 3 – `06_kiem_tra_tai_thiet.png`
- **Chạy:** mở `database/04_fragmentation.sql`, chạy cả file.
- **Chụp:** bảng kết quả đầu tiên có các cột `KiemTra, Thieu, Thua, LechSoDong, KetQua` (khoảng 17 dòng).
- **Mong đợi:** `Thieu = Thua = LechSoDong = 0` và `KetQua = OK` ở mọi dòng. Nếu bảng dài hơn màn hình, chụp 2 ảnh ghép.

### Hình 4 – `06_kiem_tra_view.png`
- **Chạy:** mở `database/05_views.sql`, chạy cả file.
- **Chụp:** bảng 3 dòng `vw_SinhVien_ToanCuc`, `vw_SinhVien_DayDu (tái thiết dọc)`, `vw_DangKy_ToanCuc` với `Thieu` và `Thua` = 0.

### Hình 5 – `06_view_minh_hoa.png`
- **Chạy:** hai câu SELECT trong phần "Ví dụ dùng VIEW" cuối `05_views.sql`: `SELECT TOP (10) * FROM dbo.vw_SinhVien_ToanCuc ...` và `SELECT TOP (5) MaSV, HoTen, CCCD, DienThoai FROM dbo.vw_SinhVien_DayDu ...`
- **Chụp:** hai bảng (hai tab, ghép chung một ảnh hoặc chụp hai lần rồi dán cạnh nhau).
- **Lưu ý:** bảng thứ hai có CCCD thật của dữ liệu mẫu (dữ liệu giả), không phải che.

### Hình 6–13: các câu truy vấn của `06_queries_40.sql`
**Cách làm chung:** mở `database/06_queries_40.sql`, bôi đen từ dòng `-- Câu N ...` đến hết câu lệnh (không gồm dòng `GO`), chạy, chụp mã và bảng kết quả.

| Hình | Lưu | Câu | Mong đợi |
| --- | --- | --- | --- |
| 6 | `07_cau_01.png` | Câu 1 | Danh sách sinh viên nữ đang học, sắp xếp theo khoa, lớp (chụp 10–15 dòng đầu) |
| 7 | `07_cau_09.png` | Câu 9 | 1 dòng: điểm trung bình toàn trường HK2-2526 và số lượt có điểm |
| 8 | `07_cau_13.png` | Câu 13 | 3 dòng (CNTT, Du lịch, Ngoại ngữ), `SiSo = 24` |
| 9 | `07_cau_19.png` | Câu 19 | 5 sinh viên điểm trung bình cao nhất (có thể hơn 5 dòng nếu đồng hạng) |
| 10 | `07_cau_22.png` | Câu 22 | 3 sinh viên chưa đăng ký môn nào (24010016, 24020016, 24030016) |
| 11 | `07_cau_28.png` | Câu 28 | sinh viên học ở cả HK1-2425 và HK1-2627, có tên khoa |
| 12 | `07_cau_30.png` | Câu 30 | **hai bảng**: "Sau INSERT" (1 dòng có CCCD) và "Sau ROLLBACK" (`SoDong = 0`); chụp cả hai tab |
| 13 | `07_cau_37.png` | Câu 37 | các sinh viên học đủ mọi lớp học phần HK1-2425 của khoa mình (dự kiến 6) |

### Hình 14–17: ví dụ chạy của `07_procedures.sql`
Mở `database/07_procedures.sql`, cuộn xuống phần "VÍ DỤ GỌI (EXEC)" ở cuối; chạy **riêng từng khối** (từ dòng `-- N. ...` đến `GO` kế tiếp).

- **Hình 14 – `08_sp_them_sinh_vien.png`:** khối `-- 2. sp_ThemSinhVien` (bảng 1 dòng sinh viên mới) và khối `-- 2b.` (bảng lỗi `MaLoi 2627`, thông báo UNIQUE KEY, rồi bảng `KiemTra ... SoDong = 0`). Chụp cả hai.
- **Hình 15 – `08_sp_chuyen_khoa.png`:** khối `-- 3. sp_ChuyenKhoa` (bảng 3 dòng: Node CNTT = 0, Node NN = 1, Hồ sơ = 1) và khối `-- 3b.` (lỗi "Sinh viên đã có đăng ký học phần ở khoa cũ", mã 50023).
- **Hình 16 – `08_sp_dang_ky_nhap_diem.png`:** các khối `-- 4.` (đăng ký thành công; rồi hai ca lỗi: đã đăng ký và lớp khoa khác) và `-- 5.` (nhập điểm thành công; điểm 11 bị từ chối, 50041). Có thể chụp 2 ảnh ghép.
- **Hình 17 – `08_sp_bang_diem_thong_ke.png`:** khối `-- 6.` (hai bảng: bảng điểm 13 dòng và tổng hợp) và khối `-- 7.` (bảng phân bố học lực).

### Hình 18–20: hàm và view
- **Hình 18 – `08_ham_vo_huong.png`:** mở `database/08_functions.sql`, chạy cả file; chụp bảng `fn_XepLoaiDiem` (7 dòng theo ngưỡng) và bảng điểm TB tích lũy, tín chỉ, xếp loại của lớp `66.CNTT-1`.
- **Hình 19 – `08_ham_tra_ve_bang.png`:** từ kết quả file `08`: `fn_BangDiemSinhVien` (13 dòng), `fn_DanhSachLop('66.NN-1')` (8 dòng), `fn_TopSinhVien` (top 5).
- **Hình 20 – `08_view_bao_cao.png`:** hai câu SELECT cuối `05_views.sql`: `vw_ThongKe_Khoa_HocKy` (15 dòng) và 10 dòng `vw_BangDiem` có `KetQua = Không đạt`.

### Hình 21–24: trigger (`09_triggers.sql`)
Chạy cả file một lần (để cài trigger), rồi trong PHẦN 3 chạy riêng từng khối.
- **Hình 21 – `08_trigger_1.png`:** khối `-- Trigger 1`. Chụp bảng 2 dòng NhatKy: `UPDATE` và `DELETE` với `NoiDungCu`, `NoiDungMoi`.
- **Hình 22 – `08_trigger_2_3.png`:** khối `-- Trigger 2` (lỗi 50901, rồi `SoDong = 0`) và `-- Trigger 3` (lỗi 50902, rồi `SoDong = 0`).
- **Hình 23 – `08_trigger_4_5.png`:** khối `-- Trigger 4` (50905) và `-- Trigger 5` (50903 và 50904, rồi bảng `SiSoToiDa` không còn là 10).
- **Hình 24 – `08_trigger_6_7.png`:** khối cuối `-- Trigger 6 và 7`. Chụp bảng 8 dòng nhật ký (CNTT, NgoaiNgu, TongHop; INSERT, UPDATE, DELETE; CCCD dạng `***0096`) và dòng `SoDong = 0` sau ROLLBACK.

### Hình 25–31: phân quyền (`10_security.sql`)
Chạy cả file `database/10_security.sql` (cần tài khoản sysadmin). Mỗi `EXECUTE AS LOGIN` cho ra các bảng riêng; chụp đúng tab.
- **Hình 25 – `09_quyen_va_role.png`:** ba bảng cuối file: "thành viên các role" (có `rl_DaoTao`, `rl_GiaoVu`, `rl_BGH`) và "quyền đã GRANT / DENY" (có cột `TrangThai = GRANT/DENY`).
- **Hình 26 – `09_grant_nham.png`:** bảng 1 dòng `Sau GRANT nhầm: giáo vụ đọc được CCCD` (có cột `CCCD`).
- **Hình 27 – `09_ca_1_2.png`:** Ca 1 (bảng 3 sinh viên, `DangNhapVoi = lg_giaovu_cntt`) và Ca 2 (hai bảng lỗi `MaLoi 229` cho `vw_SinhVien_DayDu` và `SinhVien_HoSo`).
- **Hình 28 – `09_ca_3_4_5.png`:** Ca 3 (nhập điểm CNTT thành công, bảng điểm), Ca 4 (lỗi "Không tìm thấy sinh viên", 50042), Ca 5 (lỗi 229 khi xóa trực tiếp).
- **Hình 29 – `09_ca_6_7_8.png`:** Ca 6 (3 dòng có CCCD qua view), Ca 7 (lỗi 229 khi đọc thẳng bảng) và Ca 8 (thêm sinh viên bằng thủ tục thành công).
- **Hình 30 – `09_ca_9_10_11.png`:** Ca 9 (thống kê của Ban giám hiệu), Ca 10 (lỗi 229 khi xem `vw_BangDiem`), Ca 11 (các bảng phạm vi khoa: chỉ có CNTT; `sp_ThongKeKhoa @MaKhoa='NN'` rỗng; lỗi "Không tìm thấy sinh viên").
- **Hình 31 – `09_dang_nhap_giaovu.png`:** trong SQLPro tạo **kết nối mới**: Authentication = SQL Server Authentication, Login = `lg_giaovu_cntt` (mật khẩu ở phần 1 của `10_security.sql`, **che mật khẩu khi chụp**). Chạy `SELECT SUSER_NAME();` rồi `SELECT TOP 3 * FROM QLSV_TongHop.dbo.vw_SinhVien_ToanCuc;`. Chụp cửa sổ có tên đăng nhập và kết quả. Nếu đăng nhập lỗi, xem `docs/HuongDan_DangNhap_SSMS.md`.

### Hình 32–33: giao dịch (`11_transactions_concurrency.sql`, phần A)
- **Hình 32 – `10_a1_commit.png`:** chạy khối `-- A1. COMMIT`. Chụp bảng `Sau COMMIT` với `DongOTNodeCNTT = 1`, `DongOTongHop = 1`.
- **Hình 33 – `10_a2_rollback.png`:** chạy khối `-- A2. ROLLBACK`. Chụp ba bảng: `Sau INSERT thứ nhất` (1), thông báo lỗi UNIQUE KEY và `Sau ROLLBACK` (cả hai cột = 0).

---

## Giai đoạn 2. Blocking và deadlock: cần hai cửa sổ (hình 34–39)

**Chuẩn bị:** mở **hai cửa sổ SQLPro, mỗi cửa sổ một kết nối riêng** (mở lại ứng dụng hoặc `File > New Window` rồi kết nối lại) bằng tài khoản quản trị, đặt cạnh nhau trên màn hình. Ở mỗi cửa sổ chạy `SELECT @@SPID;`: hai số phải **khác nhau**. Nếu giống nhau, chúng đang dùng chung một phiên và sẽ không bị chặn.
**Mở file:** `database/11_transactions_concurrency.sql`; các khối B, C nằm trong comment `/* ... */`, hãy chép nội dung từng bước ra cửa sổ rồi chạy.
**Thời gian:** cửa sổ 2 chờ tối đa 120 giây trước khi báo lỗi timeout, nên làm các bước 2–4 liên tục.

### Phần B – blocking
- **Hình 34 – `10_b1_cua_so_1.png`:** cửa sổ 1 chạy "BƯỚC 1" (`SELECT @@SPID; BEGIN TRAN; UPDATE QLSV_CNTT.dbo.DangKy SET DiemThi = 9 WHERE ...`). Chụp cửa sổ 1: có số `@@SPID`, lệnh UPDATE đã chạy xong và **chưa** có COMMIT hay ROLLBACK.
- **Hình 35 – `10_b2_cua_so_2_bi_chan.png`:** cửa sổ 2 chạy "BƯỚC 2" (`BEGIN TRAN; UPDATE ... DiemThi = 8 ...` cùng dòng). Ngay lúc nó **đang chạy không dừng**, chụp cửa sổ 2 (nút Execute đang quay, trạng thái chạy).
- **Hình 36 – `10_d1_blocking.png`:** trong khi cửa sổ 2 còn chờ, ở **cửa sổ 1** chạy truy vấn `D1` (phần D của file). Chụp bảng 1 dòng: `SessionBiChan` = số `@@SPID` của cửa sổ 2, `SessionGayChan` = số của cửa sổ 1, `wait_type = LCK_M_U`, `DB = QLSV_CNTT`.
- **Hình 37 – `10_d2_locks.png`:** vẫn ở cửa sổ 1, chạy truy vấn `D2`. Chụp bảng: phiên của cửa sổ 1 có khóa `X` trạng thái `GRANT` ở `QLSV_CNTT`, phiên của cửa sổ 2 có dòng `WAIT`.
- **Hình 38 – `10_b3_het_chan.png`:** ở cửa sổ 1 chạy `ROLLBACK TRAN;`. Cửa sổ 2 sẽ chạy tiếp ngay; chụp cửa sổ 2 vừa hoàn tất (hết quay). Sau đó chạy `ROLLBACK TRAN;` ở cửa sổ 2 để dữ liệu mẫu nguyên.
- **Lưu ý:** các ảnh 36 và 37 phải chụp **trước** khi ROLLBACK ở cửa sổ 1.

### Phần C – deadlock
- **Hình 39 – `10_c_deadlock_1205.png`:** làm theo "PHẦN C": chạy khối cửa sổ 1 **trước**, rồi **trong 15 giây** chạy khối cửa sổ 2 (cửa sổ 2 đặt `DEADLOCK_PRIORITY LOW` nên là nạn nhân). Chụp **cửa sổ 2** hiện lỗi `Msg 1205 ... was deadlocked on lock resources ... chosen as the deadlock victim`. Có thể chụp thêm cửa sổ 1 chạy xong.
- **Nếu không ra lỗi 1205** (bấm chậm quá 15 giây): chạy lại sau khi `ROLLBACK TRAN;` ở cả hai cửa sổ. Phần C chưa được chạy thử cùng bạn, nếu kết quả khác mô tả hãy báo để chỉnh script.

---

## Giai đoạn 3. Execution plan và index (hình 40–43)

Chạy phần E của `database/11_transactions_concurrency.sql` (từ dòng `PHẦN E` đến hết file). Kế hoạch thực tế có thể xem hai cách:
- **Cách 1 (đã bật sẵn):** `SET STATISTICS PROFILE ON` cho các bảng chữ có cột `StmtText` ghi tên toán tử. Dùng được trong mọi công cụ.
- **Cách 2 (sơ đồ đồ họa):** dùng công cụ có hiển thị kế hoạch thực tế (nếu SQLPro không có, dùng Azure Data Studio hoặc SSMS ở máy Windows): bật Actual Execution Plan rồi chạy cùng đoạn E1.

### Hình 40 – `11_plan_truoc.png`
- **Chụp:** kế hoạch của **truy vấn A lần 1** (thống kê theo `MaLHP`, chưa có index): sơ đồ có toán tử **Clustered Index Scan**, hoặc dòng `StmtText` chứa `Clustered Index Scan(... WHERE: ... MaLHP='LHP05000')`.

### Hình 41 – `11_plan_sau.png`
- **Chụp:** kế hoạch của **truy vấn A lần 2** (sau `CREATE NONCLUSTERED INDEX`): toán tử **Index Seek** (dòng `StmtText` chứa `Index Seek(... SEEK: ... MaLHP='LHP05000')`).

### Hình 42 – `11_logical_reads.png`
- **Chụp:** tab Messages với ba dòng `logical reads` của `#PerfDangKy`: khoảng **1753** (A trước), **3** (B) và **3** (A sau); có thêm một dòng 1753 là lúc tạo index (bình thường). Nếu công cụ không hiện Messages, chạy đoạn này trong Azure Data Studio.

### Hình 43 – `11_index_that.png`
- **Chạy:** phần `E2` (dòng `DECLARE @tpl ...` đến hết).
- **Chụp:** bảng 3 dòng: `QLSV_CNTT`, `QLSV_NgoaiNgu`, `QLSV_DuLich` với `IX_DangKy_MaLHP` loại `NONCLUSTERED`.

---

## Giai đoạn 4. Ứng dụng web (hình 44–54, 57, 58)

**Trước khi bắt đầu:** dữ liệu sạch (mục 0), ứng dụng chạy, trình duyệt cỡ cửa sổ rộng (nên thu nhỏ chữ bằng `Cmd + -` để một trang lọt gần hết màn hình). Cắt bỏ thanh địa chỉ khi chụp. Mật khẩu từng tài khoản ở phần 1 của `database/10_security.sql`.

| Hình | Lưu | Tài khoản, trang | Việc làm và nội dung phải có trong ảnh |
| --- | --- | --- | --- |
| 44 | `12_dang_nhap.png` | chưa đăng nhập | bấm Đăng xuất (hoặc mở cửa sổ ẩn danh): màn hình có tiêu đề, danh sách tài khoản, ô mật khẩu |
| 45 | `12_thong_ke_daotao.png` | `lg_daotao`, Thống kê | các ô số liệu, hai biểu đồ điểm (trục 0–10, vạch đỏ), bảng thanh màu, biểu đồ phân bố học lực của 3 khoa (chụp 2 ảnh nếu dài) |
| 46 | `12_thong_ke_giaovu.png` | `lg_giaovu_cntt`, Thống kê | dòng "Bạn chỉ xem được thống kê của khoa Công nghệ thông tin", biểu đồ và bảng chỉ có CNTT; thanh bên ghi "Bạn chỉ xem và sửa dữ liệu của khoa mình" |
| 47 | `12_tim_kiem.png` | `lg_daotao`, Tìm kiếm | gõ `nguyen`, bấm Tìm: danh sách kết quả, cột Trạng thái tô màu |
| 48 | `12_bang_diem.png` | `lg_daotao`, Bảng điểm | chọn Khoa CNTT, lớp `66.CNTT-1`, sinh viên `24010001`: bảng có thanh điểm, ô điểm tổng kết tô màu, ba ô tổng hợp |
| 49 | `12_nhap_diem_ca_lop.png` | `lg_giaovu_cntt`, Nhập điểm, tab "Cả lớp học phần" | chọn học kỳ và lớp học phần, sửa 1 ô điểm: chụp dòng "1 dòng đã sửa, chưa lưu"; bấm Lưu và chụp thông báo thành công. **Sau khi chụp, sửa lại giá trị cũ** |
| 50 | `12_chuyen_khoa.png` | `lg_daotao`, Sinh viên, tab Chuyển khoa | ảnh 1: sinh viên `23010001` có cảnh báo vàng, không có nút. Ảnh 2: sinh viên `24010016` có ô chọn lớp và nút, bấm để hiện hộp "Xác nhận" rồi bấm **Hủy** (đừng bấm Đồng ý) |
| 51 | `12_dang_ky_hoc_phan.png` | `lg_daotao`, Đăng ký học phần | chọn một sinh viên, học kỳ: bảng lớp học phần có sĩ số, ô chọn lớp ghi "còn X chỗ" |
| 52 | `12_phan_tan.png` | `lg_daotao`, Phân tán | mục 1 (bốn khối node + dòng khớp CSDL gốc) và mục 2 (chọn một sinh viên: sơ đồ có node của khoa được tô đậm, ba thẻ mảnh dữ liệu) |
| 53 | `12_demo_giao_dich.png` | `lg_daotao`, Phân tán, mục 4 | bấm "ROLLBACK": khung đỏ, bước 2 ❌, hai số đếm = 0. Bấm "COMMIT": khung xanh, hai số đếm = 1 (chụp 2 ảnh). Sinh viên demo tự xóa sau mỗi lần |
| 54 | `12_nhat_ky.png` | `lg_daotao`, Nhật ký | **trước đó** tạo vài thao tác: sửa 1 điểm (trang Nhập điểm), thêm một sinh viên mới và chuyển khoa nó (trang Sinh viên). Rồi chụp trang Nhật ký: số liệu Thêm/Sửa/Xóa, biểu đồ, bảng nhật ký tô màu |

- **Hình 57 – `13_dang_nhap_sai.png`:** ở màn hình đăng nhập, chọn `lg_admin`, gõ mật khẩu **sai**, bấm Đăng nhập. Chụp thông báo `Login failed for user 'lg_admin'`.
- **Hình 58 – `13_giaovu_khoa_khac.png`:** có thể dùng lại ảnh Ca 4 của hình 28. Hoặc trong SQL: `EXECUTE AS LOGIN = 'lg_giaovu_cntt'; EXEC dbo.sp_NhapDiem @MaSV='24020001', @MaLHP='NN110-HK1-2627-01', @DiemQT=8; REVERT;` rồi chụp lỗi "Không tìm thấy sinh viên". **Nhớ `REVERT`** để không kẹt trong ngữ cảnh giáo vụ.

---

## Giai đoạn 5. Các ảnh còn lại (hình 55, 56, 59, 60)

- **Hình 55 – `13_du_lieu_mau.png`:** `SELECT TOP 5 * FROM QLSV_CNTT.dbo.SinhVien;` rồi `... LopHocPhan;` rồi `... DangKy;`. Chụp ba bảng (ba tab hoặc ghép một ảnh).
- **Hình 56 – `13_dem_dong.png`:** có thể **dùng lại ảnh của hình 1**; hoặc chạy `EXEC dbo.sp_PhanBoDuLieu;`.
- **Hình 59 – `13_linked_server.png`:** chạy cả `database/12_linked_server.sql`. Chụp: bảng `sys.servers` (có `LS_LOCAL`), kết quả câu 2 (**hai số 72 bằng nhau**) và các câu 1, 3–6. Có thể chụp 2–3 ảnh. Xem thêm `docs/HuongDan_Test_LinkedServer.md`.
- **Hình 60 – `13_linked_server_plan.png`:** chạy câu 3 hoặc câu 4 của `12_linked_server.sql` với **kế hoạch thực tế**; chụp toán tử **Remote Query / Remote Scan**. SQLPro chưa chắc có chức năng này; nếu không có, dùng Azure Data Studio hoặc SSMS (hoặc bỏ ảnh này và ghi chú trong báo cáo rằng đã chứng minh bằng kết quả câu 2).

---

## Dán ảnh vào Word

1. Mở `report/CSDLPT_DoAn_65131461.docx`; nhấn **Yes** khi Word hỏi cập nhật trường (để mục lục có số trang).
2. Đến khung vàng `[CHỤP ẢNH n]`: nháy vào khung, **xóa khung vàng** (chọn bảng, `Delete Table`), rồi **Insert > Pictures** chọn ảnh vừa lưu. Chỉnh chiều rộng khoảng 15 cm, căn giữa.
3. Giữ nguyên dòng chú thích "Hình n. ..." ngay dưới ảnh; số hình được ghi sẵn.
4. Sau khi dán hết: xóa Phụ lục A và các ô cam `[BẠN KIỂM TRA]`; cập nhật mục lục (chuột phải mục lục > Update Field > Update entire table).
5. Chép các ảnh vào thư mục `images/` của đồ án (đề yêu cầu có ảnh demo trong `images/`).
