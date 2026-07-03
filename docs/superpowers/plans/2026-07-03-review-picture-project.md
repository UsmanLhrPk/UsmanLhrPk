# Review Photo + Project Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let review submitters optionally attach a photo (URL) and attribute the review to a project (free text with suggestions), then show both on the review cards.

**Architecture:** Extend the existing moderated Supabase review feature in `index.html` (vanilla HTML/CSS/JS) and `supabase-schema.sql`. Two new nullable columns (`project`, `photo_url`); photo is an https-only URL string with an initials-circle fallback; project is a `<datalist>`-backed free-text input. No file uploads, no Storage bucket.

**Tech Stack:** Static HTML/CSS/JS, Supabase JS v2 (loaded via CDN in `index.html`), Postgres (Supabase) with RLS.

## Global Constraints

- **No new infrastructure:** no Supabase Storage bucket, no new npm deps, no build changes.
- **No JS test runner exists** (`package.json` `test` is a stub). Verification is via the browser (`npm start` opens the dev server) and Supabase SQL Editor. Do **not** add a test framework.
- **Security — https-only photos:** enforced at the DB layer via a CHECK constraint (authoritative) and mirrored in client validation (UX). Never store/render a non-https photo URL.
- **No innerHTML for user data:** review cards must be built with DOM APIs (`createElement` / `textContent`), never string-concatenated `innerHTML`, so photo URL and project text cannot inject markup.
- **Moderation unchanged:** all inserts stay `approved=false`; RLS policies are not modified.
- **Design tokens** (already defined in `index.html` `:root`): `--ink #0d0d14`, `--panel #14141d`, `--text #ededf2`, `--muted #9c9cad`, `--line rgba(255,255,255,.08)`, `--line-strong rgba(255,255,255,.14)`, `--amber #f59e0b`, `--radius 14px`. Use these — no new hard-coded colors except the HSL initials-avatar formula.
- **Known projects (datalist suggestions):** LyfeTymes, The Chalet Edit, Aviary Platform, Superviral, APC Buddy, Quartrly, Other. Custom values must still be accepted.

---

### Task 1: Add `project` and `photo_url` columns to the schema

**Files:**
- Modify: `supabase-schema.sql`

**Interfaces:**
- Produces: two nullable columns on `public.reviews` — `project text` (≤120 chars) and `photo_url text` (≤500 chars, must start with `https://`).

- [ ] **Step 1: Add the ALTER TABLE block**

Insert the following immediately after the `create table public.reviews (...)` statement (after line 14, before the RLS section) in `supabase-schema.sql`:

```sql
-- Added later: optional reviewer photo (https URL only) and project attribution.
alter table public.reviews
  add column if not exists project   text
    check (project is null or char_length(project) <= 120),
  add column if not exists photo_url text
    check (
      photo_url is null
      or (char_length(photo_url) <= 500 and photo_url ~ '^https://')
    );
```

- [ ] **Step 2: Update the seed example to include the new columns**

Replace the existing seed example comment block (the `insert into public.reviews (name, role, rating, message, approved)` example near the bottom) with:

```sql
--   insert into public.reviews (name, role, project, rating, message, photo_url, approved)
--   values ('Client Name', 'Founder, Company', 'LyfeTymes', 5,
--           'Real quote here.', 'https://example.com/photo.jpg', true);
```

- [ ] **Step 3: Apply the migration in Supabase**

In the Supabase dashboard → SQL Editor → New query, paste and run just the `alter table` block from Step 1. Expected: "Success. No rows returned."

- [ ] **Step 4: Verify the CHECK constraints**

Run each of these in the SQL Editor and confirm the stated result:

```sql
-- PASSES (valid https + custom project):
insert into public.reviews (name, project, rating, message, photo_url)
values ('Test User', 'Some Custom Project', 5, 'Great work on the thing.', 'https://example.com/p.jpg');

-- FAILS with a check-constraint violation on photo_url:
insert into public.reviews (name, rating, message, photo_url)
values ('Bad User', 5, 'Trying an unsafe url here.', 'javascript:alert(1)');
```

