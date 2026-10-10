#!/usr/bin/env python3
"""Writes the landing pages (docs/index.html and docs/vi/index.html) from one template.

Usage: python3 scripts/make-landing-pages.py
Edit the TEXT table for copy changes and TEMPLATE for layout changes, then rerun.
"""
from pathlib import Path

REPO = "https://github.com/CapiZerbino/snapwise"
SITE = "https://capizerbino.github.io/snapwise/"

TEXT = {
    "en": {
        "root": "", "other_href": "vi/", "other_lang": "vi", "other_name": "Tiếng Việt",
        "title": "Snapwise — screenshots, recordings and window snapping for macOS",
        "description": "Snapwise is a free, open-source macOS menu-bar app for screenshots, screen recordings, annotation, OCR and window snapping. Native Swift, no third-party dependencies.",
        "og": "Screenshots, screen recordings and window snapping in one native macOS menu-bar app. Free and open source.",
        "nav_features": "Features", "nav_snap": "Snapping", "nav_keys": "Shortcuts", "nav_install": "Install", "nav_get": "Download",
        "badge": "Free and open source · v1.0",
        "h1": "Capture your screen.<br><span class=\"grad\">Arrange your windows.</span>",
        "lead": "Screenshots, screen recordings, annotation, text recognition and window snapping — one native menu-bar app instead of three.",
        "download": "Download for macOS", "source": "View on GitHub",
        "note": "macOS 15 or later · Apple silicon and Intel · MIT license",
        "video_label": "Snapwise intro video: capture, annotate, record, copy text and snap windows",
        "stats": [("0", "third-party dependencies"), ("100%", "on-device, no account"), ("15", "snap layouts"), ("$0", "free, MIT licensed")],
        "f_eyebrow": "Capture and record", "f_h2": "Everything after the shortcut is already handled",
        "f_sub": "Shoot, mark up, record and share without opening a second app. Nothing leaves your Mac.",
        "cards": [
            ("Screenshots", "Area, window, full screen, previous area, self-timer and an All-In-One mode. Crosshair, magnifier, frozen screen, and window shots on wallpaper, solid or gradient backgrounds."),
            ("Scrolling capture", "Stitch long pages vertically or horizontally, by hand or with auto-scroll. Sticky headers and footers are kept once."),
            ("Annotate", "Arrows, shapes, pencil, highlighter, text, counters, blur, spotlight, crop and a background tool with gradients, padding and shadows."),
            ("Video and GIF", "Record an area, window or the full screen as MP4 or GIF with computer audio, microphone, pause, click highlights, keystroke display and a camera bubble."),
            ("Text recognition", "Select any area to copy its text. On-device OCR with automatic language detection; reads QR codes and barcodes too."),
            ("Video editor", "Trim, switch between landscape, square and vertical, add gradient backgrounds, auto-zoom on clicks, export to MP4 or GIF."),
            ("Quick access", "Every capture lands in a thumbnail stack: copy, save, annotate, pin, or drag it straight into another app."),
            ("Pin and history", "Float a screenshot above all windows. Browse, restore and re-export past captures from the history."),
        ],
        "s_eyebrow": "Window snapping", "s_h2": "Every window, exactly where you want it",
        "s_sub": "Drag to an edge or corner and a live preview shows where the window will land — or press a shortcut. Try a layout:",
        "layouts": ["Left half", "Right half", "Maximize", "Top left", "Top right", "Center", "Bottom left", "Bottom right", "Left third", "Center third", "Right third", "Right two thirds"],
        "s_more": "Also: custom snap areas, right-click actions on the title-bar buttons, hold a modifier to move or resize, adjustable gaps and excluded apps.",
        "k_eyebrow": "Shortcuts", "k_h2": "Built for the keyboard",
        "k_sub": "Every shortcut can be changed in Settings › Shortcuts, including a one-click macOS-style ⌘⇧3 / ⌘⇧4 / ⌘⇧5 preset.",
        "k_capture": "Capture and record", "k_windows": "Windows",
        "keys_capture": [("All-In-One capture", "⌃ ⇧ 1"), ("Capture text (OCR)", "⌃ ⇧ 2"), ("Capture full screen", "⌃ ⇧ 3"), ("Capture area", "⌃ ⇧ 4"), ("Capture window", "⌃ ⇧ 5"), ("Scrolling capture", "⌃ ⇧ 6"), ("Record video / GIF", "⌃ ⇧ 7 8")],
        "keys_windows": [("Snap to a half, press again for ½ → ⅔ → ⅓", "⌃ ⌥ ← →"), ("Snap to a quarter", "⌃ ⌥ U I J K"), ("Maximize / center", "⌃ ⌥ ↩ C"), ("Left / center / right third", "⌃ ⌥ D F G"), ("Left / right two thirds", "⌃ ⌥ E T"), ("Previous / next display", "⌃ ⌥ ⌘ ← →"), ("Restore the previous size", "⌃ ⌥ ⌫")],
        "i_eyebrow": "Install", "i_h2": "Up and running in a minute",
        "i_sub": "Snapwise is signed but not notarized by Apple, so the first launch needs one extra step.",
        "steps": [
            "<b>Download and move.</b> Get the zip from the <a href=\"%s/releases/latest\">latest release</a>, unzip it and move Snapwise.app to Applications." % REPO,
            "<b>Open it.</b> If macOS blocks the app, go to System Settings › Privacy &amp; Security and choose Open Anyway.",
            "<b>Grant access.</b> Allow Screen &amp; System Audio Recording, then relaunch. Window snapping also needs Accessibility.",
        ],
        "i_aside": "Prefer building it yourself? Clone the repo, <code>brew install xcodegen</code>, then run <code>./build.sh Release</code>.",
        "c_h2": "Take the next screenshot with Snapwise", "c_sub": "Free, open source, and yours to change.",
        "footer": "Snapwise is an independent open-source project released under the <a href=\"%s/blob/main/LICENSE\">MIT license</a>. It is not affiliated with any other screenshot or window-management product." % REPO,
        "f_source": "Source", "f_issue": "Report an issue",
    },
    "vi": {
        "root": "../", "other_href": "../", "other_lang": "en", "other_name": "English",
        "title": "Snapwise — chụp màn hình, quay màn hình và sắp xếp cửa sổ cho macOS",
        "description": "Snapwise là ứng dụng thanh menu miễn phí, mã nguồn mở cho macOS: chụp màn hình, quay màn hình, chú thích, OCR và sắp xếp cửa sổ. Viết bằng Swift, không phụ thuộc thư viện bên ngoài.",
        "og": "Chụp màn hình, quay màn hình và sắp xếp cửa sổ trong một ứng dụng macOS. Miễn phí, mã nguồn mở.",
        "nav_features": "Tính năng", "nav_snap": "Xếp cửa sổ", "nav_keys": "Phím tắt", "nav_install": "Cài đặt", "nav_get": "Tải về",
        "badge": "Miễn phí, mã nguồn mở · v1.0",
        "h1": "Chụp màn hình.<br><span class=\"grad\">Sắp xếp cửa sổ.</span>",
        "lead": "Chụp màn hình, quay màn hình, chú thích, nhận dạng chữ và sắp xếp cửa sổ — một ứng dụng thanh menu thay cho ba ứng dụng.",
        "download": "Tải về cho macOS", "source": "Xem trên GitHub",
        "note": "macOS 15 trở lên · Apple silicon và Intel · Giấy phép MIT",
        "video_label": "Video giới thiệu Snapwise: chụp, chú thích, quay màn hình, sao chép chữ và xếp cửa sổ",
        "stats": [("0", "thư viện bên ngoài"), ("100%", "xử lý trên máy, không cần tài khoản"), ("15", "bố cục cửa sổ"), ("0đ", "miễn phí, giấy phép MIT")],
        "f_eyebrow": "Chụp và quay", "f_h2": "Bấm phím tắt, mọi việc còn lại đã có sẵn",
        "f_sub": "Chụp, đánh dấu, quay và chia sẻ mà không cần mở thêm ứng dụng nào. Dữ liệu không rời khỏi máy của bạn.",
        "cards": [
            ("Chụp màn hình", "Vùng chọn, cửa sổ, toàn màn hình, vùng vừa chụp, hẹn giờ và chế độ All-In-One. Có tâm ngắm, kính lúp, đóng băng màn hình; ảnh cửa sổ đặt trên hình nền, màu trơn hoặc gradient."),
            ("Chụp cuộn", "Ghép trang dài theo chiều dọc hoặc ngang, cuộn tay hoặc tự động. Thanh tiêu đề và chân trang cố định chỉ xuất hiện một lần."),
            ("Chú thích", "Mũi tên, hình khối, bút vẽ, bút dạ quang, chữ, số thứ tự, làm mờ, làm nổi bật, cắt và công cụ nền với gradient, lề và đổ bóng."),
            ("Video và GIF", "Quay một vùng, một cửa sổ hoặc toàn màn hình thành MP4 hay GIF, kèm âm thanh máy, micro, tạm dừng, hiệu ứng click, hiển thị phím bấm và khung camera."),
            ("Nhận dạng chữ", "Chọn một vùng bất kỳ để sao chép chữ. OCR chạy ngay trên máy, tự nhận ngôn ngữ; đọc được cả mã QR và mã vạch."),
            ("Trình sửa video", "Cắt đoạn, đổi khung ngang, vuông hoặc dọc, thêm nền gradient, tự phóng to theo vị trí click, xuất ra MP4 hoặc GIF."),
            ("Truy cập nhanh", "Mỗi lần chụp hiện một hình thu nhỏ ở góc màn hình: sao chép, lưu, chú thích, ghim hoặc kéo thẳng sang ứng dụng khác."),
            ("Ghim và lịch sử", "Ghim ảnh chụp nổi trên mọi cửa sổ. Xem lại, khôi phục và xuất lại các lần chụp cũ trong lịch sử."),
        ],
        "s_eyebrow": "Sắp xếp cửa sổ", "s_h2": "Cửa sổ nào cũng nằm đúng chỗ bạn muốn",
        "s_sub": "Kéo cửa sổ vào cạnh hoặc góc màn hình, khung xem trước cho biết nó sẽ nằm ở đâu — hoặc bấm phím tắt. Thử một bố cục:",
        "layouts": ["Nửa trái", "Nửa phải", "Phóng to", "Góc trên trái", "Góc trên phải", "Căn giữa", "Góc dưới trái", "Góc dưới phải", "⅓ trái", "⅓ giữa", "⅓ phải", "⅔ phải"],
        "s_more": "Ngoài ra: vùng xếp tùy chỉnh, chuột phải vào các nút trên thanh tiêu đề, giữ phím để di chuyển hoặc đổi kích thước, chỉnh khoảng hở và loại trừ ứng dụng.",
        "k_eyebrow": "Phím tắt", "k_h2": "Làm mọi thứ từ bàn phím",
        "k_sub": "Mọi phím tắt đều đổi được trong Settings › Shortcuts, có sẵn bộ kiểu macOS ⌘⇧3 / ⌘⇧4 / ⌘⇧5 chỉ với một cú bấm.",
        "k_capture": "Chụp và quay", "k_windows": "Cửa sổ",
        "keys_capture": [("Chụp All-In-One", "⌃ ⇧ 1"), ("Chụp chữ (OCR)", "⌃ ⇧ 2"), ("Chụp toàn màn hình", "⌃ ⇧ 3"), ("Chụp vùng chọn", "⌃ ⇧ 4"), ("Chụp cửa sổ", "⌃ ⇧ 5"), ("Chụp cuộn", "⌃ ⇧ 6"), ("Quay video / GIF", "⌃ ⇧ 7 8")],
        "keys_windows": [("Xếp nửa màn hình, bấm lại để đổi ½ → ⅔ → ⅓", "⌃ ⌥ ← →"), ("Xếp một phần tư", "⌃ ⌥ U I J K"), ("Phóng to / căn giữa", "⌃ ⌥ ↩ C"), ("⅓ trái / giữa / phải", "⌃ ⌥ D F G"), ("⅔ trái / phải", "⌃ ⌥ E T"), ("Màn hình trước / sau", "⌃ ⌥ ⌘ ← →"), ("Trả về kích thước cũ", "⌃ ⌥ ⌫")],
        "i_eyebrow": "Cài đặt", "i_h2": "Dùng được sau một phút",
        "i_sub": "Snapwise đã được ký nhưng chưa qua bước notarize của Apple, nên lần mở đầu tiên cần thêm một thao tác. Giao diện ứng dụng hiện bằng tiếng Anh.",
        "steps": [
            "<b>Tải về và chép vào máy.</b> Lấy tệp zip ở <a href=\"%s/releases/latest\">bản phát hành mới nhất</a>, giải nén rồi kéo Snapwise.app vào Applications." % REPO,
            "<b>Mở ứng dụng.</b> Nếu macOS chặn, vào System Settings › Privacy &amp; Security và chọn Open Anyway.",
            "<b>Cấp quyền.</b> Cho phép Screen &amp; System Audio Recording rồi mở lại. Sắp xếp cửa sổ cần thêm quyền Accessibility.",
        ],
        "i_aside": "Muốn tự biên dịch? Clone repo, chạy <code>brew install xcodegen</code> rồi <code>./build.sh Release</code>.",
        "c_h2": "Chụp tấm tiếp theo bằng Snapwise", "c_sub": "Miễn phí, mã nguồn mở, tùy bạn chỉnh sửa.",
        "footer": "Snapwise là dự án mã nguồn mở độc lập, phát hành theo <a href=\"%s/blob/main/LICENSE\">giấy phép MIT</a>. Dự án không liên kết với bất kỳ sản phẩm chụp màn hình hay quản lý cửa sổ nào khác." % REPO,
        "f_source": "Mã nguồn", "f_issue": "Báo lỗi",
    },
}

