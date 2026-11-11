"""Quản lý sinh viên nhiều khoa - CSDL phân tán.  Chạy:  streamlit run app.py

Ứng dụng chỉ gọi node điều phối QLSV_TongHop (VIEW, hàm, thủ tục); thủ tục tự tìm đúng node.
Mỗi vai trò đăng nhập bằng một SQL login riêng (xem database/10_security.sql) nên quyền do SQL Server kiểm soát,
ứng dụng chỉ ẩn bớt chức năng cho gọn.
"""
import os
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
GIAOVU = ["Thống kê", "Tìm kiếm", "Bảng điểm", "Cảnh báo học vụ", "Nhập điểm"]
DAOTAO = GIAOVU + ["Sinh viên", "Đăng ký học phần", "Lớp học phần", "Danh mục", "Phân tán", "Nhật ký"]
MENU = {"lg_bgh": ["Thống kê"], "lg_daotao": DAOTAO, "lg_admin": DAOTAO + ["Kiểm thử", "Phân quyền"],
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
            "SoMonCoDiem": "Số môn có điểm", "SoMon": "Số môn có điểm",
            "SoMonKhongDat": "Môn không đạt", "LyDo": "Lý do cảnh báo", "TinChiTichLuy": "Tín chỉ tích lũy", "NodeKhoa": "Node",
            "ThoiGian": "Thời gian", "TenBang": "Bảng", "HanhDong": "Hành động", "KhoaChinh": "Khóa chính",
            "NoiDungCu": "Trước", "NoiDungMoi": "Sau", "NguoiThucHien": "Người thực hiện", "Node": "Node",
            "TenHK": "Tên học kỳ", "NamHoc": "Năm học", "NgayBatDau": "Bắt đầu", "NgayKetThuc": "Kết thúc", "LoaiMH": "Loại môn",
            "HocVi": "Học vị", "NienKhoa": "Niên khóa", "MaGVCN": "GV chủ nhiệm", "SoMucCho": "Số mục chờ", "Loi": "Lỗi",
            "SoLanThu": "Số lần thử", "LoiGanNhat": "Lỗi gần nhất", "Bang": "Bảng",
            "CCCD": "CCCD", "DienThoai": "Điện thoại", "Email": "Email", "DiaChi": "Địa chỉ",
            "MaLoi": "Mã lỗi", "ThongBao": "Thông báo"}

# Thanh bên: chức năng chia nhóm, mỗi chức năng một biểu tượng (Material Symbols) và một dòng mô tả dưới tiêu đề trang
NHOM_MENU = [("Tổng quan", ["Thống kê"]), ("Tra cứu", ["Tìm kiếm", "Bảng điểm", "Cảnh báo học vụ"]),
             ("Nghiệp vụ", ["Nhập điểm", "Sinh viên", "Đăng ký học phần", "Lớp học phần", "Danh mục"]),
             ("Hệ thống phân tán", ["Phân tán", "Nhật ký"]), ("Quản trị", ["Kiểm thử", "Phân quyền"])]
BIEU_TUONG = {"Thống kê": "monitoring", "Tìm kiếm": "search", "Bảng điểm": "grading", "Cảnh báo học vụ": "warning", "Nhập điểm": "edit_note",
              "Sinh viên": "group", "Đăng ký học phần": "how_to_reg", "Lớp học phần": "class", "Danh mục": "category",
              "Phân tán": "hub", "Nhật ký": "history", "Kiểm thử": "science", "Phân quyền": "shield_person"}
MO_TA = {"Thống kê": "Kết quả học tập theo khoa và học kỳ, tổng hợp từ cả 3 node.",
         "Tìm kiếm": "Tìm sinh viên toàn trường theo mã, họ tên (không cần gõ dấu), khoa, lớp, trạng thái.",
         "Bảng điểm": "Bảng điểm của một sinh viên hoặc của cả lớp, lịch sử sửa điểm, tải về file CSV.",
         "Cảnh báo học vụ": "Sinh viên có điểm trung bình tích lũy thấp hoặc có môn không đạt, tổng hợp từ cả 3 node.",
         "Nhập điểm": "Nhập, sửa điểm quá trình và điểm thi. Điểm tổng kết được tính tự động.",
         "Sinh viên": "Thêm, sửa, xóa và chuyển khoa. Mỗi thao tác ghi cả hai mảnh dữ liệu trong một giao dịch.",
         "Đăng ký học phần": "Đăng ký hoặc hủy lớp học phần cho một sinh viên.",
         "Lớp học phần": "Mở lớp học phần mới ở node của khoa giảng viên.",
         "Danh mục": "Thêm, sửa môn học, học kỳ (tự đồng bộ xuống 3 node) và giảng viên, lớp (ghi vào node của khoa).",
         "Phân tán": "Dữ liệu nằm ở node nào, một sinh viên được ghép từ đâu, và demo giao dịch phân tán.",
         "Nhật ký": "Các thay đổi do trigger ghi lại ở từng node.",
         "Kiểm thử": "Chạy thử hàm, thủ tục và trigger, đối chiếu với kết quả mong đợi. Mọi thay đổi đều được hoàn tác.",
         "Phân quyền": "Cùng 8 việc, thử dưới từng vai trò: ai được làm gì, ai bị SQL Server từ chối."}


def thu_tu_hk(ma):
    """Khóa sắp xếp học kỳ theo thời gian: 'HK2-2425' -> ('2425', 'HK2') (xếp theo chữ cái thì HK1-2526 đứng trước HK2-2425)."""
    return ma[4:], ma[:3]


# ----------------------------------------------------------------- kết nối và truy vấn
def ket_noi(user, pwd):
    cs = (f"DRIVER={{{config.DRIVER}}};SERVER={config.SERVER};DATABASE={config.DATABASE};"
          f"UID={user};PWD={pwd};TrustServerCertificate=yes;MARS_Connection=yes")     # MARS: cho phép nhiều tập kết quả mở cùng lúc
    conn = pyodbc.connect(cs, autocommit=True, timeout=10)
    conn.timeout = 30          # câu lệnh bị khóa chặn quá 30 giây thì báo lỗi thay vì treo mãi
    return conn


def loi(e):
    """Lấy thông báo gốc của SQL Server, bỏ phần driver."""
    msg = str(e.args[-1]).split("[SQL Server]")[-1]
    msg = re.sub(r"^\[\w+\]\s*\[Microsoft\]\[[^\]]*\]", "", msg).strip()
    return re.sub(r"\s*\(\d+\)\s*(\(SQLExec\w+\))?\s*['\")]*\s*$", "", msg).strip()


@st.cache_resource
def _kho_khoa():
    return {"khoa": threading.Lock(), "theo_ket_noi": {}}


def khoa_ket_noi(conn=None):
    """Khóa riêng của kết nối đang dùng. Một phiên đăng nhập chỉ có MỘT kết nối, nhưng có thể bị dùng từ nhiều luồng
    cùng lúc (mở ứng dụng ở hai tab, hoặc bấm liên tiếp khi trang cũ chưa chạy xong); SQL Server khi đó báo
    "Connection is busy with results for another command". Mọi lệnh phải giữ khóa này từ lúc chạy tới lúc đọc hết kết quả."""
    kho, conn = _kho_khoa(), conn or st.session_state.conn
    with kho["khoa"]:
        return kho["theo_ket_noi"].setdefault(id(conn), threading.RLock())


def chay(sql, *tham_so):
    """Chạy câu lệnh, trả về danh sách DataFrame (mỗi tập kết quả một cái)."""
    with khoa_ket_noi():
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
    return st.dataframe(sty, column_config=cau_hinh, hide_index=True, width="stretch", **kw)


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
    """Hai biểu đồ điểm trung bình, trục điểm cố định 0-10, vạch ngưỡng đạt (4). Bấm tên khoa ở chú giải để làm nổi
    bật khoa đó trên cả hai biểu đồ; rê chuột vào cột hoặc điểm để xem số."""
    truc = alt.Y("DiemTB:Q", title="Điểm trung bình", scale=alt.Scale(domain=[0, 10]), axis=alt.Axis(values=list(range(0, 11, 2))))
    tip = [alt.Tooltip("TenKhoa:N", title="Khoa"), alt.Tooltip("MaHK:N", title="Học kỳ"),
           alt.Tooltip("DiemTB:Q", title="Điểm TB", format=".2f"), alt.Tooltip("TyLeDat:Q", title="Tỷ lệ đạt (%)", format=".1f"),
           alt.Tooltip("SoLuotCoDiem:Q", title="Lượt có điểm"), alt.Tooltip("SoSinhVien:Q", title="Số sinh viên")]
    hk = alt.X("MaHK:N", title=None, sort=sorted(df["MaHK"].unique(), key=thu_tu_hk), axis=alt.Axis(labelAngle=0))
    mau = alt.Color("TenKhoa:N", title=None, scale=mau_khoa(), legend=alt.Legend(orient="bottom", labelLimit=0))
    chon = alt.selection_point(name="chon_khoa", fields=["TenKhoa"], bind="legend")   # bấm chú giải: chọn khoa (Shift: chọn nhiều)
    re_chuot = alt.selection_point(name="re_chuot", on="pointerover", nearest=True, empty=False, fields=["TenKhoa", "MaHK"])
    mo = alt.condition(chon, alt.value(1), alt.value(0.15))
    nguong = alt.Chart(pd.DataFrame({"y": [4]})).mark_rule(color="#dc2626", strokeDash=[5, 4]).encode(y="y:Q")
    cot = alt.Chart(df).mark_bar(cornerRadiusTopLeft=3, cornerRadiusTopRight=3).encode(
        x=hk, xOffset="TenKhoa:N", y=truc, color=mau, opacity=mo, tooltip=tip)
    duong = alt.Chart(df).mark_line(strokeWidth=2.5).encode(x=hk, y=truc, color=mau, opacity=mo)
    diem = alt.Chart(df).mark_point(filled=True).encode(
        x=hk, y=truc, color=mau, opacity=mo, tooltip=tip,
        size=alt.condition(re_chuot, alt.value(220), alt.value(70))).add_params(re_chuot)
    ve = alt.hconcat((cot + nguong).properties(title="So sánh các khoa theo học kỳ", height=280),
                     (duong + diem + nguong).properties(title="Xu hướng qua các học kỳ", height=280)
                     ).add_params(chon).configure_title(anchor="start", fontSize=14).configure_view(stroke=None)
    with st.container(border=True):
        st.altair_chart(ve, width="stretch")
    st.caption(":material/touch_app: Bấm tên khoa ở chú giải để làm nổi bật (bấm chỗ trống để bỏ chọn); rê chuột để xem số. "
               "Vạch đỏ nét đứt là ngưỡng đạt (điểm 4).")


