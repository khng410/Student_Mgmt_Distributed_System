"""Quản lý sinh viên nhiều khoa - CSDL phân tán.  Chạy:  streamlit run app.py

Ứng dụng chỉ gọi node điều phối QLSV_TongHop (VIEW, hàm, thủ tục); thủ tục tự tìm đúng node.
Mỗi vai trò đăng nhập bằng một SQL login riêng (xem database/10_security.sql) nên quyền do SQL Server kiểm soát,
ứng dụng chỉ ẩn bớt chức năng cho gọn.
"""
import re
from datetime import date
from decimal import Decimal

import pandas as pd
import pyodbc
import streamlit as st

import config

VAI_TRO = {
    "lg_admin": "Quản trị",
    "lg_daotao": "Phòng Đào tạo",
    "lg_giaovu_cntt": "Giáo vụ khoa CNTT",
    "lg_giaovu_nn": "Giáo vụ khoa Ngoại ngữ",
    "lg_giaovu_dl": "Giáo vụ khoa Du lịch",
    "lg_bgh": "Ban giám hiệu",
}
GIAOVU = ["Thống kê", "Tìm kiếm", "Bảng điểm", "Nhập điểm"]
DAOTAO = GIAOVU + ["Sinh viên", "Đăng ký học phần", "Lớp học phần", "Phân tán"]
MENU = {"lg_bgh": ["Thống kê"], "lg_daotao": DAOTAO, "lg_admin": DAOTAO,
        "lg_giaovu_cntt": GIAOVU, "lg_giaovu_nn": GIAOVU, "lg_giaovu_dl": GIAOVU}

KHOA = {None: "Toàn trường", "CNTT": "CNTT", "NN": "Ngoại ngữ", "DL": "Du lịch"}
NODE = {"CNTT": "QLSV_CNTT", "Ngoại ngữ": "QLSV_NgoaiNgu", "Du lịch": "QLSV_DuLich"}
BANG_NODE = ["SinhVien", "Lop", "GiangVien", "LopHocPhan", "DangKy"]
TRANG_THAI = ["Đang học", "Bảo lưu", "Thôi học", "Đã tốt nghiệp"]


# ----------------------------------------------------------------- kết nối và truy vấn
def ket_noi(user, pwd):
    cs = (f"DRIVER={{{config.DRIVER}}};SERVER={config.SERVER};DATABASE={config.DATABASE};"
          f"UID={user};PWD={pwd};TrustServerCertificate=yes")
    conn = pyodbc.connect(cs, autocommit=True, timeout=10)
    conn.timeout = 30          # câu lệnh bị khóa chặn quá 30 giây thì báo lỗi thay vì treo mãi
    return conn


def loi(e):
    """Lấy thông báo gốc của SQL Server, bỏ phần driver."""
    msg = str(e.args[-1]).split("[SQL Server]")[-1]
    msg = re.sub(r"^\[\w+\]\s*\[Microsoft\]\[[^\]]*\]", "", msg).strip()
    return re.sub(r"\s*\(\d+\)\s*(\(SQLExec\w+\))?\s*['\")]*\s*$", "", msg).strip()


def chay(sql, *tham_so):
    """Chạy câu lệnh, trả về danh sách DataFrame (mỗi tập kết quả một cái)."""
    cur = st.session_state.conn.cursor()
    try:
        cur.execute(sql, tham_so)
        kq = []
        while True:
            if cur.description:
                cot = [c[0] for c in cur.description]
                dong = [tuple(float(v) if isinstance(v, Decimal) else v for v in r) for r in cur.fetchall()]
                kq.append(pd.DataFrame.from_records(dong, columns=cot))
            if not cur.nextset():
                return kq
    finally:
        cur.close()


def xem(sql, *tham_so):
    """Đọc dữ liệu: trả về DataFrame đầu tiên, lỗi thì hiện ra và trả về None."""
    try:
        kq = chay(sql, *tham_so)
        return kq[0] if kq else None
    except pyodbc.Error as e:
        st.error(loi(e))


