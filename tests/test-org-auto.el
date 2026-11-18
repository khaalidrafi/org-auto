;;; test-org-auto.el --- ERT suite for org-auto.el -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'org-auto)

(defconst org-auto-test--dir
  (file-name-directory (or load-file-name buffer-file-name)))

(defvar org-auto-test--hits nil)
(defun org-auto-test-hit (tag) (push tag org-auto-test--hits))
(defun org-auto-test-cmd () (interactive) (push "cmd" org-auto-test--hits))

(defmacro org-auto-test--with-fixture (&rest body)
  "Run BODY with `org-agenda-files' bound to the fixture file."
  `(let ((org-agenda-files (list (expand-file-name "fixture.org"
                                                   org-auto-test--dir)))
         (org-auto-default-time "09:00")
         (org-auto-test--hits nil))
     ,@body))

(ert-deftest org-auto-test/collect-todo-only ()
  (org-auto-test--with-fixture
   (let ((all (org-auto--collect)))
     ;; sched + no-time + both x2 + past = 5; DONE, plain, no-EXEC out
     (should (= 5 (length all)))
     (should (cl-some (lambda (it)
                        (string= "future scheduled" (nth 2 it)))
                      all)))))

(ert-deftest org-auto-test/default-time-applied ()
  (org-auto-test--with-fixture
   (let* ((all (org-auto--collect))
          (hours (mapcar (lambda (it) (nth 2 (decode-time (car it)))) all)))
     (should (member 9 hours))       ; deadline without time-of-day
     (should (member 10 hours))      ; scheduled 10:00
     (should (= 2 (cl-count 8 hours :test '=))))))

(ert-deftest org-auto-test/past-timestamp-collected-but-not-armed ()
  (org-auto-test--with-fixture
   (let* ((all (org-auto--collect))
          (years (mapcar (lambda (it) (nth 5 (decode-time (car it)))) all)))
     (should (member 2020 years))    ; collected...
     (org-auto-refresh)
     (should (= 4 (length org-auto--timers)))  ; ...but not armed
     (org-auto--cancel-all))))

(ert-deftest org-auto-test/fire-elisp-form ()
  (org-auto-test--with-fixture
   (org-auto--fire "f.org" "h" "(org-auto-test-hit \"form\")")
   (should (member "form" org-auto-test--hits))))

(ert-deftest org-auto-test/fire-command-with-mx-prefix ()
  (org-auto-test--with-fixture
   (org-auto--fire "f.org" "h" "M-x org-auto-test-cmd")
   (should (member "cmd" org-auto-test--hits))))

(ert-deftest org-auto-test/fire-bogus-degrades-to-message ()
  (org-auto-test--with-fixture
   (org-auto--fire "f.org" "h" "(org-auto-test--no-such-fn)")
   (org-auto--fire "f.org" "h" "org-auto-test--no-such-cmd")
   (should (null org-auto-test--hits))))

(ert-deftest org-auto-test/current-entry-bound-while-firing ()
  (org-auto-test--with-fixture
   (let ((seen nil))
     (cl-letf (((symbol-function 'org-auto-test-hit)
                (lambda (tag)
                  (setq seen (list tag org-auto-current-entry)))))
       (org-auto--fire "f.org" "my heading" "(org-auto-test-hit \"x\")"))
     (should (equal seen (list "x" '(:file "f.org" :heading "my heading")))))))

(defmacro org-auto-test--with-fixture-buffer (&rest body)
  "Run BODY with a buffer visiting the fixture file as current."
  `(let ((buf (find-file-noselect
               (expand-file-name "fixture.org" org-auto-test--dir))))
     (unwind-protect
         (with-current-buffer buf ,@body)
       (ignore-errors (kill-buffer buf)))))

(defun org-auto-test--clear-idle-timer ()
  (when org-auto--idle-timer
    (cancel-timer org-auto--idle-timer)
    (setq org-auto--idle-timer nil)))