def ban_do_nhiet(df):
    """Tỷ lệ đạt của từng khoa ở từng học kỳ: ô càng đậm tỷ lệ càng cao, số ghi ngay trong ô."""
    goc = alt.Chart(df).encode(
        x=alt.X("MaHK:N", title=None, sort=sorted(df["MaHK"].unique(), key=thu_tu_hk), axis=alt.Axis(labelAngle=0, orient="top")),
        y=alt.Y("TenKhoa:N", title=None, axis=alt.Axis(labelLimit=0)),   # labelLimit=0: không cắt tên khoa dài
        tooltip=[alt.Tooltip("TenKhoa:N", title="Khoa"), alt.Tooltip("MaHK:N", title="Học kỳ"),
                 alt.Tooltip("TyLeDat:Q", title="Tỷ lệ đạt (%)", format=".1f"), alt.Tooltip("SoLuotKhongDat:Q", title="Lượt không đạt"),
                 alt.Tooltip("SoLuotCoDiem:Q", title="Lượt có điểm"), alt.Tooltip("DiemTB:Q", title="Điểm TB", format=".2f")])
    o = goc.mark_rect(cornerRadius=4, stroke="white", strokeWidth=3).encode(
        color=alt.Color("TyLeDat:Q", title="Tỷ lệ đạt (%)", scale=alt.Scale(domain=[min(90, float(df["TyLeDat"].min())), 100], scheme="greens"),
                        legend=None))
    chu = goc.mark_text(fontSize=13, fontWeight=600).encode(
        text=alt.Text("TyLeDat:Q", format=".1f"),
        color=alt.condition(alt.datum.TyLeDat > 97, alt.value("white"), alt.value("#14532d")))
    with st.container(border=True):
        st.markdown("**Tỷ lệ đạt (%) theo khoa và học kỳ**")
        st.altair_chart((o + chu).properties(height=60 + 46 * df["TenKhoa"].nunique()).configure_view(stroke=None), width="stretch")


def the_xu_huong(cot, nhan, theo_hk, dinh_dang, tro_giup, to_mau=True):
    """Thẻ số liệu: giá trị của học kỳ mới nhất có số (ghi rõ học kỳ), chênh lệch so với học kỳ liền trước, đường xu hướng nhỏ.
    to_mau=False: mũi tên màu xám (tăng giảm số lượng không hẳn tốt hay xấu)."""
    gt = theo_hk.dropna()
    if gt.empty:
        cot.metric(nhan, "-", help=tro_giup, border=True)
        return
    lech = None if len(gt) < 2 else round(float(gt.iloc[-1] - gt.iloc[-2]), 2)      # hiệu của hai số đã làm tròn như đang hiển thị
    if lech is not None and float(lech).is_integer():
        lech = int(lech)
    cot.metric(f"{nhan} · {gt.index[-1]}", dinh_dang(gt.iloc[-1]), delta=lech, delta_color="normal" if to_mau else "off",
               help=tro_giup + (f" Mũi tên: so với {gt.index[-2]}." if lech is not None else ""),
               border=True, chart_data=[float(v) for v in gt], chart_type="area")


def thong_ke():
    df = xem("SELECT MaKhoa, TenKhoa, MaHK, SoSinhVien, SoLuotDangKy, SoLuotCoDiem, SoLuotKhongDat, DiemTB, TyLeDat, TongDiem "
             "FROM dbo.vw_ThongKe_Khoa_HocKy")
    if df is None or df.empty:
        return
    khoa_xem = df[["MaKhoa", "TenKhoa"]].drop_duplicates().sort_values("TenKhoa")
    if len(khoa_xem) == 1:        # giáo vụ: SQL Server chỉ trả khoa của họ
        st.info(f"Bạn chỉ xem được thống kê của khoa {khoa_xem.iloc[0]['TenKhoa']}.")
    else:                         # lọc nhanh theo khoa: mọi thẻ số liệu và biểu đồ bên dưới đổi theo
        ten = dict(zip(khoa_xem["MaKhoa"], khoa_xem["TenKhoa"]))
        chon = st.pills("Khoa", list(ten), selection_mode="multi", default=list(ten), format_func=ten.get, key="tk_loc_khoa",
                        label_visibility="collapsed")
        if not chon:
            st.info("Chọn ít nhất một khoa để xem thống kê.")
            return
        df = df[df["MaKhoa"].isin(chon)]
    thu_tu = sorted(df["MaHK"].unique(), key=thu_tu_hk)

    # Một học kỳ chỉ được tính điểm khi đã có điểm cho ít nhất nửa số lượt đăng ký; học kỳ đang học mới có vài điểm lẻ
    # sẽ cho điểm trung bình không đại diện.
    g = df.groupby("MaHK")[["SoSinhVien", "SoLuotDangKy", "SoLuotCoDiem", "SoLuotKhongDat", "TongDiem"]].sum().reindex(thu_tu)
    da_chot = g.index[g["SoLuotCoDiem"] * 2 >= g["SoLuotDangKy"]].tolist()
    chua_chot = [h for h in thu_tu if h not in da_chot]
    co = df[df["MaHK"].isin(da_chot) & df["SoLuotCoDiem"].gt(0)]
    # Gộp các khoa đang chọn từ TỔNG, không lấy trung bình của các số đã làm tròn: điểm TB = tổng điểm / số lượt có điểm
    diem_tb = (g["TongDiem"] / g["SoLuotCoDiem"]).reindex(da_chot).round(2)
    ty_le = (100 * (1 - g["SoLuotKhongDat"] / g["SoLuotCoDiem"])).reindex(da_chot).round(1)

    c = st.columns(4)
    the_xu_huong(c[0], "Sinh viên", g["SoSinhVien"], lambda v: f"{int(v)}",
                 "Số sinh viên có đăng ký học phần trong học kỳ.", to_mau=False)
    the_xu_huong(c[1], "Lượt đăng ký", g["SoLuotDangKy"], lambda v: f"{int(v)}",
                 f"Cộng cả {len(thu_tu)} học kỳ: {int(g['SoLuotDangKy'].sum())} lượt.", to_mau=False)
    the_xu_huong(c[2], "Điểm TB", diem_tb, lambda v: f"{v:.2f}",
                 "Điểm tổng kết trung bình của các lượt đã có điểm.")
    the_xu_huong(c[3], "Tỷ lệ đạt", ty_le, lambda v: f"{v:.1f}%",
                 "Số lượt có điểm tổng kết từ 4 trở lên trên số lượt đã có điểm.")
    if chua_chot:
        st.caption(f":material/hourglass_top: {', '.join(chua_chot)} đang học: mới có điểm cho "
                   f"{int(g.loc[chua_chot, 'SoLuotCoDiem'].sum())}/{int(g.loc[chua_chot, 'SoLuotDangKy'].sum())} lượt đăng ký, "
                   "nên chưa tính vào điểm trung bình, tỷ lệ đạt và các biểu đồ điểm.")

    if co.empty:
        st.info("Chưa có học kỳ nào đủ điểm để vẽ biểu đồ.")
    else:
        st.subheader("Điểm trung bình theo khoa và học kỳ", anchor=False)
        bieu_do_diem(co)
        ban_do_nhiet(co)
    with st.expander("Xem bảng số liệu (mọi học kỳ)"):
        bang(df.drop(columns="MaKhoa").sort_values(["MaHK", "TenKhoa"], key=lambda c: c.map(thu_tu_hk) if c.name == "MaHK" else c),
             diem=["DiemTB"], phan_tram=["TyLeDat"])

    st.subheader("Phân bố học lực", anchor=False)
    hk = st.pills("Học kỳ", ["Tất cả"] + list(reversed(da_chot)), default="Tất cả", key="tk_hk") or "Tất cả"
    ph = xem("EXEC dbo.sp_ThongKeKhoa @MaKhoa = NULL, @MaHK = ?", None if hk == "Tất cả" else hk)
    if ph is not None:
        ph = ph[ph["TenKhoa"].isin(df["TenKhoa"])]              # theo các khoa đang chọn ở đầu trang
    if ph is None or ph.empty or ph["SoLuotCoDiem"].sum() == 0:
        st.info("Chưa có điểm trong phạm vi đã chọn.")
        return
    dai = ph.melt(id_vars=["TenKhoa", "SoLuotCoDiem"], value_vars=list(HOC_LUC_COT), var_name="HocLuc", value_name="SoLuot")
    dai["HocLuc"] = dai["HocLuc"].map(HOC_LUC_COT)
    dai["TyLe"] = dai["SoLuot"] / dai["SoLuotCoDiem"]
    dai["ThuTu"] = dai["HocLuc"].map({h: i for i, h in enumerate(HOC_LUC)})
    chon_hl = alt.selection_point(name="chon_hoc_luc", fields=["HocLuc"], bind="legend")
    thanh = alt.Chart(dai).mark_bar(cornerRadius=3, stroke="white", strokeWidth=1.5).encode(
        y=alt.Y("TenKhoa:N", title=None, axis=alt.Axis(labelLimit=0)),   # labelLimit=0: không cắt tên khoa dài
        x=alt.X("SoLuot:Q", stack="normalize", title="Tỷ lệ trên số lượt có điểm", axis=alt.Axis(format="%")),
        color=alt.Color("HocLuc:N", title=None, sort=list(HOC_LUC), legend=alt.Legend(orient="bottom"),
                        scale=alt.Scale(domain=list(HOC_LUC), range=[c[0] for c in HOC_LUC.values()])),
        order=alt.Order("ThuTu:Q"), opacity=alt.condition(chon_hl, alt.value(1), alt.value(0.2)),
        tooltip=[alt.Tooltip("TenKhoa", title="Khoa"), alt.Tooltip("HocLuc", title="Học lực"),
                 alt.Tooltip("SoLuot", title="Số lượt"), alt.Tooltip("TyLe", title="Tỷ lệ", format=".1%")]).add_params(chon_hl)
    with st.container(border=True):
        st.altair_chart(thanh.properties(height=70 + 44 * len(ph)).configure_view(stroke=None), width="stretch")
    st.caption("Giỏi ≥ 8 · Khá ≥ 6,5 · Trung bình ≥ 5 · Yếu ≥ 4 · Không đạt < 4. Bấm một mức ở chú giải để làm nổi bật.")
    bang(ph, diem=["DiemTB"])

    try:                                   # hàm này chỉ cấp cho Đào tạo và Quản trị; vai trò khác thì bỏ qua phần xếp hạng
        top = chay("SELECT MaSV, HoTen, TenKhoa, SoMon, DiemTB FROM dbo.fn_TopSinhVien(NULL, 100, 8)")[0]
    except pyodbc.Error:
        return
    top = top[top["TenKhoa"].isin(df["TenKhoa"])].head(5).reset_index(drop=True)
    if top.empty:
        return
    st.subheader("Sinh viên dẫn đầu", anchor=False)
    st.caption("5 sinh viên có điểm trung bình tích lũy cao nhất trong các khoa đang chọn (cần ít nhất 8 môn có điểm).")
    top.insert(0, "Hạng", ["🥇", "🥈", "🥉", "4", "5"][:len(top)])
    bang(top, diem=["DiemTB"])


