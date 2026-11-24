# org-islam

One Emacs Lisp package that makes Org mode aware of and work with
Islamic (Hijri) dates just like it does with Gregorian ones, and turns
Emacs' built-in `cal-islam.el` into a complete Islamic calendar with a
maghrib day boundary and Arabic timestamp rendering.

## Design

- **Hijri timestamps are stored as ordinary Org timestamps in Gregorian
  form.** Every piece of Org machinery (agenda, sorting, comparisons,
  deadlines) keeps working unchanged. A timestamp is marked as Hijri by
  a tag in the (otherwise ignored) day-name slot:

  ```
  [2026-11-24 Hijri]  or  <2026-11-24 Hijri 20:15>
  ```

- **Only Hijri timestamps display as Hijri.** Gregorian timestamps are
  never touched. Rendering happens through `display` overlays (the same
  mechanism as `org-display-custom-times`):

  ```
  [الثلاثاء ١٣ جمادى الآخرة ١٤٤٨هـ ٢٠:١٥]
  ```

- **The Islamic day starts at maghrib.** `org-islam-hijri-today` (and
  the overlay rendering for timed timestamps) roll the Hijri date over
  at sunset. Maghrib times come from the
  [Awqat](https://github.com/zkry/awqat) prayer-times package when
  available, otherwise from built-in `solar.el` (set
  `calendar-latitude`/`calendar-longitude`), otherwise from a fixed
  fallback. A timer fires at maghrib, runs `org-islam-maghrib-hook`,
  and refreshes overlays in all Org buffers.

- **Hijri-aware editing.** `S-<right>`/`S-<left>` on a marked timestamp
  move it by *Hijri* months with day clamping (Ramadan 30 + 1 month =
  Shawwal 29); `S-<up>`/`S-<down>` and `C-c .` preserve the marker.

- **Conversions build on `cal-islam.el`.** `org-islam-date-correction`
  shifts the arithmetic calendar to match local moonsighting or an
  official table (e.g. Umm al-Qura); the two converter custom variables
  let you plug in exact tables.

## Setup

```elisp
(require 'org-islam)
(global-org-islam-mode 1)
```

For accurate maghrib times, set your location (also used by Awqat and
`solar.el`):

```elisp
(setq calendar-latitude 21.42
      calendar-longitude 39.83)
```

## Keys (prefix `C-c i`)

| Key       | Action                                                    |
|-----------|-----------------------------------------------------------|
| `C-c i .` | Insert a Hijri timestamp (C-u: with time, C-u C-u: inactive) |
| `C-c i !` | Insert an inactive Hijri timestamp                        |
| `C-c i s` | SCHEDULE the entry at a Hijri date                        |
| `C-c i d` | DEADLINE at a Hijri date                                  |
| `C-c i c` | Toggle the Hijri marker on the timestamp at point         |
| `C-c i t` | Toggle Hijri overlays in this buffer                      |
| `C-c i h` | Echo today's Hijri date (maghrib aware)                   |

Hijri date input accepts `Y-M-D`, `M-D` (current year), `D` (current
month), or `RET` for today, with `-`, `/`, `.` or spaces as separators
and Arabic-Indic digits.

## Agenda and calendar

- Agenda day headings get the Hijri date appended
  (`org-islam-agenda-show-hijri`, on by default).
- `M-x org-islam-calendar-show-hijri` — echo the Hijri date under the
  calendar cursor.
- `M-x org-islam-calendar-goto-hijri-today` — jump to today's Hijri
  date (maghrib aware).
- `M-x org-islam-calendar-goto-hijri-date` — jump to a Hijri date.

## Notable custom variables

- `org-islam-display-style` (`arabic` / `translit`),
  `org-islam-display-digits` (`auto` / `arabic` / `western`)
- `org-islam-timestamp-tag` (default `"Hijri"`)
- `org-islam-maghrib-aware-display`, `org-islam-overlay-show-gregorian`
- `org-islam-day-boundary-source` (`auto` / `awqat` / `solar` / `fixed`
  / `custom`), `org-islam-fixed-maghrib-time`
- `org-islam-date-correction`, `org-islam-hijri-from-absolute-function`,
  `org-islam-absolute-from-hijri-function`
- `org-islam-agenda-show-hijri`, `org-islam-hijri-timestamp-editing`
- `org-islam-maghrib-rollover-timer`, `org-islam-maghrib-hook`

## Known limitations

- Repeaters (`+1m`) are evaluated by Org in Gregorian space. Hijri
  month arithmetic is available through interactive `S-<arrow>`
  editing.
- `cal-islam.el` implements the arithmetic (tabular) Islamic calendar;
  use `org-islam-date-correction` or the custom converter functions to
  match an official calendar.

## License

GPL-3.0-or-later.
