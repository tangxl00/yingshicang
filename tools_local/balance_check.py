#!/usr/bin/env python3
"""括号配平自检：{} [] () 三类计数配平 + raw string #\"...\"# 感知（本仓无 raw string 也安全）。"""
import sys

FILES = [
    "Yingshicang/Features/Mine/DisclaimerDialog.swift",
    "Yingshicang/Features/Mine/AliTokenDialog.swift",
    "Yingshicang/Features/Mine/RewardDialog.swift",
    "Yingshicang/Features/Home/ChannelPasswordDialog.swift",
    "Yingshicang/Features/Home/ShakeGesture.swift",
    "Yingshicang/Features/Home/ScanCodeViewController.swift",
    "Yingshicang/Features/Mine/InteractionPage.swift",
    "Yingshicang/Features/Mine/LANSync.swift",
    "Yingshicang/Features/Home/RankListViewController.swift",
    "Yingshicang/Features/Home/ConditionFilterViewController.swift",
    "Yingshicang/Features/Home/HomeViewController.swift",
    "Yingshicang/App/MainTabBarController.swift",
    "Yingshicang/Features/Mine/MineViewController.swift",
    "Yingshicang/Features/Mine/MineSubPages.swift",
    "Yingshicang/Features/Detail/DownloadManager.swift",
    "Yingshicang/Features/Detail/DetailViewController.swift",
    "Tests/Build22Batch3RegressionTests.swift",
]

def strip_strings_and_comments(text):
    # 感知 raw string（单行与三引号形态）：先剔除 raw string 再走普通扫描。
    out = []
    i = 0
    n = len(text)
    while i < n:
        # raw string 检测：任意数量 # 紧跟 "
        j = i
        while j < n and text[j] == "#":
            j += 1
        hashes = j - i
        if hashes > 0 and j < n and text[j] == '"':
            # 三引号 raw string？
            if text[j:j+3] == '"""':
                closer = '"' + '"' + '"' + "#" * hashes
                end = text.find(closer, j + 3)
                i = (end + len(closer)) if end != -1 else n
            else:
                closer = '"' + "#" * hashes
                end = text.find(closer, j + 1)
                i = (end + len(closer)) if end != -1 else n
            out.append(" ")
            continue
        out.append(text[i])
        i += 1
    text = "".join(out)

    out = []
    i = 0
    n = len(text)
    state = "code"
    while i < n:
        c = text[i]
        nxt = text[i+1] if i + 1 < n else ""
        if state == "code":
            if c == "/" and nxt == "/":
                state = "line"; i += 2; continue
            if c == "/" and nxt == "*":
                state = "block"; i += 2; continue
            if c == '"':
                state = "str"; i += 1; continue
            out.append(c); i += 1
        elif state == "line":
            if c == "\n":
                state = "code"; out.append(c)
            i += 1
        elif state == "block":
            if c == "*" and nxt == "/":
                state = "code"; i += 2; continue
            i += 1
        elif state == "str":
            if c == "\\":
                i += 2; continue
            if c == '"':
                state = "code"
            i += 1
    return "".join(out)

fails = 0
for path in FILES:
    try:
        with open(path, encoding="utf-8") as f:
            code = strip_strings_and_comments(f.read())
    except FileNotFoundError:
        print(f"MISSING {path}")
        fails += 1
        continue
    counts = {p: (code.count(p[0]), code.count(p[1])) for p in ("{}", "[]", "()")}
    bad = {p: v for p, v in counts.items() if v[0] != v[1]}
    if bad:
        print(f"FAIL {path}: {bad}")
        fails += 1
    else:
        print(f"OK   {path}")

sys.exit(1 if fails else 0)