def bieu_do_bang_diem(df):
    """Điểm tổng kết từng môn của một sinh viên, xếp theo học kỳ, tô màu theo học lực; rê chuột để xem chi tiết."""
    d = df.dropna(subset=["DiemTK"]).copy()
    if d.empty:
        return
    d["HocLuc"] = d["DiemTK"].map(muc_hoc_luc)
    d = d.sort_values("MaHK", key=lambda c: c.map(thu_tu_hk))
    cot = alt.Chart(d).mark_bar(cornerRadiusTopLeft=3, cornerRadiusTopRight=3).encode(
        x=alt.X("TenMH:N", title=None, sort=d["TenMH"].tolist(), axis=alt.Axis(labelAngle=-35, labelLimit=140)),
        y=alt.Y("DiemTK:Q", title="Điểm tổng kết", scale=alt.Scale(domain=[0, 10])),
        color=alt.Color("HocLuc:N", title=None, sort=list(HOC_LUC), legend=alt.Legend(orient="bottom"),
                        scale=alt.Scale(domain=list(HOC_LUC), range=[c[0] for c in HOC_LUC.values()])),
        tooltip=[alt.Tooltip("TenMH", title="Môn"), alt.Tooltip("MaHK", title="Học kỳ"),
                 alt.Tooltip("DiemQT", title="Quá trình", format=".1f"), alt.Tooltip("DiemThi", title="Thi", format=".1f"),
                 alt.Tooltip("DiemTK", title="Tổng kết", format=".2f"), alt.Tooltip("HocLuc", title="Xếp loại")])
    nguong = alt.Chart(pd.DataFrame({"y": [4]})).mark_rule(color="#dc2626", strokeDash=[5, 4]).encode(y="y:Q")
    st.altair_chart((cot + nguong).properties(height=280), width="stretch")


def the_sinh_vien(sv):
    """Thẻ chi tiết một sinh viên (dict một dòng của vw_SinhVien_ToanCuc): thông tin, số liệu tích lũy, biểu đồ điểm."""
    with st.container(border=True):
        a, b = st.columns([3, 2], vertical_alignment="center")
        a.markdown(f"#### {sv['HoTen']}")
        a.caption(f"`{sv['MaSV']}` · lớp {sv['MaLop']} · sinh ngày {sv['NgaySinh']} · {sv['GioiTinh']}")
        with b.container(horizontal=True, horizontal_alignment="right"):
            st.badge(sv["TenKhoa"], color=HUY_HIEU_KHOA.get(
                {"Công nghệ thông tin": "CNTT", "Ngoại ngữ": "NN", "Du lịch": "DL"}.get(sv["TenKhoa"]), "gray"))
            st.badge(sv["TrangThai"], color={"Đang học": "green", "Bảo lưu": "orange", "Thôi học": "red"}.get(sv["TrangThai"], "blue"))
        try:
            diem, tong = chay("EXEC dbo.sp_BangDiemSinhVien @MaSV = ?", sv["MaSV"])
        except pyodbc.Error as e:
            st.error(loi(e))
            return
        t = tong.iloc[0]
        m = st.columns(3)
        m[0].metric("Điểm TB tích lũy", "-" if pd.isna(t["DiemTBTichLuy"]) else f"{t['DiemTBTichLuy']:.2f}")
        m[1].metric("Tín chỉ tích lũy", int(t["TinChiTichLuy"] or 0))
        m[2].metric("Số môn có điểm", int(t["SoMonCoDiem"]))
        if diem.empty:
            st.info("Sinh viên chưa đăng ký lớp học phần nào.")
        else:
            bieu_do_bang_diem(diem)
            with st.expander("Bảng điểm chi tiết"):
                bang(diem, diem=["DiemQT", "DiemThi"], tk=["DiemTK"])


def tim_kiem(k="tk"):
    """Lọc ngay khi gõ hoặc đổi bộ lọc (không cần bấm nút); bấm một dòng để mở thẻ chi tiết sinh viên."""
    tu_khoa = st.text_input("Mã sinh viên hoặc họ tên", placeholder="Gõ rồi Enter, ví dụ: nguyen, 2401 (không cần gõ dấu)",
                            icon=":material/search:", key=f"{k}_tu_khoa")
    a, b, c = st.columns(3)
    ds_khoa = khoa_duoc_xem()
    khoa = a.selectbox("Khoa", [None] + ds_khoa if len(ds_khoa) > 1 else ds_khoa, format_func=KHOA.get, key=f"{k}_khoa")
    ds_lop = danh_sach("SELECT DISTINCT MaLop FROM dbo.vw_SinhVien_ToanCuc WHERE (? IS NULL OR MaKhoa = ?) ORDER BY MaLop", "MaLop", khoa, khoa)
    lop = b.selectbox("Lớp", [None] + ds_lop, format_func=lambda l: "Tất cả lớp" if l is None else l, key=f"{k}_lop")
    tt = c.selectbox("Trạng thái", [None] + TRANG_THAI, format_func=lambda t: "Tất cả" if t is None else t, key=f"{k}_tt")
    df = xem("EXEC dbo.sp_TimSinhVien @TuKhoa = ?, @MaKhoa = ?, @MaLop = ?, @TrangThai = ?", tu_khoa or None, khoa, lop, tt)
    if df is None:
        return
    if df.empty:
        st.info("Không tìm thấy sinh viên nào khớp điều kiện. Thử bỏ bớt điều kiện lọc.", icon=":material/search_off:")
        return
    st.caption(f"**{len(df)}** sinh viên" + (" (tối đa 100)" if len(df) == 100 else "")
               + " · :material/touch_app: bấm vào một dòng để xem chi tiết")
    chon = bang(df, on_select="rerun", selection_mode="single-row", key=f"{k}_bang", height=min(38 * len(df) + 40, 390))
    dong = chon.selection.rows if chon is not None else []
    if dong and dong[0] < len(df):
        the_sinh_vien(df.iloc[dong[0]].to_dict())


def trang_tim_kiem():
    tim_kiem()


def nut_tai_csv(df, ten_tep, nhan="Tải về CSV", key=None):
    """Nút tải bảng về file CSV. Mã hóa UTF-8 có BOM để Excel mở đúng tiếng Việt; tiêu đề cột bằng tiếng Việt."""
    du_lieu = df.rename(columns=NHAN_COT).to_csv(index=False).encode("utf-8-sig")
    st.download_button(nhan, du_lieu, file_name=ten_tep, mime="text/csv", icon=":material/download:", key=key)


def lich_su_diem(sv):
    """Các lần sửa điểm, xóa đăng ký của một sinh viên, do trigger trg_DangKy_GhiNhatKy ghi ở node của khoa."""
    db = DB_THEO_KHOA[sv["MaKhoa"]]                                   # tên database lấy từ danh sách cố định
    df = xem(f"SELECT ThoiGian, KhoaChinh, HanhDong, NoiDungCu, NoiDungMoi, NguoiThucHien FROM {db}.dbo.NhatKy "
             "WHERE TenBang = N'DangKy' AND KhoaChinh LIKE ? ORDER BY ThoiGian DESC, MaNK DESC", sv["MaSV"] + "|%")
    if df is None:
        return
    if df.empty:
        st.caption("Chưa có lần sửa điểm nào được ghi cho sinh viên này. Nhật ký do trigger ở node ghi mỗi khi điểm bị sửa "
                   "hoặc đăng ký bị xóa.")
        return
    df.insert(1, "MaLHP", df.pop("KhoaChinh").str.split("|").str[1])
    df["NguoiThucHien"] = df["NguoiThucHien"].map(lambda u: f"{VAI_TRO[u]} ({u})" if u in VAI_TRO else u)
    st.caption(f"{len(df)} lần thay đổi, mới nhất ở trên. Dữ liệu lấy từ bảng `NhatKy` của node `{db}`.")
    bang(df)


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
                    with st.container(border=True):
                        bieu_do_bang_diem(kq[0])
                    bang(kq[0], diem=["DiemQT", "DiemThi"], tk=["DiemTK"])
                    nut_tai_csv(kq[0], f"bang_diem_{sv['MaSV']}{'_' + hk if hk else ''}.csv", key="tai_bd_sv")
                with st.expander("Lịch sử sửa điểm"):
                    lich_su_diem(sv)
    with t2:
        lop = st.selectbox("Lớp", danh_sach("SELECT DISTINCT MaLop FROM dbo.vw_SinhVien_ToanCuc ORDER BY 1", "MaLop"))
        if lop:
            df = xem("SELECT * FROM dbo.fn_DanhSachLop(?) ORDER BY MaSV", lop)
            if df is not None:
                bang(df, tk=["DiemTBTichLuy"])
                nut_tai_csv(df, f"danh_sach_lop_{lop}.csv", key="tai_bd_lop")


