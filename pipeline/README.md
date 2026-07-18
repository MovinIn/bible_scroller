# Bible Scroller Image Pipeline

Generates 9:16 background images for verse groups:

**Bible API** (BSB via AO Lab) → **Gemini 2.5 Flash-Lite** (prompt) → **fal.ai FLUX schnell** (image)

```
group_bible.py  →  manifest.json     (verse groups)
assign_themes.py →  themes.json       (per-chapter mood + style)
generate_batch.py →  output/*.png     (one image per group)
```

Layout: `src/` (clients + logic), CLI scripts at repo root, `prompts/` (templates), `data/chapters/` (cache), `output/` (images + manifest).

## Setup

```bash
cd pipeline
python -m venv .venv
.venv\Scripts\activate          # Windows
# source .venv/bin/activate     # macOS / Linux
pip install -r requirements.txt
copy .env.example .env          # cp on Unix
```

Set in `.env`:

- `GEMINI_API_KEY` — [free key](https://aistudio.google.com/apikey)
- `FAL_KEY` — [fal.ai](https://fal.ai/dashboard/keys) (FLUX schnell ≈ $0.003/image)

**Gemini model** (default: `gemini-flash-lite-latest` via `GEMINI_MODEL` in `.env`):


| Model                                | Free tier (approx.)                                | Paid cost (full Bible prompts) |
| ------------------------------------ | -------------------------------------------------- | ------------------------------ |
| `gemini-flash-lite-latest` (default) | Varies by underlying release; probe-tested working | ~$1.75                         |
| `gemini-2.5-flash`                   | ~20 requests/day                                   | ~$8                            |


Flash-Lite is right-sized for prompt rewriting and theme classification. The `-latest` alias tracks Google's current Flash-Lite release (may resolve to e.g. `gemini-2.0-flash-lite` under the hood). `.env` is loaded at import via `[pipeline/src/config.py](src/config.py)`, so `GEMINI_MODEL=gemini-2.5-flash` overrides the default without code changes. Override if Flash-Lite prompt quality disappoints.

Spot-check (2026-07-10): Flash-Lite prompts for John 3:16–18 and Luke 15:11–14 were verified comparable to the Flash baseline in `output/test/REPORT.md`.

## Quick start (three steps)

```bash
# 1. Group verses into scroll-sized bunches (~4–5 verses each)
python group_bible.py --book John

# 2. Assign a visual theme to each chapter (rules + Gemini)
python assign_themes.py --book John
# Review output/groups/themes.json; tweak prompts/theme_overrides.json if needed

# 3. Generate images (picks prompt per chapter automatically)
python generate_batch.py --book John --limit 20
```

To preview a single image before batching:

```bash
python generate_one.py "John 3:16-20" --extra "dawn light, hopeful mood"
```

---

## How themes work

Each chapter gets a **mood** (what to depict) and a **style** (how it looks). All verse groups in the same chapter share one theme — e.g. every group in John 3 uses the same mood and style shell.

### Style shells (`prompts/`)


| File                        | Look                                                     |
| --------------------------- | -------------------------------------------------------- |
| `meta_prompt_realistic.txt` | Cinematic matte painting, earth tones, dramatic lighting |
| `meta_prompt_clipart.txt`   | Bold outlines, flat 3–5 color palette, stylized shapes   |


Both templates accept three placeholders:

- `{verse_text}` — scripture for the group
- `{theme_guidance}` — mood snippet from `prompts/themes/`
- `{extra_guidance}` — optional `--extra` flag at generation time

### Mood catalog (`prompts/theme_registry.json`)


| `theme_id`             | Feel                            | Default style |
| ---------------------- | ------------------------------- | ------------- |
| `creation_cosmic`      | awe, dawn light, cosmic scale   | realistic     |
| `garden_peace`         | lush, intimate, Edenic calm     | clipart       |
| `wilderness_journey`   | dust, horizon, pilgrimage       | realistic     |
| `exodus_deliverance`   | dramatic escape, sea, fire      | realistic     |
| `law_covenant`         | stone, solemn, structured       | realistic     |
| `temple_worship`       | gold, incense, reverence        | realistic     |
| `prophetic_storm`      | wind, warning, dark skies       | realistic     |
| `wisdom_lyrical`       | reflective, nature motifs, soft | clipart       |
| `gospel_light`         | warm, hopeful, human faces      | realistic     |
| `parable_storybook`    | simple scene, teaching moment   | clipart       |
| `passion_somber`       | muted, weight, shadow           | realistic     |
| `resurrection_dawn`    | breaking light, empty tomb      | realistic     |
| `apocalyptic_dramatic` | symbolic, intense contrast      | realistic     |
| `epistle_community`    | gathering, letters, fellowship  | clipart       |


Mood text lives in `prompts/themes/<theme_id>.txt` and is injected into the style shell at generation time.

### Assignment rules (`assign_themes.py`)

Rules run first (no API call). Gemini is used only for chapters that don't match a rule.


| Signal                                    | Theme                  | Style     |
| ----------------------------------------- | ---------------------- | --------- |
| Psalms, Song of Solomon                   | `wisdom_lyrical`       | clipart   |
| Revelation (all chapters)                 | `apocalyptic_dramatic` | realistic |
| Genesis 1 (creation language)             | `creation_cosmic`      | realistic |
| Genesis 2                                 | `garden_peace`         | clipart   |
| Exodus 14                                 | `exodus_deliverance`   | realistic |
| Parable chapters (Matt 13, Luke 15, etc.) | `parable_storybook`    | clipart   |
| Chapter mentions temple/sanctuary         | `temple_worship`       | realistic |
| Chapter mentions wilderness/desert        | `wilderness_journey`   | realistic |
| Chapter mentions resurrection             | `resurrection_dawn`    | realistic |
| Chapter mentions cross/crucified          | `passion_somber`       | realistic |


Keyword rules match whole words only ("crossed the Jordan" does not trigger the passion theme). Epistles have no book-level rule — Gemini judges each chapter individually (it can still pick `epistle_community` from the catalog).

Use `--rules-only` to skip Gemini entirely (unmatched chapters get the default theme).

### Resolver order at generation time

When `output/groups/themes.json` exists, each image resolves its prompt in this order:

1. `**prompts/theme_overrides.json`** — manual fixes (per chapter or `*` wildcard for whole book)
2. `**output/groups/themes.json**` — cached assignment from `assign_themes.py`
3. **Fallback** — plain `--meta-prompt` (default: `meta_prompt_realistic.txt`) with no mood guidance

Chapters without an explicit assignment or override always use the fallback — a partial `themes.json` (e.g. only John assigned) never applies a theme to other books. In overrides and `themes.json`, `"style"` is optional; when omitted, the theme's default style is used.

### `themes.json` format

```json
{
  "Genesis": {
    "1": {
      "theme_id": "creation_cosmic",
      "style": "realistic",
      "rationale": "Creation account keyword rule"
    }
  },
  "John": {
    "3": {
      "theme_id": "gospel_light",
      "style": "realistic",
      "rationale": "Nicodemus and the famous verse"
    }
  }
}
```

### Manual overrides (`prompts/theme_overrides.json`)

```json
{
  "John": {
    "3": { "theme_id": "gospel_light", "style": "realistic" }
  },
  "Psalms": {
    "*": { "theme_id": "wisdom_lyrical", "style": "clipart" }
  }
}
```

Overrides are never overwritten by `assign_themes.py`. Use `"*"` to pin every chapter in a book.

### Adding a new theme

1. Add a mood snippet: `prompts/themes/my_theme.txt`
2. Register it in `prompts/theme_registry.json` under `"themes"`
3. Re-run `assign_themes.py --force` for affected books (or add an override)

---

## Step 1 — Group verses

Structure-aware grouping splits chapters into ~4–5 verse bunches at API `heading` / `line_break` markers.

```bash
python group_bible.py                          # full Bible → output/groups/manifest.json
python group_bible.py --book John
python group_bible.py --min-size 3 --max-size 5
python group_bible.py --no-cache
```

Chapter JSON is cached under `data/chapters/`. The manifest updates incrementally per book.

## Step 2 — Assign chapter themes

```bash
python assign_themes.py --book John
python assign_themes.py --book Psalms --rules-only
python assign_themes.py --force              # re-assign chapters already in themes.json
```

One Gemini call per chapter (not per verse group). Skips chapters already assigned or covered by overrides unless `--force`.

## Step 3 — Generate images

### Single image (review)

```bash
python generate_one.py "John 3:16-20"
python generate_one.py "John 3:16-20" --extra "dawn light, hopeful mood"
```

Prints verse text, resolved theme, FLUX prompt, and timing. Saves `output/<slug>_<timestamp>.png`.

Force a fixed style shell (ignore themes):

```bash
python generate_one.py "John 3:16-20" --meta-prompt prompts/meta_prompt_clipart.txt
```

Point at a missing themes path to do the same in batch:

```bash
python generate_batch.py --book John --themes output/groups/no_themes.json
```

### Batch from manifest

```bash
python generate_batch.py --manifest output/groups/manifest.json --book John --limit 10
python generate_batch.py --from-id 100 --to-id 120 --extra "dawn light"
python generate_batch.py --force
python generate_batch.py --book John --workers 8    # parallel (paid tier)
python generate_batch.py --book John --workers 3    # parallel (free tier, 30 RPM cap)
```

**Parallel workers (`--workers N`, default 1):** Each worker runs one verse group at a time (Gemini prompt + FLUX image). I/O-bound, so threads are enough — no asyncio rewrite.


| Tier                       | Recommended `--workers` | Full Bible wall-clock (≈8,000 images) |
| -------------------------- | ----------------------- | ------------------------------------- |
| Sequential (`--workers 1`) | —                       | ~31 hours                             |
| Free (Flash-Lite, 30 RPM)  | 3                       | ~8–10 hours                           |
| Paid (150+ RPM)            | 8                       | ~1.5–3 hours                          |


On transient API errors (429/503), the batch stops and saves a resume point. With `--workers > 1`, in-flight tasks may still finish; resume uses the lowest unfinished group id.

**Ctrl+C (user interrupt):** Completed images are kept. The batch returns partial progress, writes `output/groups/stop_point.json` with error `"interrupted by user"`, and cancels in-flight workers. Resume the same way as after a transient stop — run `generate_batch.py` again (no `--from-id` needed unless you want to override).

Skips groups whose slug already has a PNG in `output/` unless `--force`. Failures are written to `output/groups/failures.json`. Exits 1 if any group failed **or** the run stopped early (transient error or Ctrl+C). Resumes from `output/groups/stop_point.json` on transient API errors or user interrupt.

---

## CLI flags


| Flag            | Description                                                                                                              | `group_bible` | `assign_themes` | `generate_one` | `generate_batch` |
| --------------- | ------------------------------------------------------------------------------------------------------------------------ | ------------- | --------------- | -------------- | ---------------- |
| `--cache-dir`   | Cached chapter JSON dir (default: `data/chapters/`)                                                                      | ✅             | ✅               | ✅              | ✅                |
| `--no-cache`    | Always fetch from API                                                                                                    | ✅             | ✅               | ✅              | ✅                |
| `--extra`       | Extra creative guidance for the meta-prompt                                                                              | ❌             | ❌               | ✅              | ✅                |
| `--meta-prompt` | Fallback style shell when themes are unavailable                                                                         | ❌             | ❌               | ✅              | ✅                |
| `--themes`      | Per-chapter themes JSON (default: `output/groups/themes.json`); **output** in `assign_themes`, **input** in `generate_`* | ❌             | ✅               | ✅              | ✅                |
| `--registry`    | Theme catalog (default: `prompts/theme_registry.json`)                                                                   | ❌             | ✅               | ❌              | ❌                |
| `--overrides`   | Manual overrides (default: `prompts/theme_overrides.json`)                                                               | ❌             | ✅               | ❌              | ❌                |
| `--rules-only`  | Rules only; no Gemini for unmatched chapters                                                                             | ❌             | ✅               | ❌              | ❌                |
| `--output-dir`  | Generated images dir (default: `output/`)                                                                                | ❌             | ❌               | ✅              | ✅                |
| `--book`        | Limit to one book, e.g. `"John"`                                                                                         | ✅             | ✅               | ❌              | ✅                |
| `--min-size`    | Min verses before splitting (default: 4)                                                                                 | ✅             | ❌               | ❌              | ❌                |
| `--max-size`    | Max verses per group (default: 5)                                                                                        | ✅             | ❌               | ❌              | ❌                |
| `--output`      | Manifest output path                                                                                                     | ✅             | ❌               | ❌              | ❌                |
| `reference`     | Verse reference positional arg                                                                                           | ❌             | ❌               | ✅              | ❌                |
| `--manifest`    | Manifest JSON path                                                                                                       | ❌             | ✅               | ❌              | ✅                |
| `--from-id`     | Start manifest group id (inclusive)                                                                                      | ❌             | ❌               | ❌              | ✅                |
| `--to-id`       | End manifest group id (inclusive)                                                                                        | ❌             | ❌               | ❌              | ✅                |
| `--limit`       | Max **new** images to generate                                                                                           | ❌             | ❌               | ❌              | ✅                |
| `--workers`     | Parallel image workers (default: 1)                                                                                      | ❌             | ❌               | ❌              | ✅                |
| `--failures`    | Failures JSON output path                                                                                                | ❌             | ❌               | ❌              | ✅                |
| `--force`       | Regenerate images or re-assign themes                                                                                    | ❌             | ✅               | ❌              | ✅                |


## Output files


| Path                            | Produced by                             | Purpose                                                 |
| ------------------------------- | --------------------------------------- | ------------------------------------------------------- |
| `output/groups/manifest.json`   | `group_bible.py`                        | Verse groups for the whole Bible                        |
| `output/groups/themes.json`     | `assign_themes.py`                      | Per-chapter theme assignments                           |
| `output/groups/failures.json`   | `generate_batch.py`                     | Failed groups from last batch run                       |
| `output/groups/stop_point.json` | `generate_batch.py` / `generate_one.py` | Resume point after transient errors or Ctrl+C interrupt |
| `output/<slug>_<timestamp>.png` | `generate_`*                            | Generated background images                             |
| `data/chapters/<BOOK>/<n>.json` | `group_bible.py` / `assign_themes.py`   | Cached chapter API responses                            |


## Run tests

```bash
pytest tests/
```

