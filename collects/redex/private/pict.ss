#lang scheme/base
(require (lib "mrpict.ss" "texpict")
         (lib "utils.ss" "texpict")
         scheme/gui/base
         scheme/class
         "reduction-semantics.ss"
         "struct.ss"
         "loc-wrapper.ss"
         "matcher.ss"
         "arrow.ss"
         "core-layout.ss")
(require (for-syntax scheme/base))

(provide language->pict
         language->ps
         reduction-relation->pict
         reduction-relation->ps
         metafunction->pict
         metafunction->ps
         
         basic-text
         
         default-style
         label-style
         literal-style
         metafunction-style
         
         label-font-size
         default-font-size
         metafunction-font-size
         reduction-relation-rule-separation
         
         linebreaks
         
         just-before
         just-after
         
         rule-pict-style
         arrow-space
         label-space
         metafunction-pict-style
         compact-vertical-min-width
         extend-language-show-union
         set-arrow-pict!)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;   reduction to pict
;;

(define reduction-relation->pict
  (λ (rr [rules #f])
    ((rule-pict-style->proc)
     (map (rr-lws->trees (language-nts (reduction-relation-lang rr)))
          (if rules
              (let ([ht (make-hash)])
                (for-each (lambda (rp)
                            (hash-set! ht (rule-pict-label rp) rp))
                          (reduction-relation-lws rr))
                (map (lambda (label)
                       (hash-ref ht label
                                 (lambda ()
                                   (error 'reduction-relation->pict
                                          "no rule found for label: ~e"
                                          label))))
                     rules))
              (reduction-relation-lws rr))))))

(define reduction-relation->ps
  (λ (rr filename [rules #f])
    (save-as-ps (λ () (reduction-relation->pict rr rules))
                filename)))

(define ((rr-lws->trees nts) rp)
  (let ([tp (λ (x) (lw->pict nts x))])
    (make-rule-pict (rule-pict-arrow rp)
                    (tp (rule-pict-lhs rp))
                    (tp (rule-pict-rhs rp))
                    (rule-pict-label rp)
                    (map tp (rule-pict-side-conditions rp))
                    (map tp (rule-pict-fresh-vars rp))
                    (map (lambda (v)
                           (cons (tp (car v)) (tp (cdr v))))
                         (rule-pict-pattern-binds rp)))))

(define current-label-extra-space (make-parameter 0))
(define reduction-relation-rule-separation (make-parameter 4))

(define (rule-picts->pict/horizontal rps)
  (let* ([sep 2]
         [max-rhs (apply max
                         0
                         (map pict-width
                              (map rule-pict-rhs rps)))]
         [max-w (apply max
                       0
                       (map (lambda (rp)
                              (+ sep sep
                                 (pict-width (rule-pict-lhs rp))
                                 (pict-width (arrow->pict (rule-pict-arrow rp)))
                                 (pict-width (rule-pict-rhs rp))))
                            rps))])
    (table 4
           (apply
            append
            (map (lambda (rp)
                   (let ([arrow (hbl-append (blank (arrow-space) 0)
                                            (arrow->pict (rule-pict-arrow rp))
                                            (blank (arrow-space) 0))]
                         [lhs (rule-pict-lhs rp)]
                         [rhs (rule-pict-rhs rp)]
                         [spc (basic-text " " (default-style))]
                         [label (hbl-append (blank (label-space) 0) (rp->pict-label rp))]
                         [sep (blank 4)])
                     (list lhs arrow rhs label
                           (blank) (blank)
                           (let ([sc (rp->side-condition-pict rp max-w)])
                             (inset sc (min 0 (- max-rhs (pict-width sc))) 0 0 0))
                           (blank)
                           sep (blank) (blank) (blank))))
                 rps))
           (list* rtl-superimpose ctl-superimpose ltl-superimpose)
           (list* rtl-superimpose ctl-superimpose ltl-superimpose)
           (list* sep sep (+ sep (current-label-extra-space))) 2)))

(define arrow-space (make-parameter 0))
(define label-space (make-parameter 0))

(define ((make-vertical-style side-condition-combiner) rps)
  (let* ([mk-top-line-spacer
          (λ (rp)
            (hbl-append (rule-pict-lhs rp)
                        (basic-text " " (default-style))
                        (arrow->pict (rule-pict-arrow rp))
                        (basic-text " " (default-style))
                        (rp->pict-label rp)))]
         [mk-bot-line-spacer
          (λ (rp)
            (rt-superimpose
             (rule-pict-rhs rp)
             (rp->side-condition-pict rp +inf.0)))]
         [multi-line-spacer
          (ghost
           (launder
            (ctl-superimpose 
             (apply ctl-superimpose (map mk-top-line-spacer rps))
             (apply ctl-superimpose (map mk-bot-line-spacer rps)))))]
         [spacer (dc void 
                     (pict-width multi-line-spacer)
                     (pict-descent multi-line-spacer) ;; probably could be zero ...
                     0
                     (pict-descent multi-line-spacer))])
    (apply
     vl-append
     (add-between
      (blank 0 (reduction-relation-rule-separation))
      (map (λ (rp)
             (side-condition-combiner
              (vl-append
               (ltl-superimpose 
                (htl-append (rule-pict-lhs rp)
                            (basic-text " " (default-style))
                            (arrow->pict (rule-pict-arrow rp)))
                (rtl-superimpose 
                 spacer
                 (rp->pict-label rp)))
               (rule-pict-rhs rp))
              (rp->side-condition-pict rp +inf.0)))
           rps)))))

(define compact-vertical-min-width (make-parameter 0))

(define rule-picts->pict/vertical 
  (make-vertical-style vr-append))

(define rule-picts->pict/vertical-overlapping-side-conditions
  (make-vertical-style rbl-superimpose))

(define (rule-picts->pict/compact-vertical rps)
  (let ([max-w (apply max
                      (compact-vertical-min-width)
                      (map pict-width
                           (append
                            (map rule-pict-lhs rps)
                            (map rule-pict-rhs rps))))])
    (table 3
           (apply
            append
            (map (lambda (rp)
                   (let ([arrow (hbl-append (arrow->pict (rule-pict-arrow rp)) (blank (arrow-space) 0))]
                         [lhs (rule-pict-lhs rp)]
                         [rhs (rule-pict-rhs rp)]
                         [spc (basic-text " " (default-style))]
                         [label (hbl-append (blank (label-space) 0) (rp->pict-label rp))]
                         [sep (blank (compact-vertical-min-width)
                                     (reduction-relation-rule-separation))])
                     (if ((apply + (map pict-width (list lhs spc arrow spc rhs)))
                          . < .
                          max-w)
                         (list 
                          (blank) (hbl-append lhs spc arrow spc rhs) label
                          (blank) (rp->side-condition-pict rp max-w) (blank)
                          (blank) sep (blank))
                         (list (blank) lhs label
                               arrow rhs (blank)
                               (blank) (rp->side-condition-pict rp max-w) (blank)
                               (blank) sep (blank)))))
                 rps))
           ltl-superimpose ltl-superimpose
           (list* 2 (+ 2 (current-label-extra-space))) 2)))

(define (side-condition-pict fresh-vars side-conditions pattern-binds max-w)
  (let* ([frsh 
          (if (null? fresh-vars)
              null
              (list
               (hbl-append
                (apply 
                 hbl-append
                 (add-between
                  (basic-text ", " (default-style))
                  fresh-vars))
                (basic-text " fresh" (default-style)))))]
         [binds (map (lambda (b)
                       (htl-append
                        (car b)
                        (make-=)
                        (cdr b)))
                     pattern-binds)]
         [lst (add-between
               'comma
               (append
                binds
                side-conditions
                frsh))])
    (if (null? lst)
        (blank)
        (let ([where (basic-text " where " (default-style))])
          (let ([max-w (- max-w (pict-width where))])
            (htl-append where
                        (let loop ([p (car lst)][lst (cdr lst)])
                          (cond
                            [(null? lst) p]
                            [(eq? (car lst) 'comma)
                             (loop (htl-append p (basic-text ", " (default-style)))
                                   (cdr lst))]
                            [((+ (pict-width p) (pict-width (car lst))) . > . max-w)
                             (vl-append p
                                        (loop (car lst) (cdr lst)))]
                            [else (loop (htl-append p (car lst)) (cdr lst))]))))))))

(define (rp->side-condition-pict rp max-w)
  (side-condition-pict (rule-pict-fresh-vars rp)
                       (rule-pict-side-conditions rp)
                       (rule-pict-pattern-binds rp)
                       max-w))

(define (rp->pict-label rp)
  (if (rule-pict-label rp)
      (let ([m (regexp-match #rx"^([^_]*)(?:_([^_]*)|)$" 
                             (format "~a" (rule-pict-label rp)))])
        (hbl-append
         ((current-text) " [" (label-style) (label-font-size))
         ((current-text) (cadr m) (label-style) (label-font-size))
         (if (caddr m)
             ((current-text) (caddr m) `(subscript . ,(label-style)) (label-font-size))
             (blank))
         ((current-text) "]" (label-style) (label-font-size))))
      (blank)))

(define (add-between i l)
  (cond
    [(null? l) l]
    [else 
     (cons (car l)
           (apply append 
                  (map (λ (x) (list i x)) (cdr l))))]))

(define (make-horiz-space picts) (blank (pict-width (apply cc-superimpose picts)) 0))

(define rule-pict-style (make-parameter 'vertical))
(define (rule-pict-style->proc)
  (case (rule-pict-style)
    [(vertical) rule-picts->pict/vertical]
    [(compact-vertical) rule-picts->pict/compact-vertical]
    [(vertical-overlapping-side-conditions)
     rule-picts->pict/vertical-overlapping-side-conditions]
    [else rule-picts->pict/horizontal]))

(define (mk-arrow-pict sz style)
  (let ([cache (make-hash)])
    (lambda ()
      (let ([s (default-font-size)])
        ((hash-ref cache s
                   (lambda ()
                     (let ([f (make-arrow-pict sz style 'roman s)])
                       (hash-set! cache s f)
                       f))))))))

(define long-arrow-pict (mk-arrow-pict "xxx" 'straight))
(define short-arrow-pict (mk-arrow-pict "m" 'straight))
(define curvy-arrow-pict (mk-arrow-pict "xxx" 'curvy))
(define short-curvy-arrow-pict (mk-arrow-pict "m" 'curvy))
(define double-arrow-pict (mk-arrow-pict "xxx" 'straight-double))
(define short-double-arrow-pict (mk-arrow-pict "m" 'straight-double))

(define user-arrow-table (make-hasheq))
(define (set-arrow-pict! arr thunk)
  (hash-set! user-arrow-table arr thunk))

(define (arrow->pict arr)
  (let ([ut (hash-ref user-arrow-table arr #f)])
    (if ut
        (ut)
        (case arr
          [(--> -+>) (long-arrow-pict)]
          [(==>) (double-arrow-pict)]
          [(->) (short-arrow-pict)]
          [(=>) (short-double-arrow-pict)]
          [(..>) (basic-text "\u21E2" (default-style))]
          [(>->) (basic-text "\u21a3" (default-style))]
          [(~~>) (curvy-arrow-pict)]
          [(~>) (short-curvy-arrow-pict)]
          [(:->) (basic-text "\u21a6" (default-style))]
          [(c->) (basic-text "\u21aa" (default-style))]
          [(-->>) (basic-text "\u21a0" (default-style))]
          [(>--) (basic-text "\u291a" (default-style))]
          [(--<) (basic-text "\u2919" (default-style))]
          [(>>--) (basic-text "\u291c" (default-style))]
          [(--<<) (basic-text "\u291b" (default-style))]
          [else (error 'arrow->pict "unknown arrow ~s" arr)]))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;  language to pict
;;

;; type flattened-language-pict-info =
;;   (listof (cons (listof symbol[nt]) (listof loc-wrapper[rhs])))
;; type language-pict-info = 
;;  (union (vector flattened-language-pict-info language-pict-info) 
;;         flattened-language-pict-info)

(define (language->ps lang filename [non-terminals #f] #:pict-wrap [pict-wrap (lambda (p) p)])
  (when non-terminals
    (check-non-terminals 'language->ps non-terminals lang))
  (save-as-ps (λ () (pict-wrap (language->pict lang non-terminals)))
              filename))

(define (language->pict lang [non-terminals #f])
  (when non-terminals
    (check-non-terminals 'language->pict non-terminals lang))
  (let* ([all-non-terminals (hash-map (compiled-lang-ht lang) (λ (x y) x))]
         [non-terminals (or non-terminals all-non-terminals)])
    (make-grammar-pict (compiled-lang-pict-builder lang) 
                       non-terminals
                       all-non-terminals)))

(define (check-non-terminals what nts lang)
  (let ([langs-nts (language-nts lang)])
    (for-each
     (λ (nt) 
       (unless (memq nt langs-nts)
         (error what 
                "the non-terminal ~s is not one of the language's nonterminals (~a)"
                nt
                (if (null? langs-nts)
                    "it has no non-terminals"
                    (apply
                     string-append
                     "which are: "
                     (format "~a" (car langs-nts))
                     (map (λ (x) (format " ~a" x)) (cdr langs-nts)))))))
     nts)))

;; lang-pict-builder : (-> pict) string -> void
(define (save-as-ps mk-pict filename) 
  (let ([ps-dc (make-ps-dc filename)])
    (parameterize ([dc-for-text-size ps-dc])
      (send ps-dc start-doc "x")
      (send ps-dc start-page)
      (draw-pict (mk-pict) ps-dc 0 0)
      (send ps-dc end-page)
      (send ps-dc end-doc))))

(define (make-ps-dc filename)
  (let ([ps-setup (make-object ps-setup%)])
    (send ps-setup copy-from (current-ps-setup))
    (send ps-setup set-file filename)
    (parameterize ([current-ps-setup ps-setup])
      (make-object post-script-dc% #f #f))))

;; raw-info : language-pict-info
;; nts : (listof symbol) -- the nts that the user expects to see
(define (make-grammar-pict raw-info nts all-nts)
  (let* ([info (remove-unwanted-nts nts (flatten-grammar-info raw-info all-nts))]
         [term-space 
          (launder
           (ghost
            (apply cc-superimpose (map (λ (x) (sequence-of-non-terminals (car x)))
                                       info))))])
    (apply vl-append
           (map (λ (line)
                  (htl-append 
                   (rc-superimpose term-space (sequence-of-non-terminals (car line)))
                   (lw->pict
                    all-nts
                    (find-enclosing-loc-wrapper (add-bars-and-::= (cdr line))))))
                info))))

(define (sequence-of-non-terminals nts)
  (let loop ([nts (cdr nts)]
             [pict (non-terminal (format "~a" (car nts)))])
    (cond
      [(null? nts) pict]
      [else 
       (loop (cdr nts)
             (hbl-append pict 
                         (non-terminal (format ", ~a" (car nts)))))])))


(define extend-language-show-union (make-parameter #f))

;; remove-unwanted-nts : (listof symbol) flattened-language-pict-info -> flattened-language-pict-info
(define (remove-unwanted-nts nts info)
  (filter (λ (x) (not (null? (car x))))
          (map
           (λ (x) (cons (filter (λ (x) (member x nts)) (car x))
                        (cdr x)))
           info)))


;; flatten-grammar-info : language-pict-info (listof symbol) -> flattened-language-pict-info
(define (flatten-grammar-info info all-nts)
  (let ([union? (extend-language-show-union)])
    (let loop ([info info])
      (cond
        [(vector? info) 
         (let ([orig (loop (vector-ref info 0))]
               [extensions (vector-ref info 1)])
           (if union?
               (map (λ (orig-line)
                      (let* ([nt (car orig-line)]
                             [extension (assoc nt extensions)])
                        (if extension
                            (let ([rhss (cdr extension)])
                              (cons nt
                                    (map (λ (x) 
                                           (if (and (lw? x) (eq? '.... (lw-e x)))
                                               (struct-copy lw
                                                            x
                                                            [e
                                                             (lw->pict all-nts
                                                                       (find-enclosing-loc-wrapper
                                                                        (add-bars (cdr orig-line))))])
                                               x))
                                         (cdr extension))))
                            orig-line)))
                    orig)
               extensions))]
        [else info]))))

(define (make-::=) (basic-text " ::= " (default-style)))
(define (make-bar) 
  (basic-text " | " (default-style))
  #;
  (let ([p (basic-text " | " (default-style))])
    (dc 
     (λ (dc dx dy)
       (cond
         [(is-a? dc post-script-dc%)
          (let ([old-pen (send dc get-pen)])
            (send dc set-pen "black" .6 'solid)
            (send dc draw-line 
                  (+ dx (/ (pict-width p) 2)) dy
                  (+ dx (/ (pict-width p) 2)) (+ dy (pict-height p)))
            (send dc set-pen old-pen))]
         [else
          (send dc draw-text " | " dx dy)]))
     (pict-width p)
     (pict-height p)
     (pict-ascent p)
     (pict-descent p))))

(define (add-bars-and-::= lst)
  (cond
    [(null? lst) null]
    [else
     (cons
      (let ([fst (car lst)])
        (build-lw
         (rc-superimpose (ghost (make-bar)) (make-::=))
         (lw-line fst)
         (lw-line-span fst)
         (lw-column fst)
         0))
      (let loop ([fst (car lst)]
                 [rst (cdr lst)])
        (cond
          [(null? rst) (list fst)]
          [else 
           (let* ([snd (car rst)]
                  [bar 
                   (cond
                     [(= (lw-line snd)
                         (lw-line fst))
                      (let* ([line (lw-line snd)]
                             [line-span (lw-line-span snd)]
                             [column (+ (lw-column fst)
                                        (lw-column-span fst))]
                             [column-span
                              (- (lw-column snd)
                                 (+ (lw-column fst)
                                    (lw-column-span fst)))])
                        (build-lw (make-bar) line line-span column column-span))]
                     [else
                      (build-lw
                       (rc-superimpose (make-bar) (ghost (make-::=)))
                       (lw-line snd)
                       (lw-line-span snd)
                       (lw-column snd)
                       0)])])
             (list* fst
                    bar
                    (loop snd (cdr rst))))])))]))

(define (add-bars lst)
  (let loop ([fst (car lst)]
             [rst (cdr lst)])
    (cond
      [(null? rst) (list fst)]
      [else 
       (let* ([snd (car rst)]
              [bar 
               (cond
                 [(= (lw-line snd)
                     (lw-line fst))
                  (let* ([line (lw-line snd)]
                         [line-span (lw-line-span snd)]
                         [column (+ (lw-column fst)
                                    (lw-column-span fst))]
                         [column-span
                          (- (lw-column snd)
                             (+ (lw-column fst)
                                (lw-column-span fst)))])
                    (build-lw (make-bar) line line-span column column-span))]
                 [else
                  (build-lw
                   (make-bar)
                   (lw-line snd)
                   (lw-line-span snd)
                   (lw-column snd)
                   0)])])
         (list* fst
                bar
                (loop snd (cdr rst))))])))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;   metafunction to pict
;;

(define (make-=) (basic-text " = " (default-style)))

(define-syntax (metafunction->pict stx)
  (syntax-case stx ()
    [(_ name)
     (identifier? #'name)
     #'(metafunction->pict/proc (metafunction name))]))

(define-syntax (metafunction->ps stx)
  (syntax-case stx ()
    [(_ name file)
     (identifier? #'name)
     #'(metafunction->ps/proc (metafunction name) file)]))

(define linebreaks (make-parameter #f))

(define metafunction-pict-style (make-parameter 'left-right))

(define metafunction->pict/proc
  (lambda (mf)
    (let ([current-linebreaks (linebreaks)]
          [all-nts (language-nts (metafunc-proc-lang (metafunction-proc mf)))]
          [sep 2])
      (let* ([wrapper->pict (lambda (lw) (lw->pict all-nts lw))]
             [eqns (metafunc-proc-pict-info (metafunction-proc mf))]
             [lhss (map (lambda (eqn) 
                          (wrapper->pict
                           (metafunction-call (metafunc-proc-name (metafunction-proc mf))
                                              (car eqn)
                                              (metafunc-proc-multi-arg? (metafunction-proc mf)))))
                        eqns)]
             [scs (map (lambda (eqn)
                         (if (and (null? (cadr eqn))
                                  (null? (caddr eqn)))
                             #f
                             (side-condition-pict null 
                                                  (map wrapper->pict (cadr eqn)) 
                                                  (map (lambda (p)
                                                         (cons (wrapper->pict (car p)) (wrapper->pict (cdr p))))
                                                       (caddr eqn))
                                                  +inf.0)))
                       eqns)]
             [rhss (map (lambda (eqn) (wrapper->pict (cadddr eqn))) eqns)]
             [linebreak-list (or current-linebreaks
                                 (map (lambda (x) #f) eqns))]
             [=-pict (make-=)]
             [max-lhs-w (apply max (map pict-width lhss))]
             [max-line-w (apply
                          max
                          (map (lambda (lhs sc rhs linebreak?)
                                 (max
                                  (if sc (pict-width sc) 0)
                                  (if linebreak?
                                      (max (pict-width lhs)
                                           (+ (pict-width rhs) (pict-width =-pict)))
                                      (+ (pict-width lhs) (pict-width rhs) (pict-width =-pict)
                                         (* 2 sep)))))
                               lhss scs rhss linebreak-list))])
        (case (metafunction-pict-style)
          [(left-right)
           (table 3
                  (apply append
                         (map (lambda (lhs sc rhs linebreak?)
                                (append
                                 (if linebreak?
                                     (list lhs (blank) (blank))
                                     (list lhs =-pict rhs))
                                 (if linebreak?
                                     (let ([p rhs])
                                       (list (hbl-append sep
                                                         =-pict
                                                         (inset p 0 0 (- 5 (pict-width p)) 0))
                                             (blank)
                                             ;; n case this line sets the max width, add suitable space in the right:
                                             (blank (max 0 (- (pict-width p) max-lhs-w sep))
                                                    0)))
                                     null)
                                 (if (not sc)
                                     null
                                     (list (inset sc 0 0 (- 5 (pict-width sc)) 0)
                                           (blank)
                                           ;; In case sc set the max width...
                                           (blank (max 0 (- (pict-width sc) max-lhs-w (pict-width =-pict) (* 2 sep)))
                                                  0)))))
                              lhss
                              scs
                              rhss
                              linebreak-list))
                  ltl-superimpose ltl-superimpose
                  sep sep)]
          [(up-down)
           (apply vl-append
                  sep
                  (apply append
                         (map (lambda (lhs sc rhs)
                                (cons
                                 (vl-append (hbl-append lhs =-pict) rhs)
                                 (if (not sc)
                                     null
                                     (list (inset sc 0 0 (- 5 (pict-width sc)) 0)))))
                              lhss
                              scs
                              rhss)))])))))

(define (metafunction-call name an-lw flattened?)
  (if flattened?
      (struct-copy lw an-lw
                   [e
                    (list*
                     ;; the first loc wrapper is just there to make the
                     ;; shape of this line be one that the apply-rewrites
                     ;; function (in core-layout.ss) recognizes as a metafunction
                     (make-lw ""
                              (lw-line an-lw)
                              0
                              (lw-column an-lw)
                              0 
                              #f
                              #f)
                     (make-lw name
                              (lw-line an-lw)
                              0
                              (lw-column an-lw)
                              0 
                              #f
                              'multi)
                     (cdr (lw-e an-lw)))])
      
      (build-lw
       (list
        (build-lw "("
                  (lw-line an-lw)
                  0
                  (lw-column an-lw)
                  0)
        (make-lw name
                 (lw-line an-lw)
                 0
                 (lw-column an-lw)
                 0
                 #f
                 'single)
        an-lw
        (build-lw ")"
                  (+ (lw-line an-lw)
                     (lw-line-span an-lw))
                  0
                  (+ (lw-column an-lw)
                     (lw-column-span an-lw))
                  0))
       (lw-line an-lw)
       (lw-line-span an-lw)
       (lw-column an-lw)
       (lw-column-span an-lw))))  

(define (add-commas-and-rewrite-parens eles)
  (let loop ([eles eles]
             [between-parens? #f]
             [comma-pending #f])
    (cond
      [(null? eles) null]
      [else 
       (let ([an-lw (car eles)])
         (cond
           [(not (lw? an-lw)) 
            (cons an-lw (loop (cdr eles) between-parens? #f))]
           [(equal? "(" (lw-e an-lw))
            (cons (struct-copy lw
                               an-lw
                               [e (open-white-square-bracket)])
                  (loop (cdr eles) #t #f))]
           [(equal? ")" (lw-e an-lw))
            (cons (struct-copy lw
                               an-lw
                               [e (close-white-square-bracket)])
                  (loop (cdr eles) #f #f))]
           [(and between-parens?
                 comma-pending)
            (list* (build-lw (basic-text ", " (default-style))
                             (car comma-pending)
                             0
                             (cdr comma-pending)
                             0)
                   'spring
                   (loop eles #t #f))]
           [else
            (cons an-lw 
                  (loop (cdr eles)
                        between-parens?
                        (if between-parens?
                            (cons (+ (lw-line an-lw) (lw-line-span an-lw))
                                  (+ (lw-column an-lw) (lw-column-span an-lw)))
                            #f)))]))])))

(define (replace-paren x)
  (cond
    [(not (lw? x)) x]
    [(equal? "(" (lw-e x))
     (struct-copy lw
                  x
                  [e (hbl-append -2 
                                 (basic-text "[" (default-style))
                                 (basic-text "[" (default-style)))])]
    [(equal? ")" (lw-e x))
     (struct-copy lw
                  x
                  [e
                   (hbl-append -2 
                               (basic-text "]" (default-style))
                               (basic-text "]" (default-style)))])]
    [else x]))

(define (metafunction->ps/proc mf filename)
  (save-as-ps (λ () (metafunction->pict/proc mf))
              filename))