def canh_bao():
    """Sinh viên cần chú ý: điểm TB tích lũy dưới ngưỡng, hoặc số môn không đạt từ một mức trở lên."""
    df = xem("SELECT MaSV, HoTen, TenLop, TenKhoa, COUNT(DiemTK) AS SoMonCoDiem, "
             "SUM(CASE WHEN DiemTK < 4 THEN 1 ELSE 0 END) AS SoMonKhongDat, "
             "CAST(SUM(DiemTK * SoTinChi) / NULLIF(SUM(CASE WHEN DiemTK IS NOT NULL THEN SoTinChi END), 0) AS DECIMAL(4,2)) AS DiemTBTichLuy "
             "FROM dbo.vw_BangDiem GROUP BY MaSV, HoTen, TenLop, TenKhoa HAVING COUNT(DiemTK) > 0")
    if df is None:
        return
    if df.empty:
        st.info("Chưa có sinh viên nào có điểm.")
        return
    a, b = st.columns(2)
    nguong = a.slider("Cảnh báo khi điểm TB tích lũy dưới", 4.0, 8.0, 6.0, 0.1, key="cb_nguong")
    so_mon = b.slider("hoặc số môn không đạt (điểm tổng kết dưới 4) từ", 1, 5, 1, key="cb_so_mon")
    thap, rot = df["DiemTBTichLuy"] < nguong, df["SoMonKhongDat"] >= so_mon
    cb = df[thap | rot].copy()
    cb["LyDo"] = [" + ".join(x for x in (f"điểm TB dưới {nguong:.1f}" if t else "", f"{int(n)} môn không đạt" if r else "") if x)
                  for t, r, n in zip(thap[thap | rot], rot[thap | rot], cb["SoMonKhongDat"])]
    cb = cb.sort_values(["DiemTBTichLuy", "SoMonKhongDat"], ascending=[True, False]).reset_index(drop=True)
    m = st.columns(4)
    m[0].metric("Sinh viên bị cảnh báo", len(cb), help=f"Trên {len(df)} sinh viên đã có điểm.", border=True)
    m[1].metric("Tỷ lệ", f"{100 * len(cb) / len(df):.1f}%", border=True)
    m[2].metric(f"Điểm TB dưới {nguong:.1f}", int(thap.sum()), border=True)
    m[3].metric(f"Từ {so_mon} môn không đạt", int(rot.sum()), border=True)
    if cb.empty:
        st.success("Không có sinh viên nào chạm ngưỡng cảnh báo.", icon=":material/check_circle:")
        return
    if cb["TenKhoa"].nunique() > 1:
        dem = cb.groupby("TenKhoa").size().reset_index(name="SoSV")
        with st.container(border=True):
            st.altair_chart(alt.Chart(dem).mark_bar(cornerRadius=3).encode(
                y=alt.Y("TenKhoa:N", title=None, axis=alt.Axis(labelLimit=0)), x=alt.X("SoSV:Q", title="Số sinh viên bị cảnh báo", axis=alt.Axis(tickMinStep=1)),
                color=alt.Color("TenKhoa:N", scale=mau_khoa(), legend=None),
                tooltip=[alt.Tooltip("TenKhoa", title="Khoa"), alt.Tooltip("SoSV", title="Số sinh viên")]).properties(height=50 + 34 * len(dem)),
                width="stretch")
    st.caption(f"**{len(cb)}** sinh viên, điểm thấp nhất ở trên · :material/touch_app: bấm vào một dòng để xem chi tiết")
    chon = bang(cb, tk=["DiemTBTichLuy"], on_select="rerun", selection_mode="single-row", key="cb_bang",
                height=min(38 * len(cb) + 40, 390))
    nut_tai_csv(cb, "canh_bao_hoc_vu.csv", key="tai_cb")
    dong = chon.selection.rows if chon is not None else []
    if dong and dong[0] < len(cb):
        sv = xem("SELECT MaSV, HoTen, NgaySinh, GioiTinh, MaLop, TenKhoa, TrangThai FROM dbo.vw_SinhVien_ToanCuc WHERE MaSV = ?",
                 cb.iloc[dong[0]]["MaSV"])
        if sv is not None and not sv.empty:
            the_sinh_vien(sv.iloc[0].to_dict())


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
        tim_kiem("sv")
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


HAU_TO_THU = " (bản mới)"          # demo đồng bộ: sửa tên môn = thêm hậu tố này, bỏ sửa = gỡ hậu tố


def bao_dong_bo(kq):
    """Thông báo kết quả dm_XuLyHangDoi (một dòng mỗi node đã thử)."""
    if kq is None or kq.empty:
        st.toast("Hàng đợi rỗng, không có gì để đồng bộ.", icon="ℹ️")
        return
    cho = kq[kq["KetQua"] != "Đã đồng bộ"]
    if cho.empty:
        st.toast(f"Đã đồng bộ xuống {len(kq)} node.", icon="✅")
    else:
        st.warning(f"Đã đồng bộ {len(kq) - len(cho)}/{len(kq)} node. Node chưa nhận: {', '.join(KHOA[k] for k in cho['Node'])} "
                   "(không trả lời). Thay đổi nằm trong hàng đợi, bấm **Xử lý hàng đợi** khi node chạy lại.",
                   icon=":material/schedule:")


def bang_hang_doi():
    """Hàng đợi đồng bộ: mỗi dòng là một thay đổi danh mục mà một node chưa nhận."""
    hd = xem("SELECT MaKhoa, Bang, KhoaChinh, HanhDong, ThoiGian, SoLanThu, LoiGanNhat FROM dbo.HangDoiDongBo ORDER BY MaHD")
    if hd is None:
        return 0
    if hd.empty:
        st.success("Hàng đợi rỗng: mọi node đã nhận đủ thay đổi của danh mục.", icon=":material/check_circle:")
        return 0
    hd["MaKhoa"] = hd["MaKhoa"].map(lambda k: f"Node {KHOA.get(k, k)}")
    st.warning(f"**{len(hd)}** mục đang chờ trong hàng đợi.", icon=":material/schedule:")
    st.dataframe(hd, hide_index=True, width="stretch", column_config={
        "MaKhoa": "Node chưa nhận", "Bang": "Bảng", "KhoaChinh": "Khóa", "HanhDong": "Hành động", "ThoiGian": "Lúc",
        "SoLanThu": "Số lần thử", "LoiGanNhat": "Lỗi gần nhất"})
    return len(hd)


