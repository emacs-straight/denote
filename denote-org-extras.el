;;; denote-org-extras.el --- Denote extensions for Org mode -*- lexical-binding: t -*-

;; Copyright (C) 2024  Free Software Foundation, Inc.

;; Author: Protesilaos Stavrou <info@protesilaos.com>
;; Maintainer: Protesilaos Stavrou <info@protesilaos.com>
;; URL: https://github.com/protesilaos/denote

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
;; WORK-IN-PROGRESS

;;; Code:

(require 'denote)
(require 'org)

;;;; Link to file and heading

(defun denote-org-extras--get-outline (file)
  "Return `outline-regexp' headings and line numbers of FILE."
  (with-current-buffer (find-file-noselect file)
    (let ((outline-regexp (format "^\\(?:%s\\)" (or (bound-and-true-p outline-regexp) "[*\^L]+")))
          candidates)
      (save-excursion
        (goto-char (point-min))
        (while (if (bound-and-true-p outline-search-function)
                   (funcall outline-search-function)
                 (re-search-forward outline-regexp nil t))
          (push
           ;; NOTE 2024-01-20: The -5 (minimum width) is a
           ;; sufficiently high number to keep the alignment
           ;; consistent in most cases.  Larger files will simply
           ;; shift the heading text in minibuffer, but this is not an
           ;; issue anymore.
           (format "%-5s %s"
                   (line-number-at-pos (point))
                   (buffer-substring-no-properties (line-beginning-position) (line-end-position)))
           candidates)
          (goto-char (1+ (line-end-position)))))
      (if candidates
          (nreverse candidates)
        (user-error "No outline")))))

(defun denote-org-extras--outline-prompt (&optional file)
  "Prompt for outline among headings retrieved by `denote-org-extras--get-outline'.
With optional FILE use the outline of it, otherwise use that of
the current file."
  (completing-read
   (format "Select heading inside `%s': "
           (propertize (file-name-nondirectory file) 'face 'denote-faces-prompt-current-name))
   (denote--completion-table-no-sort 'imenu (denote-org-extras--get-outline (or file buffer-file-name)))
   nil :require-match))

(defun denote-org-extras--get-heading-and-id-from-line (line file)
  "Return heading text and CUSTOM_ID from the given LINE in FILE."
  (with-current-buffer (find-file-noselect file)
    (save-excursion
      (goto-char (point-min))
      (forward-line line)
      (cons (denote-link-ol-get-heading) (denote-link-ol-get-id)))))

(defun denote-org-extras-format-link-with-heading (file heading-id description)
  "Prepare link to FILE with HEADING-ID using DESCRIPTION.

FILE-TYPE and ID-ONLY are used to get the format of the link.
See the `:link' property of `denote-file-types'."
  (format "[[denote:%s::#%s][%s]]"
          (denote-retrieve-filename-identifier file)
          heading-id
          description))

(defun denote-org-extras-format-link-get-description (file heading-text)
  "Return link description for FILE with HEADING-TEXT at the end."
  (format "%s::%s"
          (denote--retrieve-title-or-filename file 'org)
          heading-text))

;;;###autoload
(defun denote-org-extras-link-to-heading ()
  "Link to file and then specify a heading to extend the link to.

The resulting link has the following pattern:

[[denote:IDENTIFIER::#ORG-HEADING-CUSTOM-ID]][File title::Heading text]].

Because only Org files can have links to individual headings,
limit the list of possible files to those which include the .org
file extension (remember that Denote works with many file types,
per the user option `denote-file-type').

The user option `denote-org-extras-store-link-to-heading'
determined whether the `org-store-link' function can save a link
to the current heading.  Such links look the same as those of
this command, though the functionality defined herein is
independent of it.

To only link to a file, use the `denote-link' command."
  (declare (interactive-only t))
  (interactive)
  (when-let ((file (denote-file-prompt ".*\\.org"))
             (heading (denote-org-extras--outline-prompt file))
             (line (string-to-number (car (split-string heading "\t"))))
             (heading-data (denote-org-extras--get-heading-and-id-from-line line file))
             (heading-text (car heading-data))
             (heading-id (cdr heading-data))
             (description (denote-org-extras-format-link-get-description file heading-text)))
    (insert (denote-org-extras-format-link-with-heading file heading-id description))))

;;;; Extract subtree into its own note

(defun denote-org-extras--get-heading-date ()
  "Try to return a timestamp for the current Org heading.
This can be used as the value for the DATE argument of the
`denote' command."
  (when-let ((pos (point))
             (timestamp (or (org-entry-get pos "DATE")
                            (org-entry-get pos "CREATED"))))
    (date-to-time timestamp)))

;;;###autoload
(defun denote-org-extras-extract-org-subtree ()
  "Create new Denote note using the current Org subtree.
Remove the subtree from its current file and move its contents
into the new Denote file.

Take the text of the subtree's top level heading and use it as
the title of the new note.

If the heading has any tags, use them as the keywords of the new
note.  Else do not include any keywords.

If the subtree has a PROPERTIES drawer, retain it for further
review.  If the PROPERTIES drawer includes a DATE or CREATED
property with a timestamp value, use that to derive the date (or
date and time) of the new note (if there is only a date, the time
is taken as 00:00).  If both DATE and CREATED properties are
present, the former is used.

Make the new note an Org file regardless of the value of
`denote-file-type'."
  (interactive)
  (if-let ((text (org-get-entry))
           (heading (denote-link-ol-get-heading)))
      (let ((tags (org-get-tags))
            (date (denote-org-extras--get-heading-date)))
        (delete-region (org-entry-beginning-position)
                       (save-excursion (org-end-of-subtree t) (point)))
        (denote heading tags 'org nil date)
        (insert text))
    (user-error "No subtree to extract; aborting")))

(provide 'denote-org-extras)
;;; denote-org-extras.el ends here