Expected: first insert succeeds; second fails with `violates check constraint`. Then clean up the test row:

```sql
delete from public.reviews where name in ('Test User', 'Bad User');
```

- [ ] **Step 5: Commit**

```bash
git add supabase-schema.sql
git commit -m "feat: add project and photo_url columns to reviews schema"
```

---

### Task 2: Add the Project and Photo URL form fields

**Files:**
- Modify: `index.html` (review form, around lines 450–460 — after the name/role `.field-row`, before the Rating `.field`)

**Interfaces:**
- Produces: form controls `#rv-project` (name `project`, required, datalist-backed) and `#rv-photo` (name `photo_url`, type `url`, optional). Consumed by Task 3.

- [ ] **Step 1: Insert the new field row**

In `index.html`, immediately after the closing `</div>` of the first `.field-row` (the one containing `#rv-name` and `#rv-role`, ends around line 450) and before `<div class="field"><label>Rating</label>`, insert:

```html
      <div class="field-row">
        <div class="field">
          <label for="rv-project">Project</label>
          <input id="rv-project" name="project" list="rv-projects" maxlength="120" required placeholder="Which project did we work on?" />
          <datalist id="rv-projects">
            <option value="LyfeTymes"></option>
            <option value="The Chalet Edit"></option>
            <option value="Aviary Platform"></option>
            <option value="Superviral"></option>
            <option value="APC Buddy"></option>
            <option value="Quartrly"></option>
            <option value="Other"></option>
          </datalist>
        </div>
        <div class="field">
          <label for="rv-photo">Photo URL <span style="color:var(--muted);font-weight:400">(optional)</span></label>
          <input id="rv-photo" name="photo_url" type="url" maxlength="500" placeholder="https://…/you.jpg" />
        </div>
      </div>
```

- [ ] **Step 2: Verify in the browser**

Run: `npm start` (opens the dev server). Scroll to the "Leave a review" form.
Expected:
- A "Project" input and a "Photo URL (optional)" input appear between Role/company and Rating, laid out as two columns (stacking on narrow screens).
- Focusing "Project" and typing "L" suggests "LyfeTymes"; the field also accepts any typed value.
- Submitting with Project empty triggers the browser's native "please fill out this field" (it's `required`).

- [ ] **Step 3: Commit**

```bash
git add index.html
git commit -m "feat: add project and photo url fields to review form"
```

---

### Task 3: Send and read the new fields (submit + select)

**Files:**
- Modify: `index.html` `<script>` — `loadReviews()` select (line ~638) and the submit handler (lines ~660–677)

**Interfaces:**
- Consumes: `#rv-project`, `#rv-photo` from Task 2; `sb` Supabase client, `showMsg`, `rating` (already defined).
- Produces: inserts rows containing `project` and `photo_url`; the read query returns `project` and `photo_url` for Task 4's renderer.

- [ ] **Step 1: Include the new columns in the read query**

In `loadReviews()`, change:

```js
      .select("name, role, rating, message")
```

to:

```js
      .select("name, role, project, rating, message, photo_url")
```

- [ ] **Step 2: Read and validate the new fields in the submit handler**

In the `form.addEventListener("submit", ...)` handler, after the line `const message = form.message.value.trim();`, add:

```js
  const project = form.project.value.trim();
  const photoUrl = form.photo_url.value.trim();
```

Then, after the existing `if (!rating) return showMsg(...)` line and before the `if (message.length < 10)` line, add:

```js
  if (!project) return showMsg("err", "Pick or type the project we worked on.");
  if (photoUrl && !/^https:\/\//i.test(photoUrl)) return showMsg("err", "Photo URL must start with https://");
```

- [ ] **Step 3: Include the new fields in the insert**

Change:

```js
    const { error } = await sb.from("reviews").insert({ name, role: role || null, rating, message });
```

to:

```js
    const { error } = await sb.from("reviews").insert({
      name, role: role || null, project, rating, message, photo_url: photoUrl || null
    });
```

- [ ] **Step 4: Verify a submission lands in Supabase**

Run: `npm start`. Fill the form: name "Render Test", any role, Project "A Custom Project XYZ", Photo URL `https://i.pravatar.cc/80`, pick 5 stars, message "Testing the new fields end to end.". Submit.
Expected: success message ("in the moderation queue"). Then in Supabase SQL Editor:

```sql
select name, project, photo_url, rating from public.reviews where name = 'Render Test';
```

Expected: one row with `project = 'A Custom Project XYZ'` and `photo_url = 'https://i.pravatar.cc/80'`. Leave this row in place (unapproved) — Task 4 will approve it to test rendering.

Also verify validation: try submitting with Photo URL `http://x.jpg` → expect the inline error "Photo URL must start with https://" and **no** insert.

- [ ] **Step 5: Commit**

```bash
git add index.html
git commit -m "feat: submit and read project and photo_url for reviews"
```

---

### Task 4: Render avatar + project chip on review cards

**Files:**
- Modify: `index.html` CSS (reviews block, around lines 234–237) and the `renderReviews()` function + `esc()` (lines ~604–627)

**Interfaces:**
- Consumes: `grid` element, and row objects shaped `{ name, role, project, rating, message, photo_url }` from Task 3's select.
- Produces: DOM-built cards with an image-or-initials avatar and an optional project chip.

- [ ] **Step 1: Add CSS for the avatar, card footer, and project chip**

In the `/* ---------- reviews ---------- */` CSS block in `index.html`, after the `.review-meta strong { ... }` rule (line ~237), add:

```css
  .review-foot { display: flex; align-items: center; gap: 12px; }
  .review-avatar {
    width: 42px; height: 42px; border-radius: 50%; flex-shrink: 0;
    object-fit: cover; border: 1px solid var(--line-strong);
  }
  .review-avatar--initials {
    display: flex; align-items: center; justify-content: center;
    font-size: 14px; font-weight: 700; letter-spacing: 0.5px;
  }
  .review-project {
    display: inline-block; margin-top: 5px;
    font-size: 12px; font-weight: 500; color: var(--muted);
    border: 1px solid var(--line-strong); border-radius: 7px; padding: 2px 9px;
  }
```

- [ ] **Step 2: Replace `esc()` and `renderReviews()` with DOM-built rendering**

Delete the entire `esc()` function (lines ~604–608) and replace the entire `renderReviews()` function (lines ~610–627) with:

```js
function initials(name) {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  const first = (parts[0] || "?")[0];
  const last = parts.length > 1 ? parts[parts.length - 1][0] : "";
  return (first + last).toUpperCase();
}

function hueFromName(name) {
  let h = 0;
  for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) % 360;
  return h;
}

function makeAvatar(name, photoUrl) {
  const initEl = document.createElement("div");
  initEl.className = "review-avatar review-avatar--initials";
  initEl.textContent = initials(name);
  const hue = hueFromName(name);
  initEl.style.background = "hsl(" + hue + " 45% 22%)";
  initEl.style.color = "hsl(" + hue + " 70% 78%)";

  if (photoUrl) {
    const img = document.createElement("img");
    img.className = "review-avatar";
    img.src = photoUrl;
    img.alt = "";
    img.loading = "lazy";
    img.referrerPolicy = "no-referrer";
    img.addEventListener("error", () => img.replaceWith(initEl));
    return img;
  }
  return initEl;
}

function renderReviews(rows) {
  grid.innerHTML = "";
  if (!rows || rows.length === 0) {
    const empty = document.createElement("div");
    empty.className = "empty-state";
    empty.textContent = "No reviews yet — worked with me? Be the first below.";
    grid.appendChild(empty);
    return;
  }
  rows.forEach(r => {
    const card = document.createElement("article");
    card.className = "review-card";

    const stars = document.createElement("div");
    stars.className = "stars";
    stars.setAttribute("aria-label", r.rating + " out of 5 stars");
    const on = document.createElement("span");
    on.textContent = "★".repeat(r.rating);
    const off = document.createElement("span");
    off.style.color = "var(--line-strong)";
    off.textContent = "★".repeat(5 - r.rating);
    stars.append(on, off);

    const quote = document.createElement("blockquote");
    quote.textContent = "“" + r.message + "”";

    const foot = document.createElement("div");
    foot.className = "review-foot";
    foot.appendChild(makeAvatar(r.name, r.photo_url));

    const meta = document.createElement("div");
    meta.className = "review-meta";
    const nameEl = document.createElement("strong");
    nameEl.textContent = r.name;
    meta.appendChild(nameEl);
    if (r.role) meta.appendChild(document.createTextNode(" · " + r.role));
    if (r.project) {
      const proj = document.createElement("div");
      proj.className = "review-project";
      proj.textContent = r.project;
      meta.appendChild(proj);
    }
    foot.appendChild(meta);

    card.append(stars, quote, foot);
    grid.appendChild(card);
  });
}
```

- [ ] **Step 3: Approve the test review so it renders**

In Supabase SQL Editor:

```sql
update public.reviews set approved = true where name = 'Render Test';
```

- [ ] **Step 4: Verify rendering in the browser**

Run: `npm start`. Scroll to the reviews grid.
Expected for the "Render Test" card:
- The pravatar image shows as a round 42px avatar.
- A "A Custom Project XYZ" chip appears under the name.
- Stars show 5 filled.

Then test the fallbacks:
```sql
-- break the photo to test onerror fallback:
update public.reviews set photo_url = 'https://example.invalid/nope.jpg' where name = 'Render Test';
```
Reload the page → the avatar falls back to a colored "RT" initials circle (no broken-image icon).

```sql
-- test no-photo path:
update public.reviews set photo_url = null where name = 'Render Test';
```
Reload → initials circle shows directly.

- [ ] **Step 5: Clean up the test row**

```sql
delete from public.reviews where name = 'Render Test';
```

- [ ] **Step 6: Commit**

```bash
git add index.html
git commit -m "feat: render reviewer avatar and project chip on review cards"
```

---

## Self-Review

**Spec coverage:**
- Data model (project + photo_url columns, https CHECK, nullable) → Task 1. ✅
- Project = free-text datalist, required, custom allowed → Task 2 (form) + Task 3 (required validation). ✅
- Photo = optional https URL, no Storage → Task 2 (field) + Task 3 (validation/insert) + Task 4 (render with fallback). ✅
- Role/company kept as optional → unchanged existing field; nothing removed. ✅
- Rendering: image-or-initials avatar, project chip, DOM APIs not innerHTML → Task 4. ✅
- Security: https-only (DB + client), referrerpolicy no-referrer, onerror fallback, textContent → Tasks 1, 3, 4. ✅
- Read query extended → Task 3 Step 1. ✅
- Moderation unchanged → no RLS changes in any task. ✅

**Placeholder scan:** No TBD/TODO; every code step contains complete code and every verify step has exact commands + expected results.

**Type/name consistency:** `project` / `photo_url` column names match the form control `name` attributes, the insert keys, the select list, and the render accessors (`r.project`, `r.photo_url`) across Tasks 1–4. `makeAvatar(name, photoUrl)`, `initials(name)`, `hueFromName(name)` are defined and called consistently in Task 4.

**Note on TDD:** This codebase has no JS test runner and the spec/global constraints explicitly forbid adding one for a static portfolio (YAGNI). Tasks therefore substitute concrete browser + Supabase-SQL verification for automated unit tests, keeping the red→verify→implement→verify→commit rhythm.
