"""Quản lý sinh viên nhiều khoa - CSDL phân tán.  Chạy:  streamlit run app.py

Ứng dụng chỉ gọi node điều phối QLSV_TongHop (VIEW, hàm, thủ tục); thủ tục tự tìm đúng node.
Mỗi vai trò đăng nhập bằng một SQL login riêng (xem database/10_security.sql) nên quyền do SQL Server kiểm soát,
ứng dụng chỉ ẩn bớt chức năng cho gọn.
"""
import re
from datetime import date
from decimal import Decimal

import altair as alt
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
DAOTAO = GIAOVU + ["Sinh viên", "Đăng ký học phần", "Lớp học phần", "Phân tán", "Nhật ký"]
MENU = {"lg_bgh": ["Thống kê"], "lg_daotao": DAOTAO, "lg_admin": DAOTAO,
        "lg_giaovu_cntt": GIAOVU, "lg_giaovu_nn": GIAOVU, "lg_giaovu_dl": GIAOVU}

KHOA = {None: "Toàn trường", "CNTT": "CNTT", "NN": "Ngoại ngữ", "DL": "Du lịch"}
DB_THEO_KHOA = {"CNTT": "QLSV_CNTT", "NN": "QLSV_NgoaiNgu", "DL": "QLSV_DuLich"}   # tên database lấy từ đây, không ghép từ dữ liệu nhập
NODE = {KHOA[k]: db for k, db in DB_THEO_KHOA.items()}
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


def danh_sach(sql, cot, *tham_so):
    df = xem(sql, *tham_so)
    return [] if df is None else df[cot].tolist()


def bao(loai, noi_dung):
    """Lưu thông báo để hiện ở lần vẽ lại trang kế tiếp (sau st.rerun)."""
    st.session_state["flash"] = (loai, noi_dung)


def khoa_duoc_xem():
    """Các khoa mà tài khoản hiện tại thấy dữ liệu sinh viên (giáo vụ: chỉ khoa mình; Đào tạo/Quản trị: cả 3)."""
    df = xem("SELECT DISTINCT MaKhoa FROM dbo.vw_SinhVien_ToanCuc ORDER BY MaKhoa")
    return [] if df is None else df["MaKhoa"].tolist()


def chon_sinh_vien(k):
    """Ba ô chọn nối tiếp Khoa -> Lớp -> Sinh viên. Trả về dict thông tin sinh viên hoặc None."""
    a, b, c = st.columns(3)
    khoa = a.selectbox("Khoa", khoa_duoc_xem(), format_func=KHOA.get, key=f"{k}_khoa")
    lop = b.selectbox("Lớp", danh_sach("SELECT DISTINCT MaLop FROM dbo.vw_SinhVien_ToanCuc WHERE MaKhoa = ? ORDER BY MaLop",
                                      "MaLop", khoa), key=f"{k}_lop")
    if not lop:
        return None
    df = xem("SELECT MaSV, HoTen, TrangThai, MaKhoa FROM dbo.vw_SinhVien_ToanCuc WHERE MaLop = ? ORDER BY MaSV", lop)
    if df is None or df.empty:
        return None
    theo_ma = {r["MaSV"]: r for r in df.to_dict("records")}
    masv = c.selectbox("Sinh viên", list(theo_ma), key=f"{k}_sv",
                       format_func=lambda m: f"{m} - {theo_ma[m]['HoTen']}")
    return theo_ma[masv]


