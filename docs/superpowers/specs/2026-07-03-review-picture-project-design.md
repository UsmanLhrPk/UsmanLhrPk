# Review submissions: add photo + project

**Date:** 2026-07-03
**Status:** Design — awaiting user review

## Context

The portfolio site (`index.html`, vanilla HTML/CSS/JS, GitHub Pages, webpack) already
has a working, moderated review feature backed by Supabase:

- Form fields today: **name** (required), **role/company** (optional), **rating** 1–5
  (required), **message** (required), plus a honeypot.
- `reviews` table with RLS: anon can insert only `approved=false` rows and read only
  `approved=true` rows; no update/delete via the public API.
- Owner approves each review from the Supabase dashboard before it appears.

This change **extends** that feature. It does not rebuild it and adds no new
infrastructure (no Supabase Storage bucket).

## Goal

Let reviewers optionally attach a **photo** and attribute the review to a **project**.

## Decisions

| Question | Decision |
|---|---|
| Picture mechanism | **Optional image URL** the reviewer pastes (e.g. their LinkedIn photo). No file upload / no Storage bucket. |
| Picture fallback | Generated **colored initials circle** from the name when no/broken photo. |
| Project field | **Free-text input with datalist suggestions** — 7 known projects are suggested, but any custom project is accepted. **Required.** |
| Role/company field | **Keep** as optional (default chosen while user was away; reversible). |

## Data model — `supabase-schema.sql`

Two new **nullable** columns on `public.reviews`:

```sql
alter table public.reviews
  add column project   text check (project is null or char_length(project) <= 120),
  add column photo_url text check (
    photo_url is null
    or (char_length(photo_url) <= 500 and photo_url ~ '^https://')
  );
```

- `project` is free text (length-capped). Not an enum — custom projects are allowed.
- `photo_url` CHECK enforces **https-only** at the DB layer. This is the primary
  security boundary: it rejects `javascript:`, `data:`, and plain `http:` values even
  before owner moderation, so a malicious URL can never be stored.
- Both nullable → existing rows and role-only submissions remain valid.
- RLS policies are unchanged (insert stays `approved=false`, read stays `approved=true`).

The schema file's insert/seed examples get the two new columns added for reference.

## Form / UI — `index.html` reviews section

Add two fields to `#review-form`, between the role row and the rating:

1. **Project** — required.
   ```html
   <input id="rv-project" name="project" list="rv-projects" maxlength="120" required
          placeholder="Which project did we work on?" />
   <datalist id="rv-projects">
     <!-- LyfeTymes, The Chalet Edit, Aviary Platform, Superviral, APC Buddy, Quartrly, Other -->
   </datalist>
   ```
   Suggestions appear while typing; typing a value not in the list is allowed.

2. **Photo URL** — optional.
   ```html
   <input id="rv-photo" name="photo_url" type="url" maxlength="500"
          placeholder="https://…/you.jpg" />
   ```
   Hint text: "e.g. your LinkedIn photo — optional."

Existing fields (name, role/company, rating, message, honeypot) are untouched.

## Client logic — `<script>` in `index.html`

- **Read query:** extend `.select("name, role, rating, message")` →
  `.select("name, role, project, rating, message, photo_url")`.
- **Submit:** read `project` and `photo_url` from the form; validate:
  - project non-empty (required) — show inline error if missing.
  - photo_url, if present, must start with `https://` (mirror the DB CHECK) — otherwise
    show an inline error rather than letting the insert fail.
  - Insert `{ name, role: role || null, project, rating, message, photo_url: photo_url || null }`.
- Keep honeypot, disabled-button, and success/error messaging as-is.

## Rendering — review cards

Each card gains an **avatar** and a **project chip**. Build with DOM APIs
(`document.createElement`, `textContent`, `setAttribute`) — **not** string-concatenated
`innerHTML` — so neither the photo URL nor the project text can inject markup.

Avatar logic:
- If `photo_url` is present: render `<img>` with
  `loading="lazy"`, `referrerpolicy="no-referrer"`, `alt=""`, and an `onerror` handler
  that replaces the broken image with the initials circle.
- Otherwise: render a **colored initials circle** — 1–2 initials from the name, background
  color derived deterministically from the name (e.g. hash → hue) for a stable, varied look.

Project chip: a small pill showing the project name (only when present), styled to match
the existing `.tag`/`.chip` look.

CSS additions: `.review-avatar` (image + initials variants) and a project chip class,
consistent with existing tokens (`--amber`, `--muted`, `--line-strong`, etc.).

## Security & robustness

- **https-only** enforced in two places: DB CHECK (authoritative) + client validation (UX).
- Photo rendered with `referrerpolicy="no-referrer"` and `onerror` fallback so broken or
  slow external images never break the layout.
- All user text rendered via `textContent` / DOM nodes, never raw `innerHTML`.
- Moderation unchanged: nothing (photo, project, or message) is visible until the owner
  flips `approved=true`.

## Out of scope (YAGNI)

- File uploads / Supabase Storage.
- Image resizing, proxying, or content scanning.
- Editing or deleting submitted reviews from the public site.
- Star-rating display changes.

## Testing / verification

- SQL: run the `alter table` in Supabase; confirm an insert with a valid https photo_url
  and a custom project succeeds, and an insert with an `http:`/`javascript:` photo_url is
  rejected by the CHECK.
- Frontend: submit a review with a photo → appears (after approval) with the image;
  submit without a photo → initials circle; submit with a custom project not in the list →
  chip shows the custom name; broken image URL → falls back to initials.
- Confirm required-project validation blocks empty submissions client-side.