# Snap demo targets as unit fractions (x, y, width, height) with the default shortcut; order matches TEXT["layouts"].
LAYOUTS = [("0,0,.5,1", "⌃ ⌥ ←"), (".5,0,.5,1", "⌃ ⌥ →"), ("0,0,1,1", "⌃ ⌥ ↩"), ("0,0,.5,.5", "⌃ ⌥ U"), (".5,0,.5,.5", "⌃ ⌥ I"),
           (".2,.15,.6,.7", "⌃ ⌥ C"), ("0,.5,.5,.5", "⌃ ⌥ J"), (".5,.5,.5,.5", "⌃ ⌥ K"), ("0,0,.3333,1", "⌃ ⌥ D"),
           (".3333,0,.3334,1", "⌃ ⌥ F"), (".6667,0,.3333,1", "⌃ ⌥ G"), (".3333,0,.6667,1", "⌃ ⌥ T")]

ICONS = [
    "M4 8V5a1 1 0 0 1 1-1h3M16 4h3a1 1 0 0 1 1 1v3M20 16v3a1 1 0 0 1-1 1h-3M8 20H5a1 1 0 0 1-1-1v-3M8 9h8M8 12h8M8 15h5",
    "M4 6h16v12H4zM9 6v12M15 6v12M4 12h5M15 12h5",
    "M4 5h12v9H4zM8 18h12V9",
    "M9 4h6l-1 6 3 3H7l3-3zM12 13v7",
]

