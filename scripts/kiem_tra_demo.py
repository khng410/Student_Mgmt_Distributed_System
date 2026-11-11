"""Chạy thử 6 file demo và đối chiếu với kết quả mong đợi, in ĐÚNG / SAI cho từng điểm cần cho giảng viên xem.
Dùng trước buổi demo (sau scripts/trien_khai.py, khi dữ liệu còn là dữ liệu mẫu):  python3 -I scripts/kiem_tra_demo.py
Các file đều tự hoàn tác (ROLLBACK) nên chạy bao nhiêu lần dữ liệu mẫu vẫn nguyên."""
import contextlib, io, os, re, sys
sys.path.insert(0, os.path.dirname(__file__))
from chay_sql import chay

D = os.path.join(os.path.dirname(__file__), "..", "database")

# file -> [(điều cần chứng minh, dòng kết quả phải có — biểu thức chính quy)]
MONG_DOI = {
    "07_procedures.sql": [
        ("sp_DongBoDanhMuc chỉ đẩy thay đổi xuống node được chọn", r"Node CNTT sau đồng bộ \| CNTT101 \| 4"),
        ("... node chưa đồng bộ vẫn giữ giá trị cũ", r"Node NN chưa đồng bộ \| CNTT101 \| 3"),
        ("sp_ThemSinhVien lỗi trùng CCCD thì ROLLBACK cả phần ở node CNTT", r"node CNTT còn dòng này không\? \| 0"),
        ("sp_ChuyenKhoa: học vụ rời node CNTT", r"^Node CNTT \| 0$"),
        ("sp_ChuyenKhoa: học vụ sang node Ngoại ngữ, hồ sơ giữ nguyên", r"^Node NN \| 1$"),
        ("sp_ChuyenKhoa từ chối sinh viên đã có đăng ký (50023)", r"^50023 \|"),
        ("sp_DangKyHocPhan từ chối đăng ký trùng (50033)", r"^50033 \|"),
        ("sp_DangKyHocPhan từ chối lớp của khoa khác (50032)", r"^50032 \|"),
        ("sp_NhapDiem tính điểm tổng kết 8.5*0.4 + 9*0.6 = 8.80", r"CNTT110-HK1-2627-01 \| .* \| 8\.50 \| 9\.00 \| 8\.80"),
        ("sp_NhapDiem từ chối điểm ngoài 0-10 (50041)", r"^50041 \|"),
        ("sp_XoaSinhVien từ chối sinh viên đã có đăng ký (50062)", r"^50062 \|"),
        ("sp_HuyDangKy từ chối đăng ký đã có điểm (50072)", r"^50072 \|"),
        ("sp_MoLopHocPhan từ chối môn của khoa khác (50082)", r"^50082 \|"),
        ("sp_DemoGiaoDich COMMIT: có dòng ở cả 2 instance", r"^COMMIT: .* \| 1 \| 1 \|"),
        ("sp_DemoGiaoDich ROLLBACK: cả 2 instance đều 0 dòng", r"^ROLLBACK: .* \| 0 \| 0 \|"),
        ("Đủ 14 thủ tục", r"^14$"),
    ],
    "08_functions.sql": [
        ("fn_XepLoaiDiem đúng ngưỡng: 8 là Giỏi", r"^8\.00 \| Giỏi$"),
        ("fn_XepLoaiDiem đúng ngưỡng: 4 là Yếu, 3.9 là Không đạt", r"^3\.90 \| Không đạt$"),
        ("fn_XepLoaiDiem: chưa có điểm", r"^None \| Chưa có điểm$"),
        ("fn_DiemTBTichLuy/fn_TinChiTichLuy/fn_XepLoaiHocLuc của 24010001", r"^24010001 \| Trần Thành Huy \| 6\.89 \| 34 \| Khá$"),
        ("fn_SiSoLopHocPhan đếm đúng sĩ số lớp CNTT110", r"^CNTT110-HK1-2627-01 \| 21 \| 50$"),
        ("fn_TopSinhVien: hạng nhất toàn trường", r"^24010006 \| Phạm Quang Việt \| Công nghệ thông tin \| 8 \| 9\.24$"),
        ("Đủ 8 hàm", r"^8$"),
    ],
    "09_triggers.sql": [
        ("trg_DangKy_GhiNhatKy ghi điểm cũ và mới khi UPDATE", r"UPDATE \| 24010001\|CNTT101-HK1-2425-01 \| .*DiemThi=8\.10.* \| .*DiemThi=9\.50"),
        ("trg_SinhVien_ChanXoa chặn xóa sinh viên có đăng ký (50901)", r"^50901 \|"),
        ("trg_LopHocPhan_KiemTraMonHoc chặn môn của khoa khác (50902)", r"^50902 \|"),
        ("... và lớp bị chặn không còn ở node", r"lớp NN101-HK1-2627-09 còn ở node không\? \| 0"),
        ("trg_HoSo_KiemTraSinhVien chặn hồ sơ không có sinh viên (50905)", r"^50905 \|"),
        ("trg_DangKy_KiemTraDangKy chặn sinh viên bảo lưu (50903)", r"^50903 \|"),
        ("trg_DangKy_KiemTraDangKy chặn lớp vượt sĩ số (50904)", r"^50904 \|"),
        ("... và sĩ số tối đa trở lại 50 sau lỗi", r"sĩ số tối đa đã trở lại \| 50$"),
        ("trg_SinhVien_GhiNhatKy: chuyển khoa = DELETE ở CNTT + INSERT ở NN", r"^QLSV_NgoaiNgu \| \d+ \| SinhVien \| INSERT"),
        ("trg_HoSo_GhiNhatKy che CCCD, chỉ giữ số cuối", r"^QLSV_TongHop \| \d+ \| SinhVien_HoSo \| INSERT \| None \| CCCD=\*\*\*0096"),
        ("ROLLBACK xóa luôn nhật ký của giao dịch", r"số dòng nhật ký của sinh viên thử \| 0$"),
    ],
    "11_transactions_concurrency.sql": [
        ("A1. COMMIT: dòng có ở cả node CNTT và điều phối", r"^Sau COMMIT \| 1 \| 1$"),
        ("A2. Lệnh thứ hai lỗi trùng CCCD (2627)", r"^2627 \|"),
        ("A2. ROLLBACK: cả hai nơi đều không còn dòng", r"^Sau ROLLBACK \| 0 \| 0$"),
        ("E1. Trước index: Clustered Index Scan", r"Clustered Index Scan\(.*MaLHP\]='LHP05000'"),
        ("E1. Trước index: đọc 1753 trang", r"logical reads 1753,"),
        ("E1. Sau index: Index Seek", r"\|--Index Seek\(.*MaLHP\]='LHP05000'"),
        ("E1. Sau index: chỉ đọc 3 trang", r"logical reads 3,"),
        ("E2. Index thật có ở node CNTT", r"^QLSV_CNTT \| IX_DangKy_MaLHP \| NONCLUSTERED$"),
        ("E2. Index thật có ở node Du lịch", r"^QLSV_DuLich \| IX_DangKy_MaLHP \| NONCLUSTERED$"),
    ],
    "15_dong_bo_danh_muc.sql": [
        ("Sửa qua dm_LuuMonHoc: cả 3 bản sao đổi ngay", r"^Sau dm_LuuMonHoc \| 4\. Node Du lịch \(bản sao\) \| .*\(sửa qua thủ tục\)$"),
        ("... và hàng đợi rỗng", r"^Sau dm_LuuMonHoc: số mục còn chờ \| 0$"),
        ("Sửa thẳng bằng UPDATE: trigger xếp mục cho từng node", r"^Sau UPDATE thẳng: hàng đợi \| DL \| MonHoc \| NN101 \| UPDATE$"),
        ("... bản sao chưa đổi cho tới khi xử lý hàng đợi", r"^Sau UPDATE thẳng \| 2\. Node CNTT \(bản sao\) \| Ngữ pháp tiếng Anh 1$"),
        ("dm_XuLyHangDoi đẩy xuống, bản sao khớp", r"^Sau dm_XuLyHangDoi \| 3\. Node Ngoại ngữ \(bản sao\) \| .*\(sửa thẳng\)$"),
        ("Học kỳ mới có ở cả 3 node", r"^Học kỳ HK2-2627 có ở số node \| 3$"),
        ("Giảng viên mới chỉ nằm ở node của khoa", r"^Chỉ node Du lịch có giảng viên mới \| 0 \| 1$"),
        ("Mã khoa sai bị từ chối (50105)", r"^50105 \|"),
        ("Hàng đợi rỗng sau các ví dụ", r"^Hàng đợi sau ví dụ \| 0$"),
    ],
    "12_linked_server.sql": [
        ("Dữ liệu điều phối nằm ở instance qlsv_tonghop", r"^Điều phối \| qlsv_tonghop \| 72 \|"),
        ("Dữ liệu khoa CNTT nằm ở instance khác: qlsv_cntt", r"^CNTT \| qlsv_cntt \| 24 \|"),
        ("Dữ liệu khoa Du lịch nằm ở instance qlsv_dulich", r"^Du lịch \| qlsv_dulich \| 24 \|"),
        ("Gộp 3 node bằng tên 4 phần = view toàn cục", r"^72 \| 72$"),
        ("EXEC ... AT chạy ngay trên node CNTT", r"^qlsv_cntt \| 207$"),
        ("Tổng hợp toàn trường: 72 sinh viên, 621 đăng ký", r"\| 72 \| 621$"),
        ("Giao dịch phân tán: trong giao dịch cả 2 node đã đổi", r"^Trong giao dịch \| 9\.00 \| 9\.00$"),
        ("... sau ROLLBACK cả 2 node về điểm cũ", r"^Sau ROLLBACK \| 8\.10 \| 5\.70$"),
        ("Node từ chối quyền ghi của lg_bgh (229)", r"^Đúng: node CNTT từ chối lg_bgh \| 229"),
    ],
}

sai = 0
for tep, ds in MONG_DOI.items():
    buf = io.StringIO()
    try:
        with contextlib.redirect_stdout(buf):
            chay(14330, os.path.join(D, tep))
    except SystemExit:
        pass                                # lỗi SQL: dòng "LỖI: ..." nằm trong buf, các điểm phía sau sẽ SAI
    dong = buf.getvalue().splitlines()
    print(f"\n== {tep}")
    for y, mau in ds:
        ok = any(re.search(mau, d) for d in dong)
        sai += not ok
        print(f"  {'ĐÚNG' if ok else 'SAI '}  {y}")
    for d in dong:
        if d.startswith("LỖI:"):
            print("  ", d[:300])
print(f"\n{'Tất cả đều đúng.' if not sai else f'{sai} điểm SAI: chạy lại scripts/trien_khai.py để về dữ liệu mẫu rồi thử lại.'}")
sys.exit(1 if sai else 0)