# ----------------------------------------------------------------- trang
def bieu_do_diem(df):
    """Hai biểu đồ điểm trung bình, trục điểm cố định từ 0 đến 10, có vạch ngưỡng đạt (4)."""
    truc = alt.Y("DiemTB:Q", title="Điểm trung bình", scale=alt.Scale(domain=[0, 10]),
                 axis=alt.Axis(values=list(range(11))))
    tip = [alt.Tooltip("TenKhoa:N", title="Khoa"), alt.Tooltip("MaHK:N", title="Học kỳ"),
           alt.Tooltip("DiemTB:Q", title="Điểm TB", format=".2f")]
    nguong = alt.Chart(pd.DataFrame({"y": [4]})).mark_rule(color="red", strokeDash=[5, 4]).encode(y="y:Q")
    cot = alt.Chart(df).mark_bar().encode(
        x=alt.X("MaHK:N", title="Học kỳ"), xOffset="TenKhoa:N", y=truc,
        color=alt.Color("TenKhoa:N", title="Khoa"), tooltip=tip)
    duong = alt.Chart(df).mark_line(point=True).encode(
        x=alt.X("MaHK:N", title="Học kỳ"), y=truc, color=alt.Color("TenKhoa:N", title="Khoa"), tooltip=tip)
    a, b = st.columns(2)
    a.markdown("**So sánh theo học kỳ**")
    a.altair_chart(cot + nguong, width="stretch")
    b.markdown("**Xu hướng qua các học kỳ**")
    b.altair_chart(duong + nguong, width="stretch")
    st.caption("Vạch đỏ nét đứt là ngưỡng đạt (điểm 4).")


def thong_ke():
    st.header("Thống kê")
    df = xem("SELECT MaKhoa, TenKhoa, MaHK, SoSinhVien, SoLuotDangKy, DiemTB, TyLeDat "
             "FROM dbo.vw_ThongKe_Khoa_HocKy ORDER BY MaHK, TenKhoa")
    if df is None or df.empty:
        return
    khoa_xem = df[["MaKhoa", "TenKhoa"]].drop_duplicates()
    if len(khoa_xem) == 1:        # giáo vụ: SQL Server chỉ trả khoa của họ
        st.info(f"Bạn chỉ xem được thống kê của khoa {khoa_xem.iloc[0]['TenKhoa']}.")
    c = st.columns(3)
    c[0].metric("Số khoa", len(khoa_xem))
    c[1].metric("Số học kỳ", df["MaHK"].nunique())
    c[2].metric("Tổng lượt đăng ký", int(df["SoLuotDangKy"].sum()))

    st.subheader("Điểm trung bình theo khoa và học kỳ")
    bieu_do_diem(df)
    st.dataframe(df.drop(columns="MaKhoa"), hide_index=True, width="stretch")

    st.subheader("Phân bố học lực")
    a, b = st.columns(2)
    if len(khoa_xem) == 1:
        khoa = khoa_xem.iloc[0]["MaKhoa"]
        a.selectbox("Khoa", [khoa], format_func=KHOA.get, disabled=True, key="tk_khoa_co_dinh")
    else:
        khoa = a.selectbox("Khoa", [None] + khoa_xem["MaKhoa"].tolist(), format_func=KHOA.get, key="tk_khoa")
    hk = b.selectbox("Học kỳ", [None] + sorted(df["MaHK"].unique()),
                     format_func=lambda h: "Tất cả" if h is None else h)
    ph = xem("EXEC dbo.sp_ThongKeKhoa @MaKhoa = ?, @MaHK = ?", khoa, hk)
    if ph is not None and not ph.empty:
        dai = ph.melt(id_vars="TenKhoa", value_vars=["Gioi", "Kha", "TrungBinh", "Yeu", "KhongDat"],
                      var_name="HocLuc", value_name="SoLuot")
        thu_tu = ["Gioi", "Kha", "TrungBinh", "Yeu", "KhongDat"]
        st.altair_chart(alt.Chart(dai).mark_bar().encode(
            x=alt.X("HocLuc:N", sort=thu_tu, title="Học lực"), xOffset="TenKhoa:N",
            y=alt.Y("SoLuot:Q", title="Số lượt"), color=alt.Color("TenKhoa:N", title="Khoa"),
            tooltip=["TenKhoa", "HocLuc", "SoLuot"]), width="stretch")
        st.dataframe(ph, hide_index=True, width="stretch")


def tim_kiem():
    with st.form("tim_kiem"):
        tu_khoa = st.text_input("Mã sinh viên hoặc họ tên (không cần gõ dấu)")
        a, b, c = st.columns(3)
        ds_khoa = khoa_duoc_xem()
        khoa = a.selectbox("Khoa", [None] + ds_khoa if len(ds_khoa) > 1 else ds_khoa, format_func=KHOA.get)
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
        sv = chon_sinh_vien("bd")
        hk = st.selectbox("Học kỳ", [None] + danh_sach("SELECT DISTINCT MaHK FROM dbo.vw_ThongKe_Khoa_HocKy ORDER BY 1", "MaHK"),
                          format_func=lambda h: "Tất cả" if h is None else h)
        if sv:
            try:
                kq = chay("EXEC dbo.sp_BangDiemSinhVien @MaSV = ?, @MaHK = ?", sv["MaSV"], hk)
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


