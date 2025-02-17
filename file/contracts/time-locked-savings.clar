;; Time-Locked Savings Account V2
;; file: contracts/time-locked-savings.clar

;; Constants for validation
(define-constant MAX-LOCK-PERIOD u525600) ;; Maximum lock period (1 year in blocks)
(define-constant MIN-DEPOSIT u100000) ;; Minimum deposit amount (0.1 STX)
(define-constant MAX-DEPOSIT u1000000000000) ;; Maximum deposit amount (1M STX)
(define-constant EMERGENCY_WITHDRAW_FEE u1000) ;; 10% fee for emergency withdrawals
(define-constant MAX-INTEREST-RATE u10000) ;; Maximum interest rate (100%)
(define-constant MIN-INTEREST-RATE u1) ;; Minimum interest rate (0.01%)

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ALREADY-LOCKED (err u101))
(define-constant ERR-NO-BALANCE (err u102))
(define-constant ERR-LOCK-IN-PROGRESS (err u103))
(define-constant ERR-LOCK-PERIOD-NOT-EXPIRED (err u104))
(define-constant ERR-INVALID-AMOUNT (err u105))
(define-constant ERR-INVALID-LOCK-PERIOD (err u106))
(define-constant ERR-UNAUTHORIZED-OWNER (err u107))
(define-constant ERR-INSUFFICIENT-BALANCE (err u108))
(define-constant ERR-INVALID-INTEREST-RATE (err u109))
(define-constant ERR-INVALID-OWNER (err u110))

;; Data variables
(define-data-var interest-rate uint u500) ;; 5.00% represented as u500
(define-data-var contract-owner principal tx-sender)
(define-data-var total-deposits uint u0)

;; Data maps
(define-map savings-accounts
    principal
    {
        balance: uint,
        lock-until: uint,
        initial-deposit: uint,
        total-interest-earned: uint
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

(define-private (validate-interest-rate (rate uint))
    (if (and 
            (>= rate MIN-INTEREST-RATE)
            (<= rate MAX-INTEREST-RATE))
        (ok rate)
        ERR-INVALID-INTEREST-RATE))

(define-private (validate-new-owner (new-owner principal))
    (if (not (is-eq new-owner (var-get contract-owner)))
        (ok new-owner)
        ERR-INVALID-OWNER))

(define-private (calculate-emergency-withdrawal-fee (amount uint))
    (/ (* amount EMERGENCY_WITHDRAW_FEE) u10000))

;; Authorization check
(define-private (is-contract-owner)
    (is-eq tx-sender (var-get contract-owner)))

;; Public functions
(define-public (deposit (amount uint))
    (let
        (
            (sender tx-sender)
            (existing-account (default-to 
                { balance: u0, lock-until: u0, initial-deposit: u0, total-interest-earned: u0 } 
                (map-get? savings-accounts sender)
            ))
        )
        (asserts! (is-ok (validate-amount amount)) ERR-INVALID-AMOUNT)
        (if (> (get lock-until existing-account) block-height)
            ERR-LOCK-IN-PROGRESS
            (begin
                (try! (stx-transfer? amount sender (as-contract tx-sender)))
                (var-set total-deposits (+ (var-get total-deposits) amount))
                (ok (map-set savings-accounts
                    sender
                    {
                        balance: (+ amount (get balance existing-account)),
                        lock-until: u0,
                        initial-deposit: amount,
                        total-interest-earned: (get total-interest-earned existing-account)
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
                { balance: u0, lock-until: u0, initial-deposit: u0, total-interest-earned: u0 }
                (map-get? savings-accounts sender)
            ))
        )
        (asserts! (is-ok (validate-lock-period lock-period)) ERR-INVALID-LOCK-PERIOD)
        (asserts! (> (get balance account) u0) ERR-NO-BALANCE)
        (asserts! (<= (get lock-until account) block-height) ERR-ALREADY-LOCKED)
        
        (ok (map-set savings-accounts
            sender
            {
                balance: (get balance account),
                lock-until: (+ block-height lock-period),
                initial-deposit: (get initial-deposit account),
                total-interest-earned: (get total-interest-earned account)
            }
        ))
    )
)

(define-public (withdraw (amount uint))
    (let
        (
            (sender tx-sender)
            (account (unwrap! (map-get? savings-accounts sender) ERR-NO-BALANCE))
            (current-balance (get balance account))
            (lock-expiry (get lock-until account))
            (earned-interest (calculate-interest sender))
        )
        (asserts! (<= amount current-balance) ERR-INSUFFICIENT-BALANCE)
        (asserts! (<= lock-expiry block-height) ERR-LOCK-PERIOD-NOT-EXPIRED)
        
        (try! (as-contract (stx-transfer? amount (as-contract tx-sender) sender)))
        (var-set total-deposits (- (var-get total-deposits) amount))
        
        (ok (map-set savings-accounts
            sender
            {
                balance: (- current-balance amount),
                lock-until: lock-expiry,
                initial-deposit: (get initial-deposit account),
                total-interest-earned: (+ (get total-interest-earned account) earned-interest)
            }
        ))
    )
)

(define-public (emergency-withdraw (amount uint))
    (let
        (
            (sender tx-sender)
            (account (unwrap! (map-get? savings-accounts sender) ERR-NO-BALANCE))
            (current-balance (get balance account))
            (fee (calculate-emergency-withdrawal-fee amount))
            (withdrawal-amount (- amount fee))
        )
        (asserts! (<= amount current-balance) ERR-INSUFFICIENT-BALANCE)
        
        ;; Transfer withdrawal amount to user and fee to contract owner
        (try! (as-contract (stx-transfer? withdrawal-amount (as-contract tx-sender) sender)))
        (try! (as-contract (stx-transfer? fee (as-contract tx-sender) (var-get contract-owner))))
        
        (var-set total-deposits (- (var-get total-deposits) amount))
        
        (ok (map-set savings-accounts
            sender
            {
                balance: (- current-balance amount),
                lock-until: (get lock-until account),
                initial-deposit: (get initial-deposit account),
                total-interest-earned: (get total-interest-earned account)
            }
        ))
    )
)

;; Admin functions
(define-public (update-interest-rate (new-rate uint))
    (begin
        (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
        (asserts! (is-ok (validate-interest-rate new-rate)) ERR-INVALID-INTEREST-RATE)
        (var-set interest-rate new-rate)
        (ok true)))

(define-public (transfer-ownership (new-owner principal))
    (begin
        (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
        (asserts! (is-ok (validate-new-owner new-owner)) ERR-INVALID-OWNER)
        (var-set contract-owner new-owner)
        (ok true)))

;; Read-only functions
(define-read-only (get-account-info (account principal))
    (map-get? savings-accounts account))

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

(define-read-only (get-total-deposits)
    (var-get total-deposits))

(define-read-only (get-current-interest-rate)
    (var-get interest-rate))
