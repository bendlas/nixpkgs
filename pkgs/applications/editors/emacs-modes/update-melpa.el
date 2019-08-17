;; -*- lexical-binding: t -*-

;; This is the updater for recipes-archive-melpa.json

(require 'aio)
(require 'url)
(require 'json)
(require 'cl)
(require 'subr-x)
(require 'seq)

;; # Lib

(defun alist-set (key value alist)
  (cons
   (cons key value)
   (assq-delete-all
    key alist)))

(defun alist-update (key f alist)
  (let ((value (alist-get key alist)))
    (cons
     (cons key (funcall f value))
     (assq-delete-all
      key alist))))

(aio-defun updater--aio-all (lst)
  (cl-loop for x in lst collect (aio-await x)))

(defun updater--make-process (program &rest args) 
  "Generate an asynchronous process and return Promise to resolve
with (stdout stderr) on success and with (event stdout stderr) on error."
  (let* ((promise (aio-promise))
         (stdout (generate-new-buffer (concat "*" program "-stdout*")))
         (stderr (generate-new-buffer (concat "*" program "-stderr*")))
         (stderr-pipe (make-pipe-process
                       :name (concat "*" program "-stderr-pipe*")
                       :noquery t
                       ;; use :filter instead of :buffer, to get rid of "Process Finished" lines
                       :filter (lambda (_ output)
                                 (with-current-buffer stderr
                                   (insert output)))))
         (cleanup (lambda ()
                    (delete-process stderr-pipe)
                    (kill-buffer stdout)
                    (kill-buffer stderr))))
    (condition-case err
        (make-process :name program
                      :buffer stdout
                      :command (cons program args)
                      :stderr stderr-pipe
                      :sentinel (lambda (process event)
                                  (unwind-protect
                                      (let ((stderr-str (with-current-buffer stderr (buffer-string)))
                                            (stdout-str (with-current-buffer stdout (buffer-string))))
                                        (if (string= event "finished\n")
                                            (aio-resolve promise (lambda () (list stdout-str stderr-str)))
                                          (aio-resolve promise (lambda () (error event stdout-str stderr-str)))))
                                    (funcall cleanup))))
      (error (funcall cleanup)
             (aio-resolve promise (lambda () (signal (car err) (cdr err))))))
    promise))

(aio-defun updater--semaphore-promise (semaphore resolver)
  "Create a promise based on handler, like aio-promise + aio-resolve, but
   acquire and release the semaphore around resolving the
   handler (+ result promises)."
  (aio-sem-wait semaphore)
  (unwind-protect
      (resolver)
    (aio-sem-post semaphore)))

(aio-defun updater--process-promise (semaphore program &rest args)
  "Generate an asynchronous process and
return Promise to resolve in that process."
  (aio-sem-wait semaphore)
  (unwind-protect
      (car (aio-await (apply updater--make-process program args)))
    (aio-sem-post semaphore)))

(defun updater--maybe-message (msg)
  "Display message if non-blank"
  (let ((m (string-trim-right msg)))
    (when (not (string-empty-p m))
      (message "%s" m))))

(aio-defun updater--make-process-string (program &rest args)
  "Generate an asynchronous process and return Promise to resolve
with stdout on success and with event on error."
  (condition-case err
      (seq-let (stdout stderr) (aio-await (apply #'updater--make-process program args))
        (updater--maybe-message (propertize stderr 'face '(:foreground "yellow")))
        stdout)
    (error (seq-let (event stdout stderr) err
             (updater--maybe-message (propertize stdout 'face '(:foreground "black" :background "white")))
             (updater--maybe-message (propertize stderr 'face '(:foreground "red")))
             (signal (car err) (cdr err))))))

(defun updater--make-shell-command (script)
  "Run script in shell and return"
  (updater--make-process-string shell-file-name shell-command-switch script))

(defun mangle-name (s)
  (if (string-match "^[a-zA-Z].*" s)
      s
    (concat "_" s)))

;; ## Shell promise + env

(defun as-string (o)
  (with-output-to-string (princ o)))

(defun assocenv (env &rest namevals)
  (let ((process-environment (copy-sequence env)))
    (mapc (lambda (e)
            (setenv (as-string (car e))
                    (cadr e)))
          (seq-partition namevals 2))
    process-environment))

(aio-defun updater--shell-promise (semaphore env script)
  (when semaphore (aio-sem-wait semaphore))
  (unwind-protect
      (aio-await (let ((process-environment env))
                   (updater--make-shell-command script)))
    (when semaphore (aio-sem-post semaphore))))

;; # Updater

;; ## Previous Archive Reader

(defun previous-commit (index ename variant)
  (when-let (pdesc (and index (gethash ename index)))
    (when-let (desc (and pdesc (gethash variant pdesc)))
      (gethash 'commit desc))))

(defun previous-sha256 (index ename variant)
  (when-let (pdesc (and index (gethash ename index)))
    (when-let (desc (and pdesc (gethash variant pdesc)))
      (gethash 'sha256 desc))))

(defun parse-previous-archive (filename)
  (let ((idx (make-hash-table :test 'equal)))
    (loop for desc in
          (let ((json-object-type 'hash-table)
                (json-array-type 'list)
                (json-key-type 'symbol))
            (json-read-file filename))
          do (puthash (gethash 'ename desc)
                      desc idx))
    idx))

;; ## Prefetcher

;; (defun latest-git-revision (url)
;;   (updater--process-promise "git" "ls-remote" url))

(aio-defun prefetch (semaphore fetcher repo commit)
  (let ((res (aio-await
              (apply 'updater--process-promise
                     semaphore
                     (pcase fetcher
                       ("github"    (list "nix-prefetch-url"
                                          "--unpack" (concat "https://github.com/" repo "/archive/" commit ".tar.gz")))
                       ("gitlab"    (list "nix-prefetch-url"
                                          "--unpack" (concat "https://gitlab.com/" repo "/repository/archive.tar.gz?ref=" commit)))
                       ("bitbucket" (list "nix-prefetch-hg"
                                          (concat "https://bitbucket.com/" repo) commit))
                       ("hg"        (list "nix-prefetch-hg"
                                          repo commit))
                       ("git"       (list "nix-prefetch-git"
                                          "--fetch-submodules"
                                          "--url" repo
                                          "--rev" commit))
                       (_           (throw 'unknown-fetcher fetcher)))))))
    (pcase fetcher
      ("git" (alist-get 'sha256 (json-read-from-string res)))
      (_ (car (split-string res))))))

(aio-defun source-sha (semaphore ename eprops aprops previous variant)
  (let* ((fetcher (alist-get 'fetcher eprops))
         (url     (alist-get 'url eprops))
         (repo    (alist-get 'repo eprops))
         (commit  (gethash 'commit aprops))
         (prev-commit (previous-commit previous ename variant))
         (prev-sha256 (previous-sha256 previous ename variant)))
    (if (and commit prev-sha256
             (equal prev-commit commit))
        (progn
          (message "INFO: %s: re-using %s %s" ename prev-commit prev-sha256)
          `((sha256 . ,prev-sha256)))
      (if (and commit (or repo url))
          (condition-case err
              (let ((sha256 (aio-await (prefetch semaphore fetcher (or repo url) commit))))
                (message "INFO: %s: prefetched repository %s %s" ename commit sha256)
                `((sha256 . ,sha256)))
            (error
             (message "ERROR: %s: during prefetch %s" ename err)
             `((error . ,err))))
        (progn
          (message "ERROR: %s: no commit information" ename)
          `((error . "No commit information")))))))

(defun source-info (recipe archive source-sha)
  (let* ((esym    (car recipe))
         (ename   (symbol-name esym))
         (eprops  (cdr recipe))
         (aentry  (gethash esym archive))
         (version (and aentry (gethash 'ver aentry)))
         (deps    (when-let (deps (gethash 'deps aentry))
                    (remove 'emacs (hash-table-keys deps))))
         (aprops  (and aentry (gethash 'props aentry)))
         (commit  (gethash 'commit aprops)))
    (append `((version . ,version))
            (when (< 0 (length deps))
              `((deps . ,(sort deps 'string<))))
            `((commit . ,commit))
            source-sha)))

(defun recipe-info (recipe-index ename)
  (if-let (desc (gethash ename recipe-index))
      (destructuring-bind (rcp-commit . rcp-sha256) desc
        `((commit . ,rcp-commit)
          (sha256 . ,rcp-sha256)))
    `((error . "No recipe info"))))

(defun start-fetch (semaphore recipe-index-promise recipes unstable-archive stable-archive previous)
  (updater--aio-all
   (mapcar (aio-lambda (entry)
             (let* ((esym    (car entry))
                    (ename   (symbol-name esym))
                    (eprops  (cdr entry))
                    (fetcher (alist-get 'fetcher eprops))
                    (url     (alist-get 'url eprops))
                    (repo    (alist-get 'repo eprops))

                    (unstable-aentry  (gethash esym unstable-archive))
                    (unstable-aprops  (and unstable-aentry (gethash 'props unstable-aentry)))
                    (unstable-commit  (and unstable-aprops (gethash 'commit unstable-aprops)))

                    (stable-aentry (gethash esym stable-archive))
                    (stable-aprops (and stable-aentry (gethash 'props stable-aentry)))
                    (stable-commit  (and stable-aprops (gethash 'commit stable-aprops)))

                    (unstable-shap (when unstable-aprops
                                     (aio-await (source-sha semaphore ename eprops unstable-aprops previous 'unstable))))
                    (stable-shap (if (equal unstable-commit stable-commit)
                                     unstable-shap
                                   (when stable-aprops
                                     (aio-await (source-sha semaphore ename eprops stable-aprops previous 'stable))))))
               (seq-let [recipe-index unstable-sha stable-sha]
                   (aio-await (updater--aio-all (list recipe-index-promise unstable-shap stable-shap)))
                 (append `((ename   . ,ename))
                         (if-let (desc (gethash ename recipe-index))
                             (destructuring-bind (rcp-commit . rcp-sha256) desc
                                                 (append `((commit . ,rcp-commit)
                                                           (sha256 . ,rcp-sha256))
                                                         (when (not unstable-aprops)
                                                           (message "ERROR: %s: not in archive" ename)
                                                           `((error . "Not in archive")))))
                           `((error . "No recipe info")))
                         `((fetcher . ,fetcher))
                         (if (or (equal "github" fetcher)
                                 (equal "bitbucket" fetcher)
                                 (equal "gitlab" fetcher))
                             `((repo . ,repo))
                           `((url . ,url)))
                         (when unstable-aprops `((unstable . ,(source-info entry unstable-archive unstable-sha))))
                         (when stable-aprops `((stable . ,(source-info entry stable-archive stable-sha))))))))
           recipes)))

;; ## Emitter

(aio-defun emit-json (prefetch-semaphore recipe-index-promise recipes archive stable-archive previous)
  (let ((descriptors (aio-await (start-fetch
                                 prefetch-semaphore
                                 recipe-index-promise
                                 (sort recipes (lambda (a b)
                                                 (string-lessp
                                                  (symbol-name (car a))
                                                  (symbol-name (car b)))))
                                 archive stable-archive
                                 previous))))
    (message "Finished downloading %d descriptors" (length descriptors))
    (let ((buf (generate-new-buffer "*recipes-archive*")))
      (with-current-buffer buf
        ;; (switch-to-buffer buf)
        ;; (json-mode)
        (insert
         (let ((json-encoding-pretty-print t)
               (json-encoding-default-indentation " "))
           (json-encode descriptors)))
        buf))))

;; ## Recipe indexer

(defun http-get (url parser)
  (let ((promise (aio-promise)))
    (url-retrieve
     url (lambda (status)
           (aio-resolve promise (lambda ()
                                  (goto-char (point-min))
                                  (search-forward "\n\n")
                                  (message (buffer-substring (point-min) (point)))
                                  (delete-region (point-min) (point))
                                  (funcall parser)))))
    promise))

(defun json-read-buffer (buffer)
  (with-current-buffer buffer
    (save-excursion
      (mark-whole-buffer)
      (json-read))))

(defun error-count (recipes-archive)
  (length
   (seq-filter
    (lambda (desc)
      (alist-get 'error desc))
    recipes-archive)))

;; (error-count (json-read-buffer "recipes-archive-melpa.json"))

(defun latest-recipe-commit (semaphore repo base-rev recipe)
  (updater--shell-promise
   semaphore (assocenv process-environment
                       "GIT_DIR" repo
                       "BASE_REV" base-rev
                       "RECIPE" recipe)
   "exec git log --first-parent -n1 --pretty=format:%H $BASE_REV -- recipes/$RECIPE"))

(aio-defun latest-recipe-sha256 (semaphore repo base-rev recipe)
  (car
   (split-string
    (aio-await
     (updater--shell-promise
      semaphore (assocenv process-environment
                          "GIT_DIR" repo
                          "BASE_REV" base-rev
                          "RECIPE" recipe)
      "exec nix-hash --flat --type sha256 --base32 <(
         git cat-file blob $(
           git ls-tree $BASE_REV recipes/$RECIPE | cut -f1 | cut -d' ' -f3
         )
       )")))))

(aio-defun index-recipe-commits (semaphore repo base-rev recipes)
  (let ((idx (make-hash-table :test 'equal)))
    (mapc (lambda (rcpc)
            (puthash (car rcpc) (cdr rcpc) idx))
          (aio-await
           (updater--aio-all
            (mapcar (aio-lambda (recipe)
                      (seq-let (commit sha256) (aio-await
                                                (updater--aio-all
                                                 (list
                                                  (latest-recipe-commit semaphore repo base-rev recipe)
                                                  (latest-recipe-sha256 semaphore repo base-rev recipe))))
                        (message "Indexed Recipe %s %s %s" recipe commit sha256)
                        (cons recipe (cons commit sha256))))
                    recipes))))
    idx))

(aio-defun with-melpa-checkout (resolve)
  (let ((tmpdir (make-temp-file "melpa-" t)))
    (unwind-protect
        (progn (aio-await (updater--shell-promise
                           nil
                           (assocenv process-environment "MELPA_DIR" tmpdir)
                           "
       cd $MELPA_DIR
       (git init --bare
        git remote add origin https://github.com/melpa/melpa.git
        git fetch origin) 1>&2
       echo -n $MELPA_DIR"))
               (message "Created melpa checkout %s" tmpdir)
               (aio-await (funcall resolve tmpdir)))
      (delete-directory tmpdir t)
      (message "Deleted melpa checkout %s" tmpdir))))

(aio-defun list-recipes (repo base-rev)
  (mapcar (lambda (n)
            (substring n 8))
          (split-string (aio-await (updater--shell-promise nil (assocenv process-environment
                                                                         "GIT_DIR" repo
                                                                         "BASE_REV" base-rev)
                                                           "git ls-tree --name-only $BASE_REV recipes/")))))

;; ## Main runner

(defvar recipe-index)

(defun run-updater ()
  (message "Turning off logging to *Message* buffer")
  (setq message-log-max nil)
  (setenv "GIT_ASKPASS")
  (setenv "SSH_ASKPASS")
  (setq process-adaptive-read-buffering nil)
  (setq debug-on-error t)
  (setq max-specpdl-size 5200)
  (setq max-lisp-eval-depth 3200)

  ;; Indexer and Prefetcher run in parallel
  
  ;; Recipe Indexer
  (let ((recipe-indexp (with-melpa-checkout
                        (aio-lambda (repo)
                          (let* ((recipe-names (aio-await (list-recipes repo "origin/master")))
                                 (res (aio-await (index-recipe-commits
                                                  ;; The indexer runs on a local git repository,
                                                  ;; so it is CPU bound.
                                                  ;; Adjust for core count + 2
                                                  (aio-sem 6)
                                                  repo "origin/master"
                                                  ;; (seq-take recipe-names 20)
                                                  recipe-names))))
                            (message "Indexed Recipes: %d" (hash-table-count res))
                            (setq recipe-index res)
                            res)))))

    ;; Prefetcher + Emitter  
    (aio-wait-for
     (aio-with-async
       (seq-let [recipes-content archive-content stable-archive-content]
           (aio-await (updater--aio-all (list (http-get "https://melpa.org/recipes.json"
                                                        (lambda ()
                                                          (let ((json-object-type 'alist)
                                                                (json-array-type 'list)
                                                                (json-key-type 'symbol))
                                                            (json-read))))
                                              (http-get "https://melpa.org/archive.json"
                                                        (lambda ()
                                                          (let ((json-object-type 'hash-table)
                                                                (json-array-type 'list)
                                                                (json-key-type 'symbol))
                                                            (json-read))))
                                              (http-get "https://stable.melpa.org/archive.json"
                                                        (lambda ()
                                                          (let ((json-object-type 'hash-table)
                                                                (json-array-type 'list)
                                                                (json-key-type 'symbol))
                                                            (json-read)))))))
         (message "Finished download")
         ;; The prefetcher is network bound, so 64 seems a good estimate
         ;; for parallel network connections
         (let ((buf (aio-await (emit-json (aio-sem 64)
                                          recipe-indexp
                                          recipes-content
                                          archive-content
                                          stable-archive-content
                                          (parse-previous-archive "recipes-archive-melpa.json")))))
           (with-current-buffer buf
             (write-file "recipes-archive-melpa.json"))))))))