ART = [
    # Screenshots: a selection being dragged over a window
    '<div class="art"><div class="mock"><i style="top:15%;width:34%;background:#2a2f45"></i><u></u>'
    '<i style="left:54%;top:28%;width:36%"></i><i style="left:54%;top:36%;width:30%"></i><i style="left:54%;top:44%;width:34%"></i></div>'
    '<div class="pick"><b>640 × 360</b></div></div>',
    # Scrolling capture: a long page moving under a fixed frame
    '<div class="art"><div class="scroll-page"><u style="top:14px;background:linear-gradient(135deg,#ffb86b,#ff6b9d)"></u>'
    '<i style="top:80px;width:60%"></i><i style="top:95px;width:70%"></i><u style="top:118px;background:linear-gradient(135deg,#7dd3fc,#818cf8)"></u>'
    '<i style="top:184px;width:66%"></i><i style="top:199px;width:48%"></i><u style="top:222px;background:linear-gradient(135deg,#86efac,#22d3ee)"></u>'
    '<i style="top:288px;width:70%"></i><i style="top:303px;width:56%"></i><u style="top:326px;background:linear-gradient(135deg,#c084fc,#f472b6)"></u></div>'
    '<div class="scan"></div></div>',
    # Annotate: a rectangle and an arrow drawing themselves
    '<div class="art"><div class="canvas"><svg viewBox="0 0 360 220"><defs><linearGradient id="shot" x1="0" y1="0" x2="1" y2="1">'
    '<stop stop-color="#7dd3fc"/><stop offset=".6" stop-color="#818cf8"/><stop offset="1" stop-color="#c084fc"/></linearGradient></defs>'
    '<rect x="26" y="34" width="130" height="86" rx="8" fill="url(#shot)"/>'
    '<rect x="184" y="42" width="120" height="7" rx="3.5" fill="#dfe3f0"/><rect x="184" y="58" width="96" height="7" rx="3.5" fill="#dfe3f0"/><rect x="184" y="74" width="110" height="7" rx="3.5" fill="#dfe3f0"/>'
    '<rect class="draw" pathLength="1" x="18" y="26" width="146" height="102" rx="10" fill="none" stroke="#ff3b47" stroke-width="4"/>'
    '<path class="draw d2" pathLength="1" d="M266 140 L182 116" fill="none" stroke="#ff3b47" stroke-width="4" stroke-linecap="round"/>'
    '<path d="M171 113 l19 -4 l-5 16z" fill="#ff3b47"/>'
    '<text x="222" y="172" fill="#ff3b47" font-size="21" font-weight="700" font-family="-apple-system, sans-serif">Ship it!</text></svg></div>'
    '<div class="count">1</div></div>',
    # Video and GIF: recording pill, a click ripple and an audio meter
    '<div class="art"><div class="rec-pill"><i></i><span>00:12</span><em>MP4</em><em>GIF</em></div><div class="ring"></div><div class="bars">'
    + "".join('<i style="height:%d%%;animation-delay:-%.2fs"></i>' % (30 + (n * 37) % 70, (n * 0.23) % 1.6) for n in range(30))
    + "</div></div>",
]

