(define-module (fontutils)
  #:use-module (gnu packages)
  #:use-module (gnu packages autotools)
  #:use-module (gnu packages bash)
  #:use-module (gnu packages bison)
  #:use-module (gnu packages check)
  #:use-module (gnu packages compression)
  #:use-module (gnu packages datastructures)
  #:use-module (gnu packages docbook)
  #:use-module (gnu packages flex)
  #:use-module (gnu packages fonts)
  #:use-module (gnu packages freedesktop)
  #:use-module (gnu packages fribidi)
  #:use-module (gnu packages gcc)
  #:use-module (gnu packages gettext)
  #:use-module (gnu packages ghostscript)
  #:use-module (gnu packages glib)
  #:use-module (gnu packages gnome)
  #:use-module (gnu packages gperf)
  #:use-module (gnu packages graphics)
  #:use-module (gnu packages gtk)
  #:use-module (gnu packages image)
  #:use-module (gnu packages java)
  #:use-module (gnu packages linux)
  #:use-module (gnu packages man)
  #:use-module (gnu packages mc)
  #:use-module (gnu packages ninja)
  #:use-module (gnu packages perl)
  #:use-module (gnu packages pkg-config)
  #:use-module (gnu packages python)
  #:use-module (gnu packages python-build)
  #:use-module (gnu packages python-xyz)
  #:use-module (gnu packages qt)
  #:use-module (gnu packages sqlite)
  #:use-module (gnu packages webkit)
  #:use-module (gnu packages xdisorg)
  #:use-module (gnu packages xml)
  #:use-module (gnu packages xorg)
  #:use-module (gnu packages tex)
  #:use-module (gnu packages textutils)
  #:use-module (gnu packages fontutils)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (guix gexp)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix svn-download)
  #:use-module (guix git-download)
  #:use-module (guix build-system copy)
  #:use-module (guix build-system cmake)
  #:use-module (guix build-system gnu)
  #:use-module (guix build-system meson)
  #:use-module (guix build-system pyproject)
  #:use-module (guix build-system python)
  #:use-module (guix utils)
  #:use-module (srfi srfi-1))

(define-public fontconfig
  (hidden-package
   (package
     (name "fontconfig-minimal")
     (version "2.16.1")
     (source
      (origin
        (method git-fetch)
        (uri (git-reference
              (url "https://gitlab.freedesktop.org/fontconfig/fontconfig.git")
              (commit version)))
        (file-name (git-file-name name version))
        (sha256
         (base32 "1jys54w1dsj1pklrpbxssdlryffvgahfjpgzmd8cnw0z2kjazjjz"))
        ;; (patches (search-patches "fontconfig-cache-ignore-mtime.patch"))
        ))
     (build-system gnu-build-system)
     ;; In Requires or Requires.private of fontconfig.pc.
     (propagated-inputs
      (list expat
            freetype
            `(,util-linux "lib")))
     (inputs
      ;; We used to use 'font-ghostscript' but they are not recognized by newer
      ;; versions of Pango, causing many applications to fail to find fonts
      ;; otherwise.
      (list font-dejavu
            libtool
            gnu-gettext
            autoconf-2.71
            automake))
     (native-inputs
      (list gperf
            pkg-config
            python-minimal)) ;to avoid a cycle through tk
     (arguments
      (list
       #:configure-flags
       #~(list "--disable-docs" "--with-cache-dir=/var/cache/fontconfig"
               ;; register the default fonts
               (string-append "--with-default-fonts="
                              (assoc-ref %build-inputs "font-dejavu")
                              "/share/fonts"))
       #:phases
       #~(modify-phases %standard-phases
           (add-before 'check 'skip-problematic-tests
             (lambda _
               ;; SOURCE_DATE_EPOCH doesn't make sense when ignoring mtime
               (unsetenv "SOURCE_DATE_EPOCH")
               (substitute* "test/run-test.sh"
                 ;; The crbug1004254 test attempts to fetch fonts from the
                 ;; network.
                 (("\\[ -x \"\\$BUILDTESTDIR\"/test-crbug1004254 \\]")
                  "false"))))
           (replace 'install
             (lambda _
               ;; Don't try to create /var/cache/fontconfig.
               (invoke "make" "install" "fc_cachedir=$(TMPDIR)"
                       "RUN_FC_CACHE_TEST=false"))))))
     (synopsis "Library for configuring and customizing font access")
     (description
      "Fontconfig can discover new fonts when installed automatically;
perform font name substitution, so that appropriate alternative fonts can
be selected if fonts are missing;
identify the set of fonts required to completely cover a set of languages;
have GUI configuration tools built as it uses an XML-based configuration file;
efficiently and quickly find needed fonts among the set of installed fonts;
be used in concert with the X Render Extension and FreeType to implement
high quality, anti-aliased and subpixel rendered text on a display.")
     ;; The exact license is more X11-style than BSD-style.
     (license (license:non-copyleft "file://COPYING"
                                    "See COPYING in the distribution."))
     (native-search-paths
      ;; Since version 2.13.94, fontconfig knows to find fonts from
      ;; XDG_DATA_DIRS.
      (list (search-path-specification
             (variable "XDG_DATA_DIRS")
             (files '("share")))))
     (home-page "https://www.freedesktop.org/wiki/Software/fontconfig/"))))

;;; The documentation of fontconfig is built in a separate package, as it
;;; causes a dramatic increase in the size of the closure of fontconfig.  This
;;; is intentionally named 'fontconfig', as it's intended as the user-facing
;;; fontconfig package.
(define-public fontconfig-with-documentation
  (package
    (inherit fontconfig)
    (name "fontconfig")
    (outputs (cons "doc" (package-outputs fontconfig)))
    (arguments
     (substitute-keyword-arguments (package-arguments fontconfig)
       ((#:configure-flags configure-flags)
        #~(delete "--disable-docs"
                  #$configure-flags))
       ((#:phases phases
         #~%standard-phases)
        #~(modify-phases #$phases
            (add-after 'unpack 'no-pdf-doc
              (lambda _
                ;; Don't build documentation as PDF.
                (substitute* "doc/Makefile.am"
                  (("^PDF_FILES = .*")
                   "PDF_FILES =\n"))))
            (add-after 'install 'move-man-sections
              (lambda* (#:key outputs #:allow-other-keys)
                ;; Move share/man/man{3,5} to the "doc" output.  Leave "man1" in
                ;; "out" for convenience.
                (let ((out (assoc-ref outputs "out"))
                      (doc (assoc-ref outputs "doc")))
                  (for-each (lambda (section)
                              (let ((source (string-append out "/share/man/"
                                                           section))
                                    (target (string-append doc "/share/man/"
                                                           section)))
                                (copy-recursively source target)
                                (delete-file-recursively source)))
                            '("man3" "man5")))))))))
    (native-inputs
     (append (package-native-inputs fontconfig)
             `(("docbook-utils" ,docbook-utils))))
    (properties (alist-delete 'hidden? (package-properties fontconfig)))))

;; ;;; Below are using tarball
;; (define-public fontconfig
;;   (hidden-package
;;    (package
;;      (name "fontconfig-minimal")
;;      (version "2.16.0")
;;      (source (origin
;;                (method url-fetch)
;;                (uri (string-append
;;                      "https://www.freedesktop.org/software/"
;;                      "fontconfig/release/fontconfig-" version ".tar.xz"))
;;                (sha256 (base32
;;                         "086jdsdxmc9ryr0n0dmgs0vfnkhkxxw5hsgpr888pfn9biaxqcva"))
;;                (patches (search-patches "fontconfig-cache-ignore-mtime.patch"))))
;;      (build-system gnu-build-system)
;;      ;; In Requires or Requires.private of fontconfig.pc.
;;      (propagated-inputs
;;       (list expat
;;             freetype
;;             `(,util-linux "lib")))
;;      (inputs
;;       ;; We used to use 'font-ghostscript' but they are not recognized by newer
;;       ;; versions of Pango, causing many applications to fail to find fonts
;;       ;; otherwise.
;;       (list font-dejavu))
;;      (native-inputs
;;       (list gperf
;;             pkg-config
;;             python-minimal)) ;to avoid a cycle through tk
;;      (arguments
;;       (list
;;        #:configure-flags
;;        #~(list "--disable-docs" "--with-cache-dir=/var/cache/fontconfig"
;;                ;; register the default fonts
;;                (string-append "--with-default-fonts="
;;                               (assoc-ref %build-inputs "font-dejavu")
;;                               "/share/fonts"))
;;        #:phases
;;        #~(modify-phases %standard-phases
;;            (add-before 'check 'skip-problematic-tests
;;              (lambda _
;;                ;; SOURCE_DATE_EPOCH doesn't make sense when ignoring mtime
;;                (unsetenv "SOURCE_DATE_EPOCH")
;;                (substitute* "test/run-test.sh"
;;                  ;; The crbug1004254 test attempts to fetch fonts from the network.
;;                  (("\\[ -x \"\\$BUILDTESTDIR\"/test-crbug1004254 \\]")
;;                   "false"))))
;;            (replace 'install
;;              (lambda _
;;                ;; Don't try to create /var/cache/fontconfig.
;;                (invoke "make" "install" "fc_cachedir=$(TMPDIR)"
;;                        "RUN_FC_CACHE_TEST=false"))))))
;;      (synopsis "Library for configuring and customizing font access")
;;      (description
;;       "Fontconfig can discover new fonts when installed automatically;
;; perform font name substitution, so that appropriate alternative fonts can
;; be selected if fonts are missing;
;; identify the set of fonts required to completely cover a set of languages;
;; have GUI configuration tools built as it uses an XML-based configuration file;
;; efficiently and quickly find needed fonts among the set of installed fonts;
;; be used in concert with the X Render Extension and FreeType to implement
;; high quality, anti-aliased and subpixel rendered text on a display.")
;;      ;; The exact license is more X11-style than BSD-style.
;;      (license (license:non-copyleft "file://COPYING"
;;                                     "See COPYING in the distribution."))
;;      (native-search-paths
;;       ;; Since version 2.13.94, fontconfig knows to find fonts from
;;       ;; XDG_DATA_DIRS.
;;       (list (search-path-specification
;;              (variable "XDG_DATA_DIRS")
;;              (files '("share")))))
;;      (home-page "https://www.freedesktop.org/wiki/Software/fontconfig/"))))

;; ;;; The documentation of fontconfig is built in a separate package, as it
;; ;;; causes a dramatic increase in the size of the closure of fontconfig.  This
;; ;;; is intentionally named 'fontconfig', as it's intended as the user-facing
;; ;;; fontconfig package.
;; (define-public fontconfig-with-documentation
;;   (package
;;     (inherit fontconfig)
;;     (name "fontconfig")
;;     (outputs (cons "doc" (package-outputs fontconfig)))
;;     (arguments
;;      (substitute-keyword-arguments (package-arguments fontconfig)
;;        ((#:configure-flags configure-flags)
;;         `(delete "--disable-docs" ,configure-flags))
;;        ((#:phases phases '%standard-phases)
;;         `(modify-phases ,phases
;;            (add-after 'unpack 'no-pdf-doc
;;              (lambda _
;;                ;; Don't build documentation as PDF.
;;                (substitute* "doc/Makefile.in"
;;                  (("^PDF_FILES = .*")
;;                   "PDF_FILES =\n"))))
;;            (add-after 'install 'move-man-sections
;;              (lambda* (#:key outputs #:allow-other-keys)
;;                ;; Move share/man/man{3,5} to the "doc" output.  Leave "man1" in
;;                ;; "out" for convenience.
;;                (let ((out (assoc-ref outputs "out"))
;;                      (doc (assoc-ref outputs "doc")))
;;                  (for-each (lambda (section)
;;                              (let ((source (string-append out "/share/man/"
;;                                                           section))
;;                                    (target (string-append doc "/share/man/"
;;                                                           section)))
;;                                (copy-recursively source target)
;;                                (delete-file-recursively source)))
;;                            '("man3" "man5")))))))))
;;     (native-inputs
;;      (append (package-native-inputs fontconfig)
;;              `(("docbook-utils" ,docbook-utils))))
;;     (properties (alist-delete 'hidden? (package-properties fontconfig)))))
