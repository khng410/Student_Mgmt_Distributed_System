"""Quản lý sinh viên nhiều khoa - CSDL phân tán.  Chạy:  streamlit run app.py

Ứng dụng chỉ gọi node điều phối QLSV_TongHop (VIEW, hàm, thủ tục); thủ tục tự tìm đúng node.
Mỗi vai trò đăng nhập bằng một SQL login riêng (xem database/10_security.sql) nên quyền do SQL Server kiểm soát,
ứng dụng chỉ ẩn bớt chức năng cho gọn.
"""
import re
import secrets
import threading
import time
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

# Màu dùng thống nhất: mỗi khoa một màu (biểu đồ, sơ đồ, huy hiệu); mỗi mức học lực một màu.
MAU_KHOA = {"Công nghệ thông tin": "#2563eb", "Ngoại ngữ": "#f59e0b", "Du lịch": "#16a34a"}   # theo TenKhoa
MAU_KHOA_NHAT = {"CNTT": "#dbeafe", "NN": "#fef3c7", "DL": "#dcfce7", "TH": "#ede9fe"}          # nền nhạt, theo MaKhoa
MAU_KHOA_DAM = {"CNTT": "#60a5fa", "NN": "#fbbf24", "DL": "#4ade80"}                            # node đang xem, theo MaKhoa
HUY_HIEU_KHOA = {"CNTT": "blue", "NN": "orange", "DL": "green", "TH": "violet"}                 # màu của st.badge
HUY_HIEU_VAI_TRO = {"lg_admin": "red", "lg_daotao": "violet", "lg_giaovu_cntt": "blue",
                    "lg_giaovu_nn": "orange", "lg_giaovu_dl": "green", "lg_bgh": "gray"}
HOC_LUC = {"Giỏi": ("#16a34a", "#dcfce7"), "Khá": ("#2563eb", "#dbeafe"), "Trung bình": ("#eab308", "#fef9c3"),
           "Yếu": ("#f97316", "#ffedd5"), "Không đạt": ("#dc2626", "#fee2e2")}              # (màu đậm, nền nhạt)
HOC_LUC_COT = {"Gioi": "Giỏi", "Kha": "Khá", "TrungBinh": "Trung bình", "Yeu": "Yếu", "KhongDat": "Không đạt"}
# Tên cột của CSDL -> nhãn tiếng Việt hiện trên bảng (cột không có ở đây giữ nguyên tên)
NHAN_COT = {"DiemQT": "Điểm quá trình", "DiemThi": "Điểm thi", "DiemTK": "Điểm tổng kết", "DiemTB": "Điểm TB",
            "DiemTBTichLuy": "Điểm TB tích lũy", "TyLeDat": "Tỷ lệ đạt", "MaSV": "Mã SV", "HoTen": "Họ tên",
            "NgaySinh": "Ngày sinh", "GioiTinh": "Giới tính", "MaLop": "Lớp", "TenLop": "Tên lớp", "MaKhoa": "Mã khoa",
            "TenKhoa": "Khoa", "TrangThai": "Trạng thái", "MaHK": "Học kỳ", "MaMH": "Mã môn", "TenMH": "Môn học",
            "SoTinChi": "Tín chỉ", "MaLHP": "Lớp học phần", "MaGV": "Giảng viên", "KetQua": "Kết quả",
            "SoSinhVien": "Số sinh viên", "SoLuotDangKy": "Lượt đăng ký", "SoLuotCoDiem": "Lượt có điểm",
            "Gioi": "Giỏi", "Kha": "Khá", "TrungBinh": "Trung bình", "Yeu": "Yếu", "KhongDat": "Không đạt",
            "SiSoToiDa": "Sĩ số tối đa", "DaDangKy": "Đã đăng ký", "NgayDangKy": "Ngày đăng ký", "Nhom": "Nhóm",
            "SoMonCoDiem": "Số môn có điểm", "TinChiTichLuy": "Tín chỉ tích lũy", "NodeKhoa": "Node",
            "ThoiGian": "Thời gian", "TenBang": "Bảng", "HanhDong": "Hành động", "KhoaChinh": "Khóa chính",
            "NoiDungCu": "Trước", "NoiDungMoi": "Sau", "NguoiThucHien": "Người thực hiện", "Node": "Node",
            "CCCD": "CCCD", "DienThoai": "Điện thoại", "Email": "Email", "DiaChi": "Địa chỉ"}

# Thanh bên: chức năng chia nhóm, mỗi chức năng một biểu tượng (Material Symbols) và một dòng mô tả dưới tiêu đề trang
NHOM_MENU = [("Tổng quan", ["Thống kê"]), ("Tra cứu", ["Tìm kiếm", "Bảng điểm"]),
             ("Nghiệp vụ", ["Nhập điểm", "Sinh viên", "Đăng ký học phần", "Lớp học phần"]),
             ("Hệ thống phân tán", ["Phân tán", "Nhật ký"])]
BIEU_TUONG = {"Thống kê": "monitoring", "Tìm kiếm": "search", "Bảng điểm": "grading", "Nhập điểm": "edit_note",
              "Sinh viên": "group", "Đăng ký học phần": "how_to_reg", "Lớp học phần": "class",
              "Phân tán": "hub", "Nhật ký": "history"}
MO_TA = {"Thống kê": "Kết quả học tập theo khoa và học kỳ, tổng hợp từ cả 3 node.",
         "Tìm kiếm": "Tìm sinh viên toàn trường theo mã, họ tên (không cần gõ dấu), khoa, lớp, trạng thái.",
         "Bảng điểm": "Bảng điểm của một sinh viên hoặc của cả lớp.",
         "Nhập điểm": "Nhập, sửa điểm quá trình và điểm thi. Điểm tổng kết được tính tự động.",
         "Sinh viên": "Thêm, sửa, xóa và chuyển khoa. Mỗi thao tác ghi cả hai mảnh dữ liệu trong một giao dịch.",
         "Đăng ký học phần": "Đăng ký hoặc hủy lớp học phần cho một sinh viên.",
         "Lớp học phần": "Mở lớp học phần mới ở node của khoa giảng viên.",
         "Phân tán": "Dữ liệu nằm ở node nào, một sinh viên được ghép từ đâu, và demo giao dịch phân tán.",
         "Nhật ký": "Các thay đổi do trigger ghi lại ở từng node."}