def thuc_hien(sql, *tham_so, ok="Thành công"):
    """Gọi thủ tục ghi dữ liệu: hiện thông báo và kết quả trả về."""
    try:
        kq = chay(sql, *tham_so)
    except pyodbc.Error as e:
        st.error(loi(e))
        return None
    st.success(ok)
    for df in kq:
        st.dataframe(df, hide_index=True, width="stretch")
    return kq


def danh_sach(sql, cot):
    df = xem(sql)
    return [] if df is None else df[cot].tolist()


# ----------------------------------------------------------------- trang
def thong_ke():
    st.header("Thống kê")
    df = xem("SELECT TenKhoa, MaHK, SoSinhVien, SoLuotDangKy, DiemTB, TyLeDat "
             "FROM dbo.vw_ThongKe_Khoa_HocKy ORDER BY MaHK, TenKhoa")
    if df is None or df.empty:
        return
    c = st.columns(3)
    c[0].metric("Số khoa", df["TenKhoa"].nunique())
    c[1].metric("Số học kỳ", df["MaHK"].nunique())
    c[2].metric("Tổng lượt đăng ký", int(df["SoLuotDangKy"].sum()))
    st.subheader("Điểm trung bình theo khoa và học kỳ")
    st.bar_chart(df.pivot(index="MaHK", columns="TenKhoa", values="DiemTB"))
    st.dataframe(df, hide_index=True, width="stretch")

    st.subheader("Phân bố học lực")
    a, b = st.columns(2)
    khoa = a.selectbox("Khoa", list(KHOA), format_func=KHOA.get, key="tk_khoa")
    hk = b.selectbox("Học kỳ", [None] + sorted(df["MaHK"].unique()),
                     format_func=lambda h: "Tất cả" if h is None else h)
    ph = xem("EXEC dbo.sp_ThongKeKhoa @MaKhoa = ?, @MaHK = ?", khoa, hk)
    if ph is not None and not ph.empty:
        st.bar_chart(ph.set_index("TenKhoa")[["Gioi", "Kha", "TrungBinh", "Yeu", "KhongDat"]])
        st.dataframe(ph, hide_index=True, width="stretch")


def tim_kiem():
    with st.form("tim_kiem"):
        tu_khoa = st.text_input("Mã sinh viên hoặc họ tên (không cần gõ dấu)")
        a, b, c = st.columns(3)
        khoa = a.selectbox("Khoa", list(KHOA), format_func=KHOA.get)
        lop = b.text_input("Mã lớp (ví dụ 66.CNTT-1)")
        tt = c.selectbox("Trạng thái", [None] + TRANG_THAI, format_func=lambda t: "Tất cả" if t is None else t)
        gui = st.form_submit_button("Tìm")
    if gui:
        df = xem("EXEC dbo.sp_TimSinhVien @TuKhoa = ?, @MaKhoa = ?, @MaLop = ?, @TrangThai = ?",
                 tu_khoa or None, khoa, lop or None, tt)
        if df is not None:
            st.caption(f"{len(df)} sinh viên")
            st.dataframe(df, hide_index=True, width="stretch")


def trang_tim_kiem():
    st.header("Tìm kiếm sinh viên")
    tim_kiem()


def bang_diem():
    st.header("Bảng điểm")
    t1, t2 = st.tabs(["Theo sinh viên", "Theo lớp"])
    with t1:
        masv = st.text_input("Mã sinh viên", key="bd_masv")
        hk = st.selectbox("Học kỳ", [None] + danh_sach("SELECT DISTINCT MaHK FROM dbo.vw_ThongKe_Khoa_HocKy ORDER BY 1", "MaHK"),
                          format_func=lambda h: "Tất cả" if h is None else h)
        if masv:
            try:
                kq = chay("EXEC dbo.sp_BangDiemSinhVien @MaSV = ?, @MaHK = ?", masv, hk)
            except pyodbc.Error as e:
                st.error(loi(e))
            else:
                st.dataframe(kq[0], hide_index=True, width="stretch")
                tong = kq[1].iloc[0]
                a, b, c = st.columns(3)
                a.metric("Số môn có điểm", int(tong["SoMonCoDiem"]))
                b.metric("Tín chỉ tích lũy", int(tong["TinChiTichLuy"] or 0))
                c.metric("Điểm TB tích lũy", "-" if pd.isna(tong["DiemTBTichLuy"]) else tong["DiemTBTichLuy"])
    with t2:
        lop = st.selectbox("Lớp", danh_sach("SELECT DISTINCT MaLop FROM dbo.vw_SinhVien_ToanCuc ORDER BY 1", "MaLop"))
        if lop:
            df = xem("SELECT * FROM dbo.fn_DanhSachLop(?) ORDER BY MaSV", lop)
            if df is not None:
                st.dataframe(df, hide_index=True, width="stretch")


