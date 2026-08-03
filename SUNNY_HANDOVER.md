# feat/care-polish — Sunny's iOS work (2026-08-02)
Based on feat/gateway-camera-ownership @ e6e3970 (snapshot — rebase once
after the wave lands; the cherry-picked login-resilience commit dedupes).
Full details: nemara-backend/docs/plans/2026-08-02-sunny-handover.md
Highlights: Features/Home/HomeStatusView.swift (per-person verdict fold +
AI report), InfoDot declutter pattern, wandering camera picker
(whereRooms-gated exit doors), tolerant Detector decode (fixes sign-in vs
prod), AM/PM events, duplicate camera-name guard.
Backend endpoints it calls (all optional-degrade): /v1/home-briefing,
/v1/home-report, /v1/patients/{id}/last-presence — on branch
nemara-backend:feat/review-gate-and-home-endpoints.