def thu_tu_hk(ma):
    """Khóa sắp xếp học kỳ theo thời gian: 'HK2-2425' -> ('2425', 'HK2') (xếp theo chữ cái thì HK1-2526 đứng trước HK2-2425)."""
    return ma[4:], ma[:3]


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


def muc_hoc_luc(v):
    if pd.isna(v):
        return None
    return "Giỏi" if v >= 8 else "Khá" if v >= 6.5 else "Trung bình" if v >= 5 else "Yếu" if v >= 4 else "Không đạt"


def o_diem(v):
    """CSS cho ô điểm tổng kết: nền theo mức học lực."""
    m = muc_hoc_luc(v)
    return "" if m is None else f"background-color: {HOC_LUC[m][1]}; color: #0f172a; font-weight: 600"


O_KET_QUA = {"Đạt": HOC_LUC["Giỏi"][1], "Không đạt": HOC_LUC["Không đạt"][1], "Chưa có điểm": "#e5e7eb"}
O_TRANG_THAI = {"Đang học": "#dcfce7", "Bảo lưu": "#fef9c3", "Thôi học": "#fee2e2", "Đã tốt nghiệp": "#dbeafe"}
O_HANH_DONG = {"INSERT": "#dcfce7", "UPDATE": "#fef9c3", "DELETE": "#fee2e2"}


def o_nhan(bang_mau):
    return lambda v: f"background-color: {bang_mau[v]}; color: #0f172a" if v in bang_mau else ""


def bang(df, diem=(), tk=(), phan_tram=(), **kw):
    """Hiện bảng có màu: diem = cột điểm vẽ thanh 0-10; tk = cột điểm tổng kết tô nền theo học lực;
    phan_tram = cột vẽ thanh 0-100. Cột KetQua, TrangThai, HanhDong tự được tô màu."""
    cau_hinh = {c: st.column_config.ProgressColumn(NHAN_COT.get(c, c), min_value=0, max_value=10, format="%.1f")
                for c in diem if c in df}
    cau_hinh.update({c: st.column_config.ProgressColumn(NHAN_COT.get(c, c), min_value=0, max_value=100, format="%.0f%%")
                     for c in phan_tram if c in df})
    for c in df.columns:                      # cột còn lại: chỉ đổi tên sang tiếng Việt
        if c not in cau_hinh and c in NHAN_COT:
            cau_hinh[c] = st.column_config.Column(NHAN_COT[c])
    sty = df.style.format(precision=2)
    for c in tk:
        if c in df:
            sty = sty.map(o_diem, subset=[c])
    for c, bm in (("KetQua", O_KET_QUA), ("TrangThai", O_TRANG_THAI), ("HanhDong", O_HANH_DONG)):
        if c in df:
            sty = sty.map(o_nhan(bm), subset=[c])
    st.dataframe(sty, column_config=cau_hinh, hide_index=True, width="stretch", **kw)


def thuc_hien(sql, *tham_so, ok="Thành công"):
    """Gọi thủ tục ghi dữ liệu: hiện thông báo (và toast) cùng kết quả trả về."""
    try:
        kq = chay(sql, *tham_so)
    except pyodbc.Error as e:
        st.error(loi(e))
        return None
    st.toast(ok, icon="✅")
    st.success(ok)
    for df in kq:
        bang(df, diem=["DiemQT", "DiemThi"], tk=["DiemTK"])
    return kq


@st.dialog("Xác nhận")
def hop_xac_nhan(noi_dung, sql, tham_so, ok):
    """Hộp thoại hỏi lại trước khi ghi; đồng ý thì chạy lệnh rồi tải lại trang kèm thông báo."""
    st.write(noi_dung)
    a, b = st.columns(2)
    if a.button("Đồng ý", type="primary", width="stretch"):
        try:
            chay(sql, *tham_so)
        except pyodbc.Error as e:
            st.error(loi(e))
            return
        bao("success", ok)
        st.rerun()
    if b.button("Hủy", width="stretch"):
        st.rerun()


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
def mau_khoa():
    return alt.Scale(domain=list(MAU_KHOA), range=list(MAU_KHOA.values()))


def bieu_do_diem(df):
    """Hai biểu đồ điểm trung bình, trục điểm cố định từ 0 đến 10, có vạch ngưỡng đạt (4)."""
    truc = alt.Y("DiemTB:Q", title="Điểm trung bình", scale=alt.Scale(domain=[0, 10]),
                 axis=alt.Axis(values=list(range(11))))
    tip = [alt.Tooltip("TenKhoa:N", title="Khoa"), alt.Tooltip("MaHK:N", title="Học kỳ"),
           alt.Tooltip("DiemTB:Q", title="Điểm TB", format=".2f")]
    df = df.dropna(subset=["DiemTB"])          # học kỳ đang học chưa có điểm tổng kết: không vẽ
    hk = alt.X("MaHK:N", title=None, sort=sorted(df["MaHK"].unique(), key=thu_tu_hk), axis=alt.Axis(labelAngle=0))
    mau = alt.Color("TenKhoa:N", title=None, scale=mau_khoa(), legend=alt.Legend(orient="bottom"))
    nguong = alt.Chart(pd.DataFrame({"y": [4]})).mark_rule(color="#dc2626", strokeDash=[5, 4]).encode(y="y:Q")
    cot = alt.Chart(df).mark_bar(cornerRadiusTopLeft=3, cornerRadiusTopRight=3).encode(
        x=hk, xOffset="TenKhoa:N", y=truc, color=mau, tooltip=tip)
    duong = alt.Chart(df).mark_line(point=True, strokeWidth=2.5).encode(x=hk, y=truc, color=mau, tooltip=tip)
    a, b = st.columns(2)
    with a.container(border=True):
        st.markdown("**So sánh các khoa theo học kỳ**")
        st.altair_chart((cot + nguong).properties(height=300), width="stretch")
    with b.container(border=True):
        st.markdown("**Xu hướng qua các học kỳ**")
        st.altair_chart((duong + nguong).properties(height=300), width="stretch")
    st.caption("Vạch đỏ nét đứt là ngưỡng đạt (điểm 4). Học kỳ đang học chưa có điểm tổng kết nên không có trên biểu đồ.")


