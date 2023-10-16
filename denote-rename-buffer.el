;;; denote-rename-buffer.el --- Rename Denote buffers to be shorter and easier to read -*- lexical-binding: t -*-

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
;; Rename Denote buffers to be shorter and easier to read.  Enable
;; `denote-rename-buffer-mode' to automatically rename the buffer of a
;; Denote file.  The renaming function is specified in the user option
;; `denote-rename-buffer-function'.

;;; Code:

(require 'denote)

(defgroup denote-rename-buffer nil
  "Rename Denote buffers to be shorter and easier to read."
  :group 'denote
  :link '(info-link "(denote) Top")
  :link '(url-link :tag "Homepage" "https://protesilaos.com/emacs/denote"))

(defcustom denote-rename-buffer-format "%t"
  "The format of the buffer name `denote-rename-buffer' should use.
Thie value is a string that treats specially the following
specifiers:

- The %t is the Denote TITLE of the file.
- The %i is the Denote IDENTIFIER of the file.
- The %d is the same as %i (DATE mnemonic).
- The %s is the Denote SIGNATURE of the file.
- The %k is the Denote KEYWORDS of the file.
- The %% is a literal percent sign.

In addition, the following flags are available for each of the specifiers:

- 0 :: Pad to the width, if given, with zeros instead of spaces.
- - :: Pad to the width, if given, on the right instead of the left.
- < :: Truncate to the width and precision, if given, on the left.
- > :: Truncate to the width and precision, if given, on the right.
- ^ :: Convert to upper case.
- _ :: Convert to lower case.

When combined all together, the above are written thus:

    %<flags><width><precision>SPECIFIER-CHARACTER

Any other string it taken as-is.  Users may want, for example, to
include some text that makes Denote buffers stand out, such as
a [D] prefix."
  :type 'string
  :package-version '(denote . "2.1.0")
  :group 'denote-rename-buffer)

(defcustom denote-rename-buffer-function #'denote-rename-buffer
  "Symbol of function that is called to rename the Denote file buffer.
The default `denote-rename-buffer' function uses the pattern
described in `denote-rename-buffer-format'.

Users can set this variable to an arbitrary function that does
something else.  The function is called without arguments from
the `find-file-hook' and `denote-after-new-note-hook'.

A nil value for this variable means that the title of the Denote
buffer will be used, if available."
  :type '(choice
          (const :tag "Rename using the `denote-rename-buffer-format'" denote-rename-buffer)
          (function :tag "Use a custom renaming function"))
  :package-version '(denote . "2.1.0")
  :group 'denote-rename-buffer)

(defun denote-rename-buffer--common-check (buffer)
  "Determine if BUFFER shall be renamed.
Return the file path and the type of it as a cons cell."
  (when-let ((file (buffer-file-name buffer))
             ((denote-file-has-identifier-p file))
             (type (denote-filetype-heuristics file)))
    (cons file type)))

(defun denote-rename-buffer--get-title (buffer)
  "Return Denote title of BUFFER."
  (when-let ((file-and-type (denote-rename-buffer--common-check buffer)))
    (denote-retrieve-title-value (car file-and-type) (cdr file-and-type))))

(defun denote-rename-buffer--get-identifier (buffer)
  "Return Denote identifier of BUFFER."
  (when-let ((file-and-type (denote-rename-buffer--common-check buffer)))
    (denote-retrieve-filename-identifier (car file-and-type))))

(defun denote-rename-buffer--get-signature (buffer)
  "Return Denote signature of BUFFER."
  (when-let ((file-and-type (denote-rename-buffer--common-check buffer)))
    (denote-retrieve-filename-signature (car file-and-type))))

(defun denote-rename-buffer--get-keywords (buffer)
  "Return Denote keywords of BUFFER."
  (when-let ((file-and-type (denote-rename-buffer--common-check buffer)))
    (denote--keywords-combine
     (denote-retrieve-keywords-value (car file-and-type) (cdr file-and-type)))))

(defun denote-rename-buffer--format (buffer)
  "Parse the BUFFER through the `denote-rename-buffer-format'."
  (format-spec denote-rename-buffer-format
               (list (cons ?t (denote-rename-buffer--get-title buffer))
                     (cons ?i (denote-rename-buffer--get-identifier buffer))
                     (cons ?d (denote-rename-buffer--get-identifier buffer))
                     (cons ?s (denote-rename-buffer--get-signature buffer))
                     (cons ?k (denote-rename-buffer--get-keywords buffer))
                     (cons ?% "%"))
               'delete))

(defun denote-rename-buffer--with-unique-name (name)
  "Call `rename-buffer' with NAME and uniquify it."
  (unless (or (string-empty-p name)
              (string-blank-p name))
    (rename-buffer name :unique)))

(defun denote-rename-buffer (&optional buffer)
  "Rename current buffer or optional BUFFER with `denote-rename-buffer-format'.
The symbol of this function is the default value of the user
option `denote-rename-buffer-function' and is thus used by the
`denote-rename-buffer-mode'."
  (denote-rename-buffer--with-unique-name
   (denote-rename-buffer--format (or buffer (current-buffer)))))

(make-obsolete
 'denote-rename-buffer-with-title
 'denote-rename-buffer
 "2.1.0")

(make-obsolete
 'denote-rename-buffer-with-identifier
 'denote-rename-buffer
 "2.1.0")

(defun denote-rename-buffer--fallback (&optional buffer)
  "Fallback to rename BUFFER or `current-buffer'.
This is called if `denote-rename-buffer-rename-function' is nil."
  (denote-rename-buffer--with-unique-name
   (denote-rename-buffer--get-title (or buffer (current-buffer)))))

(defun denote-rename-buffer-rename-function-or-fallback ()
  "Call `denote-rename-buffer-function' or its fallback to rename with title.
Add this to `find-file-hook' and `denote-after-new-note-hook'."
  (funcall (or denote-rename-buffer-function #'denote-rename-buffer--fallback)))

;;;###autoload
(define-minor-mode denote-rename-buffer-mode
  "Automatically rename Denote buffers to be easier to read.
A buffer is renamed upon visiting the underlying file.  This
means that existing buffers are not renamed until they are
visited again in a new buffer (files are visited with the command
`find-file' or related)."
  :global t
  (if denote-rename-buffer-mode
      (progn
        (add-hook 'denote-after-new-note-hook #'denote-rename-buffer-rename-function-or-fallback)
        (add-hook 'find-file-hook #'denote-rename-buffer-rename-function-or-fallback))
    (remove-hook 'denote-after-new-note-hook #'denote-rename-buffer-rename-function-or-fallback)
    (remove-hook 'find-file-hook #'denote-rename-buffer-rename-function-or-fallback)))

(provide 'denote-rename-buffer-with-title)
;;; denote-rename-buffer.el ends here
