#|

Note: the patterns described in the doc.txt file are
slightly different than the patterns processed here.
The difference is in the form of the side-condition
expressions. Here they are procedures that accept
binding structures, instead of expressions. The
reduction (And other) macros do this transformation
before the pattern compiler is invoked.

|#
(module matcher mzscheme
  (require (lib "list.ss")
           (lib "match.ss")
           (lib "etc.ss")
           (lib "contract.ss")
           "underscore-allowed.ss")
  
  (define-struct compiled-pattern (cp))

  (define count 0)
  
  ;; lang = (listof nt)
  ;; nt = (make-nt sym (listof rhs))
  ;; rhs = (make-rhs single-pattern (listof var-info??))
  ;; single-pattern = sexp
  (define-struct nt (name rhs) (make-inspector))
  (define-struct rhs (pattern var-info) (make-inspector))
  
  ;; var = (make-var sym sexp)
  ;; patterns are sexps with `var's embedded
  ;; in them. It means to match the
  ;; embedded sexp and return that binding
  
  ;; bindings = (make-bindings (listof rib))
  ;; rib = (make-bind sym sexp)
  ;; if a rib has a pair, the first element of the pair should be treated as a prefix on the identifer
  ;; NOTE: the bindings may contain mismatch-ribs temporarily, but they are all removed
  ;;       by merge-multiples/remove, a helper function called from match-pattern
  (define-values (make-bindings bindings-table bindings?)
    (let () 
      (define-struct bindings (table) (make-inspector)) ;; for testing, add inspector
      (values (lambda (table)
                (unless (and (list? table)
                             (andmap (λ (x) (or (bind? x) (mismatch-bind? x))) table))
                  (error 'make-bindings "expected <(listof (union rib mismatch-rib))>, got ~e" table))
                (make-bindings table))
              bindings-table
              bindings?)))
  
  (define-struct bind (name exp) (make-inspector)) ;; for testing, add inspector
  (define-struct mismatch-bind (name exp) (make-inspector)) ;; for testing, add inspector

  ;; repeat = (make-repeat compiled-pattern (listof rib) (union #f symbol) boolean)
  (define-struct repeat (pat empty-bindings suffix mismatch?) (make-inspector)) ;; inspector for tests below
  
  ;; compiled-pattern : exp (union #f none sym) -> (union #f (listof mtch))
  ;; mtch = (make-mtch bindings sexp[context w/none-inside for the hole] (union none sexp[hole]))
  ;; mtch is short for "match"
  (define-values (mtch-bindings mtch-context mtch-hole make-mtch mtch?)
    (let ()
      (define-struct mtch (bindings context hole) (make-inspector))
      (values mtch-bindings
              mtch-context
              mtch-hole
              (lambda (a b c)
                (unless (bindings? a)
                  (error 'make-mtch "expected bindings for first agument, got ~e" a))
                (make-mtch a b c))
              mtch?)))
  
  ;; used to mean no context is available; also used as the "name" for an unnamed (ie, normal) hole
  (define none
    (let ()
      (define-struct none ())
      (make-none)))
  (define (none? x) (eq? x none))
  
  ;; compiled-lang : (make-compiled-lang (listof nt) 
  ;;                                     hash-table[sym -o> compiled-pattern]
  ;;                                     hash-table[sym -o> compiled-pattern]
  ;;                                     hash-table[sym -o> compiled-pattern]
  ;;                                     hash-table[sym -o> boolean])
  ;;                                     hash-table[sexp[pattern] -o> (cons compiled-pattern boolean)]
  ;;                                     hash-table[sexp[pattern] -o> (cons compiled-pattern boolean)]
  ;;                                     pict-builder
  ;;                                     (listof symbol)
  ;;                                     (listof (listof symbol))) -- keeps track of `primary' non-terminals
  ;; hole-info = (union #f none symbol)
  ;;               #f means we're not in a `in-hole' context
  ;;               none means we're looking for a normal hole
  ;;               symbol means we're looking for a named hole named by the symbol
  
  (define-struct compiled-lang (lang ht list-ht across-ht across-list-ht has-hole-ht
                                     cache bind-names-cache pict-builder literals
                                     nt-map))
  
  ;; lookup-binding : bindings (union sym (cons sym sym)) [(-> any)] -> any
  (define lookup-binding 
    (opt-lambda (bindings
		 sym
		 [fail (lambda () (error 'lookup-binding "didn't find ~e in ~e" sym bindings))])
      (let loop ([ribs (bindings-table bindings)])
        (cond
          [(null? ribs) (fail)]
          [else
           (let ([rib (car ribs)])
             (if (and (bind? rib) (equal? (bind-name rib) sym))
                 (bind-exp rib)
                 (loop (cdr ribs))))]))))
  
  ;; compile-language : language-pict-info[see pict.ss] (listof nt) (listof (listof sym)) -> compiled-lang
  (define (compile-language pict-info lang nt-map)
    (let* ([clang-ht (make-hash-table)]
           [clang-list-ht (make-hash-table)]
           [across-ht (make-hash-table)]
           [across-list-ht (make-hash-table)]
           [has-hole-ht (build-has-hole-ht lang)]
           [cache (make-hash-table 'equal)]
           [bind-names-cache (make-hash-table 'equal)]
           [literals (extract-literals lang)]
           [clang (make-compiled-lang lang clang-ht clang-list-ht 
                                      across-ht across-list-ht
                                      has-hole-ht 
                                      cache bind-names-cache
                                      pict-info
                                      literals
                                      nt-map)]
           [non-list-nt-table (build-non-list-nt-label lang)]
           [list-nt-table (build-list-nt-label lang)]
           [do-compilation
            (lambda (ht list-ht lang prefix-cross?)
              (for-each
               (lambda (nt)
                 (for-each
                  (lambda (rhs)
                    (let-values ([(compiled-pattern has-hole?) 
                                  (compile-pattern/cross? clang (rhs-pattern rhs) prefix-cross? #f)])
                      (let ([add-to-ht
                             (lambda (ht)
                               (hash-table-put!
                                ht
                                (nt-name nt)
                                (cons compiled-pattern (hash-table-get ht (nt-name nt)))))])
                        (when (may-be-non-list-pattern? (rhs-pattern rhs)
                                                        non-list-nt-table)
                          (add-to-ht ht))
                        (when (may-be-list-pattern? (rhs-pattern rhs) 
                                                    list-nt-table)
                          (add-to-ht list-ht)))))
                  (nt-rhs nt)))
               lang))]
           [init-ht
            (lambda (ht)
              (for-each (lambda (nt) (hash-table-put! ht (nt-name nt) null))
                        lang))])
      
      (init-ht clang-ht)
      (init-ht clang-list-ht)
      
      (hash-table-for-each
       clang-ht
       (lambda (nt rhs)
         (when (has-underscore? nt)
           (error 'compile-language "cannot use underscore in nonterminal name, ~s" nt))))
      
      (let ([compatible-context-language
             (build-compatible-context-language clang-ht lang)])
        (for-each (lambda (nt)
                    (hash-table-put! across-ht (nt-name nt) null)
                    (hash-table-put! across-list-ht (nt-name nt) null))
                  compatible-context-language)
        (do-compilation clang-ht clang-list-ht lang #t)
        (do-compilation across-ht across-list-ht compatible-context-language #f)
        clang)))
  
  ;; extract-literals : (listof nt) -> (listof symbol)
  (define (extract-literals nts)
    (let ([literals-ht (make-hash-table)]
          [nt-names (map nt-name nts)])
      (for-each (λ (nt) 
                  (for-each (λ (rhs) (extract-literals/pat nt-names (rhs-pattern rhs) literals-ht))
                            (nt-rhs nt)))
                nts)
      (hash-table-map literals-ht (λ (x y) x))))
  
  ;; extract-literals/pat : (listof sym) pattern ht -> void
  ;; inserts the literals mentioned in pat into ht
  (define (extract-literals/pat nts pat ht)
    (let loop ([pat pat])
      (match pat
	[`any (void)]
	[`number (void)]
	[`string (void)]
	[`variable (void)]
	[`(variable-except ,s ...) (void)]
	[`(variable-prefix ,s) (void)]
        [`variable-not-otherwise-mentioned (void)]
	[`hole (void)]
	[`(hole ,s) (void)]
	[(? symbol? s) 
         (unless (regexp-match #rx"_" (symbol->string s))
           (unless (regexp-match #rx"^\\.\\.\\." (symbol->string s))
             (unless (memq s nts)
               (hash-table-put! ht s #t))))]
	[`(name ,name ,pat) (loop pat)]
	[`(in-hole ,p1 ,p2) 
         (loop p1)
         (loop p2)]
        [`(hide-hole ,p) (loop p)]
	[`(in-named-hole ,s ,p1 ,p2)
         (loop p1)
         (loop p2)]
	[`(side-condition ,p ,g)
         (loop p)]
	[`(cross ,s) (void)]
	[_
         (let l-loop ([l-pat pat])
	   (when (pair? l-pat) 
             (loop (car l-pat))
             (l-loop (cdr l-pat))))])))
  
  ; build-has-hole-ht : (listof nt) -> hash-table[symbol -o> boolean]
  ; produces a map of nonterminal -> whether that nonterminal could produce a hole
  (define (build-has-hole-ht lang)
    (build-nt-property 
     lang
     (lambda (pattern recur)
       (match pattern
         [`any #f]
         [`number #f]
         [`string #f]
         [`variable #f] 
         [`(variable-except ,@(vars ...)) #f]
         [`(variable-prefix ,var) #f]
         [`variable-not-otherwise-mentioned #f]
         [`hole #t]
         [`(hole ,(? symbol? hole-name)) #t]
         [(? string?) #f]
         [(? symbol?)
          ;; cannot be a non-terminal, otherwise this function isn't called
          #f]
         [`(name ,name ,pat)
           (recur pat)]
         [`(in-hole ,context ,contractum)
           (recur contractum)]
         [`(hide-hole ,arg) #f]
         [`(in-named-hole ,hole-name ,context ,contractum)
           (recur contractum)]
         [`(side-condition ,pat ,condition)
           (recur pat)]
         [(? list?)
          (ormap recur pattern)]
         [else #f]))
     #t
     (lambda (lst) (ormap values lst))))
  
  ;; build-nt-property : lang (pattern[not-non-terminal] (pattern -> boolean) -> boolean) boolean
  ;;                  -> hash-table[symbol[nt] -> boolean]
  (define (build-nt-property lang test-rhs conservative-answer combine-rhss)
    (let ([ht (make-hash-table)]
          [rhs-ht (make-hash-table)])
      (for-each
       (lambda (nt)
         (hash-table-put! rhs-ht (nt-name nt) (nt-rhs nt))
         (hash-table-put! ht (nt-name nt) 'unknown))
       lang)
      (let ()
        (define (check-nt nt-sym)
          (let ([current (hash-table-get ht nt-sym)])
            (case current
              [(unknown)
               (hash-table-put! ht nt-sym 'computing)
               (let ([answer (combine-rhss 
                              (map (lambda (x) (check-rhs (rhs-pattern x)))
                                   (hash-table-get rhs-ht nt-sym)))])
                 (hash-table-put! ht nt-sym answer)
                 answer)]
              [(computing) conservative-answer]
              [else current])))
        (define (check-rhs rhs)
          (cond
            [(hash-table-maps? ht rhs)
             (check-nt rhs)]
            [else (test-rhs rhs check-rhs)]))
        (for-each (lambda (nt) (check-nt (nt-name nt)))
                  lang)
        ht)))
          
  ;; build-compatible-context-language : lang -> lang
  (define (build-compatible-context-language clang-ht lang)
    (apply
     append
     (map 
      (lambda (nt1)
        (map
         (lambda (nt2)
           (let ([compat-nt (build-compatible-contexts/nt clang-ht (nt-name nt1) nt2)])
             (if (eq? (nt-name nt1) (nt-name nt2))
                 (make-nt (nt-name compat-nt)
                          (cons
                           (make-rhs 'hole '())
                           (nt-rhs compat-nt)))
                 compat-nt)))
         lang))
      lang)))
    
  ;; build-compatible-contexts : clang-ht prefix nt -> nt
  ;; constructs the compatible closure evaluation context from nt.
  (define (build-compatible-contexts/nt clang-ht prefix nt)
    (make-nt
     (symbol-append prefix '- (nt-name nt))
     (apply append
            (map
             (lambda (rhs)
               (let-values ([(maker count) (build-compatible-context-maker clang-ht
                                                                           (rhs-pattern rhs)
                                                                           prefix)])
                 (let loop ([i count])
                   (cond
                     [(zero? i) null]
                     [else (let ([nts (build-across-nts (nt-name nt) count (- i 1))])
                             (cons (make-rhs (maker (box nts)) '())
                                   (loop (- i 1))))]))))
             (nt-rhs nt)))))
    
  (define (symbol-append . args)
    (string->symbol (apply string-append (map symbol->string args))))

  ;; build-across-nts : symbol number number -> (listof pattern)
  (define (build-across-nts nt count i)
    (let loop ([j count])
      (cond
        [(zero? j) null]
        [else
         (cons (= i (- j 1)) 
               (loop (- j 1)))])))
    
  ;; build-compatible-context-maker : symbol pattern -> (values ((box (listof pattern)) -> pattern) number)
  ;; when the result function is applied, it takes each element
  ;; of the of the boxed list and plugs them into the places where
  ;; the nt corresponding from this rhs appeared in the original pattern. 
  ;; The number result is the number of times that the nt appeared in the pattern.
  (define (build-compatible-context-maker clang-ht pattern prefix)
    (let ([count 0])
      (values
       (let loop ([pattern pattern])
         (match pattern
           [`any (lambda (l) 'any)]
           [`number (lambda (l) 'number)]
           [`string (lambda (l) 'string)]
           [`variable (lambda (l) 'variable)] 
           [`(variable-except ,@(vars ...)) (lambda (l) pattern)]
           [`(variable-prefix ,var) (lambda (l) pattern)]
           [`variable-not-otherwise-mentioned (λ (l) pattern)]
           [`hole  (lambda (l) 'hole)]
           [`(hole ,(? symbol? hole-name)) (lambda (l) `(hole ,hole-name))]
           [(? string?) (lambda (l) pattern)]
           [(? symbol?) 
            (cond
              [(hash-table-get clang-ht pattern #f)
               (set! count (+ count 1))
               (lambda (l)
                 (let ([fst (car (unbox l))])
                   (set-box! l (cdr (unbox l)))
                   (if fst
                       `(cross ,(symbol-append prefix '- pattern))
                       pattern)))]
              [else
               (lambda (l) pattern)])]
           [`(name ,name ,pat)
            (let ([patf (loop pat)])
              (lambda (l)
                `(name ,name ,(patf l))))]
           [`(in-hole ,context ,contractum)
            (let ([match-context (loop context)]
                  [match-contractum (loop contractum)])
              (lambda (l)
                `(in-hole ,(match-context l)
                          ,(match-contractum l))))]
           [`(hide-hole ,p)
            (let ([m (loop p)])
              (lambda (l)
                `(hide-hole ,(m l))))]
           [`(in-named-hole ,hole-name ,context ,contractum)
            (let ([match-context (loop context)]
                  [match-contractum (loop contractum)])
              (lambda (l)
                `(in-named-hole ,hole-name
                                ,(match-context l)
                                ,(match-contractum l))))]
           [`(side-condition ,pat ,condition)
            (let ([patf (loop pat)])
              (lambda (l)
                `(side-condition ,(patf l) ,condition)))]
           [(? list?)
            (let ([f/pats
                   (let l-loop ([pattern pattern])
                     (cond
                       [(null? pattern) null]
                       [(null? (cdr pattern))
                        (list (vector (loop (car pattern))
                                      #f
                                      #f))]
                       [(eq? (cadr pattern) '...)
                        (cons (vector (loop (car pattern))
                                      #t
                                      (car pattern))
                              (l-loop (cddr pattern)))]
                       [else
                        (cons (vector (loop (car pattern))
                                      #f
                                      #f)
                              (l-loop (cdr pattern)))]))])
              (lambda (l)
                (let loop ([f/pats f/pats])
                  (cond
                    [(null? f/pats) null]
                    [else
                     (let ([f/pat (car f/pats)])
                       (cond
                         [(vector-ref f/pat 1)
                          (let ([new ((vector-ref f/pat 0) l)]
                                [pat (vector-ref f/pat 2)])
                            (if (equal? new pat)
                                (list* pat
                                       '...
                                       (loop (cdr f/pats)))
                                (list* (vector-ref f/pat 2)
                                       '...
                                       new
                                       (vector-ref f/pat 2)
                                       '...
                                       (loop (cdr f/pats)))))]
                         [else
                          (cons ((vector-ref f/pat 0) l)
                                (loop (cdr f/pats)))]))]))))]
           [else 
            (lambda (l) pattern)]))
       count)))
  
  ;; build-list-nt-label : lang -> hash-table[symbol -o> boolean]
  (define (build-list-nt-label lang)
    (build-nt-property 
     lang
     (lambda (pattern recur)
       (may-be-list-pattern?/internal pattern
                                      (lambda (sym) #f)
                                      recur))
     #t
     (lambda (lst) (ormap values lst))))
  
  (define (may-be-list-pattern? pattern list-nt-table)
    (let loop ([pattern pattern])
      (may-be-list-pattern?/internal
       pattern
       (lambda (sym) 
         (hash-table-get list-nt-table (symbol->nt sym) #t))
       loop)))
  
  (define (may-be-list-pattern?/internal pattern handle-symbol recur)
    (match pattern
      [`any #t]
      [`number #f]
      [`string #f]
      [`variable #f] 
      [`(variable-except ,@(vars ...)) #f]
      [`variable-not-otherwise-mentioned #f]
      [`(variable-prefix ,var) #f]
      [`hole  #t]
      [`(hole ,(? symbol? hole-name)) #t]
      [(? string?) #f]
      [(? symbol?)
       (handle-symbol pattern)]
      [`(name ,name ,pat)
        (recur pat)]
      [`(in-hole ,context ,contractum)
        (recur context)]
      [`(hide-hole ,p)
       (recur p)]
      [`(in-named-hole ,hole-name ,context ,contractum)
        (recur context)]
      [`(side-condition ,pat ,condition)
        (recur pat)]
      [(? list?)
       #t]
      [else 
       ;; is this right?!
       (or (null? pattern) (pair? pattern))]))

  
  ;; build-non-list-nt-label : lang -> hash-table[symbol -o> boolean]
  (define (build-non-list-nt-label lang)
    (build-nt-property 
     lang
     (lambda (pattern recur)
       (may-be-non-list-pattern?/internal pattern
                                 (lambda (sym) #t)
                                 recur))
     #t
     (lambda (lst) (ormap values lst))))
  
  (define (may-be-non-list-pattern? pattern non-list-nt-table)
    (let loop ([pattern pattern])
      (may-be-non-list-pattern?/internal
       pattern
       (lambda (sym)
         (hash-table-get non-list-nt-table (symbol->nt sym) #t))
       loop)))
  
  (define (may-be-non-list-pattern?/internal pattern handle-sym recur)
    (match pattern
      [`any #t]
      [`number #t]
      [`string #t]
      [`variable #t] 
      [`(variable-except ,@(vars ...)) #t]
      [`variable-not-otherwise-mentioned #t]
      [`(variable-prefix ,prefix) #t]
      [`hole #t]
      [`(hole ,(? symbol? hole-name)) #t]
      [(? string?) #t]
      [(? symbol?) (handle-sym pattern)]
      [`(name ,name ,pat)
        (recur pat)]
      [`(in-hole ,context ,contractum)
        (recur context)]
      [`(hide-hole ,p)
       (recur p)]
      [`(in-named-hole ,hole-name ,context ,contractum)
        (recur context)]
      [`(side-condition ,pat ,condition)
        (recur pat)]
      [(? list?)
       #f]
      [else 
       ;; is this right?!
       (not (or (null? pattern) (pair? pattern)))]))
  
  ;; match-pattern : compiled-pattern exp -> (union #f (listof bindings))
  (define (match-pattern compiled-pattern exp)
    (let ([results ((compiled-pattern-cp compiled-pattern) exp #f)])
      (and results
           (let ([filtered (filter-multiples results)])
             (and (not (null? filtered))
                  filtered)))))
  
  ;; filter-multiples : (listof mtch) -> (listof mtch)
  (define (filter-multiples matches)
    (let loop ([matches matches]
               [acc null])
      (cond
        [(null? matches) acc]
        [else
         (let ([merged (merge-multiples/remove (car matches))])
           (if merged
               (loop (cdr matches) (cons merged acc))
               (loop (cdr matches) acc)))])))
  
  ;; merge-multiples/remove : bindings -> (union #f bindings)
  ;; returns #f if all duplicate bindings don't bind the same thing
  ;; returns a new bindings 
  (define (merge-multiples/remove match)
    (let/ec fail
      (let (
            ;; match-ht : sym -o> sexp
            [match-ht (make-hash-table 'equal)]
            
            ;; mismatch-ht : sym -o> hash-table[sexp -o> #t]
            [mismatch-ht (make-hash-table 'equal)]
            
            [ribs (bindings-table (mtch-bindings match))])
        (for-each
         (lambda (rib)
           (cond
             [(bind? rib)
              (let ([name (bind-name rib)]
                    [exp (bind-exp rib)])
                (let ([previous-exp (hash-table-get match-ht name uniq)])
                  (cond
                    [(eq? previous-exp uniq)
                     (hash-table-put! match-ht name exp)]
                    [else
                     (unless (equal? exp previous-exp)
                       (fail #f))])))]
             [(mismatch-bind? rib)
              (let* ([name (mismatch-bind-name rib)]
                     [exp (mismatch-bind-exp rib)]
                     [priors (hash-table-get mismatch-ht name uniq)])
                (when (eq? priors uniq)
                  (let ([table (make-hash-table 'equal)])
                    (hash-table-put! mismatch-ht name table)
                    (set! priors table)))
                (when (hash-table-get priors exp #f)
                  (fail #f))
                (hash-table-put! priors exp #t))]))
         ribs)
        (make-mtch
         (make-bindings (hash-table-map match-ht make-bind))
         (mtch-context match)
         (mtch-hole match)))))
  
  ;; compile-pattern : compiled-lang pattern boolean (listof sym) -> compiled-pattern
  (define compile-pattern
    (opt-lambda (clang pattern bind-names?)
      (let-values ([(pattern has-hole?) (compile-pattern/cross? clang pattern #t bind-names?)])
        (make-compiled-pattern pattern))))

  ;; name-to-key/binding : hash-table[symbol -o> key-wrap]
  (define name-to-key/binding (make-hash-table))
  (define-struct key-wrap (sym) (make-inspector))
  
  ;; compile-pattern/cross? : compiled-lang pattern boolean boolean -> (values compiled-pattern boolean)
  (define (compile-pattern/cross? clang pattern prefix-cross? bind-names?)
    (define clang-ht (compiled-lang-ht clang))
    (define clang-list-ht (compiled-lang-list-ht clang))
    (define has-hole-ht (compiled-lang-has-hole-ht clang))
    (define across-ht (compiled-lang-across-ht clang))
    (define across-list-ht (compiled-lang-across-list-ht clang))
    
    (define (compile-pattern/default-cache pattern)
      (compile-pattern/cache pattern 
                             (if bind-names?
                                 (compiled-lang-bind-names-cache clang)
                                 (compiled-lang-cache clang))))
    
    (define (compile-pattern/cache pattern compiled-pattern-cache)
      (let ([compiled-cache (hash-table-get compiled-pattern-cache pattern uniq)])
        (cond 
          [(eq? compiled-cache uniq)
           (let-values ([(compiled-pattern has-hole?)
                         (true-compile-pattern pattern)])
             (let ([val (list (memoize compiled-pattern has-hole?) has-hole?)])
               (hash-table-put! compiled-pattern-cache pattern val)
               (apply values val)))]
          [else
           (apply values compiled-cache)])))
    
    (define (true-compile-pattern pattern)
      (match pattern
        [(? (lambda (x) (eq? x '....)))
         (error 'compile-language "the pattern .... can only be used in extend-language")]
        [`(variable-except ,@(vars ...))
          (values
           (lambda (exp hole-info)
             (and (symbol? exp)
                  (not (memq exp vars))
                  (list (make-mtch (make-bindings null)
                                   (build-flat-context exp)
                                   none))))
           #f)]
        [`(variable-prefix ,var)
          (values
           (let* ([prefix-str (symbol->string var)]
                  [prefix-len (string-length prefix-str)])
             (lambda (exp hole-info)
               (and (symbol? exp)
                    (let ([str (symbol->string exp)])
                      (and ((string-length str) . >= . prefix-len)
                           (string=? (substring str 0 prefix-len) prefix-str)
                           (list (make-mtch (make-bindings null)
                                            (build-flat-context exp)
                                            none)))))))
           #f)]
        [`variable-not-otherwise-mentioned 
         (values
          (let ([literals (compiled-lang-literals clang)])
            (lambda (exp hole-info)
              (and (symbol? exp)
                   (not (memq exp literals))
                   (list (make-mtch (make-bindings null)
                                    (build-flat-context exp)
                                    none)))))
          #f)]
        [`hole
          (values (match-hole none) #t)]
        [`(hole ,hole-id)
          (values (match-hole (or hole-id none)) #t)]
        [(? string?)
         (values
          (lambda (exp hole-info)
            (and (string? exp)
                 (string=? exp pattern)
                 (list (make-mtch (make-bindings null)
                                  (build-flat-context exp)
                                  none))))
          #f)]
        [(? symbol?)
         (cond
           [(has-underscore? pattern)
            (let*-values ([(binder before-underscore)
                           (let ([before (split-underscore pattern)])
                             (unless (or (hash-table-maps? clang-ht before)
                                         (memq before underscore-allowed))
                               (error 'compile-pattern "before underscore must be either a non-terminal ~a or a built-in pattern, found ~a in ~s" 
                                      before
                                      (format "~s" (list* 'one 'of: (hash-table-map clang-ht (λ (x y) x))))
                                      pattern))
                             (values pattern before))]
                          [(match-raw-name has-hole?)
                           (compile-id-pattern before-underscore)])
              (values
               (match-named-pat binder match-raw-name)
               has-hole?))]
           [else 
            (let-values ([(match-raw-name has-hole?) (compile-id-pattern pattern)])
              (values (if (non-underscore-binder? pattern)
                          (match-named-pat pattern match-raw-name)
                          match-raw-name)
                      has-hole?))])]
        [`(cross ,(? symbol? pre-id))
          (let ([id (if prefix-cross?
                        (symbol-append pre-id '- pre-id)
                        pre-id)])
            (cond
              [(hash-table-maps? across-ht id)
               (values
                (lambda (exp hole-info)
                  (match-nt (hash-table-get across-list-ht id)
                            (hash-table-get across-ht id)
                            id exp hole-info))
                #t)]
              [else
               (error 'compile-pattern "unknown cross reference ~a" id)]))]
        
        [`(name ,name ,pat)
         (let-values ([(match-pat has-hole?) (compile-pattern/default-cache pat)])
           (values (match-named-pat name match-pat)
                   has-hole?))]
        [`(in-hole ,context ,contractum) 
          (let-values ([(match-context ctxt-has-hole?) (compile-pattern/default-cache context)]
                       [(match-contractum contractum-has-hole?) (compile-pattern/default-cache contractum)])
            (values
             (match-in-hole context contractum exp match-context match-contractum none)
             (or ctxt-has-hole? contractum-has-hole?)))]
        [`(hide-hole ,p)
         (let-values ([(match-pat has-hole?) (compile-pattern/default-cache p)])
           (values
            (lambda (exp hole-info)
              (let ([matches (match-pat exp #f)])
                (and matches
                     (map (λ (match) (make-mtch (mtch-bindings match) (mtch-context match) none))
                          matches))))
            #f))]
        [`(in-named-hole ,hole-id ,context ,contractum) 
          (let-values ([(match-context ctxt-has-hole?) (compile-pattern/default-cache context)]
                       [(match-contractum contractum-has-hole?) (compile-pattern/default-cache contractum)])
            (values
             (match-in-hole context contractum exp match-context match-contractum hole-id)
             (or ctxt-has-hole? contractum-has-hole?)))]
        
        [`(side-condition ,pat ,condition)
          (let-values ([(match-pat has-hole?) (compile-pattern/default-cache pat)])
            (values
             (lambda (exp hole-info)
               (let ([matches (match-pat exp hole-info)])
                 (and matches
                      (let ([filtered (filter (λ (m) (condition (mtch-bindings m))) matches)])
                        (if (null? filtered)
                            #f
                            filtered)))))
             has-hole?))]
        [(? (lambda (x) (list? x))) ;; this eta expansion is to defeat a bug in match
         (let-values ([(rewritten has-hole?) (rewrite-ellipses non-underscore-binder? pattern compile-pattern/default-cache)])
           (let ([count (and (not (ormap repeat? rewritten))
                             (length rewritten))])
             (values
              (lambda (exp hole-info)
                (cond
                  [(list? exp)
                   ;; shortcircuit: if the list isn't the right length, give up immediately.
                   (if (and count
                            (not (= (length exp) count)))
                       #f
                       (match-list rewritten exp hole-info))]
                  [else #f]))
              has-hole?)))]
        
        ;; an already comiled pattern
        [(? compiled-pattern?)
         ;; return #t here as a failsafe; no way to check better.
         (values (compiled-pattern-cp pattern)
                 #t)]
        
        [else 
         (values
          (lambda (exp hole-info)
            (and (eqv? pattern exp)
                 (list (make-mtch (make-bindings null)
                                  (build-flat-context exp)
                                  none))))
          #f)]))
    
    (define (non-underscore-binder? pattern)
      (and bind-names?
           (or (hash-table-maps? clang-ht pattern)
               (memq pattern underscore-allowed))))
    
    ;; compile-id-pattern : symbol[with-out-underscore] -> (values <compiled-pattern-proc> boolean)
    (define (compile-id-pattern pat)
      (match pat
        [`any (simple-match 'any (λ (x) #t))]
        [`number (simple-match 'number number?)]
        [`string (simple-match 'string string?)]
        [`variable (simple-match 'variable symbol?)]
        [(? is-non-terminal?)
         (values
          (lambda (exp hole-info)
            (match-nt (hash-table-get clang-list-ht pat)
                      (hash-table-get clang-ht pat)
                      pat exp hole-info))
          (hash-table-get has-hole-ht pat))]
        [else
         (values
          (lambda (exp hole-info) 
            (and (eq? exp pat)
                 (list (make-mtch (make-bindings null)
                                  (build-flat-context exp)
                                  none))))
          #f)]))
    
    (define (is-non-terminal? sym) (hash-table-maps? clang-ht sym))

    ;; simple-match : sym (any -> bool) -> (values <compiled-pattern> boolean)
    ;; does a match based on a built-in Scheme predicate
    (define (simple-match binder pred)
      (values (lambda (exp hole-info) 
                (and (pred exp) 
                     (list (make-mtch
                            (make-bindings null)
                            (build-flat-context exp)
                            none))))
              #f))
    
    (compile-pattern/default-cache pattern))
  
  ;; match-named-pat : symbol <compiled-pattern> -> <compiled-pattern>
  (define (match-named-pat name match-pat)
    (let ([mismatch-bind? (regexp-match #rx"_!_" (symbol->string name))])
      (lambda (exp hole-info)
        (let ([matches (match-pat exp hole-info)])
          (and matches 
               (map (lambda (match)
                      (make-mtch
                       (make-bindings (cons (if mismatch-bind?
                                                (make-mismatch-bind name (mtch-context match))
                                                (make-bind name (mtch-context match)))
                                            (bindings-table (mtch-bindings match))))
                       (mtch-context match)
                       (mtch-hole match)))
                    matches))))))
  
  ;; split-underscore : symbol -> symbol
  ;; returns the text before the underscore in a symbol (as a symbol)
  ;; raise an error if there is more than one underscore in the input
  (define (split-underscore sym)
    (let ([str (symbol->string sym)])
      (cond
        [(regexp-match #rx"^([^_]*)_[^_]*$" str)
         =>
         (λ (m) (string->symbol (cadr m)))]
        [(regexp-match #rx"^([^_]*)_!_[^_]*$" str)
         =>
         (λ (m) (string->symbol (cadr m)))]
        [else
         (error 'compile-pattern "found a symbol with multiple underscores: ~s" sym)])))
  
  ;; has-underscore? : symbol -> boolean
  (define (has-underscore? sym)
    (memq #\_ (string->list (symbol->string sym))))
  
  ;; symbol->nt : symbol -> symbol
  ;; strips the trailing underscore from a symbol, if one is there.
  (define (symbol->nt sym)
    (cond
      [(has-underscore? sym)
       (split-underscore sym)]
      [else sym]))
  
  (define (memoize f needs-all-args?)
    (if needs-all-args?
        (memoize2 f)
        (memoize1 f)))
  
  ; memoize1 : (x y -> w) -> x y -> w
  ; memoizes a function of two arguments under the assumption
  ; that the function is constant w.r.t the second
  (define (memoize1 f) (memoize/key f (lambda (x y) x) nohole))
  (define (memoize2 f) (memoize/key f cons w/hole))

  (define cache-size 350)
  (define (set-cache-size! cs) (set! cache-size cs))
  
  ;; original version, but without closure allocation in hash-table lookup
  (define (memoize/key f key-fn statsbox)
    (let ([ht (make-hash-table 'equal)]
          [entries 0])
      (lambda (x y)
        (if cache-size
            (let* ([key (key-fn x y)])
              ;(record-cache-test! statsbox)
              (unless (< entries cache-size)
                (set! entries 0)
                (set! ht (make-hash-table 'equal)))
              (let ([ans (hash-table-get ht key uniq)])
                (cond
                  [(eq? ans uniq)
                   ;(record-cache-miss! statsbox)
                   (set! entries (+ entries 1))
                   (let ([res (f x y)])
                     (hash-table-put! ht key res)
                     res)]
                  [else
                   ans])))
            (f x y)))))
  
  ;; hash-table version, but with an extra hash-table that tells when to evict cache entries
  #;
  (define (memoize/key f key-fn statsbox)
    (let* ([cache-size 50]
           [ht (make-hash-table 'equal)]
           [uniq (gensym)]
           [when-to-evict-table (make-hash-table)]
           [pointer 0])
      (lambda (x y)
        (record-cache-test! statsbox)
        (let* ([key (key-fn x y)]
               [value-in-cache (hash-table-get ht key uniq)])
          (cond
            [(eq? value-in-cache uniq)
             (record-cache-miss! statsbox)
             (let ([res (f x y)])
               (let ([to-remove (hash-table-get when-to-evict-table pointer uniq)])
                 (unless (eq? uniq to-remove)
                   (hash-table-remove! ht to-remove)))
               (hash-table-put! when-to-evict-table pointer key)
               (hash-table-put! ht key res)
               (set! pointer (modulo (+ pointer 1) cache-size))
               res)]
            [else
             value-in-cache])))))
  
  ;; lru cache
  ;; for some reason, this seems to hit *less* than the "just dump stuff out" strategy!
  #;
  (define (memoize/key f key-fn statsbox)
    (let* ([cache-size 50]
           [cache '()])
      (lambda (x y)
        (record-cache-test! statsbox)
        (let ([key (key-fn x y)])
          (cond
            [(null? cache)
             ;; empty cache
             (let ([ans (f x y)])
               (record-cache-miss! statsbox)
               (set! cache (cons (cons key ans) '()))
               ans)]
            [(null? (cdr cache))
             ;; one element cache
             (if (equal? (car (car cache)) key)
                 (cdr (car cache))
                 (let ([ans (f x y)])
                   (record-cache-miss! statsbox)
                   (set! cache (cons (cons key ans) cache))
                   ans))]
            [else
             ;; two of more element cache
             (cond
               [(equal? (car (car cache)) key)
                ;; check first element
                (cdr (car cache))]
               [(equal? (car (cadr cache)) key)
                ;; check second element
                (cdr (cadr cache))]
               [else
                ;; iterate from the 3rd element onwards
                (let loop ([previous2 cache]
                           [previous1 (cdr cache)]
                           [current (cddr cache)]
                           [i 0])
                  (cond
                    [(null? current)
                     ;; found the end of the cache -- need to drop the last element if the cache is too full,
                     ;; and put the current value at the front of the cache.
                     (let ([ans (f x y)])
                       (record-cache-miss! statsbox)
                       (set! cache (cons (cons key ans) cache))
                       (unless (< i cache-size)
                         ;; drop the last element from the cache
                         (set-cdr! previous2 '()))
                       ans)]
                    [else
                     (let ([entry (car current)])
                       (cond
                         [(equal? (car entry) key)
                          ;; found a hit 
                          
                          ; remove this element from the list where it is.
                          (set-cdr! previous1 (cdr current))
                          
                          ; move it to the front of the cache
                          (set! cache (cons current cache))
                          
                          ; return the found element
                          (cdr entry)]
                         [else
                          ;; didnt hit yet, continue searchign
                          (loop previous1 current (cdr current) (+ i 1))]))]))])])))))
  
  ;; hash-table version, but with a vector that tells when to evict cache entries
  #;
  (define (memoize/key f key-fn statsbox)
    (let* ([cache-size 50]
           [ht (make-hash-table 'equal)]
           [uniq (gensym)]
           [vector (make-vector cache-size uniq)] ;; vector is only used to evict things from the hash-table
           [pointer 0])
      (lambda (x y)
        (let* ([key (key-fn x y)]
               [value-in-cache (hash-table-get ht key uniq)])
          (cond
            [(eq? value-in-cache uniq)
             (let ([res (f x y)])
               (let ([to-remove (vector-ref vector pointer)])
                 (unless (eq? uniq to-remove)
                   (hash-table-remove! ht to-remove)))
               (vector-set! vector pointer key)
               (hash-table-put! ht key res)
               (set! pointer (modulo (+ pointer 1) cache-size))
               res)]
            [else
             value-in-cache])))))
  
  ;; vector-based version, with a cleverer replacement strategy
  #;
  (define (memoize/key f key-fn statsbox)
    (let* ([cache-size 20]
           ;; cache : (vector-of (union #f (cons key val)))
           ;; the #f correspond to empty spots in the cache
           [cache (make-vector cache-size #f)] 
           [pointer 0])
      (lambda (x y)
        (let ([key (key-fn x y)])
          (let loop ([i 0])
            (cond
              [(= i cache-size)
               (unless (vector-ref cache pointer)
                 (vector-set! cache pointer (cons #f #f)))
               (let ([pair (vector-ref cache pointer)]
                     [ans (f x y)])
                 (set-car! pair key)
                 (set-cdr! pair ans)
                 (set! pointer (modulo (+ 1 pointer) cache-size))
                 ans)]
              [else
               (let ([entry (vector-ref cache i)])
                 (if entry
                     (let ([e-key (car entry)]
                           [e-val (cdr entry)])
                       (if (equal? e-key key)
                           e-val
                           (loop (+ i 1))))
                     
                     ;; if we hit a #f, just skip ahead and store this in the cache
                     (loop cache-size)))]))))))
  
  ;; original version
  #;
  (define (memoize/key f key-fn statsbox)
    (let ([ht (make-hash-table 'equal)]
          [entries 0])
      (lambda (x y)
        (record-cache-test! statsbox)
        (let* ([key (key-fn x y)]
               [compute/cache
                (lambda ()
                  (set! entries (+ entries 1))
                  (record-cache-miss! statsbox)
                  (let ([res (f x y)])
                    (hash-table-put! ht key res)
                    res))])
          (unless (< entries 200) ; 10000 was original size
            (set! entries 0)
            (set! ht (make-hash-table 'equal)))
          (hash-table-get ht key compute/cache)))))
  
  (define (record-cache-miss! statsbox)
    (set-cache-stats-hits! statsbox (sub1 (cache-stats-hits statsbox)))
    (set-cache-stats-misses! statsbox (add1 (cache-stats-misses statsbox))))
  
  (define (record-cache-test! statsbox)
    (set-cache-stats-hits! statsbox (add1 (cache-stats-hits statsbox))))
  
  (define-struct cache-stats (name misses hits))
  (define (new-cache-stats name) (make-cache-stats name 0 0))
  
  (define w/hole (new-cache-stats "hole"))
  (define nohole (new-cache-stats "no-hole"))
  
  (define (print-stats)
    (let ((stats (list w/hole nohole)))
      (for-each 
       (lambda (s) 
         (when (> (+ (cache-stats-hits s) (cache-stats-misses s)) 0)
           (printf "~a has ~a hits, ~a misses (~a% miss rate)\n" 
                   (cache-stats-name s)
                   (cache-stats-hits s)
                   (cache-stats-misses s)
                   (floor
                    (* 100 (/ (cache-stats-misses s)
                              (+ (cache-stats-hits s) (cache-stats-misses s))))))))
       stats)
      (let ((overall-hits (apply + (map cache-stats-hits stats)))
            (overall-miss (apply + (map cache-stats-misses stats))))
        (printf "---\nOverall hits: ~a\n" overall-hits)
        (printf "Overall misses: ~a\n" overall-miss)
        (when (> (+ overall-hits overall-miss) 0)
          (printf "Overall miss rate: ~a%\n" 
                  (floor (* 100 (/ overall-miss (+ overall-hits overall-miss)))))))))
  
  ;; match-hole : (union none symbol) -> compiled-pattern
  (define (match-hole hole-id)
    (let ([mis-matched-hole
           (λ (exp)
             (and (hole? exp)
                  (equal? (hole-name exp) hole-id)
                  (list (make-mtch (make-bindings '())
                                   (make-hole/intern (hole-name exp))
                                   none))))])
      (lambda (exp hole-info)
        (if hole-info
            (if (eq? hole-id hole-info)
                (list (make-mtch (make-bindings '())
                                 (make-hole/intern hole-info)
                                 exp))
                (mis-matched-hole exp))
            (mis-matched-hole exp)))))
  
  ;; match-in-hole : sexp sexp sexp compiled-pattern compiled-pattern hole-info -> compiled-pattern
  (define (match-in-hole context contractum exp match-context match-contractum hole-info)
    (lambda (exp old-hole-info)
      (let ([mtches (match-context exp hole-info)])
        (and mtches
             (let loop ([mtches mtches]
                        [acc null])
               (cond
                 [(null? mtches) acc]
                 [else 
                  (let* ([mtch (car mtches)]
                         [bindings (mtch-bindings mtch)]
                         [hole-exp (mtch-hole mtch)]
                         [contractum-mtches (match-contractum hole-exp old-hole-info)])
                    (when (eq? none hole-exp)
                      (error 'matcher.ss "found zero holes when matching a decomposition"))
                    (if contractum-mtches
                        (let i-loop ([contractum-mtches contractum-mtches]
                                     [acc acc])
                          (cond
                            [(null? contractum-mtches) (loop (cdr mtches) acc)]
                            [else (let* ([contractum-mtch (car contractum-mtches)]
                                         [contractum-bindings (mtch-bindings contractum-mtch)])
                                    (i-loop
                                     (cdr contractum-mtches)
                                     (cons
                                      (make-mtch (make-bindings
                                                  (append (bindings-table contractum-bindings)
                                                          (bindings-table bindings)))
                                                 (build-nested-context 
                                                  (mtch-context mtch)
                                                  (mtch-context contractum-mtch)
                                                  hole-info)
                                                 (mtch-hole contractum-mtch))
                                      acc)))]))
                        (loop (cdr mtches) acc)))]))))))
  
  ;; match-list : (listof (union repeat compiled-pattern)) sexp hole-info -> (union #f (listof bindings))
  (define (match-list patterns exp hole-info)
    (let (;; raw-match : (listof (listof (listof mtch)))
          [raw-match (match-list/raw patterns exp hole-info)])
      
      (and (not (null? raw-match))
           
           (let* (;; combined-matches : (listof (listof mtch))
                  ;; a list of complete possibilities for matches 
                  ;; (analagous to multiple matches of a single non-terminal)
                  [combined-matches (map combine-matches raw-match)]
                  
                  ;; flattened-matches : (union #f (listof bindings))
                  [flattened-matches (if (null? combined-matches)
                                         #f
                                         (apply append combined-matches))])
             flattened-matches))))
  
  ;; match-list/raw : (listof (union repeat compiled-pattern)) 
  ;;                  sexp
  ;;                  hole-info
  ;;               -> (listof (listof (listof mtch)))
  ;; the result is the raw accumulation of the matches for each subpattern, as follows:
  ;;  (listof (listof (listof mtch)))
  ;;  \       \       \-------------/  a match for one position in the list (failures don't show up)
  ;;   \       \-------------------/   one element for each position in the pattern list
  ;;    \-------------------------/    one element for different expansions of the ellipses
  ;; the failures to match are just removed from the outer list before this function finishes
  ;; via the `fail' argument to `loop'.
  (define (match-list/raw patterns exp hole-info)
    (let/ec k
      (let loop ([patterns patterns]
                 [exp exp]
                 ;; fail : -> alpha
                 ;; causes one possible expansion of ellipses to fail
                 ;; initially there is only one possible expansion, so
                 ;; everything fails.
                 [fail (lambda () (k null))])
        (cond
          [(pair? patterns)
           (let ([fst-pat (car patterns)])
             (cond
               [(repeat? fst-pat)
                (if (or (null? exp) (pair? exp))
                    (let ([r-pat (repeat-pat fst-pat)]
                          [r-mt (make-mtch (make-bindings (repeat-empty-bindings fst-pat))
                                           (build-flat-context '())
                                           none)])
                      (apply 
                       append
                       (cons (let/ec k
                               (let ([mt-fail (lambda () (k null))])
                                 (map (lambda (pat-ele) 
                                        (cons (add-ellipses-index (list r-mt) (repeat-suffix fst-pat) (repeat-mismatch? fst-pat) 0)
                                              pat-ele))
                                      (loop (cdr patterns) exp mt-fail))))
                             (let r-loop ([exp exp]
                                          ;; past-matches is in reverse order
                                          ;; it gets reversed before put into final list
                                          [past-matches (list r-mt)]
                                          [index 1])
                               (cond
                                 [(pair? exp)
                                  (let* ([fst (car exp)]
                                         [m (r-pat fst hole-info)])
                                    (if m
                                        (let* ([combined-matches (collapse-single-multiples m past-matches)]
                                               [reversed 
                                                (add-ellipses-index 
                                                 (reverse-multiples combined-matches)
                                                 (repeat-suffix fst-pat)
                                                 (repeat-mismatch? fst-pat)
                                                 index)])
                                          (cons 
                                           (let/ec fail-k
                                             (map (lambda (x) (cons reversed x))
                                                  (loop (cdr patterns) 
                                                        (cdr exp)
                                                        (lambda () (fail-k null)))))
                                           (r-loop (cdr exp)
                                                   combined-matches
                                                   (+ index 1))))
                                        (list null)))]
                                 ;; what about dotted pairs?
                                 [else (list null)])))))
                    (fail))]
               [else
                (cond
                  [(pair? exp)
                   (let* ([fst-exp (car exp)]
                          [match (fst-pat fst-exp hole-info)])
                     (if match
                         (let ([exp-match (map (λ (mtch) (make-mtch (mtch-bindings mtch)
                                                                    (build-list-context (mtch-context mtch))
                                                                    (mtch-hole mtch)))
                                               match)])
                           (map (lambda (x) (cons exp-match x))
                                (loop (cdr patterns) (cdr exp) fail)))
                         (fail)))]
                  [else
                   (fail)])]))]
          [else
           (if (null? exp)
               (list null)
               (fail))]))))
  
  ;; add-ellipses-index : (listof mtch) sym boolean number -> (listof mtch)
  (define (add-ellipses-index mtchs key mismatch-bind? i)
    (if key
        (let ([rib (if mismatch-bind? 
                       (make-mismatch-bind key i)
                       (make-bind key i))])
          (map (λ (mtch) (make-mtch (make-bindings (cons rib (bindings-table (mtch-bindings mtch))))
                                    (mtch-context mtch)
                                    (mtch-hole mtch)))
               mtchs))
        mtchs))
  
  ;; collapse-single-multiples : (listof mtch) (listof mtch[to-lists]) -> (listof mtch[to-lists])
  (define (collapse-single-multiples bindingss multiple-bindingss)
    (apply append 
           (map
            (lambda (multiple-match)
              (let ([multiple-bindings (mtch-bindings multiple-match)])
                (map
                 (lambda (single-match)
                   (let ([single-bindings (mtch-bindings single-match)])
                     (let ([rib-ht (make-hash-table 'equal)]
                           [mismatch-rib-ht (make-hash-table 'equal)])
                       (for-each
                        (lambda (multiple-rib)
                          (cond
                            [(bind? multiple-rib)
                             (hash-table-put! rib-ht (bind-name multiple-rib) (bind-exp multiple-rib))]
                            [(mismatch-bind? multiple-rib)
                             (hash-table-put! mismatch-rib-ht (mismatch-bind-name multiple-rib) (mismatch-bind-exp multiple-rib))]))
                        (bindings-table multiple-bindings))
                       (for-each
                        (lambda (single-rib)
                          (cond
                            [(bind? single-rib)
                             (let* ([key (bind-name single-rib)]
                                    [rst (hash-table-get rib-ht key '())])
                               (hash-table-put! rib-ht key (cons (bind-exp single-rib) rst)))]
                            [(mismatch-bind? single-rib)
                             (let* ([key (mismatch-bind-name single-rib)]
                                    [rst (hash-table-get mismatch-rib-ht key '())])
                               (hash-table-put! mismatch-rib-ht key (cons (mismatch-bind-exp single-rib) rst)))]))
                        (bindings-table single-bindings))
                       (make-mtch (make-bindings (append (hash-table-map rib-ht make-bind)
                                                         (hash-table-map mismatch-rib-ht make-mismatch-bind)))
                                  (build-cons-context
                                   (mtch-context single-match)
                                   (mtch-context multiple-match))
                                  (pick-hole (mtch-hole single-match)
                                             (mtch-hole multiple-match))))))
                 bindingss)))
            multiple-bindingss)))
  
  ;; pick-hole : (union none sexp) (union none sexp) -> (union none sexp)
  (define (pick-hole s1 s2)
    (cond
      [(eq? none s1) s2]
      [(eq? none s2) s1]
      ;; MF: error message simplified because it is too close to
      ;; implementation matters. 
      [(error 'matcher.ss "found two holes" #;s1 #;s2)]))
  
  ;; reverse-multiples : (listof mtch[to-lists]) -> (listof mtch[to-lists])
  ;; reverses the rhs of each rib in the bindings and reverses the context.
  (define (reverse-multiples matches)
    (map (lambda (match)
           (let ([bindings (mtch-bindings match)])
             (make-mtch
              (make-bindings
               (map (lambda (rib)
                      (cond
                        [(bind? rib)
                         (make-bind (bind-name rib)
                                   (reverse (bind-exp rib)))]
                        [(mismatch-bind? rib)
                         (make-mismatch-bind (mismatch-bind-name rib)
                                            (reverse (mismatch-bind-exp rib)))]))
                    (bindings-table bindings)))
              (reverse-context (mtch-context match))
              (mtch-hole match))))
         matches))
  
  ;; match-nt : (listof compiled-rhs) (listof compiled-rhs) sym exp hole-info
  ;;        -> (union #f (listof bindings))
  (define (match-nt list-rhs non-list-rhs nt term hole-info)
    (let loop ([rhss (if (or (null? term) (pair? term))
                         list-rhs
                         non-list-rhs)]
               [ht #f])
      (cond
        [(null? rhss) 
         (if ht
             (hash-table-map ht (λ (k v) k))
             #f)]
        [else
         (let ([mth (remove-bindings/filter ((car rhss) term hole-info))])
           (cond
             [mth
              (let ([ht (or ht (make-hash-table 'equal))])
                (for-each (λ (x) (hash-table-put! ht x #t)) mth)
                (loop (cdr rhss) ht))]
             [else 
              (loop (cdr rhss) ht)]))])))
  
  ;; remove-bindings/filter : (union #f (listof mtch)) -> (union #f (listof mtch))
  (define (remove-bindings/filter matches)
    (and matches
         (let ([filtered (filter-multiples matches)])
           (and (not (null? filtered))
                (map (λ (match)
                       (make-mtch (make-bindings '())
                                  (mtch-context match)
                                  (mtch-hole match)))
                     matches)))))
  
  ;; rewrite-ellipses : (symbol -> boolean)
  ;;                    (listof pattern) 
  ;;                    (pattern -> (values compiled-pattern boolean))
  ;;                 -> (values (listof (union repeat compiled-pattern)) boolean)
  ;; moves the ellipses out of the list and produces repeat structures
  (define (rewrite-ellipses non-underscore-binder? pattern compile)
    (let loop ([exp-eles pattern]
               [fst dummy])
      (cond
        [(null? exp-eles)
         (if (eq? fst dummy)
             (values empty #f)
             (let-values ([(compiled has-hole?) (compile fst)])
               (values (list compiled) has-hole?)))]
        [else
         (let ([exp-ele (car exp-eles)])
           (cond
             [(or (eq? '... exp-ele)
                  (prefixed-with? "..._" exp-ele))
              (when (eq? fst dummy)
                (error 'match-pattern "bad ellipses placement: ~s" pattern))
              (let-values ([(compiled has-hole?) (compile fst)]
                           [(rest rest-has-hole?) (loop (cdr exp-eles) dummy)])
                (let ([underscore-key (if (eq? exp-ele '...) #f exp-ele)]
                      [mismatch? (and (regexp-match #rx"_!_" (symbol->string exp-ele)) #t)])
                  (values
                   (cons (make-repeat compiled (extract-empty-bindings non-underscore-binder? fst) underscore-key mismatch?) 
                         rest)
                   (or has-hole? rest-has-hole?))))]
             [(eq? fst dummy)
              (loop (cdr exp-eles) exp-ele)]
             [else
              (let-values ([(compiled has-hole?) (compile fst)]
                           [(rest rest-has-hole?) (loop (cdr exp-eles) exp-ele)])
                (values
                 (cons compiled rest)
                 (or has-hole? rest-has-hole?)))]))])))
  
  (define (prefixed-with? prefix exp)
    (and (symbol? exp)
         (let* ([str (symbol->string exp)]
                [len (string-length str)])
           (and (len . >= . (string-length prefix))
                (string=? (substring str 0 (string-length prefix))
                          prefix)))))
  
  (define dummy (box 0))
  
  ;; extract-empty-bindings : (symbol -> boolean) pattern -> (listof rib)
  (define (extract-empty-bindings non-underscore-binder? pattern)
    (let loop ([pattern pattern]
               [ribs null])
      (match pattern
        [`(variable-except ,@(vars ...)) ribs]
        [`(variable-prefix ,vars) ribs]
        [`variable-not-otherwise-mentioned ribs]
        
        [`hole (error 'match-pattern "cannot have a hole inside an ellipses")]
        [(? symbol?) 
         (cond
           [(regexp-match #rx"_!_" (symbol->string pattern))
            (cons (make-mismatch-bind pattern '()) ribs)]
           [(or (has-underscore? pattern)
                (non-underscore-binder? pattern))
            (cons (make-bind pattern '()) ribs)]
           [else ribs])]
        [`(name ,name ,pat) 
         (if (regexp-match #rx"_!_" (symbol->string name))
             (loop pat (cons (make-mismatch-bind name '()) ribs))
             (loop pat (cons (make-bind name '()) ribs)))]
        [`(in-hole ,context ,contractum) (loop context (loop contractum ribs))]
        [`(hide-hole ,p) (loop p ribs)]
        [`(in-named-hole ,hole-name ,context ,contractum) (loop context (loop contractum ribs))]
        [`(side-condition ,pat ,test) (loop pat ribs)]
        [(? list?)
         (let-values ([(rewritten has-hole?) (rewrite-ellipses non-underscore-binder? pattern (lambda (x) (values x #f)))])
           (let i-loop ([r-exps rewritten]
                        [ribs ribs])
             (cond
               [(null? r-exps) ribs]
               [else (let ([r-exp (car r-exps)])
                       (cond
                         [(repeat? r-exp) 
                          (i-loop
                           (cdr r-exps)
                           (append (repeat-empty-bindings r-exp) ribs))]
                         [else
                          (i-loop 
                           (cdr r-exps)
                           (loop (car r-exps) ribs))]))])))]
        [else ribs])))
  
  ;; combine-matches : (listof (listof mtch)) -> (listof mtch)
  ;; input is the list of bindings corresonding to a piecewise match
  ;; of a list. produces all of the combinations of complete matches
  (define (combine-matches matchess)
    (let loop ([matchess matchess])
      (cond
        [(null? matchess) (list (make-mtch (make-bindings null) (build-flat-context '()) none))]
        [else (combine-pair (car matchess) (loop (cdr matchess)))])))
  
  ;; combine-pair : (listof mtch) (listof mtch) -> (listof mtch)
  (define (combine-pair fst snd)
    (let ([mtchs null])
      (for-each 
       (lambda (mtch1)
         (for-each
          (lambda (mtch2)
            (set! mtchs (cons (make-mtch 
                               (make-bindings (append (bindings-table (mtch-bindings mtch1))
                                                      (bindings-table (mtch-bindings mtch2))))
                               (build-append-context (mtch-context mtch1) (mtch-context mtch2))
                               (pick-hole (mtch-hole mtch1) 
                                          (mtch-hole mtch2)))
                              mtchs)))
          snd))
       fst)
      mtchs))
  
  (define (hash-table-maps? ht key)
    (not (eq? (hash-table-get ht key uniq) uniq)))
  
  
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;;
  ;; context adt
  ;;
  
  #|
  ;; This version of the ADT isn't right yet -- 
  ;; need to figure out what to do about (name ...) patterns.

  (define-values (struct:context make-context context? context-ref context-set!)
    (make-struct-type 'context #f 1 0 #f '() #f 0))
  (define hole values)
  (define (build-flat-context exp) (make-context (lambda (x) exp)))
  (define (build-cons-context c1 c2) (make-context (lambda (x) (cons (c1 x) (c2 x)))))
  (define (build-append-context l1 l2) (make-context (lambda (x) (append (l1 x) (l2 x)))))
  (define (build-list-context l) (make-context (lambda (x) (list (l x)))))
  (define (build-nested-context c1 c2) (make-context (lambda (x) (c1 (c2 x)))))
  (define (plug exp hole-stuff) (exp hole-stuff))
  (define (reverse-context c) (make-context (lambda (x) (reverse (c x)))))

|#
  (define (context? x) #t)
  (define-values (make-hole/intern hole-name hole?)
    (let ()
      (define-struct hole () #f)
      (define-struct (named-hole hole) (name) #f)
      (define (hole-name h)
        (cond
          [(named-hole? h) 
           (named-hole-name h)]
          [(hole? h)
           none]
          [else (error 'hole-name "expected a hole, given ~e" h)]))
      (define (make-hole/intern a)
        (or (hash-table-get hole-cache a #f)
            (let ([h (make-named-hole a)])
              (hash-table-put! hole-cache a h)
              h)))
      (define the-hole?
        (let ([hole? (λ (x) (or (hole? x) (named-hole? x)))])
          hole?))
      (define hole-cache (make-hash-table 'equal))
      (hash-table-put! hole-cache none (make-hole)) ;; see the cache to avoid a case in make-hole/intern
      (values make-hole/intern hole-name the-hole?)))
  
  (define (build-flat-context exp) exp)
  (define (build-cons-context e1 e2) (cons e1 e2))
  (define (build-append-context e1 e2) (append e1 e2))
  (define (build-list-context x) (list x))
  (define (reverse-context x) (reverse x))
  (define (build-nested-context c1 c2 hole-info) 
    (plug c1 c2 hole-info))
  (define plug
    (case-lambda
      [(exp hole-stuff) (plug exp hole-stuff none)]
      [(exp hole-stuff hole-info)
       (let ([done? #f])
         (let loop ([exp exp])
           (cond
             [(pair? exp) 
              (cons (loop (car exp))
                    (if done?
                        (cdr exp)
                        (loop (cdr exp))))]
             
             [(and (hole? exp) 
                   (equal? (hole-name exp) hole-info))
              (set! done? #t)
              hole-stuff]
             [else exp])))]))
  
  ;;
  ;; end context adt
  ;;
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  
  ;; used in hash-table lookups to tell when something isn't in the table
  (define uniq (gensym))
  
  (provide/contract
   (match-pattern (compiled-pattern? any/c . -> . (union false/c (listof mtch?))))
   (compile-pattern (-> compiled-lang? any/c boolean?
                        compiled-pattern?))

   (set-cache-size! (-> (or/c false/c (and/c integer? positive?)) void?))
   
   (make-bindings ((listof bind?) . -> . bindings?))
   (bindings-table (bindings? . -> . (listof bind?)))
   (bindings? (any/c . -> . boolean?))
   
   (mtch? (any/c . -> . boolean?))
   (make-mtch (bindings? any/c any/c . -> . mtch?))
   (mtch-bindings (mtch? . -> . bindings?))
   (mtch-context (mtch? . -> . any/c))
   (mtch-hole (mtch? . -> . (union none? any/c)))
   
   (make-bind (symbol? any/c . -> . bind?))
   (bind? (any/c . -> . boolean?))
   (bind-name (bind? . -> . symbol?))
   (bind-exp (bind? . -> . any/c))
   (compile-language (-> any/c (listof nt?) (listof (listof symbol?)) compiled-lang?))
   (symbol->nt (symbol? . -> . symbol?))
   (split-underscore (symbol? . -> . symbol?)))
  (provide compiled-pattern? 
           print-stats)
  
  ;; for test suite
  (provide build-cons-context
           build-flat-context
           context?)
  
  (provide (struct nt (name rhs))
           (struct rhs (pattern var-info))
           (struct compiled-lang 
                   (lang ht list-ht across-ht across-list-ht has-hole-ht cache pict-builder literals nt-map))
           
           lookup-binding
           
           compiled-pattern
           
           plug
           none? none
           
           make-repeat
           make-hole/intern hole? hole-name
           rewrite-ellipses
           build-compatible-context-language))