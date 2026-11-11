"""So số trên trang Thống kê của ứng dụng với số tính lại từ bảng gốc ở 3 node (bằng sa, không qua view thống kê).
Dùng: app/.venv/bin/python scripts/kiem_tra_thong_ke.py   (cần streamlit, nên chạy bằng Python của app/.venv)"""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from chay_sql import ket_noi
from streamlit.testing.v1 import AppTest
mk = dict(re.findall(r"\(N'(lg_\w+)',\s*N'([^']+)'\)", open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "database", "10_security.sql"), encoding="utf-8-sig").read()))
c = ket_noi(14330, "QLSV_TongHop").cursor()
RAW = " UNION ALL ".join(f"SELECT '{k}' AS K, d.MaSV, lp.MaHK, d.DiemQT, d.DiemThi FROM {db}.dbo.DangKy d JOIN {db}.dbo.LopHocPhan lp ON lp.MaLHP = d.MaLHP"
                         for k, db in (("CNTT", "QLSV_CNTT"), ("NN", "QLSV_NgoaiNgu"), ("DL", "QLSV_DuLich")))
def mong_doi(khoa):
    ds = ",".join(f"'{k}'" for k in khoa)
    # điểm tổng kết tính lại từ công thức 0,4 QT + 0,6 Thi, không dùng cột DiemTK
    rows = c.execute(f"""SELECT MaHK, COUNT(DISTINCT MaSV), COUNT(*), COUNT(tk), AVG(tk), 100.0 * SUM(CASE WHEN tk >= 4 THEN 1 ELSE 0 END) / NULLIF(COUNT(tk), 0)
        FROM (SELECT *, CAST(ROUND(0.4 * DiemQT + 0.6 * DiemThi, 1) AS DECIMAL(4,2)) AS tk FROM ({RAW}) r WHERE K IN ({ds})) x GROUP BY MaHK""").fetchall()
    rows = sorted(rows, key=lambda r: (r[0][4:], r[0][:3]))
    chot = [r for r in rows if r[3] * 2 >= r[2]]
    return {"sv": (rows[-1][0], rows[-1][1]), "dk": (rows[-1][0], rows[-1][2]),
            "tb": (chot[-1][0], round(float(chot[-1][4]), 2)), "dat": (chot[-1][0], round(float(chot[-1][5]), 1)),
            "truoc_tb": round(float(chot[-2][4]), 2), "truoc_dat": round(float(chot[-2][5]), 1)}
print("công thức DiemTK ở CSDL:", c.execute("SELECT definition FROM LS_QLSV_CNTT.QLSV_CNTT.sys.computed_columns WHERE name = 'DiemTK'").fetchone()[0])
sai = 0
def kiem(user, khoa, bo_chon=()):
    global sai
    at = AppTest.from_file(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "app", "app.py"), default_timeout=120).run()
    at.selectbox[0].set_value(user); at.text_input[0].set_value(mk[user]); at.button[0].click().run()
    if bo_chon:
        p = next(w for w in at.button_group if w.key == "tk_loc_khoa"); p.set_value([k for k in ["CNTT", "DL", "NN"] if k not in bo_chon]).run()
    assert not at.exception, at.exception
    m = {x.label.split(" · ")[0]: (x.label.split(" · ")[1], x.value, x.delta) for x in at.metric[:4]}
    e = mong_doi(khoa)
    so = [("Sinh viên", e["sv"][0], str(e["sv"][1])), ("Lượt đăng ký", e["dk"][0], str(e["dk"][1])),
          ("Điểm TB", e["tb"][0], f"{e['tb'][1]:.2f}"), ("Tỷ lệ đạt", e["dat"][0], f"{e['dat'][1]:.1f}%")]
    for nhan, hk, gt in so:
        ok = m[nhan][0] == hk and m[nhan][1] == gt
        sai += not ok
        print(f"  {'ĐÚNG' if ok else 'SAI '} {user:15} {','.join(khoa):10} {nhan:13} trang: {m[nhan][1]:>7} ({m[nhan][0]})  tính lại: {gt:>7} ({hk})  delta trang: {m[nhan][2]}")
    print(f"       delta mong đợi: điểm TB {e['tb'][1] - e['truoc_tb']:+.2f}, tỷ lệ đạt {e['dat'][1] - e['truoc_dat']:+.2f}")
kiem("lg_daotao", ["CNTT", "NN", "DL"])
kiem("lg_daotao", ["CNTT", "NN"], bo_chon=("DL",))
kiem("lg_giaovu_cntt", ["CNTT"])
kiem("lg_bgh", ["CNTT", "NN", "DL"])
print("SAI:", sai)