def diem_thay_doi(goc, moi):
    """So hai bảng điểm (cùng thứ tự dòng): trả về [(MaSV, DiemQT, DiemThi)] của các dòng bị sửa.
    Ô để trống (NaN) giữ nguyên điểm cũ ở CSDL, nên điểm đã có không xóa trắng được."""
    def gt(x):
        return None if pd.isna(x) else float(x)
    ket_qua = []
    for (_, a), (_, b) in zip(goc.iterrows(), moi.iterrows()):
        if (gt(a["DiemQT"]), gt(a["DiemThi"])) != (gt(b["DiemQT"]), gt(b["DiemThi"])):
            ket_qua.append((a["MaSV"], gt(b["DiemQT"]), gt(b["DiemThi"])))
    return ket_qua


def luu_diem(lhp, thay_doi):
    """Gọi sp_NhapDiem cho từng sinh viên bị sửa; trả về (số dòng lưu được, danh sách lỗi)."""
    ok, loi_ds = 0, []
    for masv, qt, thi in thay_doi:
        try:
            chay("EXEC dbo.sp_NhapDiem @MaSV = ?, @MaLHP = ?, @DiemQT = ?, @DiemThi = ?", masv, lhp, qt, thi)
            ok += 1
        except pyodbc.Error as e:
            loi_ds.append(f"{masv}: {loi(e)}")
    return ok, loi_ds


def nhap_diem_ca_lop():
    st.caption("Sửa điểm ngay trong bảng rồi bấm Lưu: chỉ những dòng bị sửa mới được gửi lên. "
               "Giáo vụ chỉ lưu được điểm của khoa mình, khoa khác sẽ bị SQL Server từ chối.")
    a, b, c = st.columns(3)
    khoa = a.selectbox("Khoa", khoa_duoc_xem(), format_func=KHOA.get, key="dl_khoa")
    hk = b.selectbox("Học kỳ", danh_sach("SELECT DISTINCT MaHK FROM dbo.vw_DangKy_ToanCuc WHERE MaKhoa = ? ORDER BY MaHK DESC",
                                          "MaHK", khoa), key="dl_hk")
    lop_hp = xem("SELECT DISTINCT MaLHP, TenMH FROM dbo.vw_DangKy_ToanCuc WHERE MaKhoa = ? AND MaHK = ? ORDER BY MaLHP", khoa, hk)
    if lop_hp is None or lop_hp.empty:
        st.info("Học kỳ này chưa có lớp học phần nào có sinh viên đăng ký.")
        return
    ten = dict(zip(lop_hp["MaLHP"], lop_hp["TenMH"]))
    lhp = c.selectbox("Lớp học phần", list(ten), format_func=lambda m: f"{m} - {ten[m]}", key="dl_lhp")
    goc = xem("SELECT d.MaSV, s.HoTen, d.DiemQT, d.DiemThi, d.DiemTK FROM dbo.vw_DangKy_ToanCuc d "
              "JOIN dbo.vw_SinhVien_ToanCuc s ON s.MaSV = d.MaSV WHERE d.MaLHP = ? ORDER BY d.MaSV", lhp)
    if goc is None:
        return
    ver = st.session_state.get("dl_ver", 0)
    cau_hinh = {"MaSV": "Mã SV", "HoTen": "Họ tên", "DiemTK": st.column_config.NumberColumn("Điểm TK (tự tính)", format="%.1f"),
                "DiemQT": st.column_config.NumberColumn("Điểm quá trình", min_value=0.0, max_value=10.0, step=0.1, format="%.1f"),
                "DiemThi": st.column_config.NumberColumn("Điểm thi", min_value=0.0, max_value=10.0, step=0.1, format="%.1f")}
    moi = st.data_editor(goc, hide_index=True, width="stretch", disabled=["MaSV", "HoTen", "DiemTK"],
                         column_config=cau_hinh, key=f"dl_{lhp}_{ver}")
    thay_doi = diem_thay_doi(goc, moi)
    st.caption(f"{len(thay_doi)} dòng đã sửa, chưa lưu" if thay_doi else "Chưa có thay đổi nào")
    if st.button("Lưu thay đổi", disabled=not thay_doi):
        ok, loi_ds = luu_diem(lhp, thay_doi)
        st.session_state["dl_ver"] = ver + 1          # bảng sửa được tạo lại từ dữ liệu mới
        if loi_ds:
            bao("warning", f"Đã lưu {ok}/{len(thay_doi)} dòng. Lỗi:\n\n" + "\n\n".join(f"- {m}" for m in loi_ds))
        else:
            bao("success", f"Đã lưu điểm cho {ok} sinh viên. Xem trang Nhật ký để thấy các thay đổi được trigger ghi lại.")
        st.rerun()


