# Kế hoạch đồ án CSDL phân tán – Quản lý sinh viên nhiều khoa

Nov 6, 2026 · @KhanhNG

## Tổng quan

Nhóm hoàn thành và nộp đồ án trước Nov 27, 2026, chia làm 3 tuần: dựng CSDL phân tán, viết toàn bộ T-SQL, rồi làm giao diện Python và báo cáo. Mỗi tuần kết thúc bằng một mốc kiểm tra; trễ mốc nào thì xử lý ngay trong tuần đó.

1. **Mốc 1 – Nov 13, 2026:** các node chạy được, đủ 7+ bảng, mỗi bảng chính 20+ bản ghi, đã có phân mảnh ngang/dọc và VIEW toàn cục.
2. **Mốc 2 – Nov 20, 2026:** đủ 40 truy vấn (15+ câu phân tán), 7 SP, 8 function, 5 view, 5 trigger, phân quyền và giao dịch.
3. **Mốc 3 – Nov 25, 2026:** giao diện chạy được, báo cáo xong bản nháp, đã tập demo một lần.
4. **Nộp – Nov 27, 2026:** đóng gói file .zip theo đúng cấu trúc thư mục của đề.

Làm việc hằng ngày: mọi script để chung trên một repo GitHub, đặt tên theo `01_…` đến `12_…` như đề yêu cầu; cuối mỗi tuần cả nhóm chạy lại toàn bộ script từ đầu trên một máy sạch.

## Kiến trúc đề xuất

Nên dùng **một SQL Server instance chứa 4 database**: 3 node khoa và 1 node điều phối. Đây cũng là cách đề gợi ý (“ưu tiên mô phỏng bằng 3 database độc lập”).

**Instance là gì?** Là một bản SQL Server đang chạy trên máy, bạn gõ tên nó khi đăng nhập SSMS (ví dụ `localhost` hoặc `localhost\SQLEXPRESS`). Một instance chứa được nhiều database.

|  | 1 instance, nhiều database (khuyên dùng) | Nhiều instance |
| --- | --- | --- |
| Truy vấn chéo node | Tên 3 phần `QLSV_CNTT.dbo.SinhVien`, chạy ngay | Bắt buộc cấu hình Linked Server |
| Transaction giữa các node | Chạy ngay, không cần cài thêm | Cần MSDTC, dễ lỗi khi demo |
| Chạy trên máy khác | Chỉ cần sửa 1 chuỗi kết nối | Phải cài và cấu hình lại nhiều instance |
| Giống phân tán thật | Ít hơn | Nhiều hơn |

Vẫn demo được Linked Server trên 1 instance: tạo một *loopback linked server* `LS_LOCAL` trỏ về chính nó, rồi truy vấn bằng tên 4 phần. Nếu tuần 3 còn thời gian, cài thêm instance thứ hai (bản Developer hoặc Docker) cho node Du lịch để có Linked Server thật.

&#91;embedded content: kiến trúc · 4 database trên 1 instance\]

Ứng dụng chỉ gọi node điều phối; node này dùng VIEW để gom dữ liệu từ 3 khoa nên người dùng không cần biết dữ liệu nằm ở đâu.

**Cách phân bố dữ liệu** (đã chốt trong `database/02_create_tables.sql`; thiết kế tập trung gồm 9 bảng, đặt ở `QLSV_TapTrung`):

| Bảng | Cách phân bố | Đặt tại | Tái thiết |
| --- | --- | --- | --- |
| Khoa, HocKy, MonHoc | Nhân bản toàn phần (danh mục nhỏ, ít đổi) | TongHop (bản chính) + 3 node khoa | Đọc bản chính |
| GiangVien, Lop | Ngang chính theo MaKhoa, có CHECK `MaKhoa = 'CNTT'`… | 3 node khoa | UNION ALL |
| SinhVien (MaSV, HoTen, NgaySinh, GioiTinh, MaLop, TrangThai) | Dọc + ngang dẫn xuất theo Lop | 3 node khoa | UNION ALL rồi JOIN hồ sơ |
| SinhVien\_HoSo (MaSV, CCCD, DienThoai, Email, DiaChi) | Dọc, tách từ SinhVien | TongHop | JOIN theo MaSV |
| LopHocPhan | Ngang dẫn xuất theo GiangVien (khoa mở lớp) | 3 node khoa | UNION ALL |
| DangKy (có cột điểm tổng kết tự tính) | Ngang dẫn xuất theo SinhVien | 3 node khoa | UNION ALL |
| NhatKy (log của trigger) | Mỗi node một bảng | Mọi node | UNION ALL khi xem |

