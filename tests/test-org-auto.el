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