def pt_dong_bo():
    """Mục 6: sửa thẳng một môn ở bản chính -> trigger xếp hàng đợi -> xử lý hàng đợi chép xuống các node đang sống."""
    st.markdown("Khoa, Học kỳ, Môn học được **nhân bản**: bản chính ở điều phối, mỗi node giữ một bản sao. Khi bản chính đổi, "
                "trigger ghi vào **hàng đợi** một mục cho mỗi node; xử lý hàng đợi chép thay đổi xuống. Node mất kết nối thì "
                "mục của nó ở lại hàng đợi cho tới khi node chạy lại. Trang **Danh mục** sửa qua thủ tục nên tự xử lý hàng đợi ngay.")
    mon = xem("SELECT MaMH, TenMH FROM dbo.MonHoc ORDER BY MaMH")
    if mon is None or mon.empty:
        return
    ten = dict(zip(mon["MaMH"], mon["TenMH"]))
    ma = st.selectbox("Môn học", list(ten), format_func=lambda m: f"{m} - {ten[m]}", key="db_mon")
    quan_tri = st.session_state.user == "lg_admin"
    da_sua = ten[ma].endswith(HAU_TO_THU)
    c1, c2, c3 = st.columns(3)
    if c1.button("Bỏ sửa ở bản chính" if da_sua else "1. Sửa thẳng tên ở bản chính", icon=":material/edit:", width="stretch",
                 disabled=not quan_tri, help="Chạy UPDATE thẳng vào bảng MonHoc (không qua thủ tục), để thấy hàng đợi trước khi xử lý."
                 if quan_tri else "Chỉ Quản trị sửa thẳng được bảng danh mục; Phòng Đào tạo sửa ở trang Danh mục (qua thủ tục)."):
        moi = ten[ma][:-len(HAU_TO_THU)] if da_sua else ten[ma] + HAU_TO_THU
        try:
            chay("UPDATE dbo.MonHoc SET TenMH = ? WHERE MaMH = ?", moi, ma)
            bao("success", f"Đã đổi tên môn {ma} ở bản chính thành “{moi}”. Trigger đã xếp 3 mục vào hàng đợi; các bản sao chưa đổi.")
        except pyodbc.Error as e:
            bao("error", loi(e))
        st.rerun()
    pham_vi = c2.selectbox("Xử lý cho", [None, "CNTT", "NN", "DL"], key="db_pham_vi", label_visibility="collapsed",
                           format_func=lambda k: "Mọi node còn mục chờ" if k is None else f"Chỉ node {KHOA[k]}")
    if c3.button("2. Xử lý hàng đợi", type="primary", icon=":material/sync:", width="stretch"):
        with st.spinner("Đang đồng bộ (node mất kết nối sẽ mất khoảng 10 giây mới báo lỗi)..."):
            kq = xem("EXEC dbo.dm_XuLyHangDoi @MaKhoa = ?", pham_vi)
        st.session_state["db_kq"] = kq
        bao_dong_bo(kq)

    # Tên môn ở 4 nơi; hỏi riêng từng nơi để một node mất kết nối không làm hỏng cả bảng
    dong, goc = [], None
    for noi, db in [("Điều phối (bản chính)", "dbo"), ("Node CNTT (bản sao)", "QLSV_CNTT.dbo"),
                    ("Node Ngoại ngữ (bản sao)", "QLSV_NgoaiNgu.dbo"), ("Node Du lịch (bản sao)", "QLSV_DuLich.dbo")]:
        try:
            r = chay(f"SELECT TenMH, SoTinChi FROM {db}.MonHoc WHERE MaMH = ?", ma)[0]      # tên lấy từ danh sách cố định
            gt = (r.iloc[0]["TenMH"], int(r.iloc[0]["SoTinChi"])) if not r.empty else None
        except pyodbc.Error:
            gt = "mat"
        if goc is None:
            goc = gt
        dong.append((noi, "" if gt in (None, "mat") else gt[0],
                     "bản chính" if noi.startswith("Điều phối") else "⚠️ không kết nối được" if gt == "mat" else
                     "❌ chưa có" if gt is None else "✅ khớp" if gt == goc else "❌ lệch (bản cũ)"))
    vi_tri = pd.DataFrame(dong, columns=["Nơi lưu", "Tên môn", "Khớp bản chính"])
    to = lambda v: ("background-color: #dcfce7; color: #0f172a" if str(v).startswith("✅") else
                    "background-color: #fee2e2; color: #0f172a" if str(v).startswith("❌") else
                    "background-color: #fef9c3; color: #0f172a" if str(v).startswith("⚠️") else "")
    st.dataframe(vi_tri.style.map(to, subset=["Khớp bản chính"]), hide_index=True, width="stretch")
    bang_hang_doi()
    if st.session_state.get("db_kq") is not None and not st.session_state["db_kq"].empty:
        with st.expander("Kết quả lần xử lý hàng đợi gần nhất"):
            bang(st.session_state["db_kq"])


def pt_trang_thai():
    """Mục 5: hỏi từng instance qua Linked Server xem còn sống không, mất bao lâu để trả lời."""
    st.markdown("Điều phối gửi một câu hỏi nhỏ tới từng node qua Linked Server. Thử dừng một node "
                "(`docker stop qlsv_dulich`) rồi bấm **Kiểm tra lại**: node đó chuyển sang đỏ, các node khác vẫn xanh.")
    st.button("Kiểm tra lại", icon=":material/refresh:", key="pt_kiem_tra")           # bấm nút chỉ để chạy lại trang
    ket_qua = []
    with st.spinner("Đang hỏi 4 instance (node mất kết nối sẽ mất khoảng 10 giây mới báo lỗi)..."):
        for k, db in [("TH", "QLSV_TongHop")] + list(DB_THEO_KHOA.items()):
            cau = ("SELECT @@SERVERNAME AS MayChu, (SELECT COUNT(*) FROM dbo.MonHoc) AS SoDong" if k == "TH" else
                   f"SELECT MayChu, SoDong FROM OPENQUERY(LS_{db}, 'SELECT @@SERVERNAME AS MayChu, "
                   f"(SELECT COUNT(*) FROM {db}.dbo.SinhVien) AS SoDong')")              # tên lấy từ danh sách cố định
            bat_dau = time.time()
            try:
                r = chay(cau)[0].iloc[0]
                ket_qua.append((k, db, True, r["MayChu"], int(r["SoDong"]), time.time() - bat_dau, None))
            except pyodbc.Error as e:
                ket_qua.append((k, db, False, None, None, time.time() - bat_dau, loi(e)))
    song = sum(r[2] for r in ket_qua)
    (st.success if song == 4 else st.error)(
        f"{song}/4 instance đang hoạt động" + ("" if song == 4 else ". Dữ liệu ở node mất kết nối tạm thời không đọc, ghi được; "
                                               "view toàn cục cũng lỗi vì cần đủ 3 node."),
        icon=":material/check_circle:" if song == 4 else ":material/error:")
    for cot, (k, db, ok, may_chu, so_dong, giay, thong_bao) in zip(st.columns(4), ket_qua):
        with cot.container(border=True):
            st.badge(db, color=HUY_HIEU_KHOA[k])
            if ok:
                st.markdown(":green[:material/circle:] **Hoạt động**")
                st.metric("Thời gian trả lời", f"{giay * 1000:.0f} ms")
                st.caption(f"máy chủ `{may_chu}` · {so_dong} " + ("môn học trong danh mục gốc" if k == "TH" else "sinh viên"))
            else:
                st.markdown(":red[:material/circle:] **Mất kết nối**")
                st.metric("Báo lỗi sau", f"{giay:.1f} giây")
                st.caption(thong_bao[:160])


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
                "Bảng của từng node": pt_bang_tho, "Giao dịch phân tán": pt_giao_dich, "Trạng thái node": pt_trang_thai,
                "Đồng bộ danh mục": pt_dong_bo}


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


# ----------------------------------------------------------------- trang Kiểm thử (chỉ lg_admin)
def tren_node(db, lenh):
    """Gói một lô lệnh để chạy NGAY TRÊN instance node qua Linked Server. Trigger ở node tự ROLLBACK khi chặn lỗi;
    nếu lệnh chạy trong giao dịch phân tán của điều phối thì MSDTC báo lỗi 1206 và mất mã lỗi của trigger."""
    return f"EXEC LS_{db}.{db}.sys.sp_executesql N'" + lenh.replace("'", "''") + "'"


def thu_chan(lenh):
    """Khuôn cho ca 'phải bị chặn': luôn ROLLBACK (kể cả khi không bị chặn), trả về mã lỗi (0 = không bị chặn)."""
    return (f"BEGIN TRY BEGIN TRAN; {lenh}; ROLLBACK; SELECT 0 AS MaLoi, N'Không bị chặn' AS ThongBao; END TRY "
            "BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT ERROR_NUMBER() AS MaLoi, ERROR_MESSAGE() AS ThongBao; END CATCH")


def ca_trigger(trigger, bang, lenh, db=None):
    """Câu lệnh của một ca trigger, dạng hàm theo cờ 'mô phỏng lỗi'. Khi bật cờ, trigger bị tắt NGAY TRONG giao dịch thử
    (DISABLE TRIGGER cũng là lệnh có giao dịch), nên ROLLBACK ở cuối ca tự bật lại trigger: không cần dọn dẹp."""
    def sql(mo_phong):
        l = (f"DISABLE TRIGGER dbo.{trigger} ON dbo.{bang}; " if mo_phong else "") + lenh
        return tren_node(db, thu_chan(l)) if db else thu_chan(l)
    return sql


def ma_loi_la(ma):
    return lambda kq: int(kq[-1].iloc[0]["MaLoi"]) == ma


def cot_bang(cot, gia_tri):
    return lambda kq: list(kq[-1][cot].astype(str)) == gia_tri