TEMPLATE = """<!doctype html>
<html lang="{lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<meta name="description" content="{description}">
<meta name="theme-color" content="#07080f">
<meta property="og:title" content="Snapwise">
<meta property="og:description" content="{og}">
<meta property="og:image" content="{site}promo-{lang}.jpg">
<meta property="og:type" content="website">
<link rel="icon" type="image/png" href="{root}icon.png">
<link rel="alternate" hreflang="en" href="{site}">
<link rel="alternate" hreflang="vi" href="{site}vi/">
<link rel="stylesheet" href="{root}style.css">
<script>document.documentElement.classList.add('js')</script>
<!-- Generated by scripts/make-landing-pages.py; edit that file, not this one. -->
</head>
<body>
<div class="nav"><div class="wrap">
  <a class="brand" href="#"><img src="{root}icon.png" alt="">Snapwise</a>
  <div class="links">
    <a class="hide" href="#features">{nav_features}</a>
    <a class="hide" href="#snapping">{nav_snap}</a>
    <a class="hide" href="#shortcuts">{nav_keys}</a>
    <a class="hide" href="#install">{nav_install}</a>
    <a class="hide" href="{repo}">GitHub</a>
    <a class="lang" href="{other_href}" lang="{other_lang}">{other_name}</a>
    <a class="get" href="{repo}/releases/latest">{nav_get}</a>
  </div>
</div></div>

<header class="hero">
  <div class="aurora"></div><div class="gridlines"></div>
  <div class="wrap">
    <span class="badge"><i></i>{badge}</span>
    <h1>{h1}</h1>
    <p class="lead">{lead}</p>
    <div class="cta">
      <a class="btn primary" href="{repo}/releases/latest"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 4v11M7 11l5 5 5-5M5 20h14"/></svg>{download}</a>
      <a class="btn" href="{repo}">{source}</a>
    </div>
    <p class="note">{note}</p>
    <div class="stage"><div class="frame">
      <video autoplay muted loop playsinline preload="metadata" poster="{root}promo-{lang}.jpg" aria-label="{video_label}">
        <source src="{root}promo-{lang}.mp4" type="video/mp4">
      </video>
    </div></div>
    <div class="stats reveal">{stats}</div>
  </div>
</header>

<div class="wrap">
  <section id="features">
    <div class="center reveal"><span class="eyebrow grad">{f_eyebrow}</span><h2>{f_h2}</h2><p class="sub">{f_sub}</p></div>
    <div class="bento">
{cards}
    </div>
  </section>

  <section id="snapping">
    <div class="reveal"><span class="eyebrow grad">{s_eyebrow}</span><h2>{s_h2}</h2><p class="sub">{s_sub}</p></div>
    <div class="snap reveal">
      <div class="display"><div class="area"><div class="ghost"></div>
        <div class="window"><i style="top:22%;width:42%;background:#2a2f45"></i><i style="top:34%;width:70%"></i><i style="top:42%;width:58%"></i><i style="top:50%;width:66%"></i></div>
        <div class="keys"></div></div></div>
      <div class="layouts">{layouts}</div>
    </div>
    <p class="aside reveal">{s_more}</p>
  </section>

  <section id="shortcuts">
    <div class="center reveal"><span class="eyebrow grad">{k_eyebrow}</span><h2>{k_h2}</h2><p class="sub">{k_sub}</p></div>
    <div class="duo">
      <div class="sheet reveal"><h3>{k_capture}</h3>{keys_capture}</div>
      <div class="sheet reveal" style="--d:.1s"><h3>{k_windows}</h3>{keys_windows}</div>
    </div>
  </section>

  <section id="install">
    <div class="reveal"><span class="eyebrow grad">{i_eyebrow}</span><h2>{i_h2}</h2><p class="sub">{i_sub}</p></div>
    <ol class="steps">{steps}</ol>
    <p class="aside reveal">{i_aside}</p>
  </section>

  <div class="final center reveal">
    <img src="{root}icon.png" alt="">
    <h2>{c_h2}</h2>
    <p class="sub" style="margin-bottom:0;margin-left:auto;margin-right:auto">{c_sub}</p>
    <div class="cta">
      <a class="btn primary" href="{repo}/releases/latest">{download}</a>
      <a class="btn" href="{repo}">{source}</a>
    </div>
  </div>

  <footer>{footer}<br><a href="{repo}">{f_source}</a> · <a href="{repo}/issues">{f_issue}</a></footer>
</div>
<script src="{root}site.js"></script>
</body>
</html>
"""