def thong_ke():
    df = xem("SELECT MaKhoa, TenKhoa, MaHK, SoSinhVien, SoLuotDangKy, DiemTB, TyLeDat "
             "FROM dbo.vw_ThongKe_Khoa_HocKy ORDER BY MaHK, TenKhoa")
    if df is None or df.empty:
        return
    khoa_xem = df[["MaKhoa", "TenKhoa"]].drop_duplicates()
    if len(khoa_xem) == 1:        # giáo vụ: SQL Server chỉ trả khoa của họ
        st.info(f"Bạn chỉ xem được thống kê của khoa {khoa_xem.iloc[0]['TenKhoa']}.")
    hk_moi = max(df["MaHK"], key=thu_tu_hk)
    co_diem = df.dropna(subset=["DiemTB"])
    c = st.columns(4)
    c[0].metric("Sinh viên", int(df[df["MaHK"] == hk_moi]["SoSinhVien"].sum()), help=f"Số sinh viên có đăng ký ở học kỳ mới nhất ({hk_moi})", border=True)
    c[1].metric("Tổng lượt đăng ký", f"{int(df['SoLuotDangKy'].sum()):,}".replace(",", "."), help=f"{df['MaHK'].nunique()} học kỳ", border=True)
    c[2].metric("Điểm trung bình", f"{co_diem['DiemTB'].mean():.2f}" if not co_diem.empty else "-", help="Trung bình các học kỳ đã có điểm", border=True)
    c[3].metric("Tỷ lệ đạt", f"{co_diem['TyLeDat'].mean():.1f}%" if not co_diem.empty else "-", help="Điểm tổng kết từ 4 trở lên", border=True)

    st.subheader("Điểm trung bình theo khoa và học kỳ", anchor=False)
    bieu_do_diem(df)
    with st.expander("Xem bảng số liệu"):
        bang(df.drop(columns="MaKhoa").sort_values(["MaHK", "TenKhoa"], key=lambda c: c.map(thu_tu_hk) if c.name == "MaHK" else c),
             diem=["DiemTB"], phan_tram=["TyLeDat"])

    st.subheader("Phân bố học lực")
    a, b = st.columns(2)
    if len(khoa_xem) == 1:
        khoa = khoa_xem.iloc[0]["MaKhoa"]
        a.selectbox("Khoa", [khoa], format_func=KHOA.get, disabled=True, key="tk_khoa_co_dinh")
    else:
        khoa = a.selectbox("Khoa", [None] + khoa_xem["MaKhoa"].tolist(), format_func=KHOA.get, key="tk_khoa")
    hk = b.selectbox("Học kỳ", [None] + sorted(df["MaHK"].unique(), key=thu_tu_hk, reverse=True),
                     format_func=lambda h: "Tất cả học kỳ" if h is None else h)
    ph = xem("EXEC dbo.sp_ThongKeKhoa @MaKhoa = ?, @MaHK = ?", khoa, hk)
    if ph is not None and not ph.empty:
        dai = ph.melt(id_vars="TenKhoa", value_vars=list(HOC_LUC_COT), var_name="HocLuc", value_name="SoLuot")
        dai["HocLuc"] = dai["HocLuc"].map(HOC_LUC_COT)
        with st.container(border=True):
            st.altair_chart(alt.Chart(dai).mark_bar(cornerRadiusTopLeft=3, cornerRadiusTopRight=3).encode(
                x=alt.X("TenKhoa:N", title=None, axis=alt.Axis(labelAngle=0)), xOffset=alt.XOffset("HocLuc:N", sort=list(HOC_LUC)),
                y=alt.Y("SoLuot:Q", title="Số lượt có điểm"),
                color=alt.Color("HocLuc:N", title=None, sort=list(HOC_LUC), legend=alt.Legend(orient="bottom"),
                                scale=alt.Scale(domain=list(HOC_LUC), range=[c[0] for c in HOC_LUC.values()])),
                tooltip=[alt.Tooltip("TenKhoa", title="Khoa"), alt.Tooltip("HocLuc", title="Học lực"),
                         alt.Tooltip("SoLuot", title="Số lượt")]).properties(height=300), width="stretch")
        bang(ph, diem=["DiemTB"])


def tim_kiem():
    with st.form("tim_kiem"):
        tu_khoa = st.text_input("Mã sinh viên hoặc họ tên", placeholder="ví dụ: nguyen, 2401 (không cần gõ dấu)")
        a, b, c = st.columns(3)
        ds_khoa = khoa_duoc_xem()
        khoa = a.selectbox("Khoa", [None] + ds_khoa if len(ds_khoa) > 1 else ds_khoa, format_func=KHOA.get)
        lop = b.text_input("Mã lớp", placeholder="ví dụ 66.CNTT-1")
        tt = c.selectbox("Trạng thái", [None] + TRANG_THAI, format_func=lambda t: "Tất cả" if t is None else t)
        gui = st.form_submit_button("Tìm", type="primary", icon=":material/search:")
    if gui:
        df = xem("EXEC dbo.sp_TimSinhVien @TuKhoa = ?, @MaKhoa = ?, @MaLop = ?, @TrangThai = ?",
                 tu_khoa or None, khoa, lop or None, tt)
        if df is not None and df.empty:
            st.info("Không tìm thấy sinh viên nào khớp điều kiện. Thử bỏ bớt điều kiện lọc.")
        elif df is not None:
            st.caption(f"Tìm thấy **{len(df)}** sinh viên")
            bang(df)


def trang_tim_kiem():
    tim_kiem()