Lưu ý: SQL Server không cho tạo khóa ngoại giữa hai database. Nhờ nhân bản danh mục xuống từng node, mọi khóa ngoại trong node khoa đều là cục bộ. Chỉ còn `SinhVien_HoSo.MaSV` phải kiểm tra bằng trigger, và bản sao danh mục được đồng bộ từ TongHop bằng trigger hoặc stored procedure. Nên ghi điều này vào báo cáo vì giảng viên hay hỏi.

## Tuần 1 (06–13/11): Thiết kế và dựng CSDL phân tán

Kết thúc tuần, 4 database chạy được từ script, có dữ liệu mẫu và VIEW toàn cục trả về đúng toàn bộ sinh viên 3 khoa.

| # | Việc | Hạn | Trạng thái | Kết quả |
| --- | --- | --- | --- | --- |
| 1 | Chốt nhóm và vai trò; tạo repo GitHub; cài SQL Server Developer + SSMS trên máy mỗi người | Nov 7, 2026 | Chưa làm | Repo + README khung |
| 2 | Vẽ ERD tập trung 9 bảng, chuẩn hóa 3NF, xác định PK/FK/CHECK/UNIQUE | Nov 9, 2026 | Đã xong | `images/erd_taptrung.mmd`, `images/erd_taptrung.png` |
| 3 | Chốt phân mảnh ngang theo MaKhoa, phân mảnh dọc SinhVien\_HoSo; ghi tiêu chí phân mảnh | Nov 9, 2026 | Đã xong | Sơ đồ kiến trúc |
| 4 | Tạo 5 database (4 node + CSDL tập trung) và các bảng ở từng node | Nov 10, 2026 | Đã xong | `database/01_create_databases.sql`, `database/02_create_tables.sql` |
| 5 | Sinh dữ liệu mẫu có ý nghĩa, mỗi bảng chính tối thiểu 20 dòng mỗi khoa | Nov 11, 2026 | Đã xong | `database/03_seed_data.sql` |
| 6 | Viết script chuyển dữ liệu từ CSDL tập trung sang các mảnh (INSERT…SELECT theo MaKhoa) và kiểm tra đủ, không trùng | Nov 12, 2026 | Đã xong | `database/04_fragmentation.sql` |
| 7 | Tạo VIEW toàn cục (UNION ALL) và VIEW tái thiết mảnh dọc (JOIN) | Nov 12, 2026 | Đã xong | `database/05_views.sql` |
| 8 | Dựng khung app Streamlit, kết nối pyodbc tới QLSV\_TongHop, trang đăng nhập | Nov 13, 2026 | Chưa làm | `app/` chạy được |
| 9 | Viết báo cáo mục 1–5 (bìa, giới thiệu, phân tích yêu cầu, thiết kế tập trung, thiết kế phân tán) | Nov 13, 2026 | Chưa làm | Báo cáo bản nháp 1 |
| 10 | Họp mốc 1: chạy lại script 01–05 trên một máy sạch | Nov 13, 2026 | Chưa làm | Biên bản ngắn |

Mẹo: tạo thêm một database `QLSV_TapTrung` chứa bản thiết kế tập trung trước, rồi tách sang các node. Cách này cho thấy rõ bước “chuyển từ tập trung sang phân tán” mà đề yêu cầu.

## Tuần 2 (14–20/11): Toàn bộ phần T-SQL

Kết thúc tuần, các script từ `05` đến `12` chạy không lỗi và có ảnh chụp kết quả. Đây là phần chiếm 75/100 điểm nên ưu tiên hơn giao diện.

