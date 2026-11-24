;;; org-islam.el --- Islamic (Hijri) calendar support for Org mode  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Khalid Rafi
;; Author: Khalid Rafi <khaalidrafi@gmail.com>
;; Keywords: calendar, islam, hijri, org, arabic
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1") (org "9.4"))
;; URL: https://github.com/khaalidrafi/org-islam

;; This file is part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; One package that makes Org mode aware of and work with Islamic
;; (Hijri) dates just like it does with Gregorian ones, and extends
;; Emacs' built-in `cal-islam.el' into a complete Islamic calendar.
;;
;; Design principles:
;;
;; 1. Hijri timestamps are stored in Org files as ordinary Org
;;    timestamps in *Gregorian* form, so every piece of Org machinery
;;    (agenda, sorting, comparisons, deadlines) keeps working
;;    unchanged.  A timestamp is marked as Hijri by putting a tag
;;    (default "Hijri") in the day-name slot, e.g.
;;
;;        [2026-11-24 Hijri]  or  <2026-11-24 Hijri 20:15>
;;
;;    The day-name slot is ignored by `org-parse-time-string', so the
;;    marker is inert to Org itself.
;;
;; 2. Only Hijri timestamps display as Hijri.  Gregorian timestamps
;;    are never touched.  Display happens through `display' text
;;    overlays, the same mechanism Org uses for
;;    `org-display-custom-times'.  For example, the timestamp above
;;    shows as
;;
;;        <الثلاثاء ١٣ جمادى الآخرة ١٤٤٨هـ ٢٠:١٥>
;;
;;    depending on `org-islam-display-style'.
;;
;; 3. The Islamic day starts at maghrib (sunset), not midnight.
;;    `org-islam-hijri-today' and the overlay rendering honour this:
;;    after maghrib, the Hijri date has already rolled over.  Maghrib
;;    times come from the Awqat prayer-times package when installed,
;;    otherwise from Emacs' built-in `solar.el', otherwise from a
;;    fixed fallback time.  A timer fires at maghrib and runs
;;    `org-islam-maghrib-hook' so anything showing the current Hijri
;;    date (agenda, modeline, echoes) can refresh.
;;
;; 4. Editing stays Hijri-aware: `S-<right>'/`S-<left>' on a Hijri
;;    timestamp move it by *Hijri* months (with day clamping, e.g.
;;    Ramadan 30 + 1 month = Shawwal 29), and `S-<up>'/`S-<down>'
;;    keep the marker intact.  `C-c .' on a Hijri timestamp re-marks
;;    the edited timestamp.
;;
;; 5. Conversions build on `cal-islam.el' (the arithmetic/tabular
;;    Islamic calendar).  `org-islam-date-correction' shifts the
;;    arithmetic calendar by whole days to match a local moonsighting
;;    or an official table (e.g. Umm al-Qura).  For exact official
;;    calendars, plug converters into
;;    `org-islam-hijri-from-absolute-function' and
;;    `org-islam-absolute-from-hijri-function'.
;;
;; Known limitation: repeaters (`+1m') are evaluated by Org in
;; Gregorian space.  Hijri month arithmetic is available through the
;; interactive S-<arrow> editing described above.
;;
;; Quick start:
;;
;;    (require 'org-islam)
;;    (global-org-islam-mode 1)
;;
;; Then in any Org buffer (keymap prefix `C-c i'):
;;
;;    C-c i .   insert a Hijri timestamp
;;              (C-u: also a time of day; C-u C-u: inactive)
;;    C-c i !   insert an inactive Hijri timestamp (C-u: with time)
;;    C-c i s   SCHEDULE the entry at a Hijri date
;;    C-c i d   set a DEADLINE at a Hijri date
;;    C-c i c   toggle the Hijri marker on the timestamp at point
;;    C-c i t   toggle Hijri overlays in this buffer
;;    C-c i h   echo today's Hijri date (maghrib aware)
;;
;; In the calendar buffer: `M-x org-islam-calendar-show-hijri' echoes
;; the Hijri date under point, `M-x
;; org-islam-calendar-goto-hijri-today' jumps to today's Hijri date.
;;
;; Agenda: day headings get the Hijri date appended (see
;; `org-islam-agenda-show-hijri').

;;; Code:

(require 'calendar)
(require 'cal-islam)
(require 'org)
(require 'org-macs)

(declare-function awqat--times-for-day "awqat" (&optional day))
(declare-function solar-sunrise-sunset "solar" (date))

(defgroup org-islam nil
  "Islamic (Hijri) calendar support for Org mode."
  :group 'org
  :group 'calendar)


;;; Part 1: Names and digits

(defconst org-islam-arabic-month-names
  ["محرم" "صفر" "ربيع الأول" "ربيع الآخر" "جمادى الأولى" "جمادى الآخرة"
   "رجب" "شعبان" "رمضان" "شوال" "ذو القعدة" "ذو الحجة"]
  "Arabic names of the Islamic months, Muharram = index 0.")

(defconst org-islam-transliterated-month-names
  ["Muharram" "Safar" "Rabi' al-Awwal" "Rabi' al-Thani" "Jumada al-Ula"
   "Jumada al-Akhirah" "Rajab" "Sha'ban" "Ramadan" "Shawwal"
   "Dhu al-Qi'dah" "Dhu al-Hijjah"]
  "Transliterated names of the Islamic months, Muharram = index 0.")

(defconst org-islam-arabic-day-names
  ["الأحد" "الاثنين" "الثلاثاء" "الأربعاء" "الخميس" "الجمعة" "السبت"]
  "Arabic day names, Sunday = index 0.")

(defconst org-islam-transliterated-day-names
  ["Sun" "Mon" "Tue" "Wed" "Thu" "Fri" "Sat"]
  "Transliterated (abbreviated) day names, Sunday = index 0.")

(defconst org-islam-arabic-indic-digits
  ["٠" "١" "٢" "٣" "٤" "٥" "٦" "٧" "٨" "٩"]
  "Arabic-Indic digit characters for 0 through 9.")

(defun org-islam-to-arabic-digits (string)
  "Return STRING with Western digits replaced by Arabic-Indic digits."
  (replace-regexp-in-string
   "[0-9]"
   (lambda (d) (aref org-islam-arabic-indic-digits (string-to-number d)))
   string))

(defun org-islam-to-western-digits (string)
  "Return STRING with Arabic-Indic digits replaced by Western digits."
  (replace-regexp-in-string
   "[٠-٩]"
   (lambda (d) (format "%d" (- (aref d 0) ?٠)))
   string))

(defcustom org-islam-display-style 'arabic
  "How Hijri dates are rendered in overlays and echoes.
`arabic'   -- Arabic script month and day names, e.g. جمادى الآخرة.
`translit' -- Transliterated month names, e.g. Jumada al-Akhirah."
  :group 'org-islam
  :type '(choice (const :tag "Arabic script" arabic)
                 (const :tag "Transliterated" translit)))

(defcustom org-islam-display-digits 'auto
  "Digit style used for Hijri dates.
`auto'    -- Arabic-Indic digits with `arabic' style, Western otherwise.
`arabic'  -- Always Arabic-Indic digits (١٢٣).
`western' -- Always Western digits (123)."
  :group 'org-islam
  :type '(choice (const :tag "Automatic" auto)
                 (const :tag "Arabic-Indic" arabic)
                 (const :tag "Western" western)))

(defun org-islam--digitize (string)
  "Convert digits in STRING per `org-islam-display-digits' and style."
  (pcase org-islam-display-digits
    (`arabic (org-islam-to-arabic-digits string))
    (`western string)
    (_ (if (eq org-islam-display-style 'arabic)
           (org-islam-to-arabic-digits string)
         string))))


;;; Part 2: Conversions (extending cal-islam.el)

(defcustom org-islam-date-correction 0
  "Whole-day correction applied to the arithmetic Islamic calendar.
`cal-islam.el' implements the tabular (arithmetic) Islamic calendar,
which can drift a day or two from a local moonsighting or an official
table such as Umm al-Qura.  If the official Hijri date is N days
*ahead* of the arithmetic one, set this to N.

This affects every conversion this package performs (overlays, agenda,
input, editing).  The diary/calendar functions from `cal-islam.el'
itself are not affected."
  :group 'org-islam
  :type 'integer)

(defcustom org-islam-hijri-from-absolute-function nil
  "Custom converter from absolute date to Hijri date.
If non-nil, called with the absolute (Gregorian) date number and must
return the Hijri date as a list (MONTH DAY YEAR).  When nil, the
arithmetic calendar from `cal-islam.el' shifted by
`org-islam-date-correction' is used.  Use this to plug in an exact
official table, e.g. Umm al-Qura."
  :group 'org-islam
  :type '(choice (const :tag "Arithmetic (cal-islam.el) with correction" nil)
                 (function :tag "Custom function")))

(defcustom org-islam-absolute-from-hijri-function nil
  "Custom converter from Hijri date to absolute date.
If non-nil, called with the Hijri date (MONTH DAY YEAR) and must
return the absolute (Gregorian) date number.  Must be the inverse of
`org-islam-hijri-from-absolute-function'."
  :group 'org-islam
  :type '(choice (const :tag "Arithmetic (cal-islam.el) with correction" nil)
                 (function :tag "Custom function")))

(defun org-islam-hijri-from-absolute (absolute)
  "Hijri date (MONTH DAY YEAR) for ABSOLUTE date, as a moment in the daytime."
  (if org-islam-hijri-from-absolute-function
      (funcall org-islam-hijri-from-absolute-function absolute)
    (calendar-islamic-from-absolute (+ absolute org-islam-date-correction))))

(defun org-islam-absolute-from-hijri (hijri)
  "Absolute date whose daytime belongs to Hijri date HIJRI (MONTH DAY YEAR)."
  (if org-islam-absolute-from-hijri-function
      (funcall org-islam-absolute-from-hijri-function hijri)
    (- (calendar-islamic-to-absolute hijri) org-islam-date-correction)))

(defun org-islam-gregorian-to-hijri (gdate)
  "Hijri date (MONTH DAY YEAR) for Gregorian date GDATE (MONTH DAY YEAR).
This uses the daytime convention: the Hijri date whose daytime falls
on GDATE, matching `calendar-islamic-date-string'.  For the maghrib
aware \"current Hijri date\", see `org-islam-hijri-today'."
  (org-islam-hijri-from-absolute (calendar-absolute-from-gregorian gdate)))

(defun org-islam-hijri-to-gregorian (hijri)
  "Gregorian date (MONTH DAY YEAR) for Hijri date HIJRI (MONTH DAY YEAR)."
  (calendar-gregorian-from-absolute (org-islam-absolute-from-hijri hijri)))

(defun org-islam-last-day-of-hijri-month (month year)
  "Last day of Hijri MONTH in Hijri YEAR."
  (calendar-islamic-last-day-of-month month year))

(defun org-islam-hijri-month-name (month &optional style)
  "Name of Hijri MONTH (1-12) in STYLE (see `org-islam-display-style')."
  (aref (if (eq (or style org-islam-display-style) 'arabic)
            org-islam-arabic-month-names
          org-islam-transliterated-month-names)
        (1- month)))

(defun org-islam-hijri-year-valid-p (year)
  "Non-nil if Hijri YEAR is usable (positive)."
  (> year 0))


;;; Part 3: Maghrib day boundary

(defcustom org-islam-day-boundary-source 'auto
  "Where maghrib (sunset) times come from.
`auto'   -- Awqat when loaded and configured, else solar.el, else fixed.
`awqat'  -- The Awqat prayer-times package (needs `calendar-latitude'
            and `calendar-longitude' set).
`solar'  -- Built-in `solar.el' (needs the same location variables).
`fixed'  -- `org-islam-fixed-maghrib-time' every day.
`custom' -- `org-islam-custom-maghrib-function'."
  :group 'org-islam
  :type '(choice (const :tag "Automatic" auto)
                 (const :tag "Awqat" awqat)
                 (const :tag "solar.el" solar)
                 (const :tag "Fixed time" fixed)
                 (const :tag "Custom function" custom)))

(defcustom org-islam-fixed-maghrib-time "18:00"
  "Fallback maghrib time (\"HH:MM\") when nothing better is available.
Polar night/day locations should always use Awqat or solar.el."
  :group 'org-islam
  :type 'string)

(defcustom org-islam-custom-maghrib-function nil
  "Function called with a Gregorian date (MONTH DAY YEAR).
Must return the maghrib time as a float number of hours (0-24), or
nil to fall back to the fixed time."
  :group 'org-islam
  :type '(choice (const :tag "None" nil) (function :tag "Function")))

(defvar org-islam--maghrib-cache (make-hash-table :test 'equal)
  "Cache of maghrib hours, keyed by Gregorian date.")

(defun org-islam--maghrib-from-awqat (gdate)
  "Maghrib hour (float) on GDATE from Awqat, or nil."
  (and (fboundp 'awqat--times-for-day)
       (bound-and-true-p calendar-latitude)
       (bound-and-true-p calendar-longitude)
       (let ((times (ignore-errors (awqat--times-for-day gdate))))
         (and (listp times) (>= (length times) 5)
              (let ((maghrib (car (nth 4 times))))
                (and (numberp maghrib) maghrib))))))

(defun org-islam--maghrib-from-solar (gdate)
  "Maghrib hour (float) on GDATE from `solar.el', or nil."
  (and (bound-and-true-p calendar-latitude)
       (bound-and-true-p calendar-longitude)
       (ignore-errors
         (require 'solar)
         (let ((sunset (nth 1 (solar-sunrise-sunset gdate))))
           (and (numberp sunset) sunset)))))

(defun org-islam--maghrib-fixed (_gdate)
  "Fixed fallback maghrib hour."
  (let ((hms (split-string org-islam-fixed-maghrib-time "[:.]")))
    (+ (string-to-number (or (nth 0 hms) "18"))
       (/ (string-to-number (or (nth 1 hms) "0")) 60.0))))

(defun org-islam-maghrib-hour (&optional gdate)
  "Maghrib (sunset) time on Gregorian GDATE as float hours (0-24).
GDATE defaults to today.  See `org-islam-day-boundary-source'."
  (let* ((date (or gdate (calendar-current-date)))
         (key (list (calendar-extract-month date)
                    (calendar-extract-day date)
                    (calendar-extract-year date))))
    (or (gethash key org-islam--maghrib-cache)
        (let ((hour
               (or (pcase org-islam-day-boundary-source
                     ((or `auto `awqat)
                      (org-islam--maghrib-from-awqat date))
                     (`solar (org-islam--maghrib-from-solar date))
                     (`fixed nil)
                     (`custom
                      (and org-islam-custom-maghrib-function
                           (funcall org-islam-custom-maghrib-function
                                    date))))
                   (when (eq org-islam-day-boundary-source 'auto)
                     (org-islam--maghrib-from-solar date))
                   (org-islam--maghrib-fixed date))))
          (puthash key hour org-islam--maghrib-cache)
          hour))))

(defun org-islam-after-maghrib-p (&optional time)
  "Non-nil if TIME (default now) is at or after maghrib of its day."
  (let* ((d (decode-time (or time (current-time))))
         (gdate (list (nth 4 d) (nth 3 d) (nth 5 d))))
    (>= (+ (nth 2 d) (/ (nth 1 d) 60.0))
        (org-islam-maghrib-hour gdate))))

(defun org-islam-hijri-of-evening (gdate)
  "Hijri date of the Islamic day containing the evening of GDATE.
The Islamic day starts at maghrib, so the evening of GDATE belongs
to the same Islamic day as the daytime of the next Gregorian day."
  (org-islam-gregorian-to-hijri
   (calendar-gregorian-from-absolute
    (1+ (calendar-absolute-from-gregorian gdate)))))

(defun org-islam-hijri-today (&optional time)
  "Current Hijri date (MONTH DAY YEAR), maghrib aware.
The Islamic day starts at sunset.  If TIME (default now) is at or
after maghrib, the Hijri date is already that of the *next* Gregorian
day's daytime.  This is the Hijri analogue of `org-today' combined
with `org-extend-today-until'."
  (let* ((d (decode-time (or time (current-time))))
         (gdate (list (nth 4 d) (nth 3 d) (nth 5 d))))
    (if (org-islam-after-maghrib-p (or time (current-time)))
        (org-islam-hijri-of-evening gdate)
      (org-islam-gregorian-to-hijri gdate))))

(defcustom org-islam-maghrib-rollover-timer t
  "Whether to run a timer at maghrib that refreshes Hijri displays.
When non-nil, `global-org-islam-mode' arms a timer for today's (or
tomorrow's) maghrib.  When it fires, the maghrib cache is cleared,
`org-islam-maghrib-hook' is run, Hijri overlays in Org buffers are
re-rendered, and the timer re-arms itself for the next maghrib."
  :group 'org-islam
  :type 'boolean)

(defcustom org-islam-maghrib-hook nil
  "Hook run at maghrib, after the Hijri date has rolled over.
Use it to refresh anything that displays the current Hijri date."
  :group 'org-islam
  :type 'hook)

(defvar org-islam--rollover-timer nil
  "The maghrib rollover timer.")

(defun org-islam-refresh-overlays ()
  "Re-render Hijri overlays in the current Org buffer."
  (when (derived-mode-p 'org-mode)
    (when font-lock-mode
      (font-lock-flush (point-min) (point-max)))))

(defun org-islam--refresh-all-org-buffers ()
  "Re-render Hijri overlays in every live Org buffer."
  (dolist (buffer (buffer-list))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (when (and (derived-mode-p 'org-mode)
                   (bound-and-true-p org-islam-mode))
          (org-islam-refresh-overlays))))))

(defun org-islam--at-maghrib ()
  "Rollover action: clear caches, run hook, refresh, re-arm."
  (clrhash org-islam--maghrib-cache)
  (run-hooks 'org-islam-maghrib-hook)
  (org-islam--refresh-all-org-buffers)
  (org-islam--schedule-rollover))

(defun org-islam--schedule-rollover ()
  "Arm the maghrib rollover timer for the next maghrib."
  (when org-islam--rollover-timer
    (cancel-timer org-islam--rollover-timer)
    (setq org-islam--rollover-timer nil))
  (when org-islam-maghrib-rollover-timer
    (let* ((now (decode-time))
           (gdate (list (nth 4 now) (nth 3 now) (nth 5 now)))
           (hour-float (org-islam-maghrib-hour gdate))
           (hour (floor hour-float))
           (minute (floor (* 60.0 (- hour-float hour)))))
      (when (>= minute 60)
        (setq hour (1+ hour) minute 0))
      (let ((at (org-encode-time
                 (list 0 (1+ minute) hour
                       (nth 3 now) (nth 4 now) (nth 5 now)))))
        (unless (time-less-p (current-time) at)
          (setq at (time-add at 86400)))
        (setq org-islam--rollover-timer
              (run-at-time at nil #'org-islam--at-maghrib))))))


;;; Part 4: Formatting

(defun org-islam-format-hijri (hijri &optional gdate style with-time
                                      hour minute)
  "Format Hijri date HIJRI (MONTH DAY YEAR) as a display string.
GDATE is the Gregorian date, needed for the weekday name; it is
computed from HIJRI when nil.  STYLE overrides
`org-islam-display-style'.  When WITH-TIME is non-nil, HOUR and
MINUTE are appended."
  (let* ((style (or style org-islam-display-style))
         (arabic (eq style 'arabic))
         (month (nth 0 hijri)) (day (nth 1 hijri)) (year (nth 2 hijri))
         (g (or gdate (org-islam-hijri-to-gregorian hijri)))
         (weekday (calendar-day-of-week g))
         (day-name (if arabic
                       (aref org-islam-arabic-day-names weekday)
                     (aref org-islam-transliterated-day-names weekday)))
         (month-name (org-islam-hijri-month-name month style))
         (day-str (org-islam--digitize (number-to-string day)))
         (year-str (org-islam--digitize (number-to-string year)))
         (tail (if arabic "هـ" "AH")))
    (concat
     (format "%s %s %s %s %s" day-name day-str month-name year-str tail)
     (when with-time
       (format " %s"
               (org-islam--digitize
                (format "%02d:%02d" (or hour 0) (or minute 0))))))))

(defun org-islam-hijri-date-string (&optional gdate style)
  "Hijri date of Gregorian GDATE (default today) as a plain string.
Unlike `org-islam-hijri-today', \"today\" uses the daytime convention
here, which is what an agenda day heading wants."
  (let ((g (or gdate (calendar-current-date))))
    (org-islam-format-hijri (org-islam-gregorian-to-hijri g) g style)))

(defun org-islam-echo-hijri-today ()
  "Echo the current Hijri date (maghrib aware)."
  (interactive)
  (let* ((h (org-islam-hijri-today))
         (g (org-islam-hijri-to-gregorian h)))
    (message "Hijri date: %s%s"
             (org-islam-format-hijri h g)
             (if (org-islam-after-maghrib-p)
                 "  (after maghrib)"
               ""))))


;;; Part 5: Hijri timestamps in Org

(defcustom org-islam-timestamp-tag "Hijri"
  "Marker placed in the day-name slot of Hijri timestamps.
The default gives `[2026-11-24 Hijri]'.  The tag must not contain
digits, `]', `>', `+', `-', or spaces, matching Org's day-name slot
grammar (`org-ts-regexp0').  With the default `arabic' display
style that timestamp then displays as `[الثلاثاء ١٣ جمادى الآخرة
١٤٤٨هـ]'."
  :group 'org-islam
  :type 'string)

(defconst org-islam--date-core
  "\\([0-9]\\{4\\}\\)-\\([0-9]\\{2\\}\\)-\\([0-9]\\{2\\}\\)"
  "Regexp core matching the date part of an Org timestamp.")

(defun org-islam-ts-regexp ()
  "Regexp matching an Org timestamp marked as Hijri."
  (concat "[[<]" org-islam--date-core
          " *" (regexp-quote org-islam-timestamp-tag)
          "[^]>\n]*[]>]"))

(defun org-islam--ts-bounds ()
  "Bounds (BEG . END) of the Hijri timestamp containing point, or nil."
  (let ((here (point)))
    (save-excursion
      (goto-char (line-beginning-position))
      (let ((end (line-end-position)) found)
        (while (and (not found)
                    (re-search-forward (org-islam-ts-regexp) end t))
          (when (<= (match-beginning 0) here (match-end 0))
            (setq found (cons (match-beginning 0) (match-end 0)))))
        found))))

(defun org-islam-timestamp-p ()
  "Non-nil if point is inside a Hijri-marked timestamp."
  (and (org-islam--ts-bounds) t))

(defun org-islam--replace-ts (beg end new)
  "Replace the timestamp between BEG and END with string NEW."
  (goto-char beg)
  (delete-region beg end)
  (insert new))

(defun org-islam--mark-string (ts)
  "Return timestamp string TS with the Hijri tag in the day-name slot."
  (cond ((string-match (concat "\\`[<[]" org-islam--date-core
                                " +\\([^]0-9>\r\n -]+\\)") ts)
         ;; Replace the day name with the tag.
         (replace-match org-islam-timestamp-tag t t ts 4))
        ((string-match (concat "\\`[<[]" org-islam--date-core) ts)
         ;; No day name yet: insert the tag right after the date.
         (concat (substring ts 0 (match-end 0))
                 " " org-islam-timestamp-tag
                 (substring ts (match-end 0))))
        (t ts)))

(defun org-islam--unmark-string (ts)
  "Return timestamp string TS with the Gregorian day name restored."
  (let ((t0 (ignore-errors (org-parse-time-string ts))))
    (if (and t0
             (string-match (concat "\\`[<[]" org-islam--date-core
                                   " +\\("
                                   (regexp-quote org-islam-timestamp-tag)
                                   "\\)") ts))
        (replace-match
         (calendar-day-name (list (nth 4 t0) (nth 3 t0) (nth 5 t0)) t)
         t t ts 4)
      ts)))

(defun org-islam--ts-parts (ts)
  "Decompose Hijri timestamp string TS.
Return (GDATE HOUR MINUTE EXTRA ACTIVE-P) where GDATE is
\(MONTH DAY YEAR), HOUR/MINUTE are numbers or nil, EXTRA is the text
after the tag (time, repeater, ...), and ACTIVE-P is non-nil for
angle brackets."
  (let ((t0 (org-parse-time-string ts t)))
    (list (list (nth 4 t0) (nth 3 t0) (nth 5 t0))
          (nth 2 t0) (nth 1 t0)
          (and (string-match (concat (regexp-quote org-islam-timestamp-tag)
                                     "\\([^]>\n]*\\)") ts)
               (match-string 1 ts))
          (eq (aref ts 0) ?<))))

(defun org-islam--make-ts-string (gdate &optional active extra)
  "Build a Hijri timestamp string for Gregorian GDATE (MONTH DAY YEAR).
EXTRA is appended after the tag (e.g. \" 20:15\" or \" 20:15 +1w\")."
  (format "%s%04d-%02d-%02d %s%s%s"
          (if active "<" "[")
          (calendar-extract-year gdate)
          (calendar-extract-month gdate)
          (calendar-extract-day gdate)
          org-islam-timestamp-tag
          (or extra "")
          (if active ">" "]")))

(defun org-islam-read-hijri-date (&optional with-time)
  "Read a Hijri date from the minibuffer.
Accepts \"Y-M-D\", \"M-D\" (current Hijri year), \"D\" (current Hijri
month), or empty for today's Hijri date (maghrib aware).  Digits may
be Arabic-Indic.  Separators may be `-', `/', `.' or spaces.
When WITH-TIME is non-nil, also read a time of day \"HH:MM\".
Return (MONTH DAY YEAR HOUR MINUTE); HOUR and MINUTE are nil unless
WITH-TIME was given."
  (let* ((today (org-islam-hijri-today))
         (default (org-islam-format-hijri today))
         (ans (read-from-minibuffer
               (format "Hijri date [Y-M-D, RET = %s]: " default)))
         (parts (split-string
                 (org-islam-to-western-digits (string-trim ans))
                 "[-/. \t]+" t))
         month day year hour minute)
    (pcase parts
      (`() (setq month (nth 0 today) day (nth 1 today) year (nth 2 today)))
      (`(,d) (setq month (nth 0 today) day (string-to-number d)
                   year (nth 2 today)))
      (`(,m ,d) (setq month (string-to-number m) day (string-to-number d)
                      year (nth 2 today)))
      (`(,y ,m ,d) (setq year (string-to-number y)
                         month (string-to-number m)
                         day (string-to-number d)))
      (_ (user-error "Cannot parse Hijri date: %s" ans)))
    (unless (and (natnump month) (<= 1 month 12))
      (user-error "Hijri month must be 1-12"))
    (unless (org-islam-hijri-year-valid-p year)
      (user-error "Hijri year must be positive"))
    (let ((last (org-islam-last-day-of-hijri-month month year)))
      (unless (and (natnump day) (<= 1 day last))
        (user-error "Hijri day must be 1-%d in %s %d"
                    last (org-islam-hijri-month-name month 'translit) year)))
    (when with-time
      (let ((t-ans (read-from-minibuffer
                    "Time of day [HH:MM, RET = none]: ")))
        (when (string-match
               "\\`[ \t]*\\([0-9٠-٩]\\{1,2\\}\\)[:.]\\([0-9٠-٩]\\{2\\}\\)[ \t]*\\'"
               t-ans)
          (setq hour (string-to-number
                      (org-islam-to-western-digits (match-string 1 t-ans)))
                minute (string-to-number
                        (org-islam-to-western-digits
                         (match-string 2 t-ans))))
          (unless (and (natnump hour) (<= hour 23)
                       (natnump minute) (<= minute 59))
            (user-error "Time must be HH:MM")))))
    (list month day year hour minute)))

(defun org-islam-timestamp (arg)
  "Insert a Hijri timestamp at point.
The date is read as a Hijri date (see `org-islam-read-hijri-date').
An active timestamp is inserted by default.  With one
\\[universal-argument] also prompt for a time of day; with two, insert
an inactive timestamp instead."
  (interactive "P")
  (let* ((num (prefix-numeric-value arg))
         (with-time (memq num '(4 64)))
         (inactive (memq num '(16 64)))
         (h (org-islam-read-hijri-date with-time))
         (g (org-islam-hijri-to-gregorian
             (list (nth 0 h) (nth 1 h) (nth 2 h))))
         (extra (and (nth 3 h)
                     (format " %02d:%02d" (nth 3 h) (nth 4 h)))))
    (insert (org-islam--make-ts-string g (not inactive) extra))))

(defun org-islam-timestamp-inactive (arg)
  "Insert an inactive Hijri timestamp at point.
With one \\[universal-argument], also prompt for a time of day."
  (interactive "P")
  (org-islam-timestamp (if (>= (prefix-numeric-value arg) 4) 64 16)))

(defun org-islam--remark-planning (keyword)
  "Put the Hijri tag on the KEYWORD (SCHEDULED/DEADLINE) ts of this entry."
  (org-with-wide-buffer
   (org-back-to-heading t)
   (let ((end (save-excursion (org-end-of-subtree) (point)))
         (rx (concat keyword ": *\\(<" org-islam--date-core
                     "\\([^>\n]*\\)>\\)")))
     (when (re-search-forward rx end t)
       (org-islam--replace-ts (match-beginning 1) (match-end 1)
                              (org-islam--mark-string
                               (match-string 1)))))))

(defun org-islam-schedule (&optional remove)
  "Schedule the entry at a Hijri date.
The Hijri date is converted to Gregorian and passed to
`org-schedule', then the inserted timestamp is marked as Hijri.
With prefix REMOVE, remove the scheduling like `\\[org-schedule]'."
  (interactive "P")
  (if remove
      (org-schedule t)
    (let* ((h (org-islam-read-hijri-date t))
           (g (org-islam-hijri-to-gregorian
               (list (nth 0 h) (nth 1 h) (nth 2 h))))
           (iso (format "%04d-%02d-%02d"
                        (calendar-extract-year g)
                        (calendar-extract-month g)
                        (calendar-extract-day g)))
           (time (and (nth 3 h)
                      (format " %02d:%02d" (nth 3 h) (nth 4 h)))))
      (org-schedule nil (concat iso time))
      (org-islam--remark-planning "SCHEDULED"))))

(defun org-islam-deadline (&optional remove)
  "Set a deadline for the entry at a Hijri date.
The Hijri date is converted to Gregorian and passed to
`org-deadline', then the inserted timestamp is marked as Hijri.
With prefix REMOVE, remove the deadline like `\\[org-deadline]'."
  (interactive "P")
  (if remove
      (org-deadline t)
    (let* ((h (org-islam-read-hijri-date t))
           (g (org-islam-hijri-to-gregorian
               (list (nth 0 h) (nth 1 h) (nth 2 h))))
           (iso (format "%04d-%02d-%02d"
                        (calendar-extract-year g)
                        (calendar-extract-month g)
                        (calendar-extract-day g)))
           (time (and (nth 3 h)
                      (format " %02d:%02d" (nth 3 h) (nth 4 h)))))
      (org-deadline nil (concat iso time))
      (org-islam--remark-planning "DEADLINE"))))

(defun org-islam-toggle-timestamp ()
  "Toggle the Hijri marker on the Org timestamp at point."
  (interactive)
  (let ((bounds (org-islam--ts-bounds)))
    (if bounds
        (org-islam--replace-ts
         (car bounds) (cdr bounds)
         (org-islam--unmark-string (buffer-substring (car bounds)
                                                     (cdr bounds))))
      ;; Not marked: find any timestamp on this line containing point.
      (let ((here (point))
            (line-end (line-end-position))
            found)
        (save-excursion
          (goto-char (line-beginning-position))
          (while (and (not found)
                      (re-search-forward
                       (concat "[[<]" org-islam--date-core
                               "[^]>\n]*[]>]")
                       line-end t))
            (when (<= (match-beginning 0) here (match-end 0))
              (setq found (cons (match-beginning 0) (match-end 0))))))
        (if found
            (org-islam--replace-ts
             (car found) (cdr found)
             (org-islam--mark-string (buffer-substring (car found)
                                                       (cdr found))))
          (user-error "Not at a timestamp"))))))


;;; Part 6: Hijri-aware timestamp editing

(defcustom org-islam-hijri-timestamp-editing t
  "Whether Hijri-aware timestamp editing is installed.
This covers `org-timestamp-change' (the S-<arrow> keys) keeping the
Hijri marker and doing month/year arithmetic in Hijri space, and
`org-timestamp' (C-c .) keeping the marker when editing an existing
Hijri timestamp."
  :group 'org-islam
  :type 'boolean)

(defun org-islam--hijri-change (n what)
  "Change the Hijri timestamp at point by N units of WHAT.
WHAT is `month' or `year'.  The change happens in Hijri space with
day clamping; the stored Gregorian date and the tag are rewritten."
  (let ((bounds (org-islam--ts-bounds)))
    (unless bounds (user-error "Not at a Hijri timestamp"))
    (pcase-let ((`(,gdate ,_hour _minute ,extra _active)
                 (org-islam--ts-parts
                  (buffer-substring (car bounds) (cdr bounds)))))
      (let* ((h (org-islam-gregorian-to-hijri gdate))
             (hmonth (nth 0 h)) (hday (nth 1 h)) (hyear (nth 2 h)))
        (if (eq what 'year)
            (setq hyear (+ hyear n))
          (let ((total (+ (1- hmonth) n)))
            (setq hmonth (1+ (mod total 12))
                  hyear (+ hyear (floor total 12)))))
        (unless (org-islam-hijri-year-valid-p hyear)
          (user-error "Resulting Hijri year must be positive"))
        (let* ((last (org-islam-last-day-of-hijri-month hmonth hyear))
               (day (min hday last))
               (g (org-islam-hijri-to-gregorian (list hmonth day hyear))))
          (org-islam--replace-ts
           (car bounds) (cdr bounds)
           (org-islam--make-ts-string
            g (eq (char-after (car bounds)) ?<) extra))
          (goto-char (+ (car bounds) 11)))))))

(defun org-islam--remark-after-edit ()
  "Re-mark the timestamp nearest point after Org rewrote it.
Only looks at the current line, and only at timestamps that are not
already marked."
  (save-excursion
    (let ((here (point))
          (line-end (line-end-position))
          (best nil)
          (best-dist most-positive-fixnum))
      (goto-char (line-beginning-position))
      (while (re-search-forward
              (concat "[[<]" org-islam--date-core "[^]>\n]*[]>]")
              line-end t)
        (let ((b (match-beginning 0)) (e (match-end 0))
              (ts (match-string 0)))
          (unless (string-match-p (regexp-quote org-islam-timestamp-tag) ts)
            (let ((dist (min (abs (- here b)) (abs (- here e)))))
              (when (< dist best-dist)
                (setq best (cons b e) best-dist dist))))))
      (when best
        (org-islam--replace-ts
         (car best) (cdr best)
         (org-islam--mark-string (buffer-substring (car best)
                                                   (cdr best))))))))

(defun org-islam--timestamp-change-advice (fn n &optional what updown
                                            suppress-tmp-delay)
  "Around advice for `org-timestamp-change' (FN).
Preserves the Hijri marker on every edit; for month/year changes on
a marked timestamp, does the arithmetic in Hijri space instead."
  (if (not org-islam-hijri-timestamp-editing)
      (funcall fn n what updown suppress-tmp-delay)
    (let ((marked (org-islam-timestamp-p)))
      (if (and marked (memq what '(month year)))
          (org-islam--hijri-change n what)
        (prog1 (funcall fn n what updown suppress-tmp-delay)
          (when (and marked (not (org-islam-timestamp-p)))
            (org-islam--remark-after-edit)))))))

(defun org-islam--timestamp-advice (fn arg &optional inactive)
  "Around advice for `org-timestamp' (C-c .), see FN.
Keeps the Hijri marker when editing an existing marked timestamp."
  (if (not org-islam-hijri-timestamp-editing)
      (funcall fn arg inactive)
    (let ((marked (org-islam-timestamp-p)))
      (prog1 (funcall fn arg inactive)
        (when (and marked (not (org-islam-timestamp-p)))
          (org-islam--remark-after-edit))))))

(advice-add 'org-timestamp-change :around
            #'org-islam--timestamp-change-advice)
(advice-add 'org-timestamp :around #'org-islam--timestamp-advice)


;;; Part 7: Overlays (Arabic timestamps) and the mode

(defcustom org-islam-maghrib-aware-display t
  "Whether overlay rendering honours the maghrib day boundary.
When non-nil, a marked timestamp that carries a time of day at or
after maghrib displays the *next* Hijri date, matching the Islamic
day boundary.  All-day timestamps always use the daytime convention."
  :group 'org-islam
  :type 'boolean)

(defcustom org-islam-overlay-show-gregorian nil
  "Whether Hijri overlays also show the stored Gregorian date.
When non-nil, the overlay reads like
\"[الثلاثاء ١٣ جمادى الآخرة ١٤٤٨هـ -- 2026-11-24]\"."
  :group 'org-islam
  :type 'boolean)

(defvar-local org-islam-overlays-enabled t
  "Buffer-local switch for Hijri timestamp overlays.")

(defun org-islam--display-string (ts)
  "Compute the Hijri display string for marked timestamp string TS."
  (pcase-let ((`(,gdate ,hour ,minute ,_extra ,active)
               (org-islam--ts-parts ts)))
    (let ((hijri (org-islam-gregorian-to-hijri gdate))
          (day-gdate gdate))
      (when (and org-islam-maghrib-aware-display hour)
        (when (>= (+ hour (/ (or minute 0) 60.0))
                  (org-islam-maghrib-hour gdate))
          (setq hijri (org-islam-hijri-of-evening gdate))
          ;; The Islamic day of the evening runs to tomorrow's
          ;; daytime, so name the weekday of that day.
          (setq day-gdate (calendar-gregorian-from-absolute
                           (1+ (calendar-absolute-from-gregorian gdate))))))
      (concat (if active "<" "[")
              (org-islam-format-hijri hijri day-gdate nil (and hour t) hour minute)
              (when org-islam-overlay-show-gregorian
                (format " -- %04d-%02d-%02d"
                        (calendar-extract-year gdate)
                        (calendar-extract-month gdate)
                        (calendar-extract-day gdate)))
              (if active ">" "]")))))

(defun org-islam-fontify-hijri-timestamps (limit)
  "Font-lock matcher: render Hijri-marked timestamps with overlays."
  (let (matched)
    (while (re-search-forward (org-islam-ts-regexp) limit t)
      (when org-islam-overlays-enabled
        (let ((beg (match-beginning 0)) (end (match-end 0)))
          (put-text-property beg end 'display
                             (org-islam--display-string (match-string 0)))
          (put-text-property beg end 'org-islam-display t)
          (add-text-properties
           beg end (list 'mouse-face 'highlight
                         'help-echo "Hijri timestamp"))))
      (setq matched t))
    matched))

(defvar org-islam-mode nil
  "Non-nil when org-islam's buffer-local features are active.
Set by `org-islam-mode'; see also `global-org-islam-mode'.")

(defun org-islam--set-keywords ()
  "Add the Hijri matcher to `org-font-lock-extra-keywords'."
  (when (and org-islam-mode (derived-mode-p 'org-mode))
    (setq org-font-lock-extra-keywords
          (append org-font-lock-extra-keywords
                  '((org-islam-fontify-hijri-timestamps))))))

(defun org-islam--remove-overlays ()
  "Remove all Hijri display overlays from the current buffer."
  (let ((p (point-min)) (bmp (buffer-modified-p)))
    (while (and p (< p (point-max)))
      (if (get-text-property p 'org-islam-display)
          (let ((end (or (next-single-property-change p 'org-islam-display)
                         (point-max))))
            (remove-text-properties p end '(display t org-islam-display t))
            (setq p end))
        (setq p (next-single-property-change p 'org-islam-display))))
    (set-buffer-modified-p bmp)))

(defun org-islam-toggle-overlays ()
  "Toggle Hijri timestamp overlays in the current buffer."
  (interactive)
  (setq org-islam-overlays-enabled
        (not org-islam-overlays-enabled))
  (if org-islam-overlays-enabled
      (org-islam-refresh-overlays)
    (org-islam--remove-overlays)))

(defun org-islam-restart-font-lock ()
  "Re-run Org's font-lock setup so the Hijri keywords are installed.
`org-set-font-lock-defaults' builds `org-font-lock-keywords' from
`org-font-lock-extra-keywords' while running
`org-font-lock-set-keywords-hook', so it has to run again after the
mode added its function to that hook (Org itself only runs it during
`org-mode' init).  Afterwards fontification is refreshed."
  (when (derived-mode-p 'org-mode)
    (when (fboundp 'org-set-font-lock-defaults)
      (org-set-font-lock-defaults))
    ;; Force font-lock to recompile from the new defaults.
    (kill-local-variable 'font-lock-keywords)
    (if font-lock-mode
        (progn (font-lock-mode -1) (font-lock-mode 1))
      (when (fboundp 'font-lock-ensure)
        (font-lock-ensure)))))

(defvar org-islam-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c i .") #'org-islam-timestamp)
    (define-key map (kbd "C-c i !") #'org-islam-timestamp-inactive)
    (define-key map (kbd "C-c i s") #'org-islam-schedule)
    (define-key map (kbd "C-c i d") #'org-islam-deadline)
    (define-key map (kbd "C-c i c") #'org-islam-toggle-timestamp)
    (define-key map (kbd "C-c i t") #'org-islam-toggle-overlays)
    (define-key map (kbd "C-c i h") #'org-islam-echo-hijri-today)
    map)
  "Keymap for `org-islam-mode'.  Prefix `C-c i'.")

;;;###autoload
(define-minor-mode org-islam-mode
  "Minor mode for Islamic (Hijri) calendar support in Org buffers.
Adds Arabic-script overlays for Hijri timestamps, Hijri input
commands on the `C-c i' prefix, and Hijri-aware timestamp editing.
Use `global-org-islam-mode' to turn it on in every Org buffer."
  :group 'org-islam
  :keymap org-islam-mode-map
  (if org-islam-mode
      (progn
        (add-hook 'org-font-lock-set-keywords-hook
                  #'org-islam--set-keywords nil t)
        (org-islam-restart-font-lock))
    (remove-hook 'org-font-lock-set-keywords-hook
                 #'org-islam--set-keywords t)
    (org-islam--remove-overlays)
    (org-islam-restart-font-lock)))

(defun org-islam--turn-on-in-org ()
  "Enable `org-islam-mode' in Org buffers."
  (when (derived-mode-p 'org-mode)
    (org-islam-mode 1)))

;;;###autoload
(define-globalized-minor-mode global-org-islam-mode
  org-islam-mode org-islam--turn-on-in-org
  :group 'org-islam
  (if global-org-islam-mode
      (org-islam--schedule-rollover)
    (when org-islam--rollover-timer
      (cancel-timer org-islam--rollover-timer)
      (setq org-islam--rollover-timer nil))))


;;; Part 8: Agenda and calendar integration

(defcustom org-islam-agenda-show-hijri t
  "Whether agenda day headings show the Hijri date next to the Gregorian."
  :group 'org-islam
  :type 'boolean)

(defun org-islam--agenda-date-advice (fn date)
  "Around advice for `org-agenda-format-date-aligned' (FN).
Appends the Hijri date of DATE to the heading."
  (let ((base (funcall fn date)))
    (if (and org-islam-agenda-show-hijri (listp date) (stringp base))
        (concat base "  ·  " (org-islam-hijri-date-string date))
      base)))

(with-eval-after-load 'org-agenda
  (advice-add 'org-agenda-format-date-aligned :around
              #'org-islam--agenda-date-advice))

(defun org-islam-calendar-show-hijri ()
  "Echo the Hijri date of the date under point in the calendar."
  (interactive)
  (let ((date (calendar-cursor-to-date t)))
    (when date
      (message "Hijri date: %s" (org-islam-hijri-date-string date)))))

(defun org-islam-calendar-goto-hijri-today ()
  "Move the calendar cursor to today's Hijri date (maghrib aware)."
  (interactive)
  (let ((g (org-islam-hijri-to-gregorian (org-islam-hijri-today))))
    (unless (derived-mode-p 'calendar-mode)
      (calendar))
    (calendar-goto-date g)))

(defun org-islam-calendar-goto-hijri-date (date)
  "Move the calendar cursor to Hijri DATE (MONTH DAY YEAR)."
  (interactive (list (car (calendar-islamic-read-date))))
  (unless (derived-mode-p 'calendar-mode)
    (calendar))
  (calendar-goto-date (org-islam-hijri-to-gregorian date)))

(provide 'org-islam)

;;; org-islam.el ends here