def bang_diem():
    t1, t2 = st.tabs(["Theo sinh viên", "Theo lớp"])
    with t1:
        sv = chon_sinh_vien("bd")
        hk = st.selectbox("Học kỳ", [None] + sorted(danh_sach("SELECT DISTINCT MaHK FROM dbo.vw_ThongKe_Khoa_HocKy", "MaHK"),
                                                    key=thu_tu_hk, reverse=True),
                          format_func=lambda h: "Tất cả học kỳ" if h is None else h)
        if sv:
            try:
                kq = chay("EXEC dbo.sp_BangDiemSinhVien @MaSV = ?, @MaHK = ?", sv["MaSV"], hk)
            except pyodbc.Error as e:
                st.error(loi(e))
            else:
                tong = kq[1].iloc[0]
                a, b, c = st.columns(3)
                a.metric("Số môn có điểm", int(tong["SoMonCoDiem"]), border=True)
                b.metric("Tín chỉ tích lũy", int(tong["TinChiTichLuy"] or 0), border=True)
                c.metric("Điểm TB tích lũy", "-" if pd.isna(tong["DiemTBTichLuy"]) else f"{tong['DiemTBTichLuy']:.2f}", border=True)
                if kq[0].empty:
                    st.info("Sinh viên chưa đăng ký lớp học phần nào trong phạm vi đã chọn.")
                else:
                    bang(kq[0], diem=["DiemQT", "DiemThi"], tk=["DiemTK"])
    with t2:
        lop = st.selectbox("Lớp", danh_sach("SELECT DISTINCT MaLop FROM dbo.vw_SinhVien_ToanCuc ORDER BY 1", "MaLop"))
        if lop:
            df = xem("SELECT * FROM dbo.fn_DanhSachLop(?) ORDER BY MaSV", lop)
            if df is not None:
                bang(df, tk=["DiemTBTichLuy"])


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
    if st.button("Lưu thay đổi", disabled=not thay_doi, type="primary", icon=":material/save:"):
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
    bang(df, diem=["DiemQT", "DiemThi"], tk=["DiemTK"])
    with st.form("nhap_diem"):
        lhp = st.selectbox("Lớp học phần", df["MaLHP"].tolist())
        a, b = st.columns(2)
        qt = a.text_input("Điểm quá trình (để trống = giữ nguyên)")
        thi = b.text_input("Điểm thi (để trống = giữ nguyên)")
        gui = st.form_submit_button("Lưu điểm", type="primary", icon=":material/save:")
    if gui:
        try:
            qt_v, thi_v = (float(qt) if qt else None), (float(thi) if thi else None)
        except ValueError:
            st.error("Điểm phải là số.")
            return
        thuc_hien("EXEC dbo.sp_NhapDiem @MaSV = ?, @MaLHP = ?, @DiemQT = ?, @DiemThi = ?",
                  sv["MaSV"], lhp, qt_v, thi_v, ok="Đã lưu điểm")


def nhap_diem():
    t1, t2 = st.tabs(["Cả lớp học phần", "Từng sinh viên"])
    with t1:
        nhap_diem_ca_lop()
    with t2:
        nhap_diem_tung_sv()


def sinh_vien():
    t = st.tabs([":material/list: Danh sách", ":material/person_add: Thêm", ":material/edit: Sửa",
                 ":material/delete: Xóa", ":material/swap_horiz: Chuyển khoa"])
    with t[0]:
        tim_kiem()
    with t[1]:
        lop_ds = danh_sach("SELECT DISTINCT MaLop FROM dbo.vw_SinhVien_ToanCuc ORDER BY 1", "MaLop")
        with st.form("them_sv"):
            a, b = st.columns(2)
            masv = a.text_input("Mã sinh viên", max_chars=8, placeholder="8 chữ số, ví dụ 24010099")
            ten = b.text_input("Họ tên")
            ngay = a.date_input("Ngày sinh", date(2006, 1, 1), min_value=date(1990, 1, 1), max_value=date(2010, 12, 31))
            gt = b.selectbox("Giới tính", ["Nam", "Nữ"])
            lop = a.selectbox("Lớp", lop_ds)
            cccd = b.text_input("CCCD", max_chars=12, placeholder="12 chữ số")
            email = a.text_input("Email", placeholder="ten@sv.qlsv.edu.vn")
            sdt = b.text_input("Điện thoại (không bắt buộc)", max_chars=10, placeholder="10 chữ số, bắt đầu bằng 0")
            dc = st.text_input("Địa chỉ (không bắt buộc)")
            gui = st.form_submit_button("Thêm sinh viên", type="primary", icon=":material/person_add:")
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
                gui = st.form_submit_button("Lưu thay đổi", type="primary", icon=":material/save:")
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
            elif st.button("Xóa sinh viên", type="primary", icon=":material/delete:"):
                hop_xac_nhan(f"Xóa sinh viên **{sv['MaSV']} - {sv['HoTen']}** khỏi cả hai mảnh dữ liệu? Không hoàn tác được.",
                             "EXEC dbo.sp_XoaSinhVien @MaSV = ?", (sv["MaSV"],), "Đã xóa sinh viên")
    with t[4]:
        sv = chon_sinh_vien("ck")
        so_dk = xem("SELECT COUNT(*) AS SoDangKy FROM dbo.vw_DangKy_ToanCuc WHERE MaSV = ?", sv["MaSV"]) if sv else None
        n = 0 if so_dk is None else int(so_dk.iloc[0, 0])
        if sv and n:
            st.warning(f"Sinh viên có {n} lượt đăng ký học phần ở khoa hiện tại nên không thể chuyển khoa "
                       "(các lớp học phần đó chỉ có ở node của khoa cũ). Chỉ sinh viên chưa đăng ký môn nào chuyển được.")
        elif sv:
            lop_khac = danh_sach("SELECT DISTINCT MaLop FROM dbo.vw_SinhVien_ToanCuc WHERE MaKhoa <> ? ORDER BY MaLop", "MaLop", sv["MaKhoa"])
            lop_moi = st.selectbox("Chuyển sang lớp (khoa khác)", lop_khac, key="ck_lop_moi")
            if st.button("Chuyển khoa", type="primary", icon=":material/swap_horiz:"):
                hop_xac_nhan(f"Chuyển **{sv['MaSV']} - {sv['HoTen']}** sang lớp **{lop_moi}**? "
                             "Dữ liệu học vụ sẽ chuyển sang node của khoa mới.",
                             "EXEC dbo.sp_ChuyenKhoa @MaSV = ?, @MaLopMoi = ?", (sv["MaSV"], lop_moi), "Đã chuyển khoa")