BAI_KIEM_THU = [
    # (nhóm, tên, mong đợi, câu lệnh, hàm kiểm tra trên danh sách DataFrame trả về)
    ("Hàm", "fn_XepLoaiDiem: đúng các ngưỡng 8 / 4 / 3,9 / NULL", "Giỏi, Yếu, Không đạt, Chưa có điểm",
     "SELECT d AS Diem, dbo.fn_XepLoaiDiem(d) AS XepLoai FROM (VALUES (CAST(8 AS DECIMAL(4,2)), 1), (4, 2), (3.9, 3), (NULL, 4)) v(d, i) ORDER BY i",
     cot_bang("XepLoai", ["Giỏi", "Yếu", "Không đạt", "Chưa có điểm"])),
    ("Hàm", "fn_DiemTBTichLuy, fn_TinChiTichLuy: khớp với tính trực tiếp từ bảng điểm (sinh viên 24010001)",
     "Hai cột Hàm và Tính tay bằng nhau",
     "SELECT dbo.fn_DiemTBTichLuy('24010001') AS DiemTB_Ham, "
     "CAST(SUM(DiemTK * SoTinChi) / NULLIF(SUM(CASE WHEN DiemTK IS NOT NULL THEN SoTinChi END), 0) AS DECIMAL(4,2)) AS DiemTB_TinhTay, "
     "dbo.fn_TinChiTichLuy('24010001') AS TinChi_Ham, SUM(CASE WHEN DiemTK >= 4 THEN SoTinChi ELSE 0 END) AS TinChi_TinhTay, "
     "dbo.fn_XepLoaiHocLuc('24010001') AS XepLoai FROM dbo.vw_BangDiem WHERE MaSV = '24010001'",
     lambda kq: kq[0].iloc[0]["DiemTB_Ham"] == kq[0].iloc[0]["DiemTB_TinhTay"]
                and kq[0].iloc[0]["TinChi_Ham"] == kq[0].iloc[0]["TinChi_TinhTay"]),
    ("Hàm", "fn_SiSoLopHocPhan: bằng số dòng đăng ký đếm thẳng ở node CNTT", "Hai cột bằng nhau",
     "SELECT dbo.fn_SiSoLopHocPhan('CNTT110-HK1-2627-01') AS SiSo_Ham, "
     "(SELECT COUNT(*) FROM QLSV_CNTT.dbo.DangKy WHERE MaLHP = 'CNTT110-HK1-2627-01') AS SiSo_DemTaiNode",
     lambda kq: kq[0].iloc[0]["SiSo_Ham"] == kq[0].iloc[0]["SiSo_DemTaiNode"]),
    ("Hàm", "fn_TopSinhVien: 5 người, điểm giảm dần, ai cũng có >= 8 môn", "Đúng thứ tự giảm dần",
     "SELECT * FROM dbo.fn_TopSinhVien(NULL, 5, 8)",
     lambda kq: len(kq[0]) == 5 and kq[0]["DiemTB"].is_monotonic_decreasing and (kq[0]["SoMon"] >= 8).all()),
    ("Hàm", "fn_DanhSachLop: đủ mọi sinh viên của lớp 66.NN-1", "Số dòng bằng sĩ số lớp",
     "SELECT (SELECT COUNT(*) FROM dbo.fn_DanhSachLop('66.NN-1')) AS SoDong_Ham, "
     "(SELECT COUNT(*) FROM dbo.vw_SinhVien_ToanCuc WHERE MaLop = '66.NN-1') AS SiSoLop",
     lambda kq: kq[0].iloc[0]["SoDong_Ham"] == kq[0].iloc[0]["SiSoLop"]),
    ("Thủ tục", "sp_DongBoDanhMuc: sửa môn ở điều phối, chỉ node được đồng bộ nhận thay đổi",
     "CNTT: tên mới; Ngoại ngữ: tên cũ",
     "SET XACT_ABORT ON; BEGIN TRAN; "
     "UPDATE dbo.MonHoc SET TenMH = TenMH + N' (thử)' WHERE MaMH = 'CNTT101'; "
     "EXEC dbo.sp_DongBoDanhMuc @MaKhoa = 'CNTT'; "
     "SELECT N'Node CNTT (đã đồng bộ)' AS Noi, TenMH FROM QLSV_CNTT.dbo.MonHoc WHERE MaMH = 'CNTT101' "
     "UNION ALL SELECT N'Node Ngoại ngữ (chưa đồng bộ)', TenMH FROM QLSV_NgoaiNgu.dbo.MonHoc WHERE MaMH = 'CNTT101'; "
     "ROLLBACK;",
     lambda kq: kq[-1].iloc[0]["TenMH"].endswith("(thử)") and not kq[-1].iloc[1]["TenMH"].endswith("(thử)")),
    ("Thủ tục", "sp_ThemSinhVien: lỗi ở lệnh thứ hai (trùng CCCD) hủy cả lệnh thứ nhất ở node CNTT",
     "Lỗi 2627, node CNTT 0 dòng",
     "SET XACT_ABORT ON; DECLARE @c CHAR(12) = (SELECT TOP (1) CCCD FROM dbo.SinhVien_HoSo ORDER BY MaSV), @loi INT = 0; "
     "BEGIN TRY EXEC dbo.sp_ThemSinhVien @MaSV = '24019997', @HoTen = N'Thử Trùng CCCD', @NgaySinh = '2006-01-01', "
     "@GioiTinh = N'Nam', @MaLop = '66.CNTT-1', @CCCD = @c, @Email = '24019997@sv.qlsv.edu.vn'; END TRY "
     "BEGIN CATCH SET @loi = ERROR_NUMBER(); END CATCH; "
     "SELECT @loi AS MaLoi, (SELECT COUNT(*) FROM QLSV_CNTT.dbo.SinhVien WHERE MaSV = '24019997') AS DongONodeCNTT;",
     lambda kq: int(kq[-1].iloc[0]["MaLoi"]) == 2627 and int(kq[-1].iloc[0]["DongONodeCNTT"]) == 0),
    ("Trigger", "trg_SinhVien_ChanXoa: không xóa được sinh viên đã có đăng ký", "Lỗi 50901",
     ca_trigger("trg_SinhVien_ChanXoa", "SinhVien", "DELETE dbo.SinhVien WHERE MaSV = '24010001'", "QLSV_CNTT"), ma_loi_la(50901)),
    ("Trigger", "trg_LopHocPhan_KiemTraMonHoc: giảng viên CNTT mở lớp môn của khoa Ngoại ngữ", "Lỗi 50902",
     ca_trigger("trg_LopHocPhan_KiemTraMonHoc", "LopHocPhan", "INSERT dbo.LopHocPhan (MaLHP, MaMH, MaHK, Nhom, MaGV, SiSoToiDa) "
                "VALUES ('NN101-HK1-2627-09', 'NN101', 'HK1-2627', 9, 'GVCNTT01', 50)", "QLSV_CNTT"), ma_loi_la(50902)),
    ("Trigger", "trg_DangKy_KiemTraDangKy: sinh viên đang bảo lưu (24010008) đăng ký học phần", "Lỗi 50903",
     ca_trigger("trg_DangKy_KiemTraDangKy", "DangKy", "INSERT dbo.DangKy (MaSV, MaLHP) VALUES ('24010008', 'CNTT110-HK1-2627-01')",
                "QLSV_CNTT"), ma_loi_la(50903)),
    ("Trigger", "trg_DangKy_KiemTraDangKy: đăng ký khi lớp đã vượt sĩ số (hạ sĩ số tối đa xuống 10)", "Lỗi 50904",
     ca_trigger("trg_DangKy_KiemTraDangKy", "DangKy", "UPDATE dbo.LopHocPhan SET SiSoToiDa = 10 WHERE MaLHP = 'CNTT110-HK1-2627-01'; "
                "INSERT dbo.DangKy (MaSV, MaLHP) VALUES ('24010016', 'CNTT110-HK1-2627-01')", "QLSV_CNTT"), ma_loi_la(50904)),
    ("Trigger", "trg_HoSo_KiemTraSinhVien: hồ sơ cho mã sinh viên không có ở node nào", "Lỗi 50905",
     ca_trigger("trg_HoSo_KiemTraSinhVien", "SinhVien_HoSo",
                "INSERT dbo.SinhVien_HoSo (MaSV, CCCD, Email) VALUES ('77777777', '001306007777', 'khongcosv@sv.qlsv.edu.vn')"),
     ma_loi_la(50905)),
    ("Trigger", "trg_DangKy_GhiNhatKy: sửa điểm thì nhật ký ở node giữ điểm cũ, điểm mới và người sửa",
     "UPDATE, có DiemThi cũ và mới, người sửa = lg_admin",
     lambda mo_phong: tren_node("QLSV_CNTT", "BEGIN TRAN; "
         + ("DISABLE TRIGGER dbo.trg_DangKy_GhiNhatKy ON dbo.DangKy; " if mo_phong else "")
         + "UPDATE dbo.DangKy SET DiemThi = 9.5 WHERE MaSV = '24010001' AND MaLHP = 'CNTT101-HK1-2425-01'; "
           "SELECT TOP (1) HanhDong, NoiDungCu, NoiDungMoi, NguoiThucHien FROM dbo.NhatKy ORDER BY MaNK DESC; ROLLBACK;"),
     lambda kq: kq[-1].iloc[0]["HanhDong"] == "UPDATE" and "DiemThi=9.50" in kq[-1].iloc[0]["NoiDungMoi"]
                and kq[-1].iloc[0]["NguoiThucHien"] == st.session_state.user),
]


def chay_kiem_thu(sql, kiem):
    """Trả về (đúng hay sai, các DataFrame kết quả, thông báo lỗi nếu lệnh lỗi)."""
    try:
        kq = chay(sql)
        return bool(kq) and bool(kiem(kq)), kq, None
    except pyodbc.Error as e:
        return False, [], loi(e)
    except (KeyError, IndexError, ValueError, TypeError) as e:
        return False, [], f"Kết quả không đúng dạng mong đợi: {e}"


