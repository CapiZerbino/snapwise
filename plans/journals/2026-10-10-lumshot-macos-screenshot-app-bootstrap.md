---
title: Lumshot macOS screenshot app bootstrap
date: 2026-10-10
summary: "Built a CleanShot X-style menu-bar app in Swift (ScreenCaptureKit, AVFoundation, Vision): capture, scrolling stitcher, recording + video editor, annotate editor, overlay, pin, OCR, history. 43 unit tests pass; independent review found pause-offset, countdown-lifetime and editor undo defects, all fixed. Runtime capture paths unverified: Screen Recording permission must be granted by the user."
---

# Lumshot macOS screenshot app bootstrap

Built a CleanShot X-style menu-bar app in Swift (ScreenCaptureKit, AVFoundation, Vision): capture, scrolling stitcher, recording + video editor, annotate editor, overlay, pin, OCR, history. 43 unit tests pass; independent review found pause-offset, countdown-lifetime and editor undo defects, all fixed. Runtime capture paths unverified: Screen Recording permission must be granted by the user.

> Historical work record — not durable authority. Prefer docs/specs/ADRs for current decisions.