def dang_ky():
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
        bang(df, height=250)
        con = df[(df["TrangThai"] == "") & (df["DaDangKy"] < df["SiSoToiDa"])]
        if con.empty:
            st.info("Không còn lớp học phần nào để đăng ký trong học kỳ này.")
        else:
            thong_tin = con.set_index("MaLHP")
            lhp = st.selectbox("Lớp học phần muốn đăng ký", list(thong_tin.index), key="dk_lhp",
                               format_func=lambda m: f"{m} - {thong_tin.loc[m, 'TenMH']} "
                                                     f"(còn {int(thong_tin.loc[m, 'SiSoToiDa'] - thong_tin.loc[m, 'DaDangKy'])} chỗ)")
            if st.button("Đăng ký", type="primary", icon=":material/how_to_reg:"):
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
    mon = xem("SELECT MaMH, TenMH FROM dbo.MonHoc ORDER BY MaMH")
    hk = danh_sach("SELECT MaHK FROM dbo.HocKy ORDER BY NgayBatDau DESC", "MaHK")
    if mon is None:
        return
    with st.form("mo_lop"):
        a, b = st.columns(2)
        ma_mh = a.selectbox("Môn học", mon["MaMH"].tolist(),
                            format_func=lambda m: f"{m} - {mon.set_index('MaMH').loc[m, 'TenMH']}")
        ma_hk = b.selectbox("Học kỳ", hk)
        gv = a.text_input("Mã giảng viên", placeholder="ví dụ GVCNTT01")
        nhom = b.number_input("Nhóm", 1, 20, 1)
        siso = a.number_input("Sĩ số tối đa", 10, 200, 60)
        phong = b.text_input("Phòng học (không bắt buộc)")
        gui = st.form_submit_button("Mở lớp", type="primary", icon=":material/add:")
    if gui:
        thuc_hien("EXEC dbo.sp_MoLopHocPhan @MaMH = ?, @MaHK = ?, @MaGV = ?, @Nhom = ?, @SiSoToiDa = ?, @PhongHoc = ?",
                  ma_mh, ma_hk, gv, int(nhom), int(siso), phong or None, ok="Đã mở lớp")


MAY_CHU = {"TH": "qlsv_tonghop · cổng 14330", "CNTT": "qlsv_cntt · cổng 14331",
           "NN": "qlsv_ngoaingu · cổng 14332", "DL": "qlsv_dulich · cổng 14333"}      # 4 instance SQL Server (docker-compose.yml)


def so_do_node(node_chon=None):
    """Sơ đồ 4 instance (Graphviz), mỗi khoa một màu; node của sinh viên đang xem được tô đậm, viền dày."""
    def o(k, ten, vai_tro):
        chon = k == node_chon
        mau = MAU_KHOA_DAM[k] if chon else MAU_KHOA_NHAT[k]
        return (f'{k} [label=<<b>{ten}</b><br/>{vai_tro}<br/><font point-size="9" color="#475569">{MAY_CHU[k]}</font>>, '
                f'fillcolor="{mau}", penwidth={3 if chon else 1}];')
    def noi(k):
        chon = k == node_chon
        return (f'TH -> {k} [label=" LS_{DB_THEO_KHOA[k]} ", fontsize=9, fontcolor="#475569", '
                f'color="{"#0f172a" if chon else "#94a3b8"}", penwidth={2.2 if chon else 1}];')
    return f'''digraph G {{
      rankdir=LR; bgcolor="transparent"; nodesep=0.35; ranksep=1.3;
      node [shape=box, style="rounded,filled", fontname="Helvetica", fontsize=11, color="#94a3b8", margin="0.2,0.12"];
      edge [fontname="Helvetica", arrowsize=0.7];
      APP [label="Ứng dụng", shape=box, fillcolor="#f1f5f9"];
      TH [label=<<b>QLSV_TongHop</b><br/>node điều phối: view toàn cục, hồ sơ nhạy cảm<br/><font point-size="9" color="#475569">{MAY_CHU["TH"]}</font>>, fillcolor="{MAU_KHOA_NHAT['TH']}"];
      {o("CNTT", "QLSV_CNTT", "khoa CNTT")} {o("NN", "QLSV_NgoaiNgu", "khoa Ngoại ngữ")} {o("DL", "QLSV_DuLich", "khoa Du lịch")}
      APP -> TH [color="#94a3b8"];
      {noi("CNTT")} {noi("NN")} {noi("DL")}
    }}'''


def demo_giao_dich(gay_loi):
    try:
        kq = chay("EXEC dbo.sp_DemoGiaoDich @GayLoi = ?", int(gay_loi))
    except pyodbc.Error as e:
        st.error(loi(e))
        return
    r = kq[0].iloc[0]
    with st.status("Đang chạy giao dịch phân tán...", expanded=True) as tt:
        time.sleep(0.5)
        st.write("**1.** `INSERT` sinh viên vào **QLSV_CNTT**: ✅ thành công")
        time.sleep(0.6)
        if gay_loi:
            st.write(f"**2.** `INSERT` hồ sơ vào **QLSV_TongHop**: ❌ lỗi — {r['ThongBaoLoi'] or ''}")
            time.sleep(0.6)
            st.write("**3.** **ROLLBACK**: lệnh 1 cũng bị hủy dù đã chạy xong")
            tt.update(label="ROLLBACK: cả giao dịch bị hủy", state="error", expanded=True)
        else:
            st.write("**2.** `INSERT` hồ sơ vào **QLSV_TongHop**: ✅ thành công")
            time.sleep(0.6)
            st.write("**3.** **COMMIT**: cả hai lệnh được ghi")
            tt.update(label="COMMIT: giao dịch thành công", state="complete", expanded=True)
    a, b = st.columns(2)
    a.metric("Dòng ở QLSV_CNTT sau giao dịch", int(r["DongOTNodeCNTT"]), border=True)
    b.metric("Dòng ở QLSV_TongHop sau giao dịch", int(r["DongOTongHop"]), border=True)
    st.caption("Sinh viên demo (99999999) được xóa tự động sau mỗi lần chạy.")


def the_thuoc_tinh(df):
    """Một dòng dữ liệu hiện thành bảng dọc 2 cột: Thuộc tính | Giá trị (nhãn tiếng Việt)."""
    r = df.iloc[0]
    st.dataframe(pd.DataFrame({"Thuộc tính": [NHAN_COT.get(c, c) for c in df.columns],
                               "Giá trị": ["" if pd.isna(v) else str(v) for v in r]}),
                 hide_index=True, width="stretch")


