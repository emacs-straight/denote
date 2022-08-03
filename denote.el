;;; denote.el --- Simple notes with an efficient file-naming scheme -*- lexical-binding: t -*-

;; Copyright (C) 2022  Free Software Foundation, Inc.

;; Author: Protesilaos Stavrou <info@protesilaos.com>
;; Maintainer: Denote Development <~protesilaos/denote@lists.sr.ht>
;; URL: https://git.sr.ht/~protesilaos/denote
;; Mailing-List: https://lists.sr.ht/~protesilaos/denote
;; Version: 0.4.0
;; Package-Requires: ((emacs "27.2"))

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
;; Denote aims to be a simple-to-use, focused-in-scope, and effective
;; note-taking tool for Emacs.  The manual describes all the
;; technicalities about the file-naming scheme, points of entry to
;; creating new notes, commands to check links between notes, and more:
;; <https://protesilaos.com/emacs/denote>.  If you have the info manual
;; available, evaluate:
;;
;;    (info "(denote) Top")
;;
;; What follows is a general overview of its core core design
;; principles:
;;
;; * Predictability :: File names must follow a consistent and
;;   descriptive naming convention (see the manual's "The file-naming
;;   scheme").  The file name alone should offer a clear indication of
;;   what the contents are, without reference to any other metadatum.
;;   This convention is not specific to note-taking, as it is pertinent
;;   to any form of file that is part of the user's long-term storage
;;   (see the manual's "Renaming files").
;;
;; * Composability :: Be a good Emacs citizen, by integrating with other
;;   packages or built-in functionality instead of re-inventing
;;   functions such as for filtering or greping.  The author of Denote
;;   (Protesilaos, aka "Prot") writes ordinary notes in plain text
;;   (`.txt'), switching on demand to an Org file only when its expanded
;;   set of functionality is required for the task at hand (see the
;;   manual's "Points of entry").
;;
;; * Portability :: Notes are plain text and should remain portable.
;;   The way Denote writes file names, the front matter it includes in
;;   the note's header, and the links it establishes must all be
;;   adequately usable with standard Unix tools.  No need for a databse
;;   or some specialised software.  As Denote develops and this manual
;;   is fully fleshed out, there will be concrete examples on how to do
;;   the Denote-equivalent on the command-line.
;;
;; * Flexibility :: Do not assume the user's preference for a
;;   note-taking methodology.  Denote is conceptually similar to the
;;   Zettelkasten Method, which you can learn more about in this
;;   detailed introduction: <https://zettelkasten.de/introduction/>.
;;   Notes are atomic (one file per note) and have a unique identifier.
;;   However, Denote does not enforce a particular methodology for
;;   knowledge management, such as a restricted vocabulary or mutually
;;   exclusive sets of keywords.  Denote also does not check if the user
;;   writes thematically atomic notes.  It is up to the user to apply
;;   the requisite rigor and/or creativity in pursuit of their preferred
;;   workflow (see the manual's "Writing metanotes").
;;
;; * Hackability :: Denote's code base consists of small and reusable
;;   functions.  They all have documentation strings.  The idea is to
;;   make it easier for users of varying levels of expertise to
;;   understand what is going on and make surgical interventions where
;;   necessary (e.g. to tweak some formatting).  In this manual, we
;;   provide concrete examples on such user-level configurations (see
;;   the manual's "Keep a journal or diary").
;;
;; Now the important part...  "Denote" is the familiar word, though it
;; also is a play on the "note" concept.  Plus, we can come up with
;; acronyms, recursive or otherwise, of increasingly dubious utility
;; like:
;;
;; + Don't Ever Note Only The Epiphenomenal
;; + Denote Everything Neatly; Omit The Excesses
;;
;; But we'll let you get back to work.  Don't Eschew or Neglect your
;; Obligations, Tasks, and Engagements.

;;; Code:

(require 'seq)
(require 'xref)
(require 'dired)
(eval-when-compile (require 'subr-x))

(defgroup denote ()
  "Simple notes with an efficient file-naming scheme."
  :group 'files)

;;;; User options

;; About the autoload: (info "(elisp) File Local Variables")

;;;###autoload (put 'denote-directory 'safe-local-variable (lambda (val) (or (eq val 'local) (eq val 'default-directory))))
(defcustom denote-directory (expand-file-name "~/Documents/notes/")
  "Directory for storing personal notes.

A safe local value of either `default-directory' or `local' can
be added as a value in a .dir-local.el file.  Do this if you
intend to use multiple directory silos for your notes while still
relying on a global value (which is the value of this variable).
The Denote manual has a sample (search for '.dir-locals.el').
Those silos do not communicate with each other: they remain
separate.

The local value influences where commands such as `denote' will
place the newly created note.  If the command is called from a
directory or file where the local value exists, then that value
take precedence, otherwise the global value is used.

If you intend to reference this variable in Lisp, consider using
the function `denote-directory' instead: it returns the path as a
directory and also checks if a safe local value should be used."
  :group 'denote
  :safe (lambda (val) (or (eq val 'local) (eq val 'default-directory)))
  :link '(info-link "(denote) Maintain separate directories for notes")
  :type 'directory)

(defcustom denote-known-keywords
  '("emacs" "philosophy" "politics" "economics")
  "List of strings with predefined keywords for `denote'.
Also see user options: `denote-allow-multi-word-keywords',
`denote-infer-keywords', `denote-sort-keywords'."
  :group 'denote
  :type '(repeat string))

(defcustom denote-infer-keywords t
  "Whether to infer keywords from existing notes' file names.

When non-nil, search the file names of existing notes in the
variable `denote-directory' for their keyword field and extract
the entries as \"inferred keywords\".  These are combined with
`denote-known-keywords' and are presented as completion
candidates while using `denote' and related commands
interactively.

If nil, refrain from inferring keywords.  The aforementioned
completion prompt only shows the `denote-known-keywords'.  Use
this if you want to enforce a restricted vocabulary.

Inferred keywords are specific to the value of the variable
`denote-directory'.  If a silo with a local value is used, as
explained in that variable's doc string, the inferred keywords
are specific to the given silo.

For advanced Lisp usage, the function `denote-keywords' returns
the appropriate list of strings."
  :group 'denote
  :type 'boolean)

(defconst denote--prompt-symbols
  '(title keywords date file-type subdirectory)
  "List of symbols representing `denote' prompts.")

(defcustom denote-prompts '(title keywords)
  "Specify the prompts of the `denote' command for interactive use.

The value is a list of symbols, which includes any of the following:

- `title': Prompt for the title of the new note.

- `keywords': Prompts with completion for the keywords of the new
  note.  Available candidates are those specified in the user
  option `denote-known-keywords'.  If the user option
  `denote-infer-keywords' is non-nil, keywords in existing note
  file names are included in the list of candidates.  The
  `keywords' prompt uses `completing-read-multiple', meaning that
  it can accept multiple keywords separated by a comma (or
  whatever the value of `crm-separator' is).

- `file-type': Prompts with completion for the file type of the
  new note.  Available candidates are those specified in the user
  option `denote-file-type'.  Without this prompt, `denote' uses
  the value of `denote-file-type'.

- `subdirectory': Prompts with completion for a subdirectory in
  which to create the note.  Available candidates are the value
  of the user option `denote-directory' and all of its
  subdirectories.  Any subdirectory must already exist: Denote
  will not create it.

- `date': Prompts for the date of the new note.  It will expect
  an input like 2022-06-16 or a date plus time: 2022-06-16 14:30.
  Without the `date' prompt, the `denote' command uses the
  `current-time'.

The prompts occur in the given order.

If the value of this user option is nil, no prompts are used.
The resulting file name will consist of an identifier (i.e. the
date and time) and a supported file type extension (per
`denote-file-type').

Recall that Denote's standard file-naming scheme is defined as
follows (read the manual for the technicalities):

    DATE--TITLE__KEYWORDS.EXT

If either or both of the `title' and `keywords' prompts are not
included in the value of this variable, file names will be any of
those permutations:

    DATE.EXT
    DATE--TITLE.EXT
    DATE__KEYWORDS.EXT

When in doubt, always include the `title' and `keywords' prompts.

Finally, this user option only affects the interactive use of the
`denote' command (advanced users can call it from Lisp).  For
ad-hoc interactive actions that do not change the default
behaviour of the `denote' command, users can invoke these
convenience commands: `denote-type', `denote-subdirectory',
`denote-date'."
  :group 'denote
  :link '(info-link "(denote) The denote-prompts option")
  :type '(radio (const :tag "Use no prompts" nil)
                (set :tag "Available prompts" :greedy t
                     (const :tag "Title" title)
                     (const :tag "Keywords" keywords)
                     (const :tag "Date" date)
                     (const :tag "File type extension" file-type)
                     (const :tag "Subdirectory" subdirectory))))

(defcustom denote-sort-keywords t
  "Whether to sort keywords in new files.

When non-nil, the keywords of `denote' are sorted with
`string-lessp' regardless of the order they were inserted at the
minibuffer prompt.

If nil, show the keywords in their given order."
  :group 'denote
  :type 'boolean)

(defcustom denote-allow-multi-word-keywords t
  "If non-nil keywords can consist of multiple words.
Words are automatically separated by a hyphen when using the
`denote' command or related.  The hyphen is the only legal
character---no spaces, no other characters.  If, for example, the
user types <word1_word2> or <word1 word2>, it is converted to
<word1-word2>.

When nil, do not allow keywords to consist of multiple words.
Reduce them to a single word, such as by turning <word1_word2> or
<word1 word2> into <word1word2>."
  :group 'denote
  :type 'boolean)

(defcustom denote-file-type nil
  "The file type extension for new notes.

By default (a nil value), the file type is that of Org mode.

When the value is the symbol `markdown-yaml', the file type is
that of Markdown mode and the front matter uses YAML.  Similarly,
`markdown-toml' will use Markdown but apply TOML to the front
matter.

When the value is `text', the file type is that of Text mode.

Any other non-nil value is the same as the default."
  :type '(choice
          (const :tag "Org mode (default)" nil)
          (const :tag "Markdown (YAML front matter)" markdown-yaml)
          (const :tag "Markdown (TOML front matter)" markdown-toml)
          (const :tag "Plain text" text))
  :group 'denote)

(defcustom denote-date-format nil
  "Date format in the front matter (file header) of new notes.

When nil (the default value), use a file-type-specific
format (also check `denote-file-type'):

- For Org, an inactive timestamp is used, such as [2022-06-30 Wed
  15:31].

- For Markdown, the RFC3339 standard is applied:
  2022-06-30T15:48:00+03:00.

- For plain text, the format is that of ISO 8601: 2022-06-30.

If the value is a string, ignore the above and use it instead.
The string must include format specifiers for the date.  These
are described in the doc string of `format-time-string'."
  :type '(choice
          (const :tag "Use appropiate format for each file type" nil)
          (string :tag "Custom format for `format-time-string'"))
  :group 'denote)

;;;; Main variables

;; For character classes, evaluate: (info "(elisp) Char Classes")
(defconst denote--id-format "%Y%m%dT%H%M%S"
  "Format of ID prefix of a note's filename.")

(defconst denote--id-regexp "\\([0-9]\\{8\\}\\)\\(T[0-9]\\{6\\}\\)"
  "Regular expression to match `denote--id-format'.")

(defconst denote--title-regexp "--\\([[:alnum:][:nonascii:]-]*\\)"
  "Regular expression to match the title field.")

(defconst denote--keywords-regexp "__\\([[:alnum:][:nonascii:]_-]*\\)"
  "Regular expression to match keywords.")

(defconst denote--extension-regexp "\\.\\(org\\|md\\|txt\\)"
  "Regular expression to match supported Denote extensions.")

(defconst denote--punctuation-regexp "[][{}!@#$%^&*()=+'\"?,.\|;:~`‘’“”/]*"
  "Punctionation that is removed from file names.
We consider those characters illegal for our purposes.")

(defvar denote-punctuation-excluded-extra-regexp nil
  "Additional punctuation that is removed from file names.
This variable is for advanced users who need to extend the
`denote--punctuation-regexp'.  Once we have a better
understanding of what we should be omitting, we will update
things accordingly.")

(defvar denote-last-path nil "Store last path.")
(defvar denote-last-title nil "Store last title.")
(defvar denote-last-keywords nil "Store last keywords.")
(defvar denote-last-buffer nil "Store last buffer.")
(defvar denote-last-front-matter nil "Store last front-matter.")

;;;; File helper functions

(defun denote--completion-table (category candidates)
  "Pass appropriate metadata CATEGORY to completion CANDIDATES."
  (lambda (string pred action)
    (if (eq action 'metadata)
        `(metadata (category . ,category))
      (complete-with-action action candidates string pred))))

(defun denote-directory ()
  "Return path of variable `denote-directory' as a proper directory."
  (let* ((val (or (buffer-local-value 'denote-directory (current-buffer))
                  denote-directory))
         (path (if (or (eq val 'default-directory) (eq val 'local)) default-directory val)))
    (unless (file-directory-p path)
      (make-directory path t))
    (file-name-as-directory (expand-file-name path))))

(defun denote--slug-no-punct (str)
  "Convert STR to a file name slug."
  (replace-regexp-in-string
   (concat denote--punctuation-regexp denote-punctuation-excluded-extra-regexp)
   "" str))

(defun denote--slug-hyphenate (str)
  "Replace spaces and underscores with hyphens in STR.
Also replace multiple hyphens with a single one and remove any
trailing hyphen."
  (replace-regexp-in-string
   "-$" ""
   (replace-regexp-in-string
    "-\\{2,\\}" "-"
    (replace-regexp-in-string "_\\|\s+" "-" str))))

(defun denote--sluggify (str)
  "Make STR an appropriate slug for file names and related."
  (downcase (denote--slug-hyphenate (denote--slug-no-punct str))))

(defun denote--sluggify-and-join (str)
  "Sluggify STR while joining separate words."
  (downcase
   (replace-regexp-in-string
    "-" ""
    (denote--slug-hyphenate (denote--slug-no-punct str)))))

(defun denote--sluggify-keywords (keywords)
  "Sluggify KEYWORDS."
  (mapcar (if denote-allow-multi-word-keywords
              #'denote--sluggify
            #'denote--sluggify-and-join)
          keywords))

(defun denote--file-empty-p (file)
  "Return non-nil if FILE is empty."
  (zerop (or (file-attribute-size (file-attributes file)) 0)))

(defun denote--only-note-p (file)
  "Make sure FILE is an actual Denote note."
  (let ((file-name (file-name-nondirectory file)))
    (and (not (file-directory-p file))
         (file-regular-p file)
         (string-match-p (concat "\\`" denote--id-regexp
                                 ".*" denote--extension-regexp
                                 "\\(.gpg\\)?"
                                 "\\'")
                         file-name)
         (not (string-match-p "[#~]\\'" file)))))

(defun denote--file-name-relative-to-denote-directory (file)
  "Return file name of FILE relative to the variable `denote-directory'.
FILE must be an absolute path."
  (when-let* ((dir (denote-directory))
              ((file-name-absolute-p file))
              (file-name (expand-file-name file))
              ((string-prefix-p dir file-name)))
    (substring-no-properties file-name (length dir))))

(defun denote--current-file-is-note-p ()
  "Return non-nil if current file likely is a Denote note."
  (and (or (string-match-p denote--id-regexp (buffer-file-name))
           (string-match-p denote--id-regexp (buffer-name)))
       (string-prefix-p (denote-directory) (expand-file-name default-directory))))

(defun denote--directory-files-recursively (directory)
  "Return expanded files in DIRECTORY recursively."
  (mapcar
   (lambda (s) (expand-file-name s))
   (seq-remove
    (lambda (f)
      (not (denote--only-note-p f)))
    (directory-files-recursively directory directory-files-no-dot-files-regexp t))))

(defun denote--directory-files (&optional absolute)
  "List note files.
If optional ABSOLUTE, show full paths, else only show base file
names that are relative to the variable `denote-directory'."
  (let* ((default-directory (denote-directory))
         (files (denote--directory-files-recursively default-directory)))
    (if absolute
        files
      (mapcar
       (lambda (s) (denote--file-name-relative-to-denote-directory s))
       files))))

(defun denote--get-note-path-by-id (id)
  "Return the absolute path of ID note in variable `denote-directory'."
  (seq-find
   (lambda (f)
     (string-prefix-p id (file-name-nondirectory f)))
   (denote--directory-files :absolute)))

(defun denote--directory-files-matching-regexp (regexp)
  "Return list of files matching REGEXP."
  (delq
   nil
   (mapcar
    (lambda (f)
      (when (and (denote--only-note-p f)
                 (string-match-p regexp f)
                 (not (string= (file-name-nondirectory (buffer-file-name)) f)))
        f))
    (denote--directory-files))))

;;;; Keywords

(defun denote--extract-keywords-from-path (path)
  "Extract keywords from PATH."
  (let* ((file-name (file-name-nondirectory path))
         (kws (when (string-match denote--keywords-regexp file-name)
                (match-string-no-properties 1 file-name))))
    (when kws
      (split-string kws "_"))))

(defun denote--inferred-keywords ()
  "Extract keywords from `denote--directory-files'."
  (delete-dups
   (mapcan (lambda (p)
             (denote--extract-keywords-from-path p))
           (denote--directory-files))))

(defun denote-keywords ()
  "Return appropriate list of keyword candidates.
If `denote-infer-keywords' is non-nil, infer keywords from
existing notes and combine them into a list with
`denote-known-keywords'.  Else use only the latter."
  (delete-dups
   (if denote-infer-keywords
       (append (denote--inferred-keywords) denote-known-keywords)
     denote-known-keywords)))

(defvar denote--keyword-history nil
  "Minibuffer history of inputted keywords.")

(defun denote--keywords-crm (keywords)
  "Use `completing-read-multiple' for KEYWORDS."
  (delete-dups
   (completing-read-multiple
    "File keyword: " keywords
    nil nil nil 'denote--keyword-history)))

(defun denote--keywords-prompt ()
  "Prompt for one or more keywords.
In the case of multiple entries, those are separated by the
`crm-sepator', which typically is a comma.  In such a case, the
output is sorted with `string-lessp'."
  (let ((choice (denote--keywords-crm (denote-keywords))))
    (setq denote-last-keywords
          (if denote-sort-keywords
              (sort choice #'string-lessp)
            choice))))

(defun denote--keywords-combine (keywords)
  "Format KEYWORDS output of `denote--keywords-prompt'."
  (mapconcat #'downcase keywords "_"))

(defun denote--keywords-add-to-history (keywords)
  "Append KEYWORDS to `denote--keyword-history'."
  (mapc (lambda (kw)
          (add-to-history 'denote--keyword-history kw))
        (delete-dups keywords)))

;;;; Front matter or content retrieval functions

(defconst denote--retrieve-id-front-matter-key-regexp
  "^.?.?\\b\\(?:identifier\\)\\s-*[:=]"
  "Regular expression for identifier key.")

(defconst denote--retrieve-title-front-matter-key-regexp
  "^\\(?:#\\+\\)?\\(?:title\\)\\s-*[:=]"
  "Regular expression for title key.")

(defconst denote--retrieve-date-front-matter-key-regexp
  "^\\(?:#\\+\\)?\\(?:date\\)\\s-*[:=]"
  "Regular expression for date key.")

(defconst denote--retrieve-keywords-front-matter-key-regexp
  "^\\(?:#\\+\\)?\\(?:tags\\|filetags\\)\\s-*[:=]"
  "Regular expression for keywords key.")

(defun denote--retrieve-filename-identifier (file)
  "Extract identifier from FILE name."
  (if (file-exists-p file)
      (progn
        (string-match denote--id-regexp file)
        (match-string 0 file))
    (error "Cannot find `%s' as a file" file)))

(defun denote--retrieve-search (file key-regexp &optional key)
  "Return value of KEY-REGEXP key in current buffer from FILE.
If optional KEY is non-nil, return the key instead."
  (when (denote--only-note-p file)
    (with-temp-buffer
      (insert-file-contents file)
      (save-excursion
        (save-restriction
          (widen)
          (goto-char (point-min))
          (when (re-search-forward key-regexp nil t 1)
            (if key
                (match-string-no-properties 0)
              (let ((trims "[ \t\n\r\"']+"))
                (string-trim
                 (buffer-substring-no-properties (point) (point-at-eol))
                 trims trims)))))))))

(defun denote--retrieve-value-title (file &optional key)
  "Return title value from FILE.
If optional KEY is non-nil, return the key instead."
  (denote--retrieve-search file denote--retrieve-title-front-matter-key-regexp key))

(defun denote--retrieve-value-date (file &optional key)
  "Return date value from FILE.
If optional KEY is non-nil, return the key instead."
  (denote--retrieve-search file denote--retrieve-date-front-matter-key-regexp key))

(defun denote--retrieve-value-keywords (file &optional key)
  "Return keywords value from FILE.
If optional KEY is non-nil, return the key instead."
  (denote--retrieve-search file denote--retrieve-keywords-front-matter-key-regexp key))

(defun denote--retrieve-read-file-prompt ()
  "Prompt for regular file in variable `denote-directory'."
  (read-file-name "Select note: " (denote-directory) nil nil nil
                  (lambda (f) (or (denote--only-note-p f) (file-directory-p f)))))

(defun denote--retrieve-files-in-output (files)
  "Return list of FILES from `find' output."
  (delq nil (mapcar (lambda (f)
                      (when (denote--only-note-p f) f))
                    files)))

(defun denote--retrieve-xrefs (identifier)
  "Return xrefs of IDENTIFIER in variable `denote-directory'.
The xrefs are returned as an alist."
  (xref--alistify
   (xref-matches-in-files identifier (denote--directory-files :absolute))
   (lambda (x)
     (xref-location-group (xref-item-location x)))))

(defun denote--retrieve-files-in-xrefs (xrefs)
  "Return sorted file names sans directory from XREFS.
Parse `denote--retrieve-xrefs'."
  (sort
   (delete-dups
    (mapcar (lambda (x)
              (denote--file-name-relative-to-denote-directory (car x)))
            xrefs))
   #'string-lessp))

(defun denote--retrieve-proces-grep (identifier)
  "Process lines matching IDENTIFIER and return list of files."
  (let* ((default-directory (denote-directory))
         (file (denote--file-name-relative-to-denote-directory (buffer-file-name))))
    (denote--retrieve-files-in-output
     (delete file (denote--retrieve-files-in-xrefs
                   (denote--retrieve-xrefs identifier))))))

;;;; New note

;;;;; Common helpers for new notes

(defun denote--file-extension ()
  "Return file type extension based on `denote-file-type'."
  (pcase denote-file-type
    ('markdown-toml ".md")
    ('markdown-yaml ".md")
    ('text ".txt")
    (_ ".org")))

(defun denote--format-file (path id keywords title-slug extension)
  "Format file name.
PATH, ID, KEYWORDS, TITLE-SLUG are expected to be supplied by
`denote' or equivalent: they will all be converted into a single
string.  EXTENSION is the file type extension, either a string
which include the starting dot or the return value of
`denote--file-extension'."
  (let ((kws (denote--keywords-combine keywords))
        (ext (or extension (denote--file-extension)))
        (empty-title (string-empty-p title-slug)))
    (cond
     ((and keywords title-slug (not empty-title))
      (format "%s%s--%s__%s%s" path id title-slug kws ext))
     ((and keywords empty-title)
      (format "%s%s__%s%s" path id kws ext))
     ((and title-slug (not empty-title))
      (format "%s%s--%s%s" path id title-slug ext))
     (t
      (format "%s%s%s" path id ext)))))

(defun denote--format-markdown-keywords (keywords)
  "Quote, downcase, and comma-separate elements in KEYWORDS."
  (format "[%s]" (mapconcat (lambda (k)
                              (format "%S" (downcase k)))
                            keywords ", ")))

(defun denote--format-org-keywords (keywords)
  "Quote, downcase, and colon-separate elements in KEYWORDS."
  (format ":%s:" (mapconcat (lambda (k)
                              (downcase k))
                            keywords ":")))

(defun denote--file-meta-keywords (keywords &optional type)
  "Prepare KEYWORDS for inclusion in the file's front matter.
Parse the output of `denote--keywords-prompt', using `downcase'
on the keywords and separating them by two spaces.  A single
keyword is just downcased.

With optional TYPE, format the keywords accordingly (this might
be `toml' or, in the future, some other spec that needss special
treatment)."
  (let ((kw (denote--sluggify-keywords keywords)))
    (cond
     ((or (eq type 'markdown-toml) (eq type 'markdown-yaml) (eq type 'md))
      (denote--format-markdown-keywords kw))
     ((eq type 'text)
      (mapconcat #'downcase kw "  "))
     (t
      (denote--format-org-keywords kw)))))

(defun denote--extract-keywords-from-front-matter (file &optional type)
  "Extract keywords from front matter of FILE with TYPE.
This is the reverse operation of `denote--file-meta-keywords'."
  (let ((fm-keywords (denote--retrieve-value-keywords file)))
    (cond
     ((or (eq type 'markdown-toml) (eq type 'markdown-yaml) (eq type 'md))
      (split-string
       (string-trim-right (string-trim-left fm-keywords "\\[") "\\]")
       ", " t "\s*\"\s*"))
     ((eq type 'text)
      (split-string fm-keywords "  " t " "))
     (t
      (split-string fm-keywords "\\([:]\\|\s\s\\)" t "\\([:]\\|\s\\)")))))

(defvar denote-toml-front-matter
  "+++
title      = %S
date       = %s
tags       = %s
identifier = %S
+++\n\n"
  "TOML front matter value for `format'.
Read `denote-org-front-matter' for the technicalities.")

(defvar denote-yaml-front-matter
  "---
title:      %S
date:       %s
tags:       %s
identifier: %S
---\n\n"
  "YAML front matter value for `format'.
Read `denote-org-front-matter' for the technicalities.")

(defvar denote-text-front-matter
  "title:      %s
date:       %s
tags:       %s
identifier: %s
%s\n\n"
  "Plain text front matter value for `format'.
Read `denote-org-front-matter' for the technicalities of the
first four specifiers this variable accepts.  The fifth specifier
is specific to this variable: it expect a delimiter such as
`denote-text-front-matter-delimiter'.")

(defvar denote-text-front-matter-delimiter (make-string 27 ?-)
  "Final delimiter for plain text front matter.")

(defvar denote-org-front-matter
  "#+title:      %s
#+date:       %s
#+filetags:   %s
#+identifier: %s
\n"
  "Org front matter value for `format'.
The order of the arguments is TITLE, DATE, KEYWORDS, ID.  If you
are an avdanced user who wants to edit this variable to affect
how front matter is produced, consider using something like %2$s
to control where Nth argument is placed.

Make sure to

1. Not use empty lines inside the front matter block.

2. Insert at least one empty line after the front matter block
and do not use any empty line before it.

These help ensure consistency and might prove useful if we need
to operate on the front matter as a whole.")

(defun denote--file-meta-header (title date keywords id &optional filetype)
  "Front matter for new notes.

TITLE, DATE, KEYWORDS, FILENAME, ID are all strings which are
 provided by `denote'.

Optional FILETYPE is one of the values of `denote-file-type',
else that variable is used."
  (let ((kw-space (denote--file-meta-keywords keywords))
        (kw-md (denote--file-meta-keywords keywords 'md)))
    ;; TODO 2022-07-27: Rewrite this (and/or related) to avoid
    ;; duplication with the markdown flavours.
    (pcase (or filetype denote-file-type)
      ('markdown-toml (format denote-toml-front-matter title date kw-md id))
      ('markdown-yaml (format denote-yaml-front-matter title date kw-md id))
      ('text (format denote-text-front-matter title date kw-space id denote-text-front-matter-delimiter))
      (_ (format denote-org-front-matter title date kw-space id)))))

(defun denote--path (title keywords &optional dir id)
  "Return path to new file with TITLE and KEYWORDS.
With optional DIR, use it instead of variable `denote-directory'.
With optional ID, use it else format the current time."
  (setq denote-last-path
        (denote--format-file
         (or dir (file-name-as-directory (denote-directory)))
         (or id (format-time-string denote--id-format))
         (denote--sluggify-keywords keywords)
         (denote--sluggify title)
         (denote--file-extension))))

;; Adapted from `org-hugo--org-date-time-to-rfc3339' in the `ox-hugo'
;; package: <https://github.com/kaushalmodi/ox-hugo>.
(defun denote--date-rfc3339 (&optional date)
  "Format date using the RFC3339 specification.
With optional DATE, use it else use the current one."
  (replace-regexp-in-string
   "\\([0-9]\\{2\\}\\)\\([0-9]\\{2\\}\\)\\'" "\\1:\\2"
   (format-time-string "%FT%T%z" date)))

(defun denote--date-org-timestamp (&optional date)
  "Format date using the Org inactive timestamp notation.
With optional DATE, use it else use the current one."
  (format-time-string "[%F %a %R]" date))

(defun denote--date-iso-8601 (&optional date)
  "Format date according to ISO 8601 standard.
With optional DATE, use it else use the current one."
  (format-time-string "%F" date))

(defun denote--date (&optional date)
  "Expand the date for a new note's front matter.
With optional DATE, use it else use the current one."
  (let ((format denote-date-format))
    (cond
     ((stringp format)
      (format-time-string format date))
     ((or (eq denote-file-type 'markdown-toml)
          (eq denote-file-type 'markdown-yaml))
      (denote--date-rfc3339 date))
     ((eq denote-file-type 'text)
      (denote--date-iso-8601 date))
     (t
      (denote--date-org-timestamp date)))))

(defun denote--prepare-note (title keywords date id directory file-type)
  "Prepare a new note file.

Arguments TITLE, KEYWORDS, DATE, ID, DIRECTORY, and FILE-TYPE
should be valid for note creation."
  (let* ((default-directory directory)
         (denote-file-type file-type)
         (path (denote--path title keywords default-directory id))
         (buffer (find-file path))
         (header (denote--file-meta-header
                  title (denote--date date) keywords
                  (format-time-string denote--id-format date)
                  file-type)))
    (with-current-buffer buffer (insert header))
    (setq denote-last-buffer buffer)
    (setq denote-last-front-matter header)))

(defun denote--dir-in-denote-directory-p (directory)
  "Return DIRECTORY if in variable `denote-directory', else nil."
  (when-let* ((dir directory)
              ((string-prefix-p (expand-file-name (denote-directory))
                                (expand-file-name dir))))
    dir))

(defun denote--file-type-symbol (filetype)
  "Return FILETYPE as a symbol."
  (cond
   ((stringp filetype)
    (intern filetype))
   ((symbolp filetype)
    filetype)
   (t (user-error "`%s' is not a symbol or string" filetype))))

(defun denote--date-add-current-time (date)
  "Add current time to DATE, if necessary.
The idea is to turn 2020-01-15 into 2020-01-15 16:19 so that the
hour and minute component is not left to 00:00.

This reduces the burden on the user who would otherwise need to
input that value in order to avoid the error of duplicate
identifiers.

It also addresses a difference between Emacs 28 and Emacs 29
where the former does not read dates without a time component."
  (if (<= (length date) 10)
      (format "%s %s" date (format-time-string "%H:%M:%S" (current-time)))
    date))

(defun denote--valid-date (date)
  "Return DATE if parsed by `date-to-time', else signal error."
  (let ((datetime (denote--date-add-current-time date)))
    (date-to-time datetime)))

(defun denote--buffer-file-names ()
  "Return file names of active buffers."
  (mapcar
   (lambda (name)
     (file-name-nondirectory name))
   (seq-filter
    (lambda (name) (denote--only-note-p name))
    (delq nil
          (mapcar
           (lambda (buf)
             (buffer-file-name buf))
           (buffer-list))))))

;; This should only be relevant for `denote-date', otherwise the
;; identifier is always unique (we trust that no-one writes multiple
;; notes within fractions of a second).
(defun denote--id-exists-p (identifier)
  "Return non-nil if IDENTIFIER already exists."
  (let ((current-buffer-name (when (buffer-file-name)
                               (file-name-nondirectory (buffer-file-name)))))
    (or (seq-some (lambda (file)
                    (string-match-p (concat "\\`" identifier) file))
                  (delete current-buffer-name (denote--buffer-file-names)))
        (delete current-buffer-name
                (denote--directory-files-matching-regexp
                 (concat "\\`" identifier))))))

(defun denote--barf-duplicate-id (identifier)
  "Throw a user-error if IDENTIFIER already exists else return t."
  (if (denote--id-exists-p identifier)
      (user-error "`%s' already exists; aborting new note creation" identifier)
    t))

(defun denote--subdirs ()
  "Return list of subdirectories in variable `denote-directory'."
  (seq-remove
   (lambda (filename)
     ;; TODO 2022-07-03: Generalise for all VC backends.  Which ones?
     ;;
     ;; TODO 2022-07-03: Maybe it makes sense to also allow the user to
     ;; specify a blocklist of directories that should always be
     ;; excluded?
     (or (string-match-p "\\.git" filename)
         (not (file-directory-p filename))))
   (directory-files-recursively (denote-directory) ".*" t t)))

;;;;; The `denote' command and its prompts

;;;###autoload
(defun denote (&optional title keywords file-type subdirectory date)
  "Create a new note with the appropriate metadata and file name.

When called interactively, the metadata and file name are prompted
according to the value of `denote-prompts'.

When called from Lisp, all arguments are optional.

- TITLE is a string or a function returning a string.

- KEYWORDS is a list of strings.  The list can be empty or the
  value can be set to nil.

- FILE-TYPE is a symbol among those described in `denote-file-type'.

- SUBDIRECTORY is a string representing the path to either the
  value of the variable `denote-directory' or a subdirectory
  thereof.  The subdirectory must exist: Denote will not create
  it.  If SUBDIRECTORY does not resolve to a valid path, the
  variable `denote-directory' is used instead.

- DATE is a string representing a date like 2022-06-30 or a date
  and time like 2022-06-16 14:30.  A nil value or an empty string
  is interpreted as the `current-time'."
  (interactive
   (let ((args (make-vector 5 nil)))
     (dolist (prompt denote-prompts)
       (pcase prompt
         ('title (aset args 0 (denote--title-prompt)))
         ('keywords (aset args 1 (denote--keywords-prompt)))
         ('file-type (aset args 2 (denote--file-type-prompt)))
         ('subdirectory (aset args 3 (denote--subdirs-prompt)))
         ('date (aset args 4 (denote--date-prompt)))))
     (append args nil)))
  (let* ((file-type (denote--file-type-symbol (or file-type denote-file-type)))
         (date (if (or (null date) (string-empty-p date))
                   (current-time)
                 (denote--valid-date date)))
         (id (format-time-string denote--id-format date))
         (directory (if (denote--dir-in-denote-directory-p subdirectory)
                        (file-name-as-directory subdirectory)
                      (denote-directory))))
    (denote--barf-duplicate-id id)
    (denote--prepare-note (or title "") keywords date id directory file-type)
    (denote--keywords-add-to-history keywords)))

(defvar denote--title-history nil
  "Minibuffer history of `denote--title-prompt'.")

(defun denote--title-prompt (&optional default-title)
  "Read file title for `denote'.

Optional DEFAULT-TITLE is used as the default value."
  (let ((format (if default-title
                    (format "File title [%s]: " default-title)
                  "File title: ")))
    (setq denote-last-title
          (read-string format nil 'denote--title-history default-title))))

(defvar denote--file-type-history nil
  "Minibuffer history of `denote--file-type-prompt'.")

(defun denote--file-type-prompt ()
  "Prompt for `denote-file-type'.
Note that a non-nil value other than `text', `markdown-yaml', and
`markdown-toml' falls back to an Org file type.  We use `org'
here for clarity."
  (completing-read
   "Select file type: " '(org markdown-yaml markdown-toml text) nil t
   nil 'denote--file-type-history))

(defvar denote--date-history nil
  "Minibuffer history of `denote--date-prompt'.")

(defun denote--date-prompt ()
  "Prompt for date."
  (read-string
   "DATE and TIME for note (e.g. 2022-06-16 14:30): "
   nil 'denote--date-history))

(defvar denote--subdir-history nil
  "Minibuffer history of `denote-subdirectory'.")

(defun denote--subdirs-completion-table (dirs)
  "Match DIRS as a completion table."
  (let* ((def (car denote--subdir-history))
         (table (denote--completion-table 'file dirs))
         (prompt (if def
                     (format "Select subdirectory [%s]: " def)
                   "Select subdirectory: ")))
    (completing-read prompt table nil t nil 'denote--subdir-history def)))

(defun denote--subdirs-prompt ()
  "Handle user input on choice of subdirectory."
  (let* ((root (directory-file-name (denote-directory)))
         (subdirs (denote--subdirs))
         (dirs (push root subdirs)))
    (denote--subdirs-completion-table dirs)))

;;;;; Convenience functions

(defalias 'denote-create-note (symbol-function 'denote))

;;;###autoload
(defun denote-type ()
  "Create note while prompting for a file type.

This is the equivalent to calling `denote' when `denote-prompts'
is set to \\='(file-type title keywords)."
  (declare (interactive-only t))
  (interactive)
  (let ((denote-prompts '(file-type title keywords)))
    (call-interactively #'denote)))

(defalias 'denote-create-note-using-type (symbol-function 'denote-type))

;;;###autoload
(defun denote-date ()
  "Create note while prompting for a date.

The date can be in YEAR-MONTH-DAY notation like 2022-06-30 or
that plus the time: 2022-06-16 14:30

This is the equivalent to calling `denote' when `denote-prompts'
is set to \\='(date title keywords)."
  (declare (interactive-only t))
  (interactive)
  (let ((denote-prompts '(date title keywords)))
    (call-interactively #'denote)))

(defalias 'denote-create-note-using-date (symbol-function 'denote-date))

;;;###autoload
(defun denote-subdirectory ()
  "Create note while prompting for a subdirectory.

Available candidates include the value of the variable
`denote-directory' and any subdirectory thereof.

This is equivalent to calling `denote' when `denote-prompts' is set to
\\='(subdirectory title keywords)."
  (declare (interactive-only t))
  (interactive)
  (let ((denote-prompts '(subdirectory title keywords)))
    (call-interactively #'denote)))

(defalias 'denote-create-note-in-subdirectory (symbol-function 'denote-subdirectory))

;;;; Note modification

;;;;; Common helpers for note modifications

(defun denote--filetype-heuristics (file)
  "Return likely file type of FILE.
The return value is for `denote--file-meta-header'."
  (pcase (file-name-extension file)
    ("md" (if-let ((title-key (denote--retrieve-value-title file t))
                   ((string-match-p "title\\s-*=" title-key)))
              'markdown-toml
            'markdown-yaml))
    ("txt" 'text)
    (_ 'org)))

(defun denote--file-attributes-time (file)
  "Return `file-attribute-modification-time' of FILE as identifier."
  (format-time-string
   denote--id-format
   (file-attribute-modification-time (file-attributes file))))

(defun denote--file-name-id (file)
  "Return FILE identifier, else generate one."
  (cond
   ((string-match denote--id-regexp file)
    (substring file (match-beginning 0) (match-end 0)))
   ((denote--file-attributes-time file))
   (t (format-time-string denote--id-format))))

(defun denote-update-dired-buffers ()
  "Update Dired buffers of variable `denote-directory'."
  (mapc
   (lambda (buf)
     (with-current-buffer buf
       (when (and (eq major-mode 'dired-mode)
                  (string-prefix-p (denote-directory)
                                   (expand-file-name default-directory)))
         (revert-buffer))))
   (buffer-list)))

(defun denote--rename-buffer (old-name new-name)
  "Rename OLD-NAME buffer to NEW-NAME, when appropriate."
  (when-let ((buffer (find-buffer-visiting old-name)))
    (with-current-buffer buffer
      (set-visited-file-name new-name nil t))))

(defun denote--rename-file (old-name new-name)
  "Rename file named OLD-NAME to NEW-NAME.
Update Dired buffers if the file is renamed."
  (unless (string= (expand-file-name old-name) (expand-file-name new-name))
    (rename-file old-name new-name nil)
    (denote--rename-buffer old-name new-name)))

(defun denote--add-front-matter (file title keywords id)
  "Prepend front matter to FILE if `denote--only-note-p'.
The TITLE, KEYWORDS and ID are passed from the renaming
command and are used to construct a new front matter block if
appropriate."
  (when-let* (((denote--only-note-p file))
              (filetype (denote--filetype-heuristics file))
              (date (denote--date (date-to-time id)))
              (new-front-matter (denote--file-meta-header title date keywords id filetype)))
    (with-current-buffer (find-file-noselect file)
      (goto-char (point-min))
      (insert new-front-matter))))

(defun denote--file-match-p (regexp file)
  "Return t if REGEXP matches in the FILE."
  (with-current-buffer (find-file-noselect file)
    (save-excursion
      (save-restriction
        (widen)
        (goto-char (point-min))
        (re-search-forward regexp nil t 1)))))

(defun denote--edit-front-matter-p (file)
  "Test if FILE should be subject to front matter rewrite.
This is relevant for `denote--rewrite-front-matter'. We can edit
the front matter if it contains a \"title\" line and a \"tags\"
line (the exact syntax depending on the file type)."
  (when-let ((ext (file-name-extension file)))
    (and (file-regular-p file)
         (file-writable-p file)
         (not (denote--file-empty-p file))
         (string-match-p "\\(md\\|org\\|txt\\)\\'" ext)
         ;; Heuristic to check if this is one of our notes
         (string-prefix-p (denote-directory) (expand-file-name default-directory))
         (denote--file-match-p denote--retrieve-title-front-matter-key-regexp file)
         (denote--file-match-p denote--retrieve-keywords-front-matter-key-regexp file))))

(defun denote--rewrite-keywords (file keywords)
  "Rewrite KEYWORDS in FILE outright.

Do the same as `denote--rewrite-front-matter' for keywords,
but do not ask for confirmation.

This is for use in `denote-dired-rename-marked-files' or related.
Those commands ask for confirmation once before performing an
operation on multiple files."
  (when-let ((old-keywords (denote--retrieve-value-keywords file))
             (new-keywords (denote--file-meta-keywords
                            keywords (denote--filetype-heuristics file))))
    (with-current-buffer (find-file-noselect file)
      (save-excursion
        (save-restriction
          (widen)
          (goto-char (point-min))
          (re-search-forward denote--retrieve-keywords-front-matter-key-regexp nil t 1)
          (search-forward old-keywords nil t 1)
          (replace-match (concat "\\1" new-keywords) t))))))

(defcustom denote-dired-rename-expert nil
  "If t, renaming a file doesn't ask for confirmation.
The confiration is asked via a `y-or-n-p' prompt which shows the
old name followed by the new one.  This applies to the command
`denote-dired-rename-file'."
  :type 'boolean
  :group 'denote-dired)

(make-obsolete 'denote-dired-post-rename-functions nil "0.4.0")

;;;;; The renaming commands and their prompts

(defun denote--rename-dired-file-or-prompt ()
  "Return Dired file at point, else prompt for one.

Throw error is FILE is not regular, else return FILE."
  (or (dired-get-filename nil t)
      (let* ((file (buffer-file-name))
             (format (if file
                         (format "Rename file Denote-style [%s]: " file)
                       "Rename file Denote-style: "))
             (selected-file (read-file-name format nil file t nil)))
        (if (or (file-directory-p selected-file)
                (not (file-regular-p selected-file)))
            (user-error "Only rename regular files")
          selected-file))))

(defun denote--rename-file-prompt (old-name new-name)
  "Prompt to rename file named OLD-NAME to NEW-NAME."
  (unless (string= (expand-file-name old-name) (expand-file-name new-name))
    (y-or-n-p
     (format "Rename %s to %s?"
             (propertize (file-name-nondirectory old-name) 'face 'error)
             (propertize (file-name-nondirectory new-name) 'face 'success)))))

;; FIXME 2022-07-25: We should make the underlying regular expressions
;; that `denote--retrieve-value-title' targets more refined, so that we
;; capture eveyrhing at once.
(defun denote--rewrite-front-matter (file title keywords)
  "Rewrite front matter of note after `denote-dired-rename-file'.
The FILE, TITLE, and KEYWORDS are passed from the renaming
command and are used to construct new front matter values if
appropriate."
  (when-let ((old-title (denote--retrieve-value-title file))
             (old-keywords (denote--retrieve-value-keywords file))
             (new-title title)
             (new-keywords (denote--file-meta-keywords
                            keywords (denote--filetype-heuristics file))))
      (with-current-buffer (find-file-noselect file)
        (when (y-or-n-p (format
                         "Replace front matter?\n-%s\n+%s\n\n-%s\n+%s?"
                         (propertize old-title 'face 'error)
                         (propertize new-title 'face 'success)
                         (propertize old-keywords 'face 'error)
                         (propertize new-keywords 'face 'success)))
          (save-excursion
            (save-restriction
              (widen)
              (goto-char (point-min))
              (re-search-forward denote--retrieve-title-front-matter-key-regexp nil t 1)
              (search-forward old-title nil t 1)
              (replace-match (concat "\\1" new-title) t)
              (goto-char (point-min))
              (re-search-forward denote--retrieve-keywords-front-matter-key-regexp nil t 1)
              (search-forward old-keywords nil t 1)
              (replace-match (concat "\\1" new-keywords) t)))))))

;;;###autoload
(defun denote-rename-file (file title keywords)
  "Rename file and update existing front matter if appropriate.

If in Dired, consider FILE to be the one at point, else prompt
with minibuffer completion for one.

If FILE has a Denote-compliant identifier, retain it while
updating the TITLE and KEYWORDS fields of the file name.  Else
create an identifier based on the file's attribute of last
modification time.  If such attribute cannot be found, the
identifier falls back to the `current-time'.

The default TITLE is retrieved from a line starting with a title
field in the file's contents, depending on the given file type.
Else, the file name is used as a default value at the minibuffer
prompt.

As a final step after the FILE, TITLE, and KEYWORDS prompts, ask
for confirmation, showing the difference between old and new file
names.  If `denote-dired-rename-expert' is non-nil, conduct the
renaming operation outright---no question asked!

The file type extension (e.g. .pdf) is read from the underlying
file and is preserved through the renaming process.  Files that
have no extension are simply left without one.

Renaming only occurs relative to the current directory.  Files
are not moved between directories.

If the FILE has Denote-style front matter for the TITLE and
KEYWORDS, ask to rewrite their values in order to reflect the new
input (this step always requires confirmation and the underlying
buffer is not saved, so consider invoking `diff-buffer-with-file'
to double-check the effect).  The rewrite of the FILE and
KEYWORDS in the front matter should not affect the rest of the
block.

If the file doesn't have front matter, add one at the top of the
file without asking.

Front matter is added only when the file is one of the supported
file types (per `denote-file-type').  For per-file-type front
matter, refer to the variables:

- `denote-org-front-matter'
- `denote-text-front-matter'
- `denote-toml-front-matter'
- `denote-yaml-front-matter'

This command is intended to (i) rename existing Denote notes
while updating their title and keywords in the front matter, (ii)
rename files that can benefit from Denote's file-naming scheme.
The latter is a convenience we provide, since we already have all
the requisite mechanisms in place (though Denote does not---and
will not---manage such files)."
  (interactive
   (let ((file (denote--rename-dired-file-or-prompt)))
     (list
      file
      (denote--title-prompt
       (or (denote--retrieve-value-title file)
           (file-name-sans-extension (file-name-nondirectory file))))
      (denote--keywords-prompt))))
  (let* ((dir (file-name-directory file))
         (id (denote--file-name-id file))
         (extension (file-name-extension file t))
         (new-name (denote--format-file
                    dir id keywords (denote--sluggify title) extension))
         (max-mini-window-height 0.33)) ; allow minibuffer to be resized
    (when (denote--rename-file-prompt file new-name)
      (denote--rename-file file new-name)
      (denote-update-dired-buffers)
      (if (denote--edit-front-matter-p new-name)
          (denote--rewrite-front-matter new-name title keywords)
        (denote--add-front-matter new-name title keywords id)))))

(define-obsolete-function-alias
  'denote-dired-rename-file-and-add-front-matter
  'denote-rename-file
  "0.5.0")

(define-obsolete-function-alias
  'denote-dired-rename-file
  'denote-rename-file
  "0.5.0")

(define-obsolete-function-alias
  'denote-dired-convert-file-to-denote
  'denote-dired-rename-file-and-add-front-matter
  "0.4.0")

;;;###autoload
(defun denote-dired-rename-marked-files ()
  "Rename marked files in Dired to Denote file name.

The operation does the following:

- the file's existing file name is retained and becomes the TITLE
  field, per Denote's file-naming scheme;

- the TITLE is sluggified and downcased, per our conventions;

- an identifier is prepended to the TITLE;

- the file's extension is retained;

- a prompt is asked once for the KEYWORDS field and the input is
  applied to all file names;

- if the file is recognized as a Denote note, add a front matter
  or rewrite it to include the new keywords. A confirmation to
  carry out this step is performed once at the outset. Note that
  the affected buffers are not saved. The user can thus check
  them to confirm that the new front matter does not cause any
  problems (e.g. with the command `diff-buffer-with-file').
  Multiple buffers can be saved with `save-some-buffers' (read
  its doc string). The addition of front matter takes place only
  if the given file has the appropriate file type extension (per
  the user option `denote-file-type')."
  (interactive nil dired-mode)
  (if-let ((marks (dired-get-marked-files))
           (keywords (denote--keywords-prompt))
           ((yes-or-no-p "Add front matter or rewrite front matter of keywords (buffers are not saved)?")))
      (progn
        (dolist (file marks)
          (let* ((dir (file-name-directory file))
                 (id (denote--file-name-id file))
                 (title (or (denote--retrieve-value-title file)
                            (file-name-sans-extension
                             (file-name-nondirectory file))))
                 (extension (file-name-extension file t))
                 (new-name (denote--format-file
                            dir id keywords (denote--sluggify title) extension)))
            (denote--rename-file file new-name)
            (if (denote--edit-front-matter-p new-name)
                (denote--rewrite-keywords new-name keywords)
              (denote--add-front-matter new-name title keywords id))))
        (revert-buffer))
    (user-error "No marked files; aborting")))

(define-obsolete-function-alias
  'denote-dired-rename-marked-files-and-add-front-matter
  'denote-dired-rename-marked-files
  "0.5.0")

;;;; The Denote faces

(defgroup denote-faces ()
  "Faces for Denote."
  :group 'denote)

(defface denote-faces-subdirectory
  '((t :inherit bold))
  "Face for subdirectory of file name.
This should only ever needed in the backlinks' buffer (or
equivalent), not in Dired."
  :group 'denote-faces)

(defface denote-faces-date
  '((t :inherit font-lock-variable-name-face))
  "Face for file name date in Dired buffers.
This is the part of the identifier that covers the year, month,
and day."
  :group 'denote-faces)

(defface denote-faces-time
  '((t :inherit denote-faces-date))
  "Face for file name time in Dired buffers.
This is the part of the identifier that covers the hours, minutes,
and seconds."
  :group 'denote-faces)

(defface denote-faces-title
  '((t ))
  "Face for file name title in Dired buffers."
  :group 'denote-faces)

(defface denote-faces-extension
  '((t :inherit shadow))
  "Face for file extension type in Dired buffers."
  :group 'denote-faces)

(defface denote-faces-keywords
  '((t :inherit font-lock-builtin-face))
  "Face for file name keywords in Dired buffers."
  :group 'denote-faces)

(defface denote-faces-delimiter
  '((((class color) (min-colors 88) (background light))
     :foreground "gray70")
    (((class color) (min-colors 88) (background dark))
     :foreground "gray30")
    (t :inherit shadow))
  "Face for file name delimiters in Dired buffers."
  :group 'denote-faces)

;; For character classes, evaluate: (info "(elisp) Char Classes")
(defvar denote-faces--file-name-regexp
  (concat "\\(?1:[0-9]\\{8\\}\\)\\(?2:T[0-9]\\{6\\}\\)"
          "\\(?:\\(?3:--\\)\\(?4:[[:alnum:][:nonascii:]-]*\\)\\)?"
          "\\(?:\\(?5:__\\)\\(?6:[[:alnum:][:nonascii:]_-]*\\)\\)?"
          "\\(?7:\\..*\\)?$")
  "Regexp of file names for fontification.")

(defconst denote-faces-file-name-keywords
  `((,(concat " " denote-faces--file-name-regexp)
     (1 'denote-faces-date)
     (2 'denote-faces-time)
     (3 'denote-faces-delimiter nil t)
     (4 'denote-faces-title nil t)
     (5 'denote-faces-delimiter nil t)
     (6 'denote-faces-keywords nil t)
     (7 'denote-faces-extension nil t )))
  "Keywords for fontification of file names.")

(defconst denote-faces-file-name-keywords-for-backlinks
  `((,(concat "^\\(?8:.*/\\)?" denote-faces--file-name-regexp)
     (8 'denote-faces-subdirectory nil t)
     (1 'denote-faces-date)
     (2 'denote-faces-time)
     (3 'denote-faces-delimiter nil t)
     (4 'denote-faces-title nil t)
     (5 'denote-faces-delimiter nil t)
     (6 'denote-faces-keywords nil t)
     (7 'denote-faces-extension nil t )))
  "Keywords for fontification of file names in the backlinks buffer.")

;;;; Fontification in Dired

(defgroup denote-dired ()
  "Integration between Denote and Dired."
  :group 'denote)

(defcustom denote-dired-directories
  ;; We use different ways to specify a path for demo purposes.
  (list denote-directory
        ;; (thread-last denote-directory (expand-file-name "attachments"))
        (expand-file-name "~/Documents/vlog"))
  "List of directories where `denote-dired-mode' should apply to."
  :type '(repeat directory)
  :group 'denote-dired)

;;;###autoload
(define-minor-mode denote-dired-mode
  "Fontify all Denote-style file names in Dired."
  :global nil
  :group 'denote-dired
  (if denote-dired-mode
      (font-lock-add-keywords nil denote-faces-file-name-keywords t)
    (font-lock-remove-keywords nil denote-faces-file-name-keywords))
  (font-lock-flush (point-min) (point-max)))

(defun denote-dired--modes-dirs-as-dirs ()
  "Return `denote-dired-directories' as directories.
The intent is to basically make sure that however a path is
written, it is always returned as a directory."
  (mapcar
   (lambda (dir)
     (file-name-as-directory (file-truename dir)))
   denote-dired-directories))

;;;###autoload
(defun denote-dired-mode-in-directories ()
  "Enable `denote-dired-mode' in `denote-dired-directories'.
Add this function to `dired-mode-hook'."
  (when (member (file-truename default-directory) (denote-dired--modes-dirs-as-dirs))
    (denote-dired-mode 1)))

;;;; The linking facility

(defgroup denote-link ()
  "Link facility for Denote."
  :group 'denote)

;;;;; User options

(defcustom denote-link-fontify-backlinks t
  "When non-nil, apply faces to files in the backlinks' buffer."
  :type 'boolean
  :group 'denote-link)

(defcustom denote-link-backlinks-display-buffer-action
  '((display-buffer-reuse-window display-buffer-below-selected)
    (window-height . fit-window-to-buffer))
  "The action used to display the current file's backlinks buffer.

The value has the form (FUNCTION . ALIST), where FUNCTION is
either an \"action function\", a list thereof, or possibly an
empty list.  ALIST is a list of \"action alist\" which may be
omitted (or be empty).

Sample configuration to display the buffer in a side window on
the left of the Emacs frame:

    (setq denote-link-backlinks-display-buffer-action
          (quote ((display-buffer-reuse-window
                   display-buffer-in-side-window)
                  (side . left)
                  (slot . 99)
                  (window-width . 0.3))))

See Info node `(elisp) Displaying Buffers' for more details
and/or the documentation string of `display-buffer'."
  :type '(cons (choice (function :tag "Display Function")
                       (repeat :tag "Display Functions" function))
               alist)
  :group 'denote-link)

;;;;; Link to note

;; Arguments are: FILE-ID FILE-TITLE
(defconst denote-link--format-org "[[denote:%s][%s]]"
  "Format of Org link to note.")

(defconst denote-link--format-markdown "[%2$s](denote:%1$s)"
  "Format of Markdown link to note.")

(defconst denote-link--format-id-only "[[denote:%s]]"
  "Format of identifier-only link to note.")

(defconst denote-link--regexp-org
  (concat "\\[\\[" "denote:"  "\\(?1:" denote--id-regexp "\\)" "]" "\\[.*?]]"))

(defconst denote-link--regexp-markdown
  (concat "\\[.*?]" "(denote:"  "\\(?1:" denote--id-regexp "\\)" ")"))

(defconst denote-link--regexp-plain
  (concat "\\[\\[" "denote:"  "\\(?1:" denote--id-regexp "\\)" "]]"))

(defun denote-link--file-type-format (current-file id-only)
  "Return link format based on CURRENT-FILE format.
With non-nil ID-ONLY, use the generic link format without a
title."
  ;; Includes backup files.  Maybe we can remove them?
  (let ((current-file-ext (file-name-extension current-file)))
    (cond
     (id-only denote-link--format-id-only)
     ((string= current-file-ext "md")
      denote-link--format-markdown)
     ;; Plain text also uses [[denote:ID][TITLE]]
     (t denote-link--format-org))))

(defun denote-link--file-type-regexp (file)
  "Return link regexp based on FILE format."
  (pcase (file-name-extension file)
    ("md" denote-link--regexp-markdown)
    (_ denote-link--regexp-org)))

(defun denote-link--format-link (file pattern)
  "Prepare link to FILE using PATTERN."
  (let ((file-id (denote--retrieve-filename-identifier file))
        (file-title (unless (string= pattern denote-link--format-id-only)
                      (denote--retrieve-value-title file))))
    (format pattern file-id file-title)))

;;;###autoload
(defun denote-link (target &optional id-only)
  "Create link to TARGET note in variable `denote-directory'.
With optional ID-ONLY, such as a universal prefix
argument (\\[universal-argument]), insert links with just the
identifier and no further description.  In this case, the link
format is always [[denote:IDENTIFIER]]."
  (interactive (list (denote--retrieve-read-file-prompt) current-prefix-arg))
  (let ((beg (point)))
    (insert
     (denote-link--format-link
      target
      (denote-link--file-type-format (buffer-file-name) id-only)))
    (unless (derived-mode-p 'org-mode)
      (make-button beg (point) 'type 'denote-link-button))))

(defalias 'denote-link-insert-link (symbol-function 'denote-link))

(defun denote-link--collect-identifiers (regexp)
  "Return collection of identifiers in buffer matching REGEXP."
  (let (matches)
    (save-excursion
      (goto-char (point-min))
      (while (or (re-search-forward regexp nil t)
                 (re-search-forward denote-link--regexp-plain nil t))
        (push (match-string-no-properties 1) matches)))
    matches))

(defun denote-link--expand-identifiers (regexp)
  "Expend identifiers matching REGEXP into file paths."
  (let ((files (denote--directory-files))
        (found-files))
    (dolist (file files)
      (dolist (i (denote-link--collect-identifiers regexp))
        (when (string-prefix-p i (file-name-nondirectory file))
          (push file found-files))))
    found-files))

(defvar denote-link--find-file-history nil
  "History for `denote-link-find-file'.")

(defun denote-link--find-file-prompt (files)
  "Prompt for linked file among FILES."
  (completing-read "Find linked file "
                   (denote--completion-table 'file files)
                   nil t
                   nil 'denote-link--find-file-history))

;; TODO 2022-06-14: Do we need to add any sort of extension to better
;; integrate with Embark?  For the minibuffer interaction it is not
;; necessary, but maybe it can be done to immediately recognise the
;; identifiers are links to files?

;;;###autoload
(defun denote-link-find-file ()
  "Use minibuffer completion to visit linked file."
  (interactive)
  (if-let* ((regexp (denote-link--file-type-regexp (buffer-file-name)))
            (files (denote-link--expand-identifiers regexp)))
      (find-file (denote-link--find-file-prompt files))
    (user-error "No links found in the current buffer")))

;;;;; Link buttons

;; Evaluate: (info "(elisp) Button Properties")
;;
;; Button can provide a help-echo function as well, but I think we might
;; not need it.
(define-button-type 'denote-link-button
  'follow-link t
  'action #'denote-link--find-file-at-button)

(autoload 'thing-at-point-looking-at "thingatpt")

(defun denote-link--link-at-point-string ()
  "Return identifier at point."
  (when (or (thing-at-point-looking-at denote-link--regexp-plain)
            (thing-at-point-looking-at denote-link--regexp-markdown)
            (thing-at-point-looking-at denote-link--regexp-org)
            ;; Meant to handle the case where a link is broken by
            ;; `fill-paragraph' into two lines, in which case it
            ;; buttonizes only the "denote:ID" part.  Example:
            ;;
            ;; [[denote:20220619T175212][This is a
            ;; test]]
            ;;
            ;; Maybe there is a better way?
            (thing-at-point-looking-at "\\[\\(denote:.*\\)]"))
    (match-string-no-properties 0)))

(defun denote-link--id-from-string (string)
  "Extract identifier from STRING."
  (replace-regexp-in-string
   (concat ".*denote:" "\\(" denote--id-regexp "\\)" ".*")
   "\\1" string))

;; NOTE 2022-06-15: I add this as a variable for advanced users who may
;; prefer something else.  If there is demand for it, we can make it a
;; defcustom, but I think it would be premature at this stage.
(defvar denote-link-buton-action #'find-file-other-window
  "Action for Denote buttons.")

(defun denote-link--find-file-at-button (button)
  "Visit file referenced by BUTTON."
  (let* ((id (denote-link--id-from-string
              (buffer-substring-no-properties
               (button-start button)
               (button-end button))))
         (file (denote--get-note-path-by-id id)))
    (funcall denote-link-buton-action file)))

;;;###autoload
(defun denote-link-buttonize-buffer (&optional beg end)
  "Make denote: links actionable buttons in the current buffer.

Add this to `find-file-hook'.  It will only work with Denote
notes and will not do anything in `org-mode' buffers, as buttons
already work there.  If you do not use Markdown or plain text,
then you do not need this.

When called from Lisp, with optional BEG and END as buffer
positions, limit the process to the region in-between."
  (interactive)
  (when (and (not (derived-mode-p 'org-mode)) (denote--current-file-is-note-p))
    (save-excursion
      (goto-char (or beg (point-min)))
      (while (re-search-forward denote--id-regexp end t)
        (when-let ((string (denote-link--link-at-point-string))
                   (beg (match-beginning 0))
                   (end (match-end 0)))
          (make-button beg end 'type 'denote-link-button))))))

;;;;; Backlinks' buffer

(define-button-type 'denote-link-backlink-button
  'follow-link t
  'action #'denote-link--backlink-find-file
  'face nil)            ; we use this face though we style it later

(defun denote-link--backlink-find-file (button)
  "Action for BUTTON to `find-file'."
  (funcall denote-link-buton-action (buffer-substring (button-start button) (button-end button))))

(defun denote-link--display-buffer (buf)
  "Run `display-buffer' on BUF.
Expand `denote-link-backlinks-display-buffer-action'."
  (display-buffer
   buf
   `(,@denote-link-backlinks-display-buffer-action)))

(defun denote-link--prepare-backlinks (id files &optional title)
  "Create backlinks' buffer for ID including FILES.
Use optional TITLE for a prettier heading."
  (let ((inhibit-read-only t)
        (buf (format "*denote-backlinks to %s*" id)))
    (with-current-buffer (get-buffer-create buf)
      (erase-buffer)
      (special-mode)
      (goto-char (point-min))
      (when-let* ((title)
                  (heading (format "Backlinks to %S (%s)" title id))
                  (l (length heading)))
        (insert (format "%s\n%s\n\n" heading (make-string l ?-))))
      (mapc (lambda (f)
              (insert f)
              (make-button (point-at-bol) (point-at-eol) :type 'denote-link-backlink-button)
              (newline))
            files)
      (goto-char (point-min))
      (when denote-link-fontify-backlinks
        (font-lock-add-keywords nil denote-faces-file-name-keywords-for-backlinks t)))
    (denote-link--display-buffer buf)))

;;;###autoload
(defun denote-link-backlinks ()
  "Produce a buffer with files linking to current note.
Each file is a clickable/actionable button that visits the
referenced entry.  Files are fontified if the user option
`denote-link-fontify-backlinks' is non-nil.

The placement of the backlinks' buffer is controlled by the user
option `denote-link-backlinks-display-buffer-action'.  By
default, it will show up below the current window."
  (interactive)
  (let* ((default-directory (denote-directory))
         (file (buffer-file-name))
         (id (denote--retrieve-filename-identifier file))
         (title (denote--retrieve-value-title file)))
    (if-let ((files (denote--retrieve-proces-grep id)))
        (denote-link--prepare-backlinks id files title)
      (user-error "No links to the current note"))))

(defalias 'denote-link-show-backlinks-buffer (symbol-function 'denote-link-backlinks))

;;;;; Add links matching regexp

(defvar denote-link--links-to-files nil
  "String of `denote-link-add-links-matching-keyword'.")

(defvar denote-link--prepare-links-format "- %s\n"
  "Format specifiers for `denote-link-add-links'.")

;; NOTE 2022-06-16: There is no need to overwhelm the user with options,
;; though I expect someone to want to change the sort order.
(defvar denote-link-add-links-sort nil
  "Add REVERSE to `sort-lines' of `denote-link-add-links' when t.")

(defun denote-link--prepare-links (files current-file id-only)
  "Prepare links to FILES from CURRENT-FILE.
When ID-ONLY is non-nil, use a generic link format.  See
`denote-link--file-type-format'."
  (setq denote-link--links-to-files
        (with-temp-buffer
          (mapc (lambda (file)
                  (insert
                   (format
                    denote-link--prepare-links-format
                    (denote-link--format-link
                     file
                     (denote-link--file-type-format current-file id-only)))))
                files)
          (sort-lines denote-link-add-links-sort (point-min) (point-max))
          (buffer-string))))

(defvar denote-link--add-links-history nil
  "Minibuffer history for `denote-link-add-links'.")

;;;###autoload
(defun denote-link-add-links (regexp &optional id-only)
  "Insert links to all notes matching REGEXP.
Use this command to reference multiple files at once.
Particularly useful for the creation of metanotes (read the
manual for more on the matter).

Optional ID-ONLY has the same meaning as in `denote-link': it
inserts links with just the identifier."
  (interactive
   (list
    (read-regexp "Insert links matching REGEX: " nil 'denote-link--add-links-history)
    current-prefix-arg))
  (let* ((default-directory (denote-directory))
         (current-file (buffer-file-name)))
    (if-let ((files (denote--directory-files-matching-regexp regexp)))
        (let ((beg (point)))
          (insert (denote-link--prepare-links files current-file id-only))
          (unless (derived-mode-p 'org-mode)
            (denote-link-buttonize-buffer beg (point))))
      (user-error "No links matching `%s'" regexp))))

(defalias 'denote-link-insert-links-matching-regexp (symbol-function 'denote-link-add-links))

;;;;; Links from Dired marks

;; NOTE 2022-07-21: I don't think we need a history for this one.
(defun denote-link--buffer-prompt (buffers)
  "Select buffer from BUFFERS visiting Denote notes."
  (completing-read
   "Select note buffer: "
   (denote--completion-table 'buffer buffers)
   nil t))

(declare-function dired-get-marked-files "dired" (&optional localp arg filter distinguish-one-marked error))

(defun denote-link--map-over-notes ()
  "Return list of `denote--only-note-p' from Dired marked items."
  (delq nil
        (mapcar
	     (lambda (f)
           (when (and (denote--only-note-p f)
                      (denote--dir-in-denote-directory-p default-directory))
             f))
         (dired-get-marked-files))))

;;;###autoload
(defun denote-link-dired-marked-notes (files buffer &optional id-only)
  "Insert Dired marked FILES as links in BUFFER.

FILES are Denote notes, meaning that they have our file-naming
scheme, are writable/regular files, and use the appropriate file
type extension (per `denote-file-type').  Furthermore, the marked
files need to be inside the variable `denote-directory' or one of
its subdirectories.  No other file is recognised (the list of
marked files ignores whatever does not count as a note for our
purposes).

The BUFFER is one which visits a Denote note file.  If there are
multiple buffers, prompt with completion for one among them.  If
there isn't one, throw an error.

With optional ID-ONLY as a prefix argument, insert links with
just the identifier (same principle as with `denote-link').

This command is meant to be used from a Dired buffer."
  (interactive
   (list
    (denote-link--map-over-notes)
    (let ((buffers (denote--buffer-file-names)))
      (get-buffer
       (cond
        ((null buffers)
         (user-error "No buffers visiting Denote notes"))
        ((eq (length buffers) 1)
         (car buffers))
        (t
         (denote-link--buffer-prompt buffers)))))
    current-prefix-arg)
   dired-mode)
  (if (null files)
      (user-error "No note files to link to")
    (when (y-or-n-p (format "Create links at point in %s?" buffer))
      (with-current-buffer buffer
        (insert (denote-link--prepare-links files (buffer-file-name) id-only))
        (denote-link-buttonize-buffer)))))

;;;;; Register `denote:' custom Org hyperlink

(declare-function org-link-open-as-file "ol" (path arg))

(defun denote-link--ol-resolve-link-to-target (link &optional path-id)
  "Resolve LINK into the appropriate target.
With optional PATH-ID return a cons cell consisting of the path
and the identifier."
  (let* ((search (and (string-match "::\\(.*\\)\\'" link)
                      (match-string 1 link)))
         (id (if (and (stringp search) (not (string-empty-p search)))
                 (substring link 0 (match-beginning 0))
               link))
         (path (denote--get-note-path-by-id id)))
    (cond
     (path-id
      (cons (format "%s" path) (format "%s" id)))
     ((and (stringp search) (not (string-empty-p search)))
      (concat path "::" search))
     (path))))

(defun denote-link-ol-follow (link)
  "Find file of type `denote:' matching LINK.
LINK is the identifier of the note, optionally followed by a
search option akin to that of standard Org `file:' link types.
Read Info node `(org) Search Options'.

Uses the function `denote-directory' to establish the path to the
file."
  (org-link-open-as-file
   (denote-link--ol-resolve-link-to-target link)
   nil))

(defun denote-link-ol-complete ()
  "Like `denote-link' but for Org integration.
This lets the user complete a link through the `org-insert-link'
interface by first selecting the `denote:' hyperlink type."
  (concat
   "denote:"
   (denote--retrieve-filename-identifier (denote--retrieve-read-file-prompt))))

(defun denote-link-ol-export (link description format)
  "Export a `denote:' link from Org files.
The LINK, DESCRIPTION, and FORMAT are handled by the export
backend."
  (let* ((path-id (denote-link--ol-resolve-link-to-target link :path-id))
         (path (file-name-nondirectory (car path-id)))
         (p (file-name-sans-extension path))
         (id (cdr path-id))
         (desc (or description (concat "denote:" id))))
    (cond
     ((eq format 'html) (format "<a target=\"_blank\" href=\"%s.html\">%s</a>" p desc))
     ((eq format 'latex) (format "\\href{%s}{%s}" (replace-regexp-in-string "[\\{}$%&_#~^]" "\\\\\\&" path) desc))
     ((eq format 'texinfo) (format "@uref{%s,%s}" path desc))
     ((eq format 'ascii) (format "[%s] <denote:%s>" desc path)) ; NOTE 2022-06-16: May be tweaked further
     ((eq format 'md) (format "[%s](%s.md)" desc p))
     (t path))))

;; The `eval-after-load' part with the quoted lambda is adapted from
;; Elfeed: <https://github.com/skeeto/elfeed/>.

;;;###autoload
(eval-after-load 'org
  `(funcall
    ;; The extra quote below is necessary because uncompiled closures
    ;; do not evaluate to themselves. The quote is harmless for
    ;; byte-compiled function objects.
    ',(lambda ()
        (with-no-warnings
          (org-link-set-parameters
           "denote"
           :follow #'denote-link-ol-follow
           :complete #'denote-link-ol-complete
           :export #'denote-link-ol-export)))))

;;;; Glue code for org-capture

(defgroup denote-org-capture ()
  "Integration between Denote and Org Capture."
  :group 'denote)

(defcustom denote-org-capture-specifiers "%l\n%i\n%?"
  "String with format specifiers for `org-capture-templates'.
Check that variable's documentation for the details.

The string can include arbitrary text.  It is appended to new
notes via the `denote-org-capture' function.  Every new note has
the standard front matter we define."
  :type 'string
  :group 'denote-org-capture)

;;;###autoload
(defun denote-org-capture ()
  "Create new note through `org-capture-templates'.
Use this as a function that returns the path to the new file.
The file is populated with Denote's front matter.  It can then be
expanded with the usual specifiers or strings that
`org-capture-templates' supports.

Note that this function ignores the `denote-file-type': it always
sets the Org file extension for the created note to ensure that
the capture process works as intended, especially for the desired
output of the `denote-org-capture-specifiers' (which can include
arbitrary text).

Consult the manual for template samples."
  (let ((title (denote--title-prompt))
        (keywords (denote--keywords-prompt))
        (denote-file-type nil)) ; we enforce the .org extension for `org-capture'
    (denote--path title keywords)
    (setq denote-last-front-matter (denote--file-meta-header
                                    title (denote--date nil) keywords
                                    (format-time-string denote--id-format nil)))
    (denote--keywords-add-to-history denote-last-keywords)
    (concat denote-last-front-matter denote-org-capture-specifiers)))

(defun denote-org-capture-delete-empty-file ()
  "Delete file if capture with `denote-org-capture' is aborted."
  (when-let* ((file denote-last-path)
              ((denote--file-empty-p file)))
    (delete-file denote-last-path)))

(add-hook 'org-capture-after-finalize-hook #'denote-org-capture-delete-empty-file)

(provide 'denote)
;;; denote.el ends here