def nhap_diem_tung_sv():
    sv = chon_sinh_vien("nd")
    if not sv:
        return
    df = xem("SELECT MaLHP, TenMH, MaHK, DiemQT, DiemThi, DiemTK FROM dbo.fn_BangDiemSinhVien(?, NULL) ORDER BY MaHK, MaLHP", sv["MaSV"])
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
                  sv["MaSV"], lhp, qt_v, thi_v, ok="Đã lưu điểm")


def nhap_diem():
    st.header("Nhập điểm")
    t1, t2 = st.tabs(["Cả lớp học phần", "Từng sinh viên"])
    with t1:
        nhap_diem_ca_lop()
    with t2:
        nhap_diem_tung_sv()


def sinh_vien():
    st.header("Sinh viên")
    t = st.tabs(["Danh sách", "Thêm", "Sửa", "Xóa", "Chuyển khoa"])
    with t[0]:
        tim_kiem()
    with t[1]:
        lop_ds = danh_sach("SELECT DISTINCT MaLop FROM dbo.vw_SinhVien_ToanCuc ORDER BY 1", "MaLop")
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
        sv = chon_sinh_vien("sua")
        df = xem("SELECT * FROM dbo.vw_SinhVien_DayDu WHERE MaSV = ?", sv["MaSV"]) if sv else None
        if df is not None and not df.empty:
            r = df.iloc[0].to_dict()
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
        sv = chon_sinh_vien("xoa")
        if sv:
            so_dk = xem("SELECT COUNT(*) AS SoDangKy FROM dbo.vw_DangKy_ToanCuc WHERE MaSV = ?", sv["MaSV"])
            n = 0 if so_dk is None else int(so_dk.iloc[0, 0])
            if n:
                st.warning(f"Sinh viên có {n} lượt đăng ký học phần nên không thể xóa (để giữ lịch sử điểm).")
            elif st.checkbox(f"Tôi xác nhận xóa {sv['MaSV']} - {sv['HoTen']}") and st.button("Xóa sinh viên"):
                thuc_hien("EXEC dbo.sp_XoaSinhVien @MaSV = ?", sv["MaSV"])
    with t[4]:
        sv = chon_sinh_vien("ck")
        if sv:
            lop_khac = danh_sach("SELECT DISTINCT MaLop FROM dbo.vw_SinhVien_ToanCuc WHERE MaKhoa <> ? ORDER BY MaLop", "MaLop", sv["MaKhoa"])
            lop_moi = st.selectbox("Chuyển sang lớp (khoa khác)", lop_khac, key="ck_lop_moi")
            if st.button("Chuyển khoa"):
                thuc_hien("EXEC dbo.sp_ChuyenKhoa @MaSV = ?, @MaLopMoi = ?", sv["MaSV"], lop_moi, ok="Đã chuyển khoa")


