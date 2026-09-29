"""Writes the dashboard's inline <script> blocks to a file: page_js.py OUT.js"""
import importlib.machinery, importlib.util, re, sys
l = importlib.machinery.SourceFileLoader("handoffs", "bin/handoffs")
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("handoffs", l))
l.exec_module(m)
open(sys.argv[1], "w").write("\n".join(re.findall(r"<script>(.*?)</script>", m.PAGE, re.S)))