def nhap_diem():
    st.header("Nhập điểm")
    st.caption("Giáo vụ chỉ sửa được điểm sinh viên khoa mình; khoa khác sẽ bị SQL Server từ chối.")
    masv = st.text_input("Mã sinh viên", key="nd_masv")
    if not masv:
        return
    df = xem("SELECT MaLHP, TenMH, MaHK, DiemQT, DiemThi, DiemTK FROM dbo.fn_BangDiemSinhVien(?, NULL) ORDER BY MaHK, MaLHP", masv)
    if df is None or df.empty:
        st.info("Sinh viên chưa đăng ký lớp học phần nào.")
        return
    st.dataframe(df, hide_index=True, width="stretch")
    with st.form("nhap_diem"):
        lhp = st.selectbox("Lớp học phần", df["MaLHP"].tolist())
        a, b = st.columns(2)
        qt = a.text_input("Điểm quá trình (để trống = giữ nguyên)")
        thi = b.text_input("Điểm thi (để trống = giữ nguyên)")
        gui = st.form_submit_button("Lưu điểm")
    if gui:
        try:
            qt_v, thi_v = (float(qt) if qt else None), (float(thi) if thi else None)
        except ValueError:
            st.error("Điểm phải là số.")
            return
        thuc_hien("EXEC dbo.sp_NhapDiem @MaSV = ?, @MaLHP = ?, @DiemQT = ?, @DiemThi = ?",
                  masv, lhp, qt_v, thi_v, ok="Đã lưu điểm")


def sinh_vien():
    st.header("Sinh viên")
    lop_ds = danh_sach("SELECT DISTINCT MaLop FROM dbo.vw_SinhVien_ToanCuc ORDER BY 1", "MaLop")
    t = st.tabs(["Danh sách", "Thêm", "Sửa", "Xóa", "Chuyển khoa"])
    with t[0]:
        tim_kiem()
    with t[1]:
        with st.form("them_sv"):
            a, b = st.columns(2)
            masv = a.text_input("Mã sinh viên (8 chữ số)", max_chars=8)
            ten = b.text_input("Họ tên")
            ngay = a.date_input("Ngày sinh", date(2006, 1, 1), min_value=date(1990, 1, 1), max_value=date(2010, 12, 31))
            gt = b.selectbox("Giới tính", ["Nam", "Nữ"])
            lop = a.selectbox("Lớp", lop_ds)
            cccd = b.text_input("CCCD (12 chữ số)", max_chars=12)
            email = a.text_input("Email")
            sdt = b.text_input("Điện thoại")
            dc = st.text_input("Địa chỉ")
            gui = st.form_submit_button("Thêm sinh viên")
        if gui:
            thuc_hien("EXEC dbo.sp_ThemSinhVien @MaSV = ?, @HoTen = ?, @NgaySinh = ?, @GioiTinh = ?, @MaLop = ?, "
                      "@CCCD = ?, @Email = ?, @DienThoai = ?, @DiaChi = ?",
                      masv, ten, ngay, gt, lop, cccd, email, sdt or None, dc or None, ok="Đã thêm sinh viên")
    with t[2]:
        masv = st.text_input("Mã sinh viên cần sửa", key="sua_masv")
        if st.button("Tải thông tin"):
            df = xem("SELECT * FROM dbo.vw_SinhVien_DayDu WHERE MaSV = ?", masv)
            st.session_state.sua = None if df is None or df.empty else df.iloc[0].to_dict()
            if st.session_state.sua is None:
                st.warning("Không tìm thấy sinh viên.")
        r = st.session_state.get("sua")
        if r:
            with st.form("sua_sv"):
                a, b = st.columns(2)
                ten = a.text_input("Họ tên", r["HoTen"])
                ngay = b.date_input("Ngày sinh", r["NgaySinh"], min_value=date(1990, 1, 1), max_value=date(2010, 12, 31))
                gt = a.selectbox("Giới tính", ["Nam", "Nữ"], index=["Nam", "Nữ"].index(r["GioiTinh"]))
                tt = b.selectbox("Trạng thái", TRANG_THAI, index=TRANG_THAI.index(r["TrangThai"]))
                email = a.text_input("Email", r["Email"] or "")
                sdt = b.text_input("Điện thoại", r["DienThoai"] or "")
                dc = st.text_input("Địa chỉ", r["DiaChi"] or "")
                gui = st.form_submit_button("Lưu thay đổi")
            if gui:
                thuc_hien("EXEC dbo.sp_CapNhatSinhVien @MaSV = ?, @HoTen = ?, @NgaySinh = ?, @GioiTinh = ?, "
                          "@TrangThai = ?, @Email = ?, @DienThoai = ?, @DiaChi = ?",
                          r["MaSV"], ten, ngay, gt, tt, email or None, sdt or None, dc or None, ok="Đã cập nhật")
    with t[3]:
        masv = st.text_input("Mã sinh viên cần xóa", key="xoa_masv")
        if st.checkbox("Tôi xác nhận xóa sinh viên này (chỉ xóa được khi chưa có đăng ký học phần)") and st.button("Xóa"):
            thuc_hien("EXEC dbo.sp_XoaSinhVien @MaSV = ?", masv)
    with t[4]:
        masv = st.text_input("Mã sinh viên", key="ck_masv")
        lop = st.selectbox("Chuyển sang lớp", lop_ds, key="ck_lop")
        if st.button("Chuyển khoa"):
            thuc_hien("EXEC dbo.sp_ChuyenKhoa @MaSV = ?, @MaLopMoi = ?", masv, lop, ok="Đã chuyển khoa")