def pt_phan_bo():
    """Mục 1: mỗi instance giữ gì, bao nhiêu dòng, và tổng các node có khớp bản tập trung không."""
    try:
        pb, ho_so = chay("EXEC dbo.sp_PhanBoDuLieu")
    except pyodbc.Error as e:
        st.error(loi(e))
        return
    theo_bang = pb.set_index("Bang")
    khop = (pb["KhopTapTrung"] == "OK").all() and (ho_so["KhopTapTrung"] == "OK").all()
    st.graphviz_chart(so_do_node(), width="stretch")
    c = st.columns(4)
    with c[0].container(border=True):
        st.badge("QLSV_TongHop", color=HUY_HIEU_KHOA["TH"])
        st.metric("Hồ sơ sinh viên", int(ho_so.iloc[0, 1]))
        st.caption("Mảnh dọc nhạy cảm (CCCD, điện thoại, địa chỉ) và bản chính danh mục")
    for i, (k, ten_cot) in enumerate({"CNTT": "CNTT", "NN": "NgoaiNgu", "DL": "DuLich"}.items(), start=1):
        with c[i].container(border=True):
            st.badge(DB_THEO_KHOA[k], color=HUY_HIEU_KHOA[k])
            st.metric("Sinh viên", int(theo_bang.loc["SinhVien (mảnh học vụ)", ten_cot]))
            st.caption(f"{int(theo_bang.loc['LopHocPhan', ten_cot])} lớp học phần · "
                       f"{int(theo_bang.loc['DangKy', ten_cot])} lượt đăng ký · {int(theo_bang.loc['GiangVien', ten_cot])} giảng viên")
    st.markdown("**Số dòng của từng bảng ở từng node**")
    st.dataframe(pb, hide_index=True, width="stretch", column_config={
        "Bang": "Bảng", "NgoaiNgu": "Ngoại ngữ", "DuLich": "Du lịch", "TongCacNode": "Tổng 3 node",
        "TapTrung": "CSDL tập trung gốc", "KhopTapTrung": "Khớp"})
    (st.success if khop else st.warning)(
        "Tổng các node khớp CSDL tập trung gốc: phân mảnh không thiếu, không thừa dòng nào." if khop else
        "Có bảng không còn khớp CSDL tập trung gốc (bình thường nếu bạn đã thêm hoặc xóa dữ liệu sau khi phân mảnh).",
        icon=":material/check_circle:" if khop else ":material/info:")


def pt_ghep_sinh_vien():
    """Mục 2: một sinh viên = mảnh học vụ (node khoa) + mảnh hồ sơ (điều phối), ghép theo MaSV."""
    sv = chon_sinh_vien("pt")
    if not sv:
        st.info("Chọn một sinh viên để xem dữ liệu của họ nằm ở những node nào.")
        return
    k, db = sv["MaKhoa"], DB_THEO_KHOA[sv["MaKhoa"]]
    st.graphviz_chart(so_do_node(k), width="stretch")
    hoc_vu = xem(f"SELECT MaSV, HoTen, NgaySinh, GioiTinh, MaLop, TrangThai FROM {db}.dbo.SinhVien WHERE MaSV = ?", sv["MaSV"])
    ho_so_sv = xem("SELECT MaSV, CCCD, DienThoai, Email, DiaChi FROM dbo.vw_SinhVien_DayDu WHERE MaSV = ?", sv["MaSV"])
    so_dk = xem(f"SELECT COUNT(*) AS SoDangKy FROM {db}.dbo.DangKy WHERE MaSV = ?", sv["MaSV"])
    a, b = st.columns(2)
    with a.container(border=True):
        st.badge(db, color=HUY_HIEU_KHOA[k])
        st.markdown("**Mảnh 1: học vụ**")
        if hoc_vu is not None and not hoc_vu.empty:
            the_thuoc_tinh(hoc_vu)
        if so_dk is not None:
            st.caption(f"Cùng node này còn giữ **{int(so_dk.iloc[0, 0])}** lượt đăng ký của sinh viên (phân mảnh ngang dẫn xuất).")
    with b.container(border=True):
        st.badge("QLSV_TongHop", color=HUY_HIEU_KHOA["TH"])
        st.markdown("**Mảnh 2: hồ sơ nhạy cảm**")
        if ho_so_sv is not None and not ho_so_sv.empty:
            the_thuoc_tinh(ho_so_sv)
        st.caption("Chỉ Phòng Đào tạo và Quản trị đọc được mảnh này.")
    st.info("Hai mảnh ghép lại theo **Mã SV** thành view `vw_SinhVien_DayDu`: người dùng chỉ thấy một bảng, "
            "không cần biết các mảnh nằm ở instance nào.", icon=":material/join_inner:")


def pt_bang_tho():
    """Mục 3: xem trực tiếp bảng của một node khoa."""
    a, b = st.columns(2)
    node = a.segmented_control("Node", list(NODE), default=list(NODE)[0], key="pt_node") or list(NODE)[0]
    ten_bang = b.selectbox("Bảng", BANG_NODE)
    df = xem(f"SELECT TOP 200 * FROM {NODE[node]}.dbo.{ten_bang}")      # tên lấy từ danh sách cố định ở đầu file
    if df is not None:
        st.caption(f"`{NODE[node]}.dbo.{ten_bang}` · {len(df)} dòng" + (" (tối đa 200)" if len(df) == 200 else ""))
        bang(df, height=420)


def pt_giao_dich():
    """Mục 4: demo COMMIT / ROLLBACK của một giao dịch ghi vào 2 instance."""
    st.markdown("Thêm một sinh viên thử vào **hai instance** trong **một giao dịch**: học vụ ở node CNTT, hồ sơ ở node điều phối. "
                "Hoặc cả hai được ghi, hoặc không gì cả.")
    c1, c2 = st.columns(2)
    with c1.container(border=True):
        st.markdown("**Trường hợp thành công**")
        st.caption("Cả hai lệnh INSERT chạy được, giao dịch COMMIT: cả hai nơi đều có dòng mới.")
        chay_ok = st.button("Chạy COMMIT", type="primary", icon=":material/check_circle:", width="stretch")
    with c2.container(border=True):
        st.markdown("**Trường hợp lỗi**")
        st.caption("Lệnh thứ hai cố ý trùng CCCD nên lỗi, giao dịch ROLLBACK: lệnh thứ nhất cũng bị hủy.")
        chay_loi = st.button("Chạy ROLLBACK", icon=":material/undo:", width="stretch")
    if chay_ok or chay_loi:
        demo_giao_dich(chay_loi)