| # | Việc | Hạn | Trạng thái | Kết quả |
| --- | --- | --- | --- | --- |
| 1 | Truy vấn nhóm a–d: đơn giản 5, aggregate 7, GROUP BY/HAVING 5, cực trị/top-N 4 (21 câu) | Nov 16, 2026 | Đã xong | `database/06_queries_40.sql` |
| 2 | Truy vấn nhóm e–h: “chưa có” 5, UNION/INTERSECT/EXCEPT 3, INSERT/UPDATE/DELETE 7, phép chia 4 (19 câu); ghi chú rõ 15+ câu phân tán | Nov 17, 2026 | Đã xong | `database/06_queries_40.sql` |
| 3 | Hoàn thiện 5 VIEW: thêm view báo cáo điểm theo khoa và view bảo mật ẩn CCCD/SĐT | Nov 17, 2026 | Đã xong | `database/05_views.sql` |
| 4 | 7 stored procedure (đã làm 14: 7 lõi + 7 bổ sung cho app/demo) có tham số và ví dụ EXEC; 2 thủ tục có transaction + TRY…CATCH (ví dụ chuyển sinh viên sang khoa khác = xóa ở node cũ, thêm ở node mới) | Nov 18, 2026 | Đã xong | `database/07_procedures.sql` |
| 5 | 8 function: scalar (điểm TB tích lũy, xếp loại học lực) và table-valued (bảng điểm 1 sinh viên, danh sách theo lớp) | Nov 18, 2026 | Đã xong | `database/08_functions.sql` |
| 6 | 5 trigger: điểm trong 0–10, MaMH phải có ở TongHop, ghi NhatKy khi sửa/xóa điểm, chặn xóa sinh viên đã có điểm… | Nov 19, 2026 | Đã xong | `database/09_triggers.sql` |
| 7 | Bảo mật: 5+ LOGIN/USER/ROLE (Admin, Phòng Đào tạo, Giáo vụ từng khoa); GRANT, DENY, REVOKE; có 1 ca được phép và 1 ca bị từ chối | Nov 19, 2026 | Đã xong | `database/10_security.sql` |
| 8 | Transaction COMMIT và ROLLBACK có lỗi cố ý; kịch bản blocking/deadlock với 2 cửa sổ SSMS, kiểm tra bằng `sys.dm_tran_locks`, `sys.dm_exec_requests` | Nov 20, 2026 | Đã xong A, B; C (deadlock) chưa chạy thử | `database/11_transactions_concurrency.sql` |
| 9 | Tạo loopback Linked Server `LS_LOCAL` và vài truy vấn tên 4 phần | Nov 20, 2026 | Chưa làm | `database/12_linked_server.sql` |
| 10 | App: trang CRUD sinh viên và điểm, gọi stored procedure thay vì SQL trực tiếp | Nov 20, 2026 | Chưa làm | `app/` |
| 11 | Họp mốc 2: chạy lại toàn bộ script, chụp ảnh kết quả vào `images/` | Nov 20, 2026 | Chưa làm | Ảnh demo |

Bẫy hay gặp: VIEW ở QLSV\_TongHop đọc bảng ở database khác sẽ báo lỗi quyền nếu user không tồn tại ở database đó. Cần tạo user cho cùng login ở cả 4 database, hoặc bật `DB_CHAINING` — nên thử sớm ngay khi làm việc 7.

## Tuần 3 (21–27/11): Giao diện, hiệu năng, báo cáo và demo

Kết thúc tuần, nhóm nộp file .zip đã chạy thử trên một máy khác. Giao diện dùng **Streamlit + pyodbc**: viết nhanh nhất cho CRUD và dashboard, hợp với quỹ thời gian 3 tuần. Nếu nhóm quen Flask hơn thì có thể đổi, kế hoạch vẫn giữ nguyên.

| # | Việc | Hạn | Trạng thái | Kết quả |
| --- | --- | --- | --- | --- |
| 1 | Hiệu năng: chạy 1–2 truy vấn với STATISTICS IO/TIME và Actual Execution Plan, trước và sau khi tạo index (ví dụ `DangKy(MaSV)`); ghi nhận xét | Nov 22, 2026 | Chưa làm | Ảnh plan + nhận xét |
| 2 | App: trang tìm kiếm/lọc sinh viên và điểm qua VIEW toàn cục | Nov 22, 2026 | Chưa làm | `app/` |
| 3 | App: dashboard thống kê toàn trường và theo khoa (sĩ số, điểm TB, xếp loại) | Nov 23, 2026 | Chưa làm | `app/` |
| 4 | App: trang “Phân tán” — chọn node để xem dữ liệu, so với VIEW toàn cục, nút chạy transaction COMMIT/ROLLBACK | Nov 24, 2026 | Chưa làm | `app/` |
| 5 | App: ẩn/hiện chức năng theo vai trò đăng nhập | Nov 24, 2026 | Chưa làm | `app/` |
| 6 | Báo cáo mục 6–11 (tái thiết, 40 truy vấn, đối tượng CSDL, phân quyền, giao dịch, hiệu năng) | Nov 24, 2026 | Chưa làm | Báo cáo bản nháp 2 |
| 7 | Báo cáo mục 12–14 (giao diện, kết quả kiểm thử, kết luận, bảng phân công) | Nov 25, 2026 | Chưa làm | `report/CSDLPT_DoAn_65131461.docx` |
| 8 | README: cài đặt, thứ tự chạy script, sửa chuỗi kết nối, `pip install -r requirements.txt`, `streamlit run` | Nov 25, 2026 | Chưa làm | `README.md` |
| 9 | Tập demo đủ 7 nội dung bắt buộc (mục 6 của đề); mỗi người nắm phần mình để vấn đáp | Nov 25, 2026 | Chưa làm | Kịch bản demo |
| 10 | Giải nén file .zip, chạy lại từ đầu trên một máy khác | Nov 26, 2026 | Chưa làm | Xác nhận chạy được |
| 11 | Đóng gói `CSDLPT_65131461_QLSinhVienPhanTan.zip` và nộp | Nov 27, 2026 | Chưa làm | File nộp |
| 12 | (Không bắt buộc) Đưa node Du lịch lên instance thứ hai và demo Linked Server thật | Nov 26, 2026 | Chưa làm | `database/12_linked_server.sql` |