(ert-deftest org-auto-test/entry-live-p-happy-path ()
  (org-auto-test--with-fixture
   (should (org-auto--entry-live-p
            (expand-file-name "fixture.org" org-auto-test--dir)
            "future scheduled"
            "(org-auto-test-hit \"sched\")"))))

(ert-deftest org-auto-test/entry-live-p-rejects-done ()
  (org-auto-test--with-fixture
   (should-not (org-auto--entry-live-p
                (expand-file-name "fixture.org" org-auto-test--dir)
                "done entry"
                "(org-auto-test-hit \"done\")"))))

(ert-deftest org-auto-test/entry-live-p-rejects-changed-cmd ()
  (org-auto-test--with-fixture
   (should-not (org-auto--entry-live-p
                (expand-file-name "fixture.org" org-auto-test--dir)
                "future scheduled"
                "(org-auto-test-hit \"something-else\")"))))

(ert-deftest org-auto-test/entry-live-p-rejects-missing-file ()
  (should-not (org-auto--entry-live-p "/nonexistent/org-auto-x.org" "h" "cmd")))

(ert-deftest org-auto-test/fire-maybe-fires-live-entry ()
  (org-auto-test--with-fixture
   (org-auto--fire-maybe (expand-file-name "fixture.org" org-auto-test--dir)
                          "future scheduled"
                          "(org-auto-test-hit \"sched\")")
   (should (member "sched" org-auto-test--hits))))

(ert-deftest org-auto-test/fire-maybe-skips-stale-entry ()
  (org-auto-test--with-fixture
   ;; DONE since arming: the timer must not fire.
   (org-auto--fire-maybe (expand-file-name "fixture.org" org-auto-test--dir)
                          "done entry"
                          "(org-auto-test-hit \"done\")")
   ;; File vanished since arming: no error, no fire.
   (org-auto--fire-maybe "/nonexistent/org-auto-x.org" "h"
                          "(org-auto-test-hit \"gone\")")
   (should (null org-auto-test--hits))))

(ert-deftest org-auto-test/after-change-queues-idle-refresh-for-agenda-file ()
  (org-auto-test--with-fixture
   (let ((org-auto-mode t))
     (org-auto-test--with-fixture-buffer
      (org-auto--after-change 1 1 0)
      (should org-auto--idle-timer))
     (org-auto-test--clear-idle-timer))))

(ert-deftest org-auto-test/after-change-ignores-non-agenda-file ()
  (org-auto-test--with-fixture
   (let ((org-auto-mode t)
         (tmp (make-temp-file "org-auto-test" nil ".org")))
     (unwind-protect
         (with-temp-buffer
           (setq buffer-file-name tmp)
           (org-auto--after-change 1 1 0)
           (should-not org-auto--idle-timer))
       (delete-file tmp)))
   (org-auto-test--clear-idle-timer)))

(ert-deftest org-auto-test/after-change-respects-nil-delay ()
  (org-auto-test--with-fixture
   (let ((org-auto-mode t)
         (org-auto-idle-delay nil))
     (org-auto-test--with-fixture-buffer
      (org-auto--after-change 1 1 0)
      (should-not org-auto--idle-timer)))
   (org-auto-test--clear-idle-timer)))

(ert-deftest org-auto-test/refresh-cancels-pending-idle-timer ()
  (org-auto-test--with-fixture
   (setq org-auto--idle-timer (run-with-idle-timer 1000 nil #'ignore))
   (org-auto-refresh t)
   (should-not org-auto--idle-timer)
   (org-auto--cancel-all)))

(ert-deftest org-auto-test/mode-toggle-wires-and-cleans-up ()
  (org-auto-test--with-fixture
   (org-auto-test--with-fixture-buffer
    (unwind-protect
        (progn
          (org-auto-mode 1)
          (should (memq #'org-auto--after-change after-change-functions))
          (should org-auto--timers)
          (org-auto-mode 0)
          (should-not (memq #'org-auto--after-change after-change-functions))
          (should-not org-auto--timers)
          (should-not org-auto--idle-timer))
      (when org-auto-mode (org-auto-mode 0))
      (org-auto--cancel-all)
      (org-auto-test--clear-idle-timer)))))