def kiem_thu():
    st.caption("Mỗi ca chạy trong một giao dịch rồi ROLLBACK (hoặc chỉ đọc), nên dữ liệu mẫu không đổi. Ca trigger chặn lỗi "
               "chạy ngay trên node: trên giao diện bình thường các trigger này không bao giờ chạy tới vì thủ tục đã chặn trước.")
    a, b = st.columns([1, 1])
    nhom = a.segmented_control("Nhóm", ["Tất cả", "Hàm", "Thủ tục", "Trigger"], default="Tất cả", key="kt_nhom") or "Tất cả"
    mo_phong = b.toggle("Mô phỏng lỗi: tắt trigger trước khi thử", key="kt_mo_phong",
                        help="Mỗi ca trigger tắt chính trigger đó trong giao dịch thử rồi mới chạy, nên trigger không chặn được và ca "
                             "phải hiện SAI. ROLLBACK cuối ca bật lại trigger; dữ liệu và trigger thật không đổi.")
    if mo_phong:
        st.warning("Đang mô phỏng lỗi: các ca **Trigger** sẽ chạy khi trigger đã bị tắt, nên phải ra ❌. Đó là bằng chứng phép kiểm "
                   "tra thật sự phát hiện được lỗi. Tắt công tắc rồi chạy lại để thấy tất cả ✅.", icon=":material/science:")
    ds = [b for b in BAI_KIEM_THU if nhom == "Tất cả" or b[0] == nhom]
    kq_all = st.session_state.setdefault("kt_kq", {})        # tên ca -> (đúng?, kết quả, lỗi, câu SQL, có mô phỏng?)

    def chay_ca(b):
        sql = b[3](mo_phong) if callable(b[3]) else b[3]
        kq_all[b[1]] = chay_kiem_thu(sql, b[4]) + (sql, mo_phong and callable(b[3]))

    c1, c2, _ = st.columns([1.3, 1, 2])
    if c1.button(f"Chạy cả {len(ds)} ca", type="primary", icon=":material/play_arrow:", width="stretch"):
        with st.spinner("Đang chạy trên 4 instance..."):
            for b in ds:
                chay_ca(b)
        st.session_state["kt_vua_chay"] = None
    if c2.button("Xóa kết quả", icon=":material/restart_alt:", width="stretch", disabled=not kq_all):
        kq_all.clear()

    da_chay = [b for b in ds if b[1] in kq_all]
    if da_chay:
        dung = sum(kq_all[b[1]][0] for b in da_chay)
        (st.success if dung == len(da_chay) else st.error)(
            f"{dung}/{len(da_chay)} ca đã chạy ĐÚNG" + (f" · còn {len(ds) - len(da_chay)} ca chưa chạy" if len(da_chay) < len(ds) else ""),
            icon=":material/check_circle:" if dung == len(da_chay) else ":material/error:")

    # Mỗi ca một hàng: trạng thái, tên, nút chạy riêng; bấm xem chi tiết để thấy mong đợi, kết quả thật và câu SQL
    for i, b in enumerate(BAI_KIEM_THU):
        if b not in ds:
            continue
        n, ten, mong_doi = b[0], b[1], b[2]
        kq = kq_all.get(ten)
        with st.container(border=True):
            h1, h2 = st.columns([6, 1], vertical_alignment="center")
            trang_thai = "⚪ chưa chạy" if kq is None else ("✅ ĐÚNG" if kq[0] else "❌ SAI")
            h1.markdown(f"**{trang_thai}** · `{n}` · {ten}" + ("  \n:orange[đã tắt trigger (mô phỏng lỗi)]" if kq and kq[4] else ""))
            if h2.button("Chạy", key=f"kt_chay_{i}", icon=":material/play_arrow:", width="stretch"):
                with st.spinner("Đang chạy..."):
                    chay_ca(b)
                st.session_state["kt_vua_chay"] = ten
                st.rerun()                                       # vẽ lại hàng này với trạng thái mới
            st.caption(f"Mong đợi: {mong_doi}")
            if kq is not None:
                ok, bang_kq, thong_bao, sql, _ = kq
                if bang_kq and {"MaLoi", "ThongBao"} <= set(bang_kq[-1]):   # ca "phải bị chặn": ghi rõ mã lỗi thực tế, đủ thông báo
                    r = bang_kq[-1].iloc[0]
                    st.markdown(f"**Thực tế:** {'không bị chặn' if int(r['MaLoi']) == 0 else f'lỗi {int(r.MaLoi)}'}"
                                + ("" if int(r["MaLoi"]) == 0 else f" — {r['ThongBao']}"))
                    if int(r["MaLoi"]) == 547:
                        st.info("547 là lỗi **khóa ngoại** của SQL Server: trigger đã bị tắt nên khóa ngoại là lớp chặn còn lại. "
                                "Dữ liệu vẫn an toàn, nhưng ca vẫn SAI vì thứ cần kiểm tra là trigger (mã 50901) chứ không phải khóa ngoại.",
                                icon=":material/info:")
                with st.expander("Xem chi tiết", expanded=not ok or st.session_state.get("kt_vua_chay") == ten):
                    if thong_bao:
                        st.error(thong_bao)
                    for df in bang_kq:
                        bang(df)
                    st.code(sql, language="sql", wrap_lines=True)


BA_NODE = "SELECT * FROM QLSV_CNTT.dbo.{0} UNION ALL SELECT * FROM QLSV_NgoaiNgu.dbo.{0} UNION ALL SELECT * FROM QLSV_DuLich.dbo.{0}"


def luu_danh_muc(sql, *tham_so, ok, dong_bo=False):
    """Gọi thủ tục dm_Luu...; với danh mục nhân bản (dong_bo=True) thủ tục trả kết quả đồng bộ từng node."""
    try:
        kq = chay(sql, *tham_so)
    except pyodbc.Error as e:
        st.error(loi(e))
        return
    if dong_bo:
        cho = kq[-1][kq[-1]["KetQua"] != "Đã đồng bộ"] if kq else pd.DataFrame()
        bao("success" if cho.empty else "warning",
            ok + (" Đã đồng bộ xuống cả 3 node." if cho.empty else
                  f" Node chưa nhận: {', '.join(KHOA[k] for k in cho['Node'])} (không trả lời); thay đổi đang chờ trong hàng đợi, "
                  "xem trang Phân tán, mục Đồng bộ danh mục."))
    else:
        bao("success", ok)
    st.rerun()


def chon_de_sua(df, cot_ma, cot_ten, key):
    """Ô chọn 'Thêm mới' hoặc một dòng có sẵn để sửa; trả về dict dòng đó (hoặc None khi thêm mới)."""
    theo_ma = {r[cot_ma]: r for r in df.to_dict("records")}
    ma = st.selectbox("Thêm mới hoặc chọn để sửa", [None] + list(theo_ma), key=key,
                      format_func=lambda m: "➕ Thêm mới" if m is None else f"{m} - {theo_ma[m][cot_ten]}")
    return theo_ma.get(ma)


def danh_muc():
    t = st.tabs([":material/menu_book: Môn học", ":material/calendar_month: Học kỳ",
                 ":material/person: Giảng viên", ":material/groups: Lớp"])
    khoa3 = ["CNTT", "NN", "DL"]
    with t[0]:
        st.caption("Bản chính ở điều phối, bản sao ở 3 node. Lưu xong thủ tục tự đồng bộ; node mất kết nối sẽ nhận sau qua hàng đợi.")
        df = xem("SELECT MaMH, TenMH, SoTinChi, LoaiMH, MaKhoa FROM dbo.MonHoc ORDER BY MaMH")
        if df is not None:
            bang(df, height=250)
            r = chon_de_sua(df, "MaMH", "TenMH", "dm_mon")
            with st.form(f"f_mon_{r['MaMH'] if r else 'moi'}"):
                a, b = st.columns(2)
                ma = a.text_input("Mã môn", r["MaMH"] if r else "", max_chars=10, disabled=r is not None, placeholder="ví dụ CNTT111")
                ten = b.text_input("Tên môn", r["TenMH"] if r else "")
                tc = a.number_input("Số tín chỉ", 1, 6, int(r["SoTinChi"]) if r else 3)
                loai = b.selectbox("Loại môn", ["Bắt buộc", "Tự chọn"], index=["Bắt buộc", "Tự chọn"].index(r["LoaiMH"]) if r else 0)
                ds = [None] + khoa3
                kh = a.selectbox("Khoa phụ trách", ds, index=ds.index(r["MaKhoa"]) if r and r["MaKhoa"] in ds else 0,
                                 format_func=lambda k: "Môn chung toàn trường" if k is None else KHOA[k])
                if st.form_submit_button("Lưu môn học", type="primary", icon=":material/save:"):
                    luu_danh_muc("EXEC dbo.dm_LuuMonHoc @MaMH = ?, @TenMH = ?, @SoTinChi = ?, @LoaiMH = ?, @MaKhoa = ?",
                                 ma.strip(), ten.strip(), int(tc), loai, kh, ok=f"Đã lưu môn {ma.strip()}.", dong_bo=True)
    with t[1]:
        st.caption("Cũng là danh mục nhân bản: lưu xong tự đồng bộ xuống 3 node.")
        df = xem("SELECT MaHK, TenHK, NamHoc, NgayBatDau, NgayKetThuc FROM dbo.HocKy ORDER BY NgayBatDau")
        if df is not None:
            bang(df)
            r = chon_de_sua(df, "MaHK", "TenHK", "dm_hk")
            with st.form(f"f_hk_{r['MaHK'] if r else 'moi'}"):
                a, b = st.columns(2)
                ma = a.text_input("Mã học kỳ", r["MaHK"] if r else "", max_chars=10, disabled=r is not None, placeholder="ví dụ HK2-2627")
                ds = ["Học kỳ 1", "Học kỳ 2", "Học kỳ hè"]
                ten = b.selectbox("Tên học kỳ", ds, index=ds.index(r["TenHK"]) if r else 0)
                nam = a.text_input("Năm học", r["NamHoc"] if r else "", max_chars=9, placeholder="ví dụ 2026-2027")
                bd = b.date_input("Ngày bắt đầu", r["NgayBatDau"] if r else date.today())
                kt = a.date_input("Ngày kết thúc", r["NgayKetThuc"] if r else date.today())
                if st.form_submit_button("Lưu học kỳ", type="primary", icon=":material/save:"):
                    luu_danh_muc("EXEC dbo.dm_LuuHocKy @MaHK = ?, @TenHK = ?, @NamHoc = ?, @NgayBatDau = ?, @NgayKetThuc = ?",
                                 ma.strip(), ten, nam.strip(), bd, kt, ok=f"Đã lưu học kỳ {ma.strip()}.", dong_bo=True)
    with t[2]:
        st.caption("Giảng viên được phân mảnh ngang theo khoa: mỗi người chỉ nằm ở node của khoa mình.")
        df = xem(BA_NODE.format("GiangVien") + " ORDER BY MaKhoa, MaGV")
        if df is not None:
            bang(df, height=250)
            r = chon_de_sua(df, "MaGV", "HoTen", "dm_gv")
            with st.form(f"f_gv_{r['MaGV'] if r else 'moi'}"):
                a, b = st.columns(2)
                ma = a.text_input("Mã giảng viên", r["MaGV"] if r else "", max_chars=10, disabled=r is not None, placeholder="ví dụ GVCNTT09")
                ten = b.text_input("Họ tên", r["HoTen"] if r else "")
                kh = a.selectbox("Khoa", khoa3, index=khoa3.index(r["MaKhoa"]) if r else 0, format_func=KHOA.get, disabled=r is not None,
                                 help="Quyết định giảng viên được lưu ở node nào. Không đổi được khoa của giảng viên đã có.")
                gt = b.selectbox("Giới tính", ["Nam", "Nữ"], index=["Nam", "Nữ"].index(r["GioiTinh"]) if r else 0)
                ns = a.date_input("Ngày sinh", r["NgaySinh"] if r else date(1985, 1, 1), min_value=date(1950, 1, 1), max_value=date(2003, 12, 31))
                ds = ["Thạc sĩ", "Tiến sĩ", "PGS.TS", "GS.TS"]
                hv = b.selectbox("Học vị", ds, index=ds.index(r["HocVi"]) if r else 0)
                email = a.text_input("Email", r["Email"] if r else "", placeholder="ten@gv.qlsv.edu.vn")
                sdt = b.text_input("Điện thoại (không bắt buộc)", (r["DienThoai"] or "") if r else "", max_chars=10)
                if st.form_submit_button("Lưu giảng viên", type="primary", icon=":material/save:"):
                    luu_danh_muc("EXEC dbo.dm_LuuGiangVien @MaGV = ?, @HoTen = ?, @GioiTinh = ?, @NgaySinh = ?, @HocVi = ?, @Email = ?, "
                                 "@MaKhoa = ?, @DienThoai = ?", ma.strip(), ten.strip(), gt, ns, hv, email.strip(), kh, sdt.strip() or None,
                                 ok=f"Đã lưu giảng viên {ma.strip()} ở node {KHOA[kh]}.")
    with t[3]:
        st.caption("Lớp cũng nằm ở node của khoa. Giảng viên chủ nhiệm phải thuộc cùng khoa.")
        df = xem(BA_NODE.format("Lop") + " ORDER BY MaKhoa, MaLop")
        gv = xem("SELECT MaGV, HoTen, MaKhoa FROM (" + BA_NODE.format("GiangVien") + ") g ORDER BY MaGV")
        if df is not None and gv is not None:
            bang(df)
            r = chon_de_sua(df, "MaLop", "TenLop", "dm_lop")
            kh = st.selectbox("Khoa", khoa3, index=khoa3.index(r["MaKhoa"]) if r else 0, format_func=KHOA.get, disabled=r is not None,
                              key=f"dm_lop_khoa_{r['MaLop'] if r else 'moi'}", help="Quyết định lớp được lưu ở node nào.")
            ten_gv = dict(zip(gv["MaGV"], gv["HoTen"]))
            ds = [None] + gv[gv["MaKhoa"] == kh]["MaGV"].tolist()
            with st.form(f"f_lop_{r['MaLop'] if r else 'moi'}_{kh}"):
                a, b = st.columns(2)
                ma = a.text_input("Mã lớp", r["MaLop"] if r else "", max_chars=15, disabled=r is not None, placeholder="ví dụ 67.CNTT-1")
                ten = b.text_input("Tên lớp", r["TenLop"] if r else "", placeholder="ví dụ CNTT K67-1")
                nk = a.text_input("Niên khóa", r["NienKhoa"] if r else "", max_chars=9, placeholder="ví dụ 2025-2029")
                cn = b.selectbox("Giảng viên chủ nhiệm", ds, index=ds.index(r["MaGVCN"]) if r and r["MaGVCN"] in ds else 0,
                                 format_func=lambda m: "Chưa phân công" if m is None else f"{m} - {ten_gv[m]}")
                if st.form_submit_button("Lưu lớp", type="primary", icon=":material/save:"):
                    luu_danh_muc("EXEC dbo.dm_LuuLop @MaLop = ?, @TenLop = ?, @NienKhoa = ?, @MaKhoa = ?, @MaGVCN = ?",
                                 ma.strip(), ten.strip(), nk.strip(), kh, cn, ok=f"Đã lưu lớp {ma.strip()} ở node {KHOA[kh]}.")