## Phân công

Mỗi thành viên phụ trách một mảng xuyên suốt 3 tuần, nhưng ai cũng phải giải thích được phần phân tán khi vấn đáp. Thay TV1/TV2/TV3 bằng tên thật.

| Vai trò | Mảng phụ trách | Script / thư mục | Điểm liên quan |
| --- | --- | --- | --- |
| TV1 – Trưởng nhóm, thiết kế CSDL | ERD, phân mảnh, tạo node, SP, trigger, Linked Server, đóng gói | 01, 02, 04, 07, 09, 12 | \~40 |
| TV2 – Truy vấn và dữ liệu | Dữ liệu mẫu, VIEW, function, 40 truy vấn (chung với TV1), hiệu năng | 03, 05, 06, 08 | \~40 |
| TV3 – Ứng dụng và bảo mật | Phân quyền, transaction/lock, giao diện Streamlit, README, phần lớn báo cáo | 10, 11, `app/`, `README.md` | \~20 + báo cáo |

Nếu nhóm chỉ có 2 người: TV1 nhận thêm phần bảo mật và transaction, TV2 nhận thêm giao diện; báo cáo mỗi người viết phần của mình.

## Sản phẩm nộp và tiêu chí hoàn thành

Toàn bộ công việc là làm ra 16 thành phần của thư mục `CSDLPT_65131461_QLSinhVienPhanTan/`, gom thành 5 khối. Khối 1 làm trước vì mọi file sau chạy trên bảng và dữ liệu của nó.

| Khối việc chính | Việc con (file) | Xong tốt khi |
| --- | --- | --- |
| 1. Dựng CSDL phân tán | `database/01_create_databases.sql` | Tạo đủ 4 database; chạy lại nhiều lần không lỗi (có `IF DB_ID(...) IS NOT NULL DROP`) |
|  | `database/02_create_tables.sql` | 7+ bảng, đạt 3NF, đủ PK/FK/CHECK/UNIQUE; mỗi bảng nằm đúng node |
|  | `database/03_seed_data.sql` | Mỗi bảng chính 20+ bản ghi có ý nghĩa; khóa ngoại khớp; sinh viên nằm đúng khoa |
|  | `database/04_fragmentation.sql` | Có phân mảnh ngang và dọc; có câu kiểm tra ghép các mảnh = dữ liệu tập trung, không thiếu, không trùng |
| 2. Đối tượng CSDL và truy vấn | `database/05_views.sql` | Đủ 5 view: 1+ view toàn cục, 1+ view tái thiết, còn lại cho báo cáo/bảo mật |
|  | `database/06_queries_40.sql` | Đủ 40 câu đúng 8 nhóm a–h; 15+ câu phân tán đánh dấu `-- [PT]`; mỗi câu có comment ghi câu hỏi |
|  | `database/07_procedures.sql` | Đủ 7 SP có tham số và ví dụ `EXEC`; 2+ SP có transaction và TRY…CATCH |
|  | `database/08_functions.sql` | Đủ 8 hàm (scalar và table-valued), mỗi hàm có câu `SELECT` gọi thử |
|  | `database/09_triggers.sql` | Đủ 5 trigger; mỗi trigger có lệnh INSERT/UPDATE/DELETE làm nó chạy và kết quả cho thấy nó hoạt động |
| 3. Bảo mật, giao dịch, phân tán nâng cao | `database/10_security.sql` | 5+ login/user/role; có GRANT, DENY, REVOKE; 1 ca được phép và 1 ca bị từ chối |
|  | `database/11_transactions_concurrency.sql` | 1 ca COMMIT, 1 ca ROLLBACK do lỗi; kịch bản 2 cửa sổ SSMS gây blocking, kiểm tra bằng DMV |
|  | `database/12_linked_server.sql` | Tạo được Linked Server, chạy được truy vấn tên 4 phần |
| 4. Ứng dụng | `app/` | Đăng nhập theo vai trò, thêm/sửa/xóa, tìm kiếm, thống kê, trang thể hiện phân tán; chạy được bằng `requirements.txt` + `streamlit run` |
| 5. Hồ sơ nộp | `report/CSDLPT_DoAn_65131461.docx` | Đủ 14 mục theo đề, có bảng phân công |
|  | `images/` | Có ảnh cho từng nội dung demo bắt buộc; tên ảnh theo số file, ví dụ `11_rollback.png` |
|  | `README.md` | Người lạ đọc README là cài và chạy được từ đầu |

