(module tl-test mzscheme
  (require "../reduction-semantics.ss"
           "test-util.ss")
  
  (reset-count)
  
  
;                                                          
;                                                          
;    ;;                                                    
;     ;                                                    
;     ;     ;;;  ;; ;;    ;; ;;;;  ;;   ;;;    ;; ;;  ;;;  
;     ;    ;   ;  ;;  ;  ;  ;;  ;   ;  ;   ;  ;  ;;  ;   ; 
;     ;     ;;;;  ;   ;  ;   ;  ;   ;   ;;;;  ;   ;  ;;;;; 
;     ;    ;   ;  ;   ;  ;   ;  ;   ;  ;   ;  ;   ;  ;     
;     ;    ;   ;  ;   ;  ;   ;  ;  ;;  ;   ;  ;   ;  ;     
;   ;;;;;   ;;;;;;;; ;;;  ;;;;   ;; ;;  ;;;;;  ;;;;   ;;;; 
;                            ;                    ;        
;                         ;;;                  ;;;         
;                                                          
;                                                          

  
  (define-language empty-language)
  
  (define-language grammar
    (M (M M)
       number)
    (E hole
       (E M)
       (number E))
    (X (number any)
       (any number))
    (Q (Q ...)
       variable)
    (UN (add1 UN)
        zero))
  
  (test (pair? (redex-match grammar M '(1 1))) #t)
  (test (pair? (redex-match grammar M '(1 1 1))) #f)
  (test (pair? (redex-match grammar
                            (side-condition (M_1 M_2) (equal? (term M_1) (term M_2)))
                            '(1 1)))
        #t)
  (test (pair? (redex-match grammar
                           (side-condition (M_1 M_2) (equal? (term M_1) (term M_2))) 
                           '(1 2)))
        #f)
  
  (test (pair? ((redex-match grammar M) '(1 1)))
        #t)

  ;; next 3: test naming of subscript-less non-terminals
  (test (pair? (redex-match grammar (M M) (term (1 1)))) #t)
  (test (pair? (redex-match grammar (M M) (term (1 2)))) #f)
  (test (pair? (redex-match grammar (M_1 M_2) (term (1 2)))) #t)
  
  (define-language base-grammar
    (q 1)
    (e (+ e e) number)
    (x (variable-except +)))
  
  (define-extended-language extended-grammar
    base-grammar 
    (e .... (* e e))
    (x (variable-except + *))
    (r 2))
  
  (test (pair? (redex-match extended-grammar e '(+ 1 1))) #t)
  (test (pair? (redex-match extended-grammar e '(* 2 2))) #t)
  (test (pair? (redex-match extended-grammar r '2)) #t)
  (test (pair? (redex-match extended-grammar q '1)) #t)
  (test (pair? (redex-match extended-grammar x '*)) #f)
  (test (pair? (redex-match extended-grammar x '+)) #f)
  (test (pair? (redex-match extended-grammar e '....)) #f)
  
  ;; make sure that `language' with a four period ellipses signals an error
  (test (regexp-match #rx"[.][.][.][.]" (with-handlers ([exn? exn-message]) 
                                          (let ()
                                            (define-language x (e ....))
                                            12)))
        '("...."))
  

  
  ;; test multiple variable non-terminals
  (let ()
    (define-language lang
      ((l m) (l m) x)
      (x variable-not-otherwise-mentioned))
    (test (pair? (redex-match lang m (term x)))
          #t))
  
  ;; test multiple variable non-terminals
  (let ()
    (define-language lang
      ((l m) (l m) x)
      (x variable-not-otherwise-mentioned))
    (test (pair? (redex-match lang l (term x)))
          #t))
  
  (let ()
    (define-language lang
      ((x y) 1 2 3))
    (define-extended-language lang2 lang
      (x .... 4))
    (test (pair? (redex-match lang2 x 4)) #t)
    (test (pair? (redex-match lang2 y 4)) #t)
    (test (pair? (redex-match lang2 x 1)) #t)
    (test (pair? (redex-match lang2 y 2)) #t))
  
  ;; test that the variable "e" is not bound in the right-hand side of a side-condition
  ;; this one signaled an error at some point
  (let ()
    (define-language bad
      (e 2 (side-condition (e) #t)))
    (test (pair? (redex-match bad e '(2)))
          #t))

  ;; test that the variable "e" is not bound in the right-hand side of a side-condition
  ;; this one tests to make sure it really isn't bound
  (let ([x #f])
    (define-language bad
      (e 2 (side-condition (e) (set! x (term e)))))
    (redex-match bad e '(2))
    (test x 'e))
  
  ;; test multiple variable non-terminals being extended
  (let ()
    (define-language lang
      ((x y) 1 2 3))
    (define-extended-language lang2 lang
      (x .... 4))
    (test (pair? (redex-match lang2 x 4)) #t)
    (test (pair? (redex-match lang2 y 4)) #t)
    (test (pair? (redex-match lang2 x 1)) #t)
    (test (pair? (redex-match lang2 y 2)) #t))
  
  ;; test multiple variable non-terminals in an extended language
  (let ()
    (define-language lang
      ((x y) 1 2 3))
    (define-extended-language lang2 lang
      ((z w) 5 6 7))
    (test (pair? (redex-match lang2 z 5)) #t)
    (test (pair? (redex-match lang2 w 6)) #t))
  
  ;; test cases that ensure that extending any one of a
  ;; multiply defined non-terminal gets extended properly
  (let ()
    (define-language iswim
      ((V U W) AA))

    (define-extended-language iswim-cont
      iswim
      (W .... QQ))

    (test (pair? (redex-match iswim-cont U (term QQ)))
          #t))
  
  (let ()
    (define-language iswim
      ((V U W) AA))

    (define-extended-language iswim-cont
      iswim
      (W .... QQ))

    (test (pair? (redex-match iswim-cont V (term QQ)))
          #t)
    (test (pair? (redex-match iswim-cont U (term QQ)))
          #t)
    (test (pair? (redex-match iswim-cont W (term QQ)))
          #t))
  
  (let ()
    (define-language iswim
      ((V U W) AA))
    
    (define-extended-language iswim-cont
      iswim
      (V .... QQ))
    
    (test (pair? (redex-match iswim-cont V (term QQ)))
          #t)
    (test (pair? (redex-match iswim-cont U (term QQ)))
          #t)
    (test (pair? (redex-match iswim-cont W (term QQ)))
          #t))
  
  
;                                                                                             
;                                                                                             
;                                 ;;;                                ;                        
;                  ;             ;                           ;                                
;  ;;; ;    ;;;   ;;;;;   ;;;   ;;;;; ;;  ;; ;; ;;    ;;;;  ;;;;;  ;;;     ;;;  ;; ;;    ;;;; 
;   ; ; ;  ;   ;   ;     ;   ;   ;     ;   ;  ;;  ;  ;   ;   ;       ;    ;   ;  ;;  ;  ;   ; 
;   ; ; ;  ;;;;;   ;      ;;;;   ;     ;   ;  ;   ;  ;       ;       ;    ;   ;  ;   ;   ;;;  
;   ; ; ;  ;       ;     ;   ;   ;     ;   ;  ;   ;  ;       ;       ;    ;   ;  ;   ;      ; 
;   ; ; ;  ;       ;   ; ;   ;   ;     ;  ;;  ;   ;  ;   ;   ;   ;   ;    ;   ;  ;   ;  ;   ; 
;  ;;;;;;;  ;;;;    ;;;   ;;;;; ;;;;;   ;; ;;;;; ;;;  ;;;     ;;;  ;;;;;   ;;;  ;;; ;;; ;;;;  
;                                                                                             
;                                                                                             
;                                                                                             
;                                                                                             

  
  (define-metafunction grammar
    [(f (side-condition (number_1 number_2)
                        (< (term number_1)
                           (term number_2))))
     x]
    [(f (number 1)) y]
    [(f (number_1 2)) ,(+ (term number_1) 2)]
    [(f (4 4)) q]
    [(f (4 4)) r])

  (define-metafunction grammar
    [(g X) x])
  
  (test (term (f (1 17))) 'x)
  (test (term (f (11 1))) 'y)
  (test (term (f (11 2))) 13)
  
  
  ;; match two clauess => take first one
  (test (term (f (4 4))) 'q)
  
  ;; match one clause two ways => error
  (let ()
    (define-metafunction empty-language
      [(ll (number_1 ... number_2 ...)) 4])
    (test (with-handlers ((exn? (λ (x) 'exn-raised))) 
            (term (ll ()))
            'no-exn)
          'no-exn)
    (test (with-handlers ((exn? (λ (x) 'exn-raised))) 
            (term (ll (4 4)))
            'no-exn)
          'exn-raised))
  
  ;; match no ways => error
  (test (with-handlers ((exn? (λ (x) 'exn-raised))) (term (f mis-match)) 'no-exn)
        'exn-raised)

  (define-metafunction grammar
    [(h (M_1 M_2)) ((h M_2) (h M_1))]
    [(h number_1) ,(+ (term number_1) 1)])
  
  (test (term (h ((1 2) 3)))
        (term (4 (3 2))))
  
  (define-metafunction grammar
    [(h2 (Q_1 ...)) ((h2 Q_1) ...)]
    [(h2 variable) z])
  
  (test (term (h2 ((x y) a b c)))
        (term ((z z) z z z)))
  
  (let ()
    (define-metafunction empty-language
      [(f (1)) 1]
      [(f (2)) 2]
      [(f 3) 3])
    (test (in-domain? (f 1)) #f)
    (test (in-domain? (f (1))) #t)
    (test (in-domain? (f ((1)))) #f)
    (test (in-domain? (f 3)) #t)
    (test (in-domain? (f 4)) #f))
  
  (let ()
    (define-metafunction empty-language
      f : number -> number
      [(f 1) 1])
    (test (in-domain? (f 1)) #t)
    (test (in-domain? (f 2)) #t)
    (test (in-domain? (f x)) #f))
  
  (let ()
    (define-metafunction empty-language
      [(f x) x])
    (test 
     (term-let ((y 'x))
               (in-domain? (f y)))
     #t)
    (test 
     (term-let ((y 'z))
               (in-domain? (f y)))
     #f))
  
  ;; mutually recursive metafunctions
  (define-metafunction grammar
    [(odd zero) #f]
    [(odd (add1 UN_1)) (even UN_1)])
  
  (define-metafunction grammar
    [(even zero) #t]
    [(even (add1 UN_1)) (odd UN_1)])
  
  (test (term (odd (add1 (add1 (add1 (add1 zero))))))
        (term #f))
    
  (let ()
    (define-metafunction empty-language
      [(pRe xxx) 1])
    
    (define-metafunction empty-language
      [(Merge-Exns any_1) any_1])
    
    (test (term (pRe (Merge-Exns xxx)))
          1))
  
  (let ()
    (define-metafunction empty-language
      [(f (x)) ,(term-let ([var-should-be-lookedup 'y]) (term (f var-should-be-lookedup)))]
      [(f y) y]
      [(f var-should-be-lookedup) var-should-be-lookedup]) ;; taking this case is bad!
    
    (test (term (f (x))) (term y)))
  
  (let ()
    (define-metafunction empty-language
      [(f (x)) (x ,@(term-let ([var-should-be-lookedup 'y]) (term (f var-should-be-lookedup))) x)]
      [(f y) (y)]
      [(f var-should-be-lookedup) (var-should-be-lookedup)]) ;; taking this case is bad!
    
    (test (term (f (x))) (term (x y x))))
  
  (let ()
    (define-metafunction empty-language
      [(f (any_1 any_2))
       case1
       (side-condition (not (equal? (term any_1) (term any_2))))
       (side-condition (not (equal? (term any_1) 'x)))]
      [(f (any_1 any_2))
       case2
       (side-condition (not (equal? (term any_1) (term any_2))))]
      [(f (any_1 any_2))
       case3])
    (test (term (f (q r))) (term case1))
    (test (term (f (x y))) (term case2))
    (test (term (f (x x))) (term case3)))

  (let ()
    (define-metafunction empty-language
      [(f (n number)) (n number)]
      [(f (a any)) (a any)]
      [(f (v variable)) (v variable)]
      [(f (s string)) (s string)])
    (test (term (f (n 1))) (term (n 1)))
    (test (term (f (a (#f "x" whatever)))) (term (a (#f "x" whatever))))
    (test (term (f (v x))) (term (v x)))
    (test (term (f (s "x"))) (term (s "x"))))
  
  ;; test ..._1 patterns
  (let ()
    (define-metafunction empty-language
      [(zip ((variable_id ..._1) (number_val ..._1)))
       ((variable_id number_val) ...)])
    
    (test (term (zip ((a b) (1 2)))) (term ((a 1) (b 2)))))
  
  (let ()
    (define-metafunction empty-language
      [(f any_1 any_2 any_3) (any_3 any_2 any_1)])
    (test (term (f 1 2 3)) 
          (term (3 2 1))))
  
  (let ()
    (define-metafunction empty-language
      [(f (any_1 any_2 any_3)) 3])
    (define-metafunction/extension f empty-language
      [(g (any_1 any_2)) 2])
    (test (term (g (1 2))) 2)
    (test (term (g (1 2 3))) 3))
  
  (let ()
    (define-metafunction empty-language
      [(f any_1 any_2 any_3) 3])
    (define-metafunction/extension f empty-language
      [(g any_1 any_2) 2])
    (test (term (g 1 2)) 2)
    (test (term (g 1 2 3)) 3))
  
  (let ()
    (define-metafunction empty-language
      [(f number_1 number_2) (f number_1)])
    (define-metafunction/extension f empty-language
      [(g number_1) number_1])
    (define-metafunction empty-language
      [(h number_1 number_2) (h number_1)]
      [(h number_1) number_1])
    (test (term (g 11 17)) 11)
    (test (term (h 11 17)) 11))
  
  (let ()
    (define-metafunction empty-language
      [(f (number_1 number_2))
       number_3
       (where number_3 (+ (term number_1) (term number_2)))])
    (test (term (f (11 17))) 28))
  

;                                                                                                                                
;                                                                                                                                
;                    ;;                         ;                                        ;;                    ;                 
;                     ;                 ;                                                 ;            ;                         
;   ;; ;;   ;;;    ;; ; ;;  ;;   ;;;;  ;;;;;  ;;;     ;;;  ;; ;;          ;; ;;   ;;;     ;     ;;;   ;;;;;  ;;;     ;;;  ;; ;;  
;    ;;    ;   ;  ;  ;;  ;   ;  ;   ;   ;       ;    ;   ;  ;;  ;          ;;    ;   ;    ;    ;   ;   ;       ;    ;   ;  ;;  ; 
;    ;     ;;;;;  ;   ;  ;   ;  ;       ;       ;    ;   ;  ;   ;  ;;;;;   ;     ;;;;;    ;     ;;;;   ;       ;    ;   ;  ;   ; 
;    ;     ;      ;   ;  ;   ;  ;       ;       ;    ;   ;  ;   ;          ;     ;        ;    ;   ;   ;       ;    ;   ;  ;   ; 
;    ;     ;      ;   ;  ;  ;;  ;   ;   ;   ;   ;    ;   ;  ;   ;          ;     ;        ;    ;   ;   ;   ;   ;    ;   ;  ;   ; 
;   ;;;;;   ;;;;   ;;;;;  ;; ;;  ;;;     ;;;  ;;;;;   ;;;  ;;; ;;;        ;;;;;   ;;;;  ;;;;;   ;;;;;   ;;;  ;;;;;   ;;;  ;;; ;;;
;                                                                                                                                
;                                                                                                                                
;                                                                                                                                
;                                                                                                                                

  
  (test (apply-reduction-relation
         (reduction-relation 
          grammar
          (--> (in-hole E_1 (number_1 number_2))
               (in-hole E_1 ,(* (term number_1) (term number_2)))))
         '((2 3) (4 5)))
        (list '(6 (4 5))))

  (test (apply-reduction-relation
         (reduction-relation 
          grammar
          (~~> (number_1 number_2)
               ,(* (term number_1) (term number_2)))
          with
          [(--> (in-hole E_1 a) (in-hole E_1 b)) (~~> a b)])
         '((2 3) (4 5)))
        (list '(6 (4 5))))
  
  (test (apply-reduction-relation
         (reduction-relation 
          grammar
          (==> (number_1 number_2)
               ,(* (term number_1) (term number_2)))
          with
          [(--> (M_1 a) (M_1 b)) (~~> a b)]
          [(~~> (M_1 a) (M_1 b)) (==> a b)])
         '((1 2) ((2 3) (4 5))))
        (list '((1 2) ((2 3) 20))))
  
  (test (apply-reduction-relation
         (reduction-relation 
          grammar
          (~~> (number_1 number_2)
               ,(* (term number_1) (term number_2)))
          (==> (number_1 number_2)
               ,(* (term number_1) (term number_2)))
          with
          [(--> (M_1 a) (M_1 b)) (~~> a b)]
          [(--> (a M_1) (b M_1)) (==> a b)])
         '((2 3) (4 5)))
        (list '(6 (4 5))
              '((2 3) 20)))
  
  (test (apply-reduction-relation
         (reduction-relation 
          grammar
          (--> (M_1 (number_1 number_2))
               (M_1 ,(* (term number_1) (term number_2))))
          (==> (number_1 number_2)
               ,(* (term number_1) (term number_2)))
          with
          [(--> (a M_1) (b M_1)) (==> a b)])
         '((2 3) (4 5)))
        (list '((2 3) 20)
              '(6 (4 5))))
  
  (test (apply-reduction-relation/tag-with-names
         (reduction-relation 
          grammar
          (--> (number_1 number_2) 
               ,(* (term number_1) (term number_2))
               mul))
         '(4 5))
        (list (list "mul" 20)))
  
  (test (apply-reduction-relation/tag-with-names
         (reduction-relation 
          grammar
          (--> (number_1 number_2) 
               ,(* (term number_1) (term number_2))
               "mul"))
         '(4 5))
        (list (list "mul" 20)))
  
  (test (apply-reduction-relation/tag-with-names
         (reduction-relation 
          grammar
          (--> (number_1 number_2) 
               ,(* (term number_1) (term number_2))))
         '(4 5))
        (list (list #f 20)))
  
  (test (apply-reduction-relation/tag-with-names
         (reduction-relation 
          grammar
          (==> (number_1 number_2) 
               ,(* (term number_1) (term number_2))
               mult)
          with
          [(--> (M_1 a) (M_1 b)) (==> a b)])
         '((2 3) (4 5)))
        (list (list "mult" '((2 3) 20))))
  
  (test (apply-reduction-relation
         (union-reduction-relations
          (reduction-relation empty-language
                              (--> x a)
                              (--> x b))
          (reduction-relation empty-language
                              (--> x c)
                              (--> x d)))
         'x)
        (list 'a 'b 'c 'd))
  
  (test (apply-reduction-relation
         (union-reduction-relations
          (reduction-relation empty-language (--> x a))
          (reduction-relation empty-language (--> x b))
          (reduction-relation empty-language (--> x c))
          (reduction-relation empty-language (--> x d)))
         'x)
        (list 'a 'b 'c 'd))
  
  (test (apply-reduction-relation
         (reduction-relation 
          empty-language
          (--> (number_1 number_2) 
               number_2
               (side-condition (< (term number_1) (term number_2))))
          (--> (number_1 number_2) 
               number_1
               (side-condition (< (term number_2) (term number_1)))))
         '(1 2))
        (list 2))
  
  (test (apply-reduction-relation
         (reduction-relation 
          empty-language
          (--> x #f))
         (term x))
        (list #f))
  
  (define-language x-language
    (x variable))
  
  (test (apply-reduction-relation
         (reduction-relation 
          x-language
          (--> x (x x)))
         'y)
        (list '(y y)))
  
  (test (apply-reduction-relation
         (reduction-relation 
          x-language
          (--> (x ...) ((x ...))))
         '(p q r))
        (list '((p q r))))

  (parameterize ([current-namespace syn-err-test-namespace])
    (eval (quote-syntax
           (define-language grammar
             (M (M M)
                number)
             (E hole
                (E M)
                (number E))
             (X (number any)
                (any number))
             (Q (Q ...)
                variable)
             (UN (add1 UN)
                 zero)))))
  
  (test-syn-err (reduction-relation 
                 grammar
                 (~~> (number_1 number_2)
                      ,(* (term number_1) (term number_2)))
                 with
                 [(--> (M a) (M b)) (~~> a b)]
                 [(~~> (M a) (M b)) (==> a b)])
                #rx"no rules")
  
  (test-syn-err (reduction-relation grammar)
                #rx"no rules use -->")
  
  (test-syn-err (reduction-relation 
                 grammar
                 (~~> (number_1 number_2)
                      ,(* (term number_1) (term number_2))))
                #rx"~~> relation is not defined")
  
  (test-syn-err (reduction-relation 
                 grammar
                 (--> (number_1 number_2) 
                      ,(* (term number_1) (term number_2))
                      mult)
                 (--> (number_1 number_2) 
                      ,(* (term number_1) (term number_2))
                      mult))
                #rx"same name on multiple rules")
  
  (test-syn-err (reduction-relation 
                 grammar
                 (--> 1 2)
                 (==> 3 4))
                #rx"not defined.*==>")
  
  (test-syn-err  (reduction-relation 
                  empty-language
                  (--> 1 2)
                  (==> 3 4)
                  with
                  [(~> a b) (==> a b)])
                 #rx"not defined.*~>")
  
  (test-syn-err (define-language bad-lang1 (e name)) #rx"name")
  (test-syn-err (define-language bad-lang2 (name x)) #rx"name")
  (test-syn-err (define-language bad-lang3 (x_y x)) #rx"x_y")
  
  ;; expect union with duplicate names to fail
  (test (with-handlers ((exn? (λ (x) 'passed)))
          (union-reduction-relations
           (reduction-relation 
            grammar
            (--> (number_1 number_2) 
                 ,(* (term number_1) (term number_2))
                 mult))
           (reduction-relation 
            grammar
            (--> (number_1 number_2) 
                 ,(* (term number_1) (term number_2))
                 mult)))
          'failed)
        'passed)
  
  (test (with-handlers ((exn? (λ (x) 'passed)))
          (union-reduction-relations
           (union-reduction-relations
            (reduction-relation 
             grammar
             (--> (number_1 number_2) 
                  ,(* (term number_1) (term number_2))
                  mult))
            (reduction-relation 
             grammar
             (--> (number_1 number_2) 
                  ,(* (term number_1) (term number_2))
                  mult3)))
           
           (union-reduction-relations
            (reduction-relation 
             grammar
             (--> (number_1 number_2) 
                  ,(* (term number_1) (term number_2))
                  mult))
            (reduction-relation 
             grammar
             (--> (number_1 number_2) 
                  ,(* (term number_1) (term number_2))
                  mult2))))
          'passed)
        'passed)
  
  ;; sorting in this test case is so that the results come out in a predictable manner.
  (test (sort
         (apply-reduction-relation
          (compatible-closure 
           (reduction-relation 
            grammar
            (--> (number_1 number_2) 
                 ,(* (term number_1) (term number_2))
                 mult))
           grammar
           M)
          '((2 3) (4 5)))
         (λ (x y) (string<=? (format "~s" x) (format "~s" y))))
        (list '((2 3) 20)
              '(6 (4 5))))
  
  (test (apply-reduction-relation
         (compatible-closure 
          (reduction-relation 
           grammar
           (--> (number_1 number_2) 
                ,(* (term number_1) (term number_2))
                mult))
          grammar
          M)
         '(4 2))
        (list '8))
  
  (test (apply-reduction-relation
         (context-closure 
          (context-closure 
           (reduction-relation grammar (--> 1 2))
           grammar
           (y hole))
          grammar
          (x hole))
         '(x (y 1)))
        (list '(x (y 2))))

  (test (apply-reduction-relation
         (reduction-relation 
          grammar
          (--> (variable_1 variable_2) 
               (variable_1 variable_2 x)
               mul
               (fresh x)))
         '(x x1))
        (list '(x x1 x2)))
  
  (test (apply-reduction-relation
         (reduction-relation 
          grammar
          (~~> number 
               x
               (fresh x))
          with 
          [(--> (variable_1 variable_2 a) (variable_1 variable_2 b)) (~~> a b)])
         '(x x1 2))
        (list '(x x1 x2)))
  
  (test (apply-reduction-relation
         (reduction-relation 
          x-language
          (--> (x_1 ...)
               (x ...)
               (fresh ((x ...) (x_1 ...)))))
         '(x y x1))
        (list '(x2 x3 x4)))

  (test (apply-reduction-relation
         (reduction-relation
          empty-language
          (--> (variable_1 ...)
               (x ... variable_1 ...)
               (fresh ((x ...) (variable_1 ...) (variable_1 ...)))))
         '(x y z))
        (list '(x1 y1 z1 x y z)))
  
  (test (apply-reduction-relation
         (reduction-relation
          empty-language
          (--> variable_1
               (x variable_1)
               (fresh (x variable_1))))
         'q)
        (list '(q1 q)))
  
  (test (apply-reduction-relation
         (extend-reduction-relation (reduction-relation empty-language (--> 1 2))
                                    empty-language
                                    (--> 1 3))
         1)
        '(3 2))
  
  (let ()
    (define-language e1
      (e 1))
    (define-language e2
      (e 2))
    (define red1 (reduction-relation e1 (--> e (e e))))
    (define red2 (extend-reduction-relation red1 e2 (--> ignoreme ignoreme)))
    (test (apply-reduction-relation red1 1) '((1 1)))
    (test (apply-reduction-relation red1 2) '())
    (test (apply-reduction-relation red2 1) '())
    (test (apply-reduction-relation red2 2) '((2 2))))
  
  (let ()
    (define red1 (reduction-relation empty-language
                                     (--> a (a a) 
                                          a)
                                     (--> b (b b) 
                                          b)
                                     (--> q x)))
    (define red2 (extend-reduction-relation red1
                                            empty-language
                                            (--> a (c c)
                                                 a)
                                            (--> q z)))
    (test (apply-reduction-relation red1 (term a)) (list (term (a a))))
    (test (apply-reduction-relation red1 (term b)) (list (term (b b))))
    (test (apply-reduction-relation red1 (term q)) (list (term x)))
    (test (apply-reduction-relation red2 (term a)) (list (term (c c))))
    (test (apply-reduction-relation red2 (term b)) (list (term (b b))))
    (test (apply-reduction-relation red2 (term q)) (list (term z) (term x))))
  
  (let ()
    (define red1 
      (reduction-relation
       empty-language
       (==> a (a a) 
            a)
       (==> b (b b) 
            b)
       (==> q w)
       with
       [(--> (X a) (X b)) (==> a b)]))
    
    (define red2 
      (extend-reduction-relation
       red1
       empty-language
       (==> a (c c)
            a)
       (==> q z)
       with
       [(--> (X a) (X b)) (==> a b)]))
    
    (test (apply-reduction-relation red1 (term (X a))) (list (term (X (a a)))))
    (test (apply-reduction-relation red1 (term (X b))) (list (term (X (b b)))))
    (test (apply-reduction-relation red1 (term (X q))) (list (term (X w))))
    (test (apply-reduction-relation red2 (term (X a))) (list (term (X (c c)))))
    (test (apply-reduction-relation red2 (term (X b))) (list (term (X (b b)))))
    (test (apply-reduction-relation red2 (term (X q))) (list (term (X z)) 
                                                             (term (X w)))))
  
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;;
  ;; examples from doc.txt
  ;;
  
  (define-language lc-lang
    (e (e e ...)
       x
       v)
    (c (v ... c e ...)
       hole)
    (v (lambda (x ...) e))
    (x variable-not-otherwise-mentioned))
  
  (test (let ([m (redex-match lc-lang e (term (lambda (x) x)))])
          (and m (length m)))
        1)
  
  (define-extended-language qabc-lang lc-lang (q a b c))
  
  (test (redex-match qabc-lang
                     e
                     (term (lambda (a) a)))
        #f)
  
  (test (let ([m (redex-match qabc-lang
                              e
                              (term (lambda (z) z)))])
          (and m (length m)))
        1)
  
  (require (lib "list.ss"))
  (define-metafunction lc-lang
    free-vars : e -> (listof x)
    [(free-vars (e_1 e_2 ...))
     ,(apply append (term ((free-vars e_1) (free-vars e_2) ...)))]
    [(free-vars x_1) ,(list (term x_1))]
    [(free-vars (lambda (x_1 ...) e_1))
     ,(foldr remq (term (free-vars e_1)) (term (x_1 ...)))])
  
  (test (term (free-vars (lambda (x) (x y))))
        (list 'y))

  (test (variable-not-in (term (x y z)) 'x)
        (term x1))
  
  (test (variable-not-in (term (y z)) 'x)
        (term x))
  (test (variable-not-in (term (x x1 x2 x3 x4 x5 x6 x7 x8 x9 x10)) 'x)
        (term x11))
  (test (variable-not-in (term (x x11)) 'x)
        (term x1))
  (test (variable-not-in (term (x x1 x2 x3)) 'x1)
        (term x4))
  (test (variable-not-in (term (x x1 x1 x2 x2)) 'x)
        (term x3))
  
  (test (variables-not-in (term (x y z)) '(x))
        '(x1))
  (test (variables-not-in (term (x2 y z)) '(x x x))
        '(x x1 x3))
  
  (test ((term-match/single empty-language
                            [(variable_x variable_y)
                             (cons (term variable_x)
                                   (term variable_y))])
         '(x y))
        '(x . y))
  
  (test ((term-match/single empty-language
                            [(side-condition (variable_x variable_y)
                                             (eq? (term variable_x) 'x))
                             (cons (term variable_x)
                                   (term variable_y))])
         '(x y))
        '(x . y))
  
  (define-language x-is-1-language
    [x 1])
  
  (test ((term-match/single x-is-1-language
                            [(x x)
                             1])
         '(1 1))
        1)
  
  (test (let ([x 0])
          (cons ((term-match empty-language
                             [(any_a ... number_1 any_b ...)
                              (begin (set! x (+ x 1))
                                     (term number_1))])
                 '(1 2 3))
                x))
        '((3 2 1) . 3))
  
  (test ((term-match empty-language
                     [number_1
                      (term number_1)]
                     [number_1
                      (term number_1)])
         '1)
        '(1 1))
  
  (test (apply-reduction-relation
         (reduction-relation
          x-language
          (--> (x_one x_!_one x_!_one x_!_one)
               (x_one x_!_one)))
         (term (a a b c)))
        (list (term (a x_!_one))))
  
  ;; tests `where' clauses in reduction relation
  (test (apply-reduction-relation
         (reduction-relation empty-language
                             (--> number_1 
                                  y
                                  (where y ,(+ 1 (term number_1)))))
         3)
        '(4))
  
  ;; tests `where' clauses scoping
  (test (let ([x 5])
          (apply-reduction-relation
           (reduction-relation empty-language
                               (--> any 
                                    z
                                    (where y ,x)
                                    (where x 2)
                                    (where z ,(+ (term y) (term x)))))
           'whatever))
        '(7))
  
  ;; test that where clauses bind in side-conditions that follow
  (let ([save1 #f]
        [save2 #f])
    (term-let ([y (term outer-y)])
              (test (begin (apply-reduction-relation
                            (reduction-relation empty-language
                                                (--> number_1 
                                                     y
                                                     (side-condition (set! save1 (term y)))
                                                     (where y inner-y)
                                                     (side-condition (set! save2 (term y)))))
                            3)
                           (list save1 save2))
                    (list 'outer-y 'inner-y))))
  
  (test (apply-reduction-relation
         (reduction-relation empty-language
                             (--> any 
                                  y
                                  (fresh x)
                                  (where y x)))
         'x)
        '(x1))
  
  (print-tests-passed 'tl-test.ss))