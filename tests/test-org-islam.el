;;; test-org-islam.el --- ERT tests for org-islam.el -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Khalid Rafi
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Offline tests: no network, no real prayer-time source (the maghrib
;; source is pinned to `fixed' where a time matters), no device.

;;; Code:

(require 'ert)
(require 'org)
(require 'org-islam)

(defmacro org-islam-test--with-fixed-maghrib (time &rest body)
  "Run BODY with the maghrib source fixed at TIME (\"HH:MM\")."
  `(let ((org-islam-day-boundary-source 'fixed)
         (org-islam-fixed-maghrib-time ,time)
         (org-islam--maghrib-cache (make-hash-table :test 'equal)))
     ,@body))

(defun org-islam-test--time (iso)
  "Parse \"YYYY-MM-DD HH:MM\" into a time value."
  (apply #'encode-time
         (let ((d (parse-time-string iso)))
           (list 0 (nth 1 d) (nth 2 d)
                 (nth 3 d) (nth 4 d) (nth 5 d) -1 nil))))

;;; ------------------------------------------------------------- digits

(ert-deftest org-islam-digit-roundtrip ()
  "Western -> Arabic-Indic -> Western digits is the identity."
  (let ((s "1448-06-16 20:15"))
    (should (equal (org-islam-to-western-digits
                    (org-islam-to-arabic-digits s))
                   s))))

(ert-deftest org-islam-arabic-digits-shape ()
  "Arabic-Indic digits are the U+0660 block, not Persian forms."
  (should (equal (org-islam-to-arabic-digits "0123456789")
                 "٠١٢٣٤٥٦٧٨٩")))

;;; -------------------------------------------------------- conversions

(ert-deftest org-islam-gregorian-hijri-roundtrip ()
  "Every day in a Hijri year round-trips through the converters."
  (dotimes (m 12)
    (let ((last (org-islam-last-day-of-hijri-month (1+ m) 1447)))
      (dotimes (d last)
        (let* ((h (list (1+ m) (1+ d) 1447))
               (g (org-islam-hijri-to-gregorian h))
               (h2 (org-islam-gregorian-to-hijri g)))
          (should (equal h h2)))))))

(ert-deftest org-islam-known-pair-1-muharram-1448 ()
  "1 Muharram 1448 falls in mid-June 2026 (arithmetic calendar)."
  (let ((g (org-islam-hijri-to-gregorian '(1 1 1448))))
    (should (equal (calendar-extract-month g) 6))
    (should (equal (calendar-extract-year g) 2026))))

(ert-deftest org-islam-month-lengths ()
  "An arithmetic Hijri year has six 30-day and six 29-day months."
  (let ((lens (mapcar (lambda (m) (org-islam-last-day-of-hijri-month m 1448))
                      (number-sequence 1 12))))
    (should (equal lens '(30 29 30 29 30 29 30 29 30 29 30 29)))))

(ert-deftest org-islam-hijri-month-name-arabic ()
  "Month 9 is Ramadan in both scripts."
  (should (equal (org-islam-hijri-month-name 9 'arabic) "رمضان"))
  (should (equal (org-islam-hijri-month-name 9 'translit) "Ramadan")))

;;; ------------------------------------------------------------ maghrib

(ert-deftest org-islam-after-maghrib-p-fixed ()
  "With a fixed 18:00 maghrib, 17:59 is before and 18:00 is after."
  (org-islam-test--with-fixed-maghrib "18:00"
    (let ((before (org-islam-test--time "2026-11-24 17:59"))
          (after  (org-islam-test--time "2026-11-24 18:00")))
      (should-not (org-islam-after-maghrib-p before))
      (should (org-islam-after-maghrib-p after)))))

(ert-deftest org-islam-hijri-today-rolls-at-maghrib ()
  "17:00 and 19:00 on the same Gregorian day differ in Hijri day
when maghrib is fixed at 18:00 (the evening belongs to tomorrow)."
  (org-islam-test--with-fixed-maghrib "18:00"
    (let* ((t1 (org-islam-test--time "2026-06-17 17:00"))
           (t2 (org-islam-test--time "2026-06-17 19:00"))
           (h1 (org-islam-hijri-today t1))
           (h2 (org-islam-hijri-today t2)))
      (should (equal h1 '(1 1 1448)))       ; daytime of 1 Muharram
      (should (equal h2 '(1 2 1448)))))     ; evening already rolled
  )

(ert-deftest org-islam-hijri-of-evening-is-next-day ()
  "The evening of GDATE shares the Islamic day with GDATE+1 daytime."
  (let* ((g '(6 16 2026))
         (h1 (org-islam-hijri-of-evening g))
         (h2 (org-islam-gregorian-to-hijri '(6 17 2026))))
    (should (equal h1 h2))))

;;; ------------------------------------------------- timestamp strings

(ert-deftest org-islam-mark-string-inserts-tag ()
  "A bare timestamp gains the Hijri tag after the date."
  (should (equal (org-islam--mark-string "[2026-06-16 Tue]")
                 "[2026-06-16 Hijri]")))

(ert-deftest org-islam-mark-string-replaces-day-name ()
  "A timestamp with a day name has it replaced by the tag."
  (should (equal (org-islam--mark-string "[2026-06-16 Tue 20:15]")
                 "[2026-06-16 Hijri 20:15]")))

(ert-deftest org-islam-unmark-string-restores-day-name ()
  "Unmarking restores the Gregorian day name."
  (let ((marked (org-islam--mark-string "[2026-06-16 Tue 20:15]")))
    (should (equal (org-islam--unmark-string marked)
                   "[2026-06-16 Tue 20:15]"))))

(ert-deftest org-islam-ts-parts-parses-marked ()
  "Parts of a marked, timed timestamp decompose correctly."
  (pcase-let ((`(,gdate ,hour ,minute ,extra _active)
               (org-islam--ts-parts "<2026-06-16 Hijri 20:15>")))
    (should (equal gdate '(6 16 2026)))
    (should (equal hour 20))
    (should (equal minute 15))
    (should (string-prefix-p " 20:15" extra))))

;;; ------------------------------------------------------ display layer

(ert-deftest org-islam-display-string-arabic ()
  "A marked timestamp displays as an Arabic Hijri date."
  (org-islam-test--with-fixed-maghrib "18:00"
    (let ((s (org-islam--display-string "<2026-06-17 Hijri 10:00>")))
      (should (string-prefix-p "<" s))
      (should (string-suffix-p ">" s))
      ;; daytime: 1 Muharram 1448, in Arabic-Indic digits
      (should (string-match-p "١" s))
      (should (string-match-p "مُحَرَّم\\|محرم" s)))))

(ert-deftest org-islam-display-string-maghrib-rollover ()
  "A time after maghrib displays the NEXT Hijri day."
  (org-islam-test--with-fixed-maghrib "18:00"
    (let ((day (org-islam--display-string "<2026-06-17 Hijri 10:00>"))
          (eve (org-islam--display-string "<2026-06-17 Hijri 20:00>")))
      (should-not (equal day eve))
      ;; evening of 1 Muharram is already 2 Muharram
      (should (string-match-p "٢ *مُحَرَّم\\|٢ *محرم" eve)))))

(ert-deftest org-islam-display-string-all-day-has-no-time ()
  "An all-day marked timestamp displays without a time part."
  (let ((s (org-islam--display-string "[2026-06-17 Hijri]")))
    (should-not (string-match-p ":" s))
    (should (string-match-p "محرم" s))))

(ert-deftest org-islam-display-string-keeps-time ()
  "A timed timestamp displays the same time of day, not 00:00."
  (org-islam-test--with-fixed-maghrib "18:00"
    (let ((s (org-islam--display-string "[2026-06-17 Hijri 10:30]")))
      (should (string-match-p "١٠:٣٠" s))
      (should-not (string-match-p "٠٠:٠٠" s)))))

(ert-deftest org-islam-gregorian-timestamps-untouched ()
  "Unmarked timestamps never gain Hijri display."
  (with-temp-buffer
    (insert "* heading\n[2026-06-17 Wed] and <2026-06-17 Wed 10:00>")
    (goto-char (point-min))
    (org-islam-fontify-hijri-timestamps (point-max))
    (should-not (next-single-property-change (point-min) 'display))))

;;; ------------------------------------------------------- month change

(ert-deftest org-islam-hijri-change-month-clamps ()
  "Ramadan 29 + 1 month = Shawwal 29 with the marker intact."
  (with-temp-buffer
    (insert "* heading\n<2026-03-18 Hijri>") ; 29 Ramadan 1447 daytime
    (goto-char 13)
    (org-islam--hijri-change 1 'month)
    (should (string-match-p "Hijri" (buffer-string)))
    (goto-char 13)
    (let* ((ts (buffer-substring (car (org-islam--ts-bounds))
                                 (cdr (org-islam--ts-bounds))))
           (h (org-islam-gregorian-to-hijri
               (car (org-islam--ts-parts ts)))))
      (should (equal (nth 0 h) 10))          ; Shawwal
      (should (equal (nth 1 h) 29)))))       ; same day number carried

(ert-deftest org-islam-hijri-change-year-keeps-day ()
  "Year change keeps month/day when the day is still valid."
  (with-temp-buffer
    (insert "* heading\n<2026-06-17 Hijri>") ; 1 Muharram 1448
    (goto-char 13)
    (org-islam--hijri-change -1 'year)
    (goto-char 13)
    (let* ((ts (buffer-substring (car (org-islam--ts-bounds))
                                 (cdr (org-islam--ts-bounds))))
           (h (org-islam-gregorian-to-hijri
               (car (org-islam--ts-parts ts)))))
      (should (equal h '(1 1 1447))))))

(provide 'test-org-islam)
;;; test-org-islam.el ends here
