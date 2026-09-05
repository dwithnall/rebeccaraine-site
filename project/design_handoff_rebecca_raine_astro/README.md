# Handoff: Rebecca Raine — WordPress → Astro Conversion

## Overview
Recreation of rebeccaraine.com (WordPress, author/book marketing site) as a static site, prototyped for conversion to Astro. Content was scraped live from the production WordPress site on 2026-09-06 and is reproduced faithfully; visual design is "faithful but tidied up" — same structure and content, a cleaned-up type system and palette rather than a pixel clone of the WP theme.

## About the Design Files
The five `.html` files in this bundle are **design references**, built as streaming HTML prototypes — not production code to copy directly. The task is to **recreate these designs in Astro** (the target framework, per the brief), using Astro's conventions (`.astro` layout/page components, content collections, islands where interactivity is needed) rather than porting the HTML/inline-style markup verbatim.

## Fidelity
**Faithful but tidied up.** Content, page structure, section order, and copy match the live WordPress site exactly (pulled from the production site). Visual styling (palette, type, spacing, imagery treatment) is a cleaned-up reinterpretation, not a pixel-for-pixel clone of the WordPress/Elementor theme.

## Target Stack (per stakeholder answers)
- **Framework**: Astro, deployed to **Cloudflare** (Pages/Workers).
- **Content**: Markdown/MDX **content collections** — one collection for `books`, one for `articles` (blog posts). Do not hardcode content in page templates; define `src/content/config.ts` schemas matching the fields below and author each book/article as an `.md`/`.mdx` entry.
- **Forms**: Contact form and newsletter signup are **static UI only** in this phase — no backend wired up. Build them as real `<form>` markup (so they're easy to wire later) but they don't need to submit anywhere yet. When backend is added, **email delivery via Resend** is the planned provider — structure the form actions so a Resend-based Astro API route (or Cloudflare function) can be dropped in later without a markup rewrite.
- **Images**: Every image is a placeholder in this prototype (dashed-border drop target). Real cover art / photography will be supplied separately — use Astro's `<Image />` (or Cloudflare Images) once assets land; don't hardcode the WordPress `wp-content/uploads` URLs into the new site.

## Screens / Views

### 1. Home (`Home.dc.html`)
**Purpose**: Landing page — hero statement, featured/latest book, recent articles teaser, contact form.
**Layout**: Single column, `max-width: 1180px` centered container, `32px` side padding. Sections stack vertically with generous vertical rhythm (`60–100px` section padding).
- **Header**: sticky, `1180px` max-width row, wordmark left, nav center-right (Books / Articles / Contact), 3 circular social icons right (IG/FB/GR — 32px circles, accent fill, white initials).
- **Hero**: centered text block, eyebrow label + large serif H1 (two lines) + supporting paragraph, max-width 520px.
- **Latest Work**: card, `grid-template-columns: minmax(220px,320px) 1fr`, gap 48px, padding 40px, 1px border, cover image left, title/tagline/dual-POV blurb/CTA buttons right.
- **Recent Articles**: `repeat(auto-fit, minmax(240px,1fr))` grid, gap 32px, 4 cards (image 3:2, title, excerpt).
- **Contact** (`id="contact"`): centered form card, max-width 640px, Name/Email/Message fields + Submit button.
- **Footer**: 2-column grid (`1.3fr 1fr`) — brand/nav/social left, newsletter form right.

### 2. Books listing (`Books.dc.html`)
**Purpose**: Full bibliography grid, links out to retailers and detail pages.
**Layout**: `repeat(auto-fill, minmax(240px,1fr))` grid, gap 40px. Each of the 11 cards: cover (2:3 image), series+number eyebrow (accent color), title, one-line blurb, three text links (More / Amazon / Goodreads).
Full book list with series, blurb, and retailer URLs is in the DC's logic class — copy verbatim into the `books` content collection.

### 3. Book detail (`BookDetail.dc.html`)
**Purpose**: Single-book sales page. Built out for "The Deviation"; template for all others.
**Layout**: `grid-template-columns: minmax(220px,300px) 1fr`, gap 56px. Left: cover image + stacked Amazon/Goodreads buttons. Right: series eyebrow, serif H1, italic tagline, then dual first-person POV bios (bold speaker name + 2–3 paragraphs each). Below: full-width "Peek Inside…" excerpt card (36px padding, 1px border) with a short prose excerpt, then a centered "Read it now on [retailer]" line.

### 4. Articles listing (`Articles.dc.html`)
**Purpose**: Blog index with pagination.
**Layout**: `repeat(auto-fit, minmax(260px,1fr))` grid, gap 36px, 9 cards per page (image 3:2, title, excerpt, "Read More" text link). Pagination row below: circular page-number pills (current page filled accent, others outlined), plus "Next »". Real site has 6 pages total — build the collection to paginate at 9 items/page via Astro's built-in pagination.

### 5. Article detail (`ArticleDetail.dc.html`)
**Purpose**: Long-form post template.
**Layout**: Single column, max-width 720px. Category+date eyebrow, serif H1, full-width hero image (3:2), then 3–5 body paragraphs (16px, line-height 1.85), tag pills, prev/next post nav (border-top divider, two-column flex, right-aligned "next").
**Note**: body copy on this page is a **placeholder pattern**, not the real WordPress post text — per instruction, swap in real article bodies as MDX content when available.

## Design Tokens
- `--bg`: `oklch(97.5% 0.012 75)` — warm off-white page background
- `--ink`: `oklch(21% 0.02 55)` — primary text
- `--muted`: `oklch(48% 0.018 55)` — secondary text
- `--accent`: `oklch(40% 0.13 22)` — wine/burgundy accent (links, CTAs, eyebrows, social icons)
- `--card`: `oklch(99% 0.006 75)` — card/footer background
- `--line`: `oklch(89% 0.014 70)` — hairline borders
- **Type**: Playfair Display (serif, 500/600, italic for taglines) for all headings; Public Sans (400/500/600) for body/UI. Loaded via Google Fonts.
- **Radius**: 2px (buttons/inputs), 4px (cards).
- **Spacing scale**: 8/10/12/14/16/20/24/28/32/36/40/48/56/80/100px, used per the layout notes above.
- Buttons: solid `--accent` fill + white text for primary actions; outline (`1px solid var(--line)`) for secondary.

## Interactions & Behavior
- No client-side JS interactivity beyond standard link navigation in this phase (forms don't submit; pagination links are static).
- Header is `position: sticky; top: 0`.
- All nav/footer links are relative between the 5 page types (`Home`, `Books`, `BookDetail`, `Articles`, `ArticleDetail`) — in Astro these become real per-slug routes (`/book/[slug]`, `/blog/[slug]`) via content collections, not static single files.
- Responsive: grids use `auto-fit`/`auto-fill` with `minmax()` so columns reflow down to 1 column on narrow viewports; no fixed pixel widths on text containers.

## State Management
None — fully static content. Once forms are wired to Resend, add minimal client state for submit/loading/success/error per form.

## Assets
All imagery in the prototype is a placeholder drop-target (dashed border, labeled with what belongs there — e.g. "The Deviation — cover art"). Original WordPress asset URLs (for reference only, do not hotlink in production):
- Logo: `wp-content/uploads/2021/11/logo-wm-inv.svg`
- Book covers and article photos: various paths under `wp-content/uploads/...` (see live site).
Real cover art and article photography will be supplied separately and should be optimized (WebP/AVIF, `<Image />`) on import into Astro.

## Files
- `Home.dc.html`
- `Books.dc.html`
- `BookDetail.dc.html`
- `Articles.dc.html`
- `ArticleDetail.dc.html`
- `image-slot.js` (placeholder-image helper used only in the prototype; not needed in the Astro build)