Quy ước chung cho mọi file `.sql`: đầu file có comment ghi mục đích và người viết; mỗi khối lệnh có `USE` đúng database; chạy cả file (F5) không lỗi, chạy lại lần hai cũng không lỗi.

**Đánh giá độ hoàn thành theo 3 mức:**

1. **Chạy được:** trên máy sạch, chạy lần lượt `01` → `12` không có lỗi đỏ, mở app thấy dữ liệu. Chưa qua mức này thì các mức sau chưa có ý nghĩa.
2. **Đủ và đúng theo đề:** đếm đủ số lượng theo checklist bên dưới, rồi cả nhóm tự chấm theo thang 100 điểm. Đạt 90+ và không mục bắt buộc nào bị 0 là tốt.
3. **Thuyết phục khi demo:** mỗi nội dung demo bắt buộc (mục 6 của đề) có ảnh làm bằng chứng. Mỗi thành viên giải thích được, không cần nhìn tài liệu: dữ liệu nằm ở node nào, vì sao phân mảnh như vậy, vì sao lần chạy đó ROLLBACK.

## Rủi ro và checklist nộp bài

Rủi ro lớn nhất là làm 40 câu truy vấn chỉ trên một database — đề ghi rõ khi đó phần 40 điểm không đạt.

| Rủi ro | Cách xử lý |
| --- | --- |
| Truy vấn không mang tính phân tán | Viết truy vấn trên VIEW toàn cục hoặc tên 3/4 phần; đánh dấu `-- [PT]` trên mỗi câu phân tán để đếm đủ 15 |
| Không có khóa ngoại giữa 2 database | Kiểm tra bằng trigger, ghi rõ lý do trong báo cáo |
| Lỗi quyền khi VIEW đọc database khác | Tạo user ở cả 4 database hoặc bật `DB_CHAINING`; thử ngay tuần 2 |
| Transaction qua Linked Server cần MSDTC | Demo transaction bằng tên 3 phần trên cùng instance; Linked Server chỉ dùng để truy vấn |
| Chạy trên máy khác bị lỗi | Chuỗi kết nối để trong 1 file cấu hình; chạy thử máy sạch cuối mỗi tuần |
| Giao diện làm không kịp | T-SQL trước (75 điểm); giao diện chỉ cần đủ 5 mục a–e của phần 5.6 |

**Checklist trước khi nộp**

- [ ] 7+ bảng, đạt 3NF, có PK/FK/CHECK/UNIQUE
- [ ] Mỗi bảng chính 20+ bản ghi có ý nghĩa
- [ ] 3+ node database
- [ ] Phân mảnh ngang + dọc + tái thiết
- [ ] VIEW toàn cục và truy vấn nhiều node
- [ ] Đủ 40 truy vấn đúng cơ cấu, 15+ câu phân tán
- [ ] 7 SP, 8 function, 5 view, 5 trigger, có ví dụ chạy
- [ ] 5+ user/role, có GRANT/DENY/REVOKE
- [ ] Transaction COMMIT/ROLLBACK có tình huống lỗi
- [ ] Minh họa lock/blocking/deadlock, kiểm tra bằng DMV
- [ ] Execution plan + index + nhận xét
- [ ] Giao diện CRUD, tìm kiếm, thống kê, chức năng phân tán
- [ ] README hướng dẫn cấu hình và chạy
- [ ] Báo cáo, ảnh demo, bảng phân công
