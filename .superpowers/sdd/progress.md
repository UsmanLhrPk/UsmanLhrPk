# Progress: Review photo + project (2026-07-03)

Plan: docs/superpowers/plans/2026-07-03-review-picture-project.md
Mode: subagent-driven. **NO AUTO-COMMIT** (user instruction) — all changes stay in working tree; implementers skip commit steps.

- Task 1: schema columns — COMPLETE (working tree, uncommitted; review clean; Minor: https regex case-sensitive, matches spec)
- Task 2: form fields — COMPLETE (working tree, uncommitted; review clean; applied Minor fix: added type="text" to #rv-project)
- Task 3: submit + read — COMPLETE (working tree, uncommitted; review found 1 Important: client https regex case-insensitive vs case-sensitive DB — FIXED by dropping /i flag to mirror DB)
- Task 4: render avatar + chip — COMPLETE (working tree, uncommitted; review clean; Minors: always-created initEl node negligible; report line-num nit)
- Final whole-branch review — COMPLETE: "Ready to commit". Field consistency + security verified end-to-end; both known Minors accepted. No Critical/Important.

ALL TASKS COMPLETE. Changes uncommitted in working tree (per no-auto-commit). Pending user actions: (1) run ALTER TABLE in Supabase; (2) browser-verify; (3) decide on commit.

Open Minor roll-up for final review:
- Task 1: photo_url DB CHECK is case-sensitive `^https://` (intentional per spec; client now matches after Task 3 fix)
- Task 4: initEl created even when photo loads (negligible, ≤12 rows)