MUC_PHAN_TAN = {"Dữ liệu nằm ở đâu": pt_phan_bo, "Một sinh viên, hai mảnh": pt_ghep_sinh_vien,
                "Bảng của từng node": pt_bang_tho, "Giao dịch phân tán": pt_giao_dich}


def phan_tan():
    # Chỉ vẽ mục đang chọn: mỗi mục có truy vấn liên instance riêng, vẽ hết một lượt thì trang chậm
    muc = st.segmented_control("Nội dung", list(MUC_PHAN_TAN), default=list(MUC_PHAN_TAN)[0], key="pt_muc",
                               label_visibility="collapsed") or list(MUC_PHAN_TAN)[0]
    MUC_PHAN_TAN[muc]()


DB_NHAT_KY = {**DB_THEO_KHOA, "TH": "QLSV_TongHop"}          # NhatKy có ở 4 database: 3 node khoa và TongHop (hồ sơ)
NHAN_NODE = {**KHOA, "TH": "TongHop"}
BANG_NHAT_KY = ["DangKy", "SinhVien", "SinhVien_HoSo"]


def nhat_ky():
    with st.expander("Trigger ghi lại những gì?"):
        st.markdown("- **DangKy**: sửa điểm và xóa đăng ký.\n"
                    "- **SinhVien**: thêm, sửa, xóa; chuyển khoa = xóa ở node cũ + thêm ở node mới.\n"
                    "- **SinhVien_HoSo**: thêm, sửa, xóa hồ sơ cá nhân (CCCD và điện thoại chỉ ghi các số cuối).\n\n"
                    "Mỗi node có bảng NhatKy riêng; trang này gộp chúng lại.")
    a, b = st.columns(2)
    nodes = a.multiselect("Node", list(DB_NHAT_KY), default=list(DB_NHAT_KY), format_func=NHAN_NODE.get)
    bang_chon = b.multiselect("Bảng", BANG_NHAT_KY, default=BANG_NHAT_KY)
    c, d = st.columns(2)
    hanh_dong = c.multiselect("Hành động", ["INSERT", "UPDATE", "DELETE"], default=["INSERT", "UPDATE", "DELETE"])
    top = int(d.number_input("Số dòng tối đa", 10, 1000, 100))
    if not nodes or not hanh_dong or not bang_chon:
        st.info("Chọn ít nhất một node, một bảng và một hành động.")
        return
    gop = " UNION ALL ".join(
        f"SELECT N'{k}' AS Node, ThoiGian, TenBang, HanhDong, KhoaChinh, NoiDungCu, NoiDungMoi, NguoiThucHien "
        f"FROM {DB_NHAT_KY[k]}.dbo.NhatKy" for k in nodes)        # k và tên database lấy từ danh sách cố định
    df = xem(f"SELECT TOP ({top}) * FROM ({gop}) x WHERE HanhDong IN ({', '.join('?' * len(hanh_dong))}) "
             f"AND TenBang IN ({', '.join('?' * len(bang_chon))}) ORDER BY ThoiGian DESC", *hanh_dong, *bang_chon)
    if df is None:
        return
    if df.empty:
        st.info("Chưa có thay đổi nào được ghi. Hãy sửa điểm, thêm hoặc chuyển khoa một sinh viên rồi quay lại đây.")
        return
    m = st.columns(4)
    m[0].metric("Số thay đổi", len(df), border=True)
    for cot, hd in zip(m[1:], ("INSERT", "UPDATE", "DELETE")):
        cot.metric({"INSERT": "Thêm", "UPDATE": "Sửa", "DELETE": "Xóa"}[hd], int((df["HanhDong"] == hd).sum()), border=True)
    dem = df.groupby(["Node", "HanhDong"]).size().reset_index(name="SoLan")
    st.altair_chart(alt.Chart(dem).mark_bar().encode(
        x=alt.X("Node:N", title="Node"), xOffset="HanhDong:N", y=alt.Y("SoLan:Q", title="Số lần"),
        color=alt.Color("HanhDong:N", title="Hành động",
                        scale=alt.Scale(domain=["INSERT", "UPDATE", "DELETE"], range=["#16a34a", "#f59e0b", "#dc2626"])),
        tooltip=["Node", "HanhDong", "SoLan"]), width="stretch")
    bang(df)


TRANG = {"Thống kê": thong_ke, "Tìm kiếm": trang_tim_kiem,
         "Bảng điểm": bang_diem, "Nhập điểm": nhap_diem, "Sinh viên": sinh_vien,
         "Đăng ký học phần": dang_ky, "Lớp học phần": lop_hoc_phan, "Phân tán": phan_tan, "Nhật ký": nhat_ky}


# ----------------------------------------------------------------- khung chính
# Giữ đăng nhập khi tải lại trang: sau khi đăng nhập, kết nối được cất trong bộ nhớ máy chủ theo một mã ngẫu nhiên;
# mã nằm trên địa chỉ trang (?phien=...). Tải lại trang thì tìm lại kết nối theo mã. Hết hạn sau PHIEN_PHUT phút không dùng
# (PHIEN_PHUT = 0: không giới hạn, phiên chỉ mất khi đăng xuất hoặc khởi động lại ứng dụng).
@st.cache_resource
def kho_phien():
    return {"khoa": threading.Lock(), "phien": {}}


def _het_han():
    return time.time() + config.PHIEN_PHUT * 60 if config.PHIEN_PHUT > 0 else float("inf")     # 0 = không giới hạn


def _don_phien_het_han(kho):          # gọi khi đang giữ khóa
    bay_gio = time.time()
    for ma in [m for m, p in kho["phien"].items() if p["het_han"] < bay_gio]:
        try:
            kho["phien"][ma]["conn"].close()
        except pyodbc.Error:
            pass
        del kho["phien"][ma]