def dang_ky():
    st.header("Đăng ký học phần")
    hk = st.selectbox("Xem các lớp học phần đang có đăng ký ở học kỳ",
                      danh_sach("SELECT DISTINCT MaHK FROM dbo.vw_ThongKe_Khoa_HocKy ORDER BY 1 DESC", "MaHK"))
    df = xem("SELECT DISTINCT MaLHP, TenMH, MaKhoa, MaGV FROM dbo.vw_DangKy_ToanCuc WHERE MaHK = ? ORDER BY MaLHP", hk)
    if df is not None:
        st.dataframe(df, hide_index=True, width="stretch", height=220)
    a, b = st.columns(2)
    masv = a.text_input("Mã sinh viên", key="dk_masv")
    lhp = b.text_input("Mã lớp học phần", key="dk_lhp")
    c1, c2 = st.columns(2)
    if c1.button("Đăng ký"):
        thuc_hien("EXEC dbo.sp_DangKyHocPhan @MaSV = ?, @MaLHP = ?", masv, lhp, ok="Đã đăng ký")
    if c2.button("Hủy đăng ký"):
        thuc_hien("EXEC dbo.sp_HuyDangKy @MaSV = ?, @MaLHP = ?", masv, lhp)


def lop_hoc_phan():
    st.header("Mở lớp học phần")
    mon = xem("SELECT MaMH, TenMH FROM dbo.MonHoc ORDER BY MaMH")
    hk = danh_sach("SELECT MaHK FROM dbo.HocKy ORDER BY NgayBatDau DESC", "MaHK")
    if mon is None:
        return
    with st.form("mo_lop"):
        a, b = st.columns(2)
        ma_mh = a.selectbox("Môn học", mon["MaMH"].tolist(),
                            format_func=lambda m: f"{m} - {mon.set_index('MaMH').loc[m, 'TenMH']}")
        ma_hk = b.selectbox("Học kỳ", hk)
        gv = a.text_input("Mã giảng viên (ví dụ GVCNTT01)")
        nhom = b.number_input("Nhóm", 1, 20, 1)
        siso = a.number_input("Sĩ số tối đa", 10, 200, 60)
        phong = b.text_input("Phòng học")
        gui = st.form_submit_button("Mở lớp")
    if gui:
        thuc_hien("EXEC dbo.sp_MoLopHocPhan @MaMH = ?, @MaHK = ?, @MaGV = ?, @Nhom = ?, @SiSoToiDa = ?, @PhongHoc = ?",
                  ma_mh, ma_hk, gv, int(nhom), int(siso), phong or None, ok="Đã mở lớp")