def dang_ky():
    st.header("Đăng ký học phần")
    sv = chon_sinh_vien("dk")
    if not sv:
        return
    db = DB_THEO_KHOA[sv["MaKhoa"]]          # sinh viên chỉ đăng ký lớp của node khoa mình
    t1, t2 = st.tabs(["Đăng ký", "Hủy đăng ký"])
    with t1:
        hk = st.selectbox("Học kỳ", danh_sach("SELECT MaHK FROM dbo.HocKy ORDER BY NgayBatDau DESC", "MaHK"), key="dk_hk")
        df = xem(f"SELECT lp.MaLHP, m.TenMH, lp.MaGV, lp.SiSoToiDa, "
                 f"(SELECT COUNT(*) FROM {db}.dbo.DangKy d WHERE d.MaLHP = lp.MaLHP) AS DaDangKy, "
                 f"CASE WHEN EXISTS (SELECT 1 FROM {db}.dbo.DangKy d2 WHERE d2.MaLHP = lp.MaLHP AND d2.MaSV = ?) "
                 f"THEN N'Đã đăng ký' ELSE N'' END AS TrangThai "
                 f"FROM {db}.dbo.LopHocPhan lp JOIN dbo.MonHoc m ON m.MaMH = lp.MaMH WHERE lp.MaHK = ? ORDER BY lp.MaLHP",
                 sv["MaSV"], hk)
        if df is None:
            return
        st.dataframe(df, hide_index=True, width="stretch", height=250)
        con = df[(df["TrangThai"] == "") & (df["DaDangKy"] < df["SiSoToiDa"])]
        if con.empty:
            st.info("Không còn lớp học phần nào để đăng ký trong học kỳ này.")
        else:
            thong_tin = con.set_index("MaLHP")
            lhp = st.selectbox("Lớp học phần muốn đăng ký", list(thong_tin.index), key="dk_lhp",
                               format_func=lambda m: f"{m} - {thong_tin.loc[m, 'TenMH']} "
                                                     f"(còn {int(thong_tin.loc[m, 'SiSoToiDa'] - thong_tin.loc[m, 'DaDangKy'])} chỗ)")
            if st.button("Đăng ký"):
                thuc_hien("EXEC dbo.sp_DangKyHocPhan @MaSV = ?, @MaLHP = ?", sv["MaSV"], lhp, ok="Đã đăng ký")
    with t2:
        df = xem("SELECT MaLHP, TenMH, MaHK FROM dbo.fn_BangDiemSinhVien(?, NULL) "
                 "WHERE DiemQT IS NULL AND DiemThi IS NULL ORDER BY MaHK, MaLHP", sv["MaSV"])
        if df is None or df.empty:
            st.info("Không có đăng ký nào chưa có điểm để hủy.")
        else:
            ten = dict(zip(df["MaLHP"], df["TenMH"]))
            lhp = st.selectbox("Đăng ký muốn hủy (chỉ hủy được khi chưa có điểm)", list(ten), key="huy_lhp",
                               format_func=lambda m: f"{m} - {ten[m]}")
            if st.button("Hủy đăng ký"):
                thuc_hien("EXEC dbo.sp_HuyDangKy @MaSV = ?, @MaLHP = ?", sv["MaSV"], lhp)


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


def so_do_node(node_chon=None):
    """Sơ đồ 4 node (Graphviz); node của sinh viên đang xem được tô vàng."""
    def mau(k):
        return "#ffe699" if k == node_chon else "#dce6f2"
    return f'''digraph G {{
      rankdir=LR; node [shape=box, style="rounded,filled", fontname="Helvetica", fontsize=11];
      TH [label="QLSV_TongHop\\nnode điều phối\\nVIEW toàn cục + hồ sơ nhạy cảm", fillcolor="#c6e0b4"];
      CNTT [label="QLSV_CNTT\\nkhoa CNTT", fillcolor="{mau('CNTT')}"];
      NN [label="QLSV_NgoaiNgu\\nkhoa Ngoại ngữ", fillcolor="{mau('NN')}"];
      DL [label="QLSV_DuLich\\nkhoa Du lịch", fillcolor="{mau('DL')}"];
      TH -> CNTT [label="UNION ALL", fontsize=9]; TH -> NN [label="UNION ALL", fontsize=9];
      TH -> DL [label="UNION ALL", fontsize=9];
    }}'''