TEP_VAI_TRO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "database", "14_demo_vai_tro.sql")
VAI_TRO_THU = ["lg_admin", "lg_daotao", "lg_giaovu_cntt", "lg_giaovu_nn", "lg_bgh"]


def lo_demo_vai_tro():
    """Lô lệnh thử 8 việc trong database/14_demo_vai_tro.sql (cùng file dùng khi demo bằng công cụ SQL)."""
    with open(TEP_VAI_TRO, encoding="utf-8-sig") as f:
        return next(lo for lo in re.split(r"^\s*GO\s*$", f.read(), flags=re.M) if "DECLARE @kq" in lo)


def thu_vai_tro(login, lo):
    """Chạy lô lệnh dưới danh nghĩa một login (EXECUTE AS LOGIN) rồi luôn trả kết nối về lg_admin."""
    with khoa_ket_noi():              # giữ khóa suốt lúc đóng vai: không lệnh nào khác được chạy nhờ dưới danh nghĩa login kia
        cur = st.session_state.conn.cursor()
        try:
            if login != st.session_state.user:
                cur.execute(f"EXECUTE AS LOGIN = '{login}'")              # login lấy từ danh sách cố định VAI_TRO_THU
            cur.execute("SET NOCOUNT ON; SET XACT_ABORT ON;\n" + lo)
            while not cur.description:
                if not cur.nextset():
                    return pd.DataFrame()
            cot = [c[0] for c in cur.description]
            kq = pd.DataFrame.from_records([tuple(r) for r in cur.fetchall()], columns=cot)
            while cur.nextset():          # đọc hết các tập kết quả còn lại trước khi chạy lệnh kế tiếp
                pass
            return kq
        finally:
            try:
                cur.execute("IF @@TRANCOUNT > 0 ROLLBACK; WHILE SUSER_SNAME() <> ORIGINAL_LOGIN() REVERT;")
            finally:
                cur.close()


def phan_quyen():
    st.caption("Trang đóng vai từng tài khoản (EXECUTE AS LOGIN) và thử cùng 8 việc trong `database/14_demo_vai_tro.sql`. "
               "Mọi lệnh ghi đều hoàn tác. Ô xanh: SQL Server cho phép; ô đỏ: SQL Server từ chối, kèm mã lỗi.")
    if st.button("Thử 8 việc với 5 vai trò", type="primary", icon=":material/play_arrow:"):
        try:
            lo = lo_demo_vai_tro()
        except (OSError, StopIteration):
            st.error("Không đọc được database/14_demo_vai_tro.sql.")
            return
        kq, loi_ds = {}, []
        with st.spinner("Đang thử dưới từng vai trò..."):
            for lg in VAI_TRO_THU:
                try:
                    kq[lg] = thu_vai_tro(lg, lo)
                except pyodbc.Error as e:
                    loi_ds.append(f"{lg}: {loi(e)}")
        st.session_state["pq_kq"], st.session_state["pq_loi"] = kq, loi_ds
    for m in st.session_state.get("pq_loi", []):
        st.error(m + "  \nNếu lỗi là không có quyền IMPERSONATE: chạy lại database/10_security.sql bằng sa.")
    kq = st.session_state.get("pq_kq")
    if not kq:
        st.info("Bấm nút để chạy. Mất vài giây vì mỗi vai trò đọc và ghi thử trên cả 3 node.", icon=":material/info:")
        return

    def gon(v):                                       # "Được: 72 sinh viên" -> "✅ 72 sinh viên"; "BỊ TỪ CHỐI (lỗi 229)..." -> "⛔ lỗi 229"
        if v.startswith("Được"):
            return "✅ " + (v.split(": ", 1)[1] if ": " in v else "được")
        ma = re.search(r"lỗi (\d+)", v)
        return "⛔ từ chối" + (f" (lỗi {ma.group(1)})" if ma else "")
    dau = next(iter(kq.values()))
    ma_tran = pd.DataFrame({"Thử làm": dau["ThuLam"]})
    for lg, df in kq.items():
        ma_tran[VAI_TRO[lg]] = df["KetQua"].map(gon).values
    to = lambda v: ("background-color: #dcfce7; color: #0f172a" if str(v).startswith("✅") else
                    "background-color: #fee2e2; color: #0f172a" if str(v).startswith("⛔") else "")
    st.dataframe(ma_tran.style.map(to, subset=list(ma_tran.columns[1:])), hide_index=True, width="stretch",
                 height=38 * len(ma_tran) + 40)
    with st.expander("Cách đọc bảng"):
        st.markdown("- **Tạo bảng mới**: chỉ Quản trị được sửa cấu trúc CSDL (khác biệt với Phòng Đào tạo).\n"
                    "- **Đọc thẳng bảng SinhVien_HoSo**: Đào tạo xem CCCD qua view nhưng bị DENY trên chính bảng.\n"
                    "- **Giáo vụ**: chỉ thấy và chỉ nhập điểm cho khoa mình; sinh viên khoa khác bị lọc khỏi tầm nhìn "
                    "nên thủ tục báo “Không tìm thấy sinh viên”.\n"
                    "- **Ban giám hiệu**: chỉ xem thống kê.\n"
                    "- Lỗi 229: không có quyền trên đối tượng. Lỗi 262: không có quyền tạo đối tượng. Lỗi 500xx: thủ tục tự báo.")
    with st.expander("Thông báo đầy đủ của từng vai trò"):
        for lg, df in kq.items():
            st.markdown(f"**{VAI_TRO[lg]}** (`{lg}`)")
            st.dataframe(df[["STT", "ThuLam", "KetQua"]], hide_index=True, width="stretch",
                         column_config={"STT": "#", "ThuLam": "Thử làm", "KetQua": "Kết quả"})


TRANG = {"Thống kê": thong_ke, "Tìm kiếm": trang_tim_kiem,
         "Bảng điểm": bang_diem, "Cảnh báo học vụ": canh_bao, "Nhập điểm": nhap_diem, "Sinh viên": sinh_vien,
         "Đăng ký học phần": dang_ky, "Lớp học phần": lop_hoc_phan, "Danh mục": danh_muc, "Phân tán": phan_tan, "Nhật ký": nhat_ky,
         "Kiểm thử": kiem_thu, "Phân quyền": phan_quyen}


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
            with khoa_ket_noi(p["conn"]):                              # tab khác có thể đang chạy lệnh trên cùng kết nối
                p["conn"].cursor().execute("SELECT 1").fetchone()      # kết nối còn sống không?
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