def phan_tan():
    st.header("Phân tán")
    st.subheader("1. Dữ liệu nằm ở đâu")
    try:
        kq = chay("EXEC dbo.sp_PhanBoDuLieu")
        st.dataframe(kq[0], hide_index=True, width="stretch")
        st.dataframe(kq[1], hide_index=True, width="stretch")
    except pyodbc.Error as e:
        st.error(loi(e))

    st.subheader("2. Xem từng node so với VIEW toàn cục")
    a, b = st.columns(2)
    node = a.radio("Node", list(NODE), horizontal=True)
    bang = b.selectbox("Bảng", BANG_NODE)
    df = xem(f"SELECT TOP 200 * FROM {NODE[node]}.dbo.{bang}")      # tên lấy từ danh sách cố định ở đầu file
    if df is not None:
        st.dataframe(df, hide_index=True, width="stretch", height=250)
    tong = xem("SELECT TenKhoa, COUNT(*) AS SoSinhVien FROM dbo.vw_SinhVien_ToanCuc GROUP BY TenKhoa ORDER BY TenKhoa")
    if tong is not None:
        st.caption("VIEW toàn cục vw_SinhVien_ToanCuc gộp 3 node: người dùng không cần biết dữ liệu ở đâu.")
        st.dataframe(tong, hide_index=True, width="stretch")

    st.subheader("3. Demo giao dịch phân tán (thêm 1 sinh viên vào 2 database)")
    c1, c2 = st.columns(2)
    if c1.button("COMMIT: cả hai lệnh thành công"):
        thuc_hien("EXEC dbo.sp_DemoGiaoDich @GayLoi = 0", ok="Đã chạy giao dịch")
    if c2.button("ROLLBACK: lệnh thứ hai lỗi cố ý"):
        thuc_hien("EXEC dbo.sp_DemoGiaoDich @GayLoi = 1", ok="Đã chạy giao dịch")
    st.caption("Sinh viên demo (99999999) tự được xóa sau mỗi lần chạy. COMMIT: thấy 1 dòng ở node CNTT và 1 ở TongHop; "
               "ROLLBACK: 0 dòng ở cả hai nơi dù lệnh đầu đã chạy xong.")


TRANG = {"Thống kê": thong_ke, "Tìm kiếm": trang_tim_kiem,
         "Bảng điểm": bang_diem, "Nhập điểm": nhap_diem, "Sinh viên": sinh_vien,
         "Đăng ký học phần": dang_ky, "Lớp học phần": lop_hoc_phan, "Phân tán": phan_tan}


# ----------------------------------------------------------------- khung chính
def dang_nhap():
    st.title("Quản lý sinh viên - CSDL phân tán")
    st.caption(f"Máy chủ: {config.SERVER}   |   cơ sở dữ liệu: {config.DATABASE}")
    with st.form("dang_nhap"):
        user = st.selectbox("Tài khoản", list(VAI_TRO), format_func=lambda u: f"{u}  ({VAI_TRO[u]})")
        pwd = st.text_input("Mật khẩu", type="password")
        gui = st.form_submit_button("Đăng nhập")
    if gui:
        try:
            st.session_state.conn = ket_noi(user, pwd)
            st.session_state.user = user
        except pyodbc.Error as e:
            st.error(loi(e))
        else:
            st.rerun()


def main():
    st.set_page_config(page_title="QLSV phân tán", layout="wide")
    if "conn" not in st.session_state:
        dang_nhap()
        return
    user = st.session_state.user
    st.sidebar.markdown(f"**{VAI_TRO[user]}**  \n`{user}`")
    trang = st.sidebar.radio("Chức năng", MENU[user])
    if st.sidebar.button("Đăng xuất"):
        st.session_state.conn.close()
        st.session_state.clear()
        st.rerun()
    TRANG[trang]()


main()