def demo_giao_dich(gay_loi):
    try:
        kq = chay("EXEC dbo.sp_DemoGiaoDich @GayLoi = ?", int(gay_loi))
    except pyodbc.Error as e:
        st.error(loi(e))
        return
    r = kq[0].iloc[0]
    st.write("**1.** `INSERT` sinh viên vào **QLSV_CNTT**: ✅ thành công")
    if gay_loi:
        st.write(f"**2.** `INSERT` hồ sơ vào **QLSV_TongHop**: ❌ lỗi — {r['ThongBaoLoi'] or ''}")
        st.write("**3.** **ROLLBACK**: lệnh 1 cũng bị hủy dù đã chạy xong")
    else:
        st.write("**2.** `INSERT` hồ sơ vào **QLSV_TongHop**: ✅ thành công")
        st.write("**3.** **COMMIT**: cả hai lệnh được ghi")
    a, b = st.columns(2)
    a.metric("Dòng ở QLSV_CNTT sau giao dịch", int(r["DongOTNodeCNTT"]))
    b.metric("Dòng ở QLSV_TongHop sau giao dịch", int(r["DongOTongHop"]))
    st.caption("Sinh viên demo (99999999) được xóa tự động sau mỗi lần chạy.")


def phan_tan():
    st.header("Phân tán")

    st.subheader("1. Dữ liệu nằm ở đâu")
    try:
        pb, ho_so = chay("EXEC dbo.sp_PhanBoDuLieu")
    except pyodbc.Error as e:
        st.error(loi(e))
        pb = ho_so = None
    if pb is not None:
        theo_bang = pb.set_index("Bang")
        cot = {"CNTT": "CNTT", "NN": "NgoaiNgu", "DL": "DuLich"}
        khop = (pb["KhopTapTrung"] == "OK").all() and (ho_so["KhopTapTrung"] == "OK").all()
        (st.success if khop else st.warning)(
            "Tổng các node khớp CSDL tập trung gốc." if khop else
            "Có bảng không còn khớp CSDL tập trung gốc (bình thường nếu bạn đã thêm hoặc xóa dữ liệu mới).")
        c = st.columns(4)
        with c[0].container(border=True):
            st.markdown("**QLSV_TongHop**  \nnode điều phối")
            st.metric("Hồ sơ sinh viên (mảnh dọc)", int(ho_so.iloc[0, 1]))
        for i, (k, ten_cot) in enumerate(cot.items(), start=1):
            with c[i].container(border=True):
                st.markdown(f"**{DB_THEO_KHOA[k]}**  \nkhoa {KHOA[k]}")
                st.metric("Sinh viên", int(theo_bang.loc["SinhVien (mảnh học vụ)", ten_cot]))
                st.metric("Lớp học phần", int(theo_bang.loc["LopHocPhan", ten_cot]))
                st.metric("Lượt đăng ký", int(theo_bang.loc["DangKy", ten_cot]))

    st.subheader("2. Một sinh viên được ghép từ những node nào?")
    sv = chon_sinh_vien("pt")
    st.graphviz_chart(so_do_node(sv["MaKhoa"] if sv else None))
    if sv:
        db = DB_THEO_KHOA[sv["MaKhoa"]]
        hoc_vu = xem(f"SELECT MaSV, HoTen, NgaySinh, GioiTinh, MaLop, TrangThai FROM {db}.dbo.SinhVien WHERE MaSV = ?", sv["MaSV"])
        ho_so_sv = xem("SELECT CCCD, DienThoai, Email, DiaChi FROM dbo.vw_SinhVien_DayDu WHERE MaSV = ?", sv["MaSV"])
        so_dk = xem(f"SELECT COUNT(*) AS SoDangKy FROM {db}.dbo.DangKy WHERE MaSV = ?", sv["MaSV"])
        a, b, c = st.columns(3)
        with a.container(border=True):
            st.markdown(f"**{db}**  \nmảnh dọc 1: học vụ")
            if hoc_vu is not None:
                st.dataframe(pd.DataFrame({"Giá trị": hoc_vu.iloc[0].astype(str)}), width="stretch")
        with b.container(border=True):
            st.markdown("**QLSV_TongHop**  \nmảnh dọc 2: hồ sơ nhạy cảm")
            if ho_so_sv is not None:
                st.dataframe(pd.DataFrame({"Giá trị": ho_so_sv.iloc[0].astype(str)}), width="stretch")
        with c.container(border=True):
            st.markdown(f"**{db}**  \nđăng ký (phân mảnh ngang dẫn xuất theo sinh viên)")
            if so_dk is not None:
                st.metric("Lượt đăng ký", int(so_dk.iloc[0, 0]))
        st.caption("vw_SinhVien_DayDu = SinhVien (node khoa) JOIN SinhVien_HoSo (TongHop) theo MaSV: "
                   "người dùng chỉ thấy một bảng, không cần biết các mảnh nằm ở đâu.")

    with st.expander("3. Xem bảng thô của từng node"):
        a, b = st.columns(2)
        node = a.radio("Node", list(NODE), horizontal=True)
        bang = b.selectbox("Bảng", BANG_NODE)
        df = xem(f"SELECT TOP 200 * FROM {NODE[node]}.dbo.{bang}")      # tên lấy từ danh sách cố định ở đầu file
        if df is not None:
            st.dataframe(df, hide_index=True, width="stretch", height=250)

    st.subheader("4. Demo giao dịch phân tán (thêm 1 sinh viên vào 2 database)")
    c1, c2 = st.columns(2)
    if c1.button("COMMIT: cả hai lệnh thành công"):
        demo_giao_dich(False)
    if c2.button("ROLLBACK: lệnh thứ hai lỗi cố ý"):
        demo_giao_dich(True)


