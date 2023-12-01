;;; denote-sort.el ---  Sort Denote files based on a file name component -*- lexical-binding: t -*-

;; Copyright (C) 2023  Free Software Foundation, Inc.

;; Author: Protesilaos Stavrou <info@protesilaos.com>
;; Maintainer: Denote Development <~protesilaos/denote@lists.sr.ht>
;; URL: https://git.sr.ht/~protesilaos/denote
;; Mailing-List: https://lists.sr.ht/~protesilaos/denote

;; This file is NOT part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; Sort Denote files based on their file name components, namely, the
;; signature, title, or keywords.
;;
;; NOTE 2023-11-29: This file is in development.  My plan is to
;; integrate it with denote-org-dblock.el and maybe with denote.el
;; based on user feedback, but I first want to have a stable
;; interface.

;;; Code:

(require 'denote)

(defgroup denote-sort nil
  "Sort Denote files based on a file name component."
  :group 'denote
  :link '(info-link "(denote) Top")
  :link '(url-link :tag "Homepage" "https://protesilaos.com/emacs/denote"))

(defvar denote-sort-comparison-function #'string-collate-lessp
  "String comparison function used by `denote-sort-files' subroutines.")

(defvar denote-sort-components '(title keywords signature identifier)
  "List of sorting keys applicable for `denote-sort-files' and related.")

(defun denote-sort-title-lessp (file1 file2)
  "Return smallest between FILE1 and FILE2 based on their title.
The comparison is done with `denote-sort-comparison-function' between the
two title values."
  (let ((one (denote-retrieve-filename-title file1))
        (two (denote-retrieve-filename-title file2)))
    (cond
     ((string= one (file-name-sans-extension file1))
      file2)
     ((or (string= two (file-name-sans-extension file2))
          (funcall denote-sort-comparison-function one two))
      file1)
     (t nil))))

(defun denote-sort-keywords-lessp (file1 file2)
  "Return smallest between FILE1 and FILE2 based on their keywords.
The comparison is done with `denote-sort-comparison-function' between the
two keywords values."
  (let ((one (denote-retrieve-filename-keywords file1))
        (two (denote-retrieve-filename-keywords file2)))
    (cond
     ((and (string-empty-p one) (not (string-empty-p two))) file2)
     ((or (and (not (string-empty-p one)) (string-empty-p two))
          (funcall denote-sort-comparison-function one two))
      file1)
     (t nil))))

(defun denote-sort-signature-lessp (file1 file2)
  "Return smallest between FILE1 and FILE2 based on their signature.
The comparison is done with `denote-sort-comparison-function' between the
two signature values."
  (let ((one (denote-retrieve-filename-signature file1))
        (two (denote-retrieve-filename-signature file2)))
    (cond
     ((and (string-empty-p one) (not (string-empty-p two))) file2)
     ((or (and (not (string-empty-p one)) (string-empty-p two))
          (funcall denote-sort-comparison-function one two))
      file1)
     (t nil))))

;;;###autoload
(defun denote-sort-files (files component &optional reverse)
  "Returned sorted list of Denote FILES.

With COMPONENT as a symbol among `denote-sort-components',
sort files based on the corresponding file name component.

With COMPONENT as a nil value keep the original date-based
sorting which relies on the identifier of each file name.

With optional REVERSE as a non-nil value, reverse the sort order."
  (let* ((files-to-sort (copy-sequence files))
         (sort-fn (when component
                    (pcase component
                     ('title #'denote-sort-title-lessp)
                     ('keywords #'denote-sort-keywords-lessp)
                     ('signature #'denote-sort-signature-lessp))))
         (sorted-files (if sort-fn (sort files sort-fn) files-to-sort)))
    (if reverse
        (reverse sorted-files)
      sorted-files)))

(defun denote-sort-get-directory-files (files-matching-regexp sort-by-component &optional reverse)
  "Return sorted list of files in variable `denote-directory'.

With FILES-MATCHING-REGEXP as a string limit files to those
matching the given regular expression.

With SORT-BY-COMPONENT as a symbol among `denote-sort-components',
pass it to `denote-sort-files' to sort by the corresponding file
name component.

With optional REVERSE as a non-nil value, reverse the sort order."
  (denote-sort-files
   (denote-directory-files files-matching-regexp)
   sort-by-component
   reverse))

(defvar denote-sort--files-matching-regexp-hist nil
  "Minibuffer history of `denote-sort--files-matching-regexp-prompt'.")

(defun denote-sort--files-matching-regexp-prompt ()
  "Prompt for REGEXP to filter Denote files by."
  (read-regexp "Match files with the given REGEXP: " nil 'denote-sort--files-matching-regexp-hist))

(defvar denote-sort--component-hist nil
  "Minibuffer history of `denote-sort-component-prompt'.")

(defun denote-sort-component-prompt ()
  "Prompt `denote-sort-files' for sorting key among `denote-sort-components'."
  (let ((default (car denote-sort--component-hist)))
    (intern
     (completing-read
      (format-prompt "Sort by file name component " default)
      denote-sort-components nil :require-match
      nil 'denote-sort--component-hist default))))

(defun denote-sort--prepare-dired (buffer-name files)
  "Return Dired buffer with BUFFER-NAME showing FILES.
FILES are stripped of their directory component and are displayed
relative to the variable `denote-directory'."
  ;; TODO 2023-11-29: Can we improve font-lock to cover the directory
  ;; component which is on display for files inside a subdir of
  ;; `denote-directory'?
  (let* ((dir (denote-directory))
         (default-directory dir))
    (dired (cons buffer-name (mapcar #'file-relative-name files)))))

;;;###autoload
(defun denote-sort-dired (files-matching-regexp sort-by-component reverse)
  "Produce Dired buffer with sorted files from variable `denote-directory'.
When called interactively, prompt for FILES-MATCHING-REGEXP,
SORT-BY-COMPONENT, and REVERSE.

1. FILES-MATCHING-REGEXP limits the list of Denote files to
   those matching the provided regular expression.

2. SORT-BY-COMPONENT sorts the files by their file name
   component (one among `denote-sort-components').

3. REVERSE is a boolean to reverse the order when it is a non-nil value.

When called from Lisp, the arguments are a string, a keyword, and
a non-nil value, respectively."
  (interactive
   (list
    (denote-sort--files-matching-regexp-prompt)
    (denote-sort-component-prompt)
    (y-or-n-p "Reverse sort? ")))
  (denote-sort--prepare-dired
   (format "Denote files matching `%s' sorted by %s" files-matching-regexp sort-by-component)
   (denote-sort-get-directory-files files-matching-regexp sort-by-component reverse)))

(provide 'denote-sort)
;;; denote-sort.el ends here
