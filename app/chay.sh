#!/bin/bash
# Chạy ứng dụng trong môi trường ảo riêng (app/.venv), không dùng gói của conda hay hệ thống.
# Dùng:  bash chay.sh        (lần đầu tự tạo môi trường và cài gói)
cd "$(dirname "$0")" || exit 1
[ -d .venv ] || python3 -m venv .venv || exit 1
.venv/bin/pip install -q -r requirements.txt || exit 1
exec .venv/bin/python -m streamlit run app.py "$@"