def nhat_ky():
    st.header("Nhật ký thay đổi")
    st.caption("Trigger trg_DangKy_GhiNhatKy ghi lại mỗi lần sửa điểm hoặc xóa đăng ký, ở bảng NhatKy của từng node.")
    a, b, c = st.columns(3)
    nodes = a.multiselect("Node", list(DB_THEO_KHOA), default=list(DB_THEO_KHOA), format_func=KHOA.get)
    hanh_dong = b.multiselect("Hành động", ["UPDATE", "DELETE"], default=["UPDATE", "DELETE"])
    top = int(c.number_input("Số dòng tối đa", 10, 1000, 100))
    if not nodes or not hanh_dong:
        st.info("Chọn ít nhất một node và một hành động.")
        return
    gop = " UNION ALL ".join(
        f"SELECT N'{k}' AS Node, ThoiGian, HanhDong, KhoaChinh, NoiDungCu, NoiDungMoi, NguoiThucHien "
        f"FROM {DB_THEO_KHOA[k]}.dbo.NhatKy" for k in nodes)        # k và tên database lấy từ danh sách cố định
    df = xem(f"SELECT TOP ({top}) * FROM ({gop}) x WHERE HanhDong IN ({', '.join('?' * len(hanh_dong))}) "
             f"ORDER BY ThoiGian DESC", *hanh_dong)
    if df is None:
        return
    if df.empty:
        st.info("Chưa có thay đổi nào được ghi. Hãy sửa điểm ở trang Nhập điểm rồi quay lại đây.")
        return
    m = st.columns(3)
    m[0].metric("Số thay đổi", len(df))
    m[1].metric("Số lần sửa điểm", int((df["HanhDong"] == "UPDATE").sum()))
    m[2].metric("Số đăng ký bị xóa", int((df["HanhDong"] == "DELETE").sum()))
    st.bar_chart(df.groupby(["Node", "HanhDong"]).size().unstack(fill_value=0))
    st.dataframe(df, hide_index=True, width="stretch")


TRANG = {"Thống kê": thong_ke, "Tìm kiếm": trang_tim_kiem,
         "Bảng điểm": bang_diem, "Nhập điểm": nhap_diem, "Sinh viên": sinh_vien,
         "Đăng ký học phần": dang_ky, "Lớp học phần": lop_hoc_phan, "Phân tán": phan_tan, "Nhật ký": nhat_ky}


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
    if user.startswith("lg_giaovu"):
        st.sidebar.caption("Bạn chỉ xem và sửa dữ liệu của khoa mình.")
    trang = st.sidebar.radio("Chức năng", MENU[user])
    if st.sidebar.button("Đăng xuất"):
        st.session_state.conn.close()
        st.session_state.clear()
        st.rerun()
    flash = st.session_state.pop("flash", None)
    if flash:
        getattr(st, flash[0])(flash[1])
    TRANG[trang]()


main()