def render(lang: str) -> str:
    t = dict(TEXT[lang])
    cards = []
    for index, (title, body) in enumerate(t["cards"]):
        if index < 4:  # large cards with an illustration
            cards.append('      <div class="card %s reveal" style="--d:%.2fs">%s<h3>%s</h3><p>%s</p></div>'
                         % (("w7", "w5", "w5", "w7")[index], (index % 2) * 0.1, ART[index], title, body))
        else:
            cards.append('      <div class="card reveal" style="--d:%.2fs"><div class="ico"><svg viewBox="0 0 24 24"><path d="%s"/></svg></div><h3>%s</h3><p>%s</p></div>'
                         % ((index - 4) * 0.08, ICONS[index - 4], title, body))
    rows = lambda items: "".join('<div class="row"><span>%s</span><span>%s</span></div>'
                                 % (label, "".join("<kbd>%s</kbd>" % k for k in keys.split())) for label, keys in items)
    t.update(
        lang=lang, repo=REPO, site=SITE,
        stats="".join("<div><b class=\"grad\">%s</b><span>%s</span></div>" % s for s in t["stats"]),
        cards="\n".join(cards),
        layouts="".join('<button type="button" data-rect="%s" data-keys="%s">%s</button>' % (rect, keys, name)
                        for (rect, keys), name in zip(LAYOUTS, t["layouts"])),
        keys_capture=rows(t["keys_capture"]), keys_windows=rows(t["keys_windows"]),
        steps="".join('<li class="reveal" style="--d:%.1fs">%s</li>' % (i * 0.1, s) for i, s in enumerate(t["steps"])),
    )
    return TEMPLATE.format(**t)


docs = Path(__file__).resolve().parent.parent / "docs"
(docs / "index.html").write_text(render("en"), encoding="utf-8")
(docs / "vi" / "index.html").write_text(render("vi"), encoding="utf-8")
print("wrote docs/index.html and docs/vi/index.html")