def tao_phien(user, conn):
    kho = kho_phien()
    ma = secrets.token_urlsafe(16)
    with kho["khoa"]:
        _don_phien_het_han(kho)
        kho["phien"][ma] = {"conn": conn, "user": user, "het_han": _het_han()}
    st.query_params["phien"] = ma
    st.session_state.update(conn=conn, user=user, ma_phien=ma)


def huy_phien(ma):
    kho = kho_phien()
    with kho["khoa"]:
        p = kho["phien"].pop(ma, None)
    if p:
        try:
            p["conn"].close()
        except pyodbc.Error:
            pass


def gia_han_phien(ma):
    """Còn hạn thì gia hạn thêm PHIEN_PHUT phút và trả về phiên; hết hạn hoặc không có thì trả về None."""
    kho = kho_phien()
    with kho["khoa"]:
        _don_phien_het_han(kho)
        p = kho["phien"].get(ma)
        if p:
            p["het_han"] = _het_han()
        return p


def khoi_phuc_phien():
    """Địa chỉ có mã phiên còn hạn: lấy lại kết nối đã đăng nhập. Trả về True nếu thành công."""
    ma = st.query_params.get("phien")
    if not ma:
        return False
    p = gia_han_phien(ma)
    if p:
        try:
            p["conn"].cursor().execute("SELECT 1").fetchone()          # kết nối còn sống không?
        except pyodbc.Error:
            huy_phien(ma)
            p = None
    if not p:
        st.query_params.pop("phien", None)
        return False
    st.session_state.update(conn=p["conn"], user=p["user"], ma_phien=ma)
    return True


def dang_nhap():
    _, giua, _ = st.columns([1, 1.3, 1])
    with giua:
        st.markdown("## :material/school: Quản lý sinh viên")
        st.caption("Cơ sở dữ liệu phân tán: 3 khoa, 4 node SQL Server")
        with st.form("dang_nhap", border=True):
            user = st.selectbox("Vai trò", list(VAI_TRO), index=1, format_func=lambda u: f"{VAI_TRO[u]}  ·  {u}")
            pwd = st.text_input("Mật khẩu", type="password", placeholder="Mật khẩu của tài khoản SQL Server")
            gui = st.form_submit_button("Đăng nhập", type="primary", icon=":material/login:", width="stretch")
        if gui:
            if not pwd:
                st.error("Chưa nhập mật khẩu.")
            else:
                try:
                    with st.spinner("Đang kết nối..."):
                        conn = ket_noi(user, pwd)
                except pyodbc.Error as e:
                    st.error("Sai mật khẩu hoặc tài khoản không đăng nhập được." if "18456" in str(e) else loi(e))
                else:
                    tao_phien(user, conn)
                    st.rerun()
        st.caption(f"Máy chủ `{config.SERVER}` · cơ sở dữ liệu `{config.DATABASE}`. Mỗi vai trò là một tài khoản SQL Server riêng, "
                   "quyền do SQL Server kiểm soát.")


# Nút ở thanh bên canh trái như một menu (mặc định Streamlit canh giữa)
CSS = """<style>
[data-testid="stSidebar"] .stButton button {justify-content: flex-start !important; padding: .35rem .7rem; min-height: 0;}
[data-testid="stSidebar"] .stButton button > div {justify-content: flex-start !important; width: 100%;}
[data-testid="stSidebar"] .stButton button p {font-size: .95rem;}
[data-testid="stSidebar"] [data-testid="stVerticalBlock"] {gap: .3rem;}
[data-testid="stMainBlockContainer"] {padding-top: 2.5rem;}
</style>"""


def thanh_ben(user, menu):
    """Vẽ thanh bên, trả về tên trang đang chọn."""
    sb = st.sidebar
    sb.markdown("### :material/school: QLSV phân tán")
    with sb.container(border=True):
        st.badge(VAI_TRO[user], color=HUY_HIEU_VAI_TRO[user])
        st.caption(f"Tài khoản `{user}`" + ("  \nChỉ xem và sửa dữ liệu khoa mình." if user.startswith("lg_giaovu") else ""))
    if st.session_state.get("trang") not in menu:                        # phiên mới (kể cả sau khi tải lại): lấy trang từ địa chỉ
        trang_url = st.query_params.get("trang")
        st.session_state["trang"] = trang_url if trang_url in menu else menu[0]
    for nhom, cac_trang in NHOM_MENU:
        cac_trang = [t for t in cac_trang if t in menu]
        if cac_trang and len(menu) > 1:
            sb.caption(nhom.upper())
        for t in cac_trang:
            dang_chon = t == st.session_state["trang"]
            if sb.button(t, icon=f":material/{BIEU_TUONG[t]}:", key=f"nav_{t}", width="stretch",
                         type="primary" if dang_chon else "tertiary") and not dang_chon:
                st.session_state["trang"] = t
                st.rerun()
    sb.divider()
    if sb.button("Đăng xuất", icon=":material/logout:", width="stretch"):
        huy_phien(st.session_state.get("ma_phien"))
        st.session_state.clear()
        st.query_params.clear()
        st.rerun()
    return st.session_state["trang"]


def main():
    st.set_page_config(page_title="QLSV phân tán", page_icon=":material/school:", layout="wide")
    flash = st.session_state.pop("flash", None)
    if flash:
        if flash[0] == "success":
            st.toast(flash[1].split("\n")[0], icon="✅")
        getattr(st, flash[0])(flash[1])
    if "conn" in st.session_state:
        if not gia_han_phien(st.session_state.get("ma_phien")):        # quá hạn không dùng: bắt đăng nhập lại
            st.session_state.clear()
            st.query_params.clear()
            st.warning("Phiên đăng nhập đã hết hạn, vui lòng đăng nhập lại.")
    else:
        khoi_phuc_phien()
    if "conn" not in st.session_state:
        dang_nhap()
        return
    st.html(CSS)
    trang = thanh_ben(st.session_state.user, MENU[st.session_state.user])
    st.query_params["trang"] = trang                                     # tải lại trang vẫn ở đúng chức năng
    st.header(f":material/{BIEU_TUONG[trang]}: {trang}", anchor=False)
    st.caption(MO_TA[trang])
    TRANG[trang]()


main()
