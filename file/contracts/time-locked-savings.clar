;; Time-Locked Savings Account
;; file: contracts/time-locked-savings.clar

;; Constants for validation
(define-constant MAX-LOCK-PERIOD u525600) ;; Maximum lock period (1 year in blocks)
(define-constant MIN-DEPOSIT u100000) ;; Minimum deposit amount (0.1 STX)
(define-constant MAX-DEPOSIT u1000000000000) ;; Maximum deposit amount (1M STX)

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ALREADY-LOCKED (err u101))
(define-constant ERR-NO-BALANCE (err u102))
(define-constant ERR-LOCK-IN-PROGRESS (err u103))
(define-constant ERR-LOCK-PERIOD-NOT-EXPIRED (err u104))
(define-constant ERR-INVALID-AMOUNT (err u105))
(define-constant ERR-INVALID-LOCK-PERIOD (err u106))

;; Data variables
(define-data-var interest-rate uint u500) ;; 5.00% represented as u500
(define-map savings-accounts
    principal
    {
        balance: uint,
        lock-until: uint,
        initial-deposit: uint
    }
)

;; Private functions
(define-private (validate-amount (amount uint))
    (if (and 
            (>= amount MIN-DEPOSIT)
            (<= amount MAX-DEPOSIT))
        (ok amount)
        ERR-INVALID-AMOUNT))

(define-private (validate-lock-period (period uint))
    (if (and 
            (> period u0)
            (<= period MAX-LOCK-PERIOD))
        (ok period)
        ERR-INVALID-LOCK-PERIOD))

;; Public functions
(define-public (deposit (amount uint))
    (let
        (
            (sender tx-sender)
            (existing-account (default-to 
                { balance: u0, lock-until: u0, initial-deposit: u0 } 
                (map-get? savings-accounts sender)
            ))
        )
        (asserts! (is-ok (validate-amount amount)) ERR-INVALID-AMOUNT)
        (if (> (get lock-until existing-account) block-height)
            ERR-LOCK-IN-PROGRESS
            (begin
                (try! (stx-transfer? amount sender (as-contract tx-sender)))
                (ok (map-set savings-accounts
                    sender
                    {
                        balance: (+ amount (get balance existing-account)),
                        lock-until: u0,
                        initial-deposit: amount
                    }
                ))
            )
        )
    )
)

(define-public (lock-funds (lock-period uint))
    (let
        (
            (sender tx-sender)
            (account (default-to 
                { balance: u0, lock-until: u0, initial-deposit: u0 }
                (map-get? savings-accounts sender)
            ))
        )
        (asserts! (is-ok (validate-lock-period lock-period)) ERR-INVALID-LOCK-PERIOD)
        (if (> (get balance account) u0)
            (if (> (get lock-until account) block-height)
                ERR-ALREADY-LOCKED
                (ok (map-set savings-accounts
                    sender
                    {
                        balance: (get balance account),
                        lock-until: (+ block-height lock-period),
                        initial-deposit: (get initial-deposit account)
                    }
                ))
            )
            ERR-NO-BALANCE
        )
    )
)

(define-read-only (get-account-info (account principal))
    (map-get? savings-accounts account)
)

(define-read-only (calculate-interest (account principal))
    (let
        (
            (savings-info (unwrap-panic (map-get? savings-accounts account)))
            (lock-period (- (get lock-until savings-info) block-height))
        )
        (if (> lock-period u0)
            (/ (* (get balance savings-info) (var-get interest-rate) lock-period) u10000)
            u0
        )
    )
)
