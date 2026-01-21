;; ==============================
;; Contract: orion-vaulthouse-v1
;; Time-locked STX vaults
;; ==============================

;; ------------------------------
;; Errors
;; ------------------------------
(define-constant ERR-NOT-AUTHORIZED        u200)
(define-constant ERR-VAULT-NOT-FOUND       u201)
(define-constant ERR-VAULT-NOT-OPEN        u202)
(define-constant ERR-INVALID-AMOUNT        u203)
(define-constant ERR-LOCK-NOT-REACHED      u204)
(define-constant ERR-INVALID-LOCK          u205)
(define-constant ERR-INSUFFICIENT-BAL      u206)
(define-constant ERR-BENEFICIARY-DISABLED  u207)
(define-constant ERR-PAUSED                u208)
(define-constant ERR-ADMIN-NOT-SET         u209)
(define-constant ERR-ADMIN-ALREADY-SET     u210)
(define-constant ERR-FEE-TOO-HIGH          u211)

;; ------------------------------
;; Status
;; ------------------------------
(define-constant STATUS-OPEN   u0)
(define-constant STATUS-CLOSED u1)

;; ------------------------------
;; State
;; ------------------------------
(define-data-var vault-nonce uint u0)
(define-data-var admin (optional principal) none)
(define-data-var paused bool false)

;; emergency fee (basis points, out of 10,000). ex: 250 = 2.5%
(define-data-var emergency-fee-bps uint u250)

(define-map vaults
  uint
  {
    owner: principal,
    beneficiary: (optional principal),
    beneficiary-enabled: bool,
    lock-until: uint,
    created-at: uint,
    balance: uint,
    status: uint,
    memo: (string-ascii 64)
  }
)

;; ------------------------------
;; Private helpers
;; ------------------------------
(define-private (contract-principal)
  (as-contract tx-sender)
)

(define-private (require-not-paused)
  (begin
    (asserts! (not (var-get paused)) (err ERR-PAUSED))
    (ok true)
  )
)

(define-private (require-admin)
  (let ((a (var-get admin)))
    (asserts! (is-some a) (err ERR-ADMIN-NOT-SET))
    (asserts! (is-eq tx-sender (unwrap-panic a)) (err ERR-NOT-AUTHORIZED))
    (ok true)
  )
)

(define-private (calc-fee (amount uint) (bps uint))
  ;; fee = amount * bps / 10000
  (/ (* amount bps) u10000)
)

(define-private (assert-open (v
  {
    owner: principal,
    beneficiary: (optional principal),
    beneficiary-enabled: bool,
    lock-until: uint,
    created-at: uint,
    balance: uint,
    status: uint,
    memo: (string-ascii 64)
  }))
  (begin
    (asserts! (is-eq (get status v) STATUS-OPEN) (err ERR-VAULT-NOT-OPEN))
    (ok true)
  )
)

;; ------------------------------
;; Admin functions
;; ------------------------------

(define-public (init-admin)
  (begin
    (asserts! (is-none (var-get admin)) (err ERR-ADMIN-ALREADY-SET))
    (var-set admin (some tx-sender))
    (print { event: "admin-initialized", admin: tx-sender })
    (ok true)
  )
)

(define-public (set-paused (value bool))
  (begin
    (try! (require-admin))
    (var-set paused value)
    (print { event: "paused-updated", paused: value })
    (ok true)
  )
)

(define-public (set-emergency-fee-bps (new-bps uint))
  (begin
    (try! (require-admin))
    ;; cap at 20% for safety
    (asserts! (<= new-bps u2000) (err ERR-FEE-TOO-HIGH))
    (var-set emergency-fee-bps new-bps)
    (print { event: "fee-updated", emergency-fee-bps: new-bps })
    (ok true)
  )
)

;; ------------------------------
;; Vault lifecycle
;; ------------------------------

;; Create a vault (no STX is moved here; deposit separately)
(define-public (create-vault (lock-until uint) (memo (string-ascii 64)))
  (begin
    (try! (require-not-paused))
    (asserts! (> lock-until burn-block-height) (err ERR-INVALID-LOCK))

    (let ((id (var-get vault-nonce)))
      (begin
        (map-set vaults id
          {
            owner: tx-sender,
            beneficiary: none,
            beneficiary-enabled: false,
            lock-until: lock-until,
            created-at: burn-block-height,
            balance: u0,
            status: STATUS-OPEN,
            memo: ""
          }
        )
        (var-set vault-nonce (+ id u1))
        (print { event: "vault-created", vault-id: id, owner: tx-sender, lock-until: lock-until, memo: memo })
        (ok id)
      )
    )
  )
)

;; Deposit STX into an existing vault (owner only)
(define-public (deposit (vault-id uint) (amount uint))
  (begin
    (try! (require-not-paused))
    (asserts! (> amount u0) (err ERR-INVALID-AMOUNT))

    (let ((v-opt (map-get? vaults vault-id)))
      (asserts! (is-some v-opt) (err ERR-VAULT-NOT-FOUND))

      (let ((v (unwrap-panic v-opt)))
        (try! (assert-open v))
        (asserts! (is-eq tx-sender (get owner v)) (err ERR-NOT-AUTHORIZED))

        (try! (stx-transfer? amount tx-sender (contract-principal)))

        (map-set vaults vault-id
          (merge v { balance: (+ (get balance v) amount) })
        )

        (print { event: "deposited", vault-id: vault-id, amount: amount })
        (ok true)
      )
    )
  )
)

;; Extend lock (owner only)
(define-public (extend-lock (vault-id uint) (new-lock-until uint))
  (begin
    (try! (require-not-paused))
    (let ((v-opt (map-get? vaults vault-id)))
      (asserts! (is-some v-opt) (err ERR-VAULT-NOT-FOUND))
      (let ((v (unwrap-panic v-opt)))
        (try! (assert-open v))
        (asserts! (is-eq tx-sender (get owner v)) (err ERR-NOT-AUTHORIZED))
        (asserts! (> new-lock-until (get lock-until v)) (err ERR-INVALID-LOCK))
        (asserts! (> new-lock-until burn-block-height) (err ERR-INVALID-LOCK))

        (map-set vaults vault-id (merge v { lock-until: new-lock-until }))
        (print { event: "lock-extended", vault-id: vault-id, lock-until: new-lock-until })
        (ok true)
      )
    )
  )
)

;; Set or change beneficiary (owner only)
(define-public (set-beneficiary (vault-id uint) (b (optional principal)))
  (begin
    (try! (require-not-paused))
    (let ((v-opt (map-get? vaults vault-id)))
      (asserts! (is-some v-opt) (err ERR-VAULT-NOT-FOUND))
      (let ((v (unwrap-panic v-opt)))
        (try! (assert-open v))
        (asserts! (is-eq tx-sender (get owner v)) (err ERR-NOT-AUTHORIZED))

        (map-set vaults vault-id (merge v { beneficiary: b }))
        (print { event: "beneficiary-set", vault-id: vault-id })
        (ok true)
      )
    )
  )
)

;; Enable/disable beneficiary claim (owner only)
(define-public (set-beneficiary-enabled (vault-id uint) (enabled bool))
  (begin
    (try! (require-not-paused))
    (let ((v-opt (map-get? vaults vault-id)))
      (asserts! (is-some v-opt) (err ERR-VAULT-NOT-FOUND))
      (let ((v (unwrap-panic v-opt)))
        (try! (assert-open v))
        (asserts! (is-eq tx-sender (get owner v)) (err ERR-NOT-AUTHORIZED))

        (map-set vaults vault-id (merge v { beneficiary-enabled: enabled }))
        (print { event: "beneficiary-claim-toggled", vault-id: vault-id, enabled: enabled })
        (ok true)
      )
    )
  )
)

;; Withdraw after unlock (owner only)
(define-public (withdraw (vault-id uint) (amount uint))
  (begin
    (try! (require-not-paused))
    (asserts! (> amount u0) (err ERR-INVALID-AMOUNT))

    (let ((v-opt (map-get? vaults vault-id)))
      (asserts! (is-some v-opt) (err ERR-VAULT-NOT-FOUND))
      (let ((v (unwrap-panic v-opt)))
        (try! (assert-open v))
        (asserts! (is-eq tx-sender (get owner v)) (err ERR-NOT-AUTHORIZED))
        (asserts! (>= burn-block-height (get lock-until v)) (err ERR-LOCK-NOT-REACHED))
        (asserts! (>= (get balance v) amount) (err ERR-INSUFFICIENT-BAL))

        (try! (stx-transfer? amount (contract-principal) (get owner v)))

        (let ((new-bal (- (get balance v) amount)))
          (map-set vaults vault-id (merge v { balance: new-bal }))
        )

        (print { event: "withdrawn", vault-id: vault-id, amount: amount })
        (ok true)
      )
    )
  )
)

;; Beneficiary claims after unlock (if enabled and beneficiary set)
(define-public (beneficiary-claim (vault-id uint) (amount uint))
  (begin
    (try! (require-not-paused))
    (asserts! (> amount u0) (err ERR-INVALID-AMOUNT))

    (let ((v-opt (map-get? vaults vault-id)))
      (asserts! (is-some v-opt) (err ERR-VAULT-NOT-FOUND))
      (let ((v (unwrap-panic v-opt)))
        (try! (assert-open v))
        (asserts! (>= burn-block-height (get lock-until v)) (err ERR-LOCK-NOT-REACHED))
        (asserts! (get beneficiary-enabled v) (err ERR-BENEFICIARY-DISABLED))

        (match (get beneficiary v)
          b (begin
              (asserts! (is-eq tx-sender b) (err ERR-NOT-AUTHORIZED))
              (asserts! (>= (get balance v) amount) (err ERR-INSUFFICIENT-BAL))

              (try! (stx-transfer? amount (contract-principal) b))

              (let ((new-bal (- (get balance v) amount)))
                (map-set vaults vault-id (merge v { balance: new-bal }))
              )

              (print { event: "beneficiary-claimed", vault-id: vault-id, amount: amount })
              (ok true)
            )
          (err ERR-NOT-AUTHORIZED)
        )
      )
    )
  )
)

;; Emergency withdraw before unlock (owner only) with fee sent to admin treasury
(define-public (emergency-withdraw (vault-id uint) (amount uint))
  (begin
    (try! (require-not-paused))
    (asserts! (> amount u0) (err ERR-INVALID-AMOUNT))

    (let ((v-opt (map-get? vaults vault-id)))
      (asserts! (is-some v-opt) (err ERR-VAULT-NOT-FOUND))
      (let ((v (unwrap-panic v-opt)))
        (try! (assert-open v))
        (asserts! (is-eq tx-sender (get owner v)) (err ERR-NOT-AUTHORIZED))
        (asserts! (< burn-block-height (get lock-until v)) (err ERR-INVALID-LOCK))
        (asserts! (>= (get balance v) amount) (err ERR-INSUFFICIENT-BAL))

        (let (
              (bps (var-get emergency-fee-bps))
              (fee (calc-fee amount bps))
              (net (- amount fee))
             )
          (asserts! (is-some (var-get admin)) (err ERR-ADMIN-NOT-SET))
          (let ((treasury (unwrap-panic (var-get admin))))
            (try! (stx-transfer? net (contract-principal) (get owner v)))
            (if (> fee u0)
                (try! (stx-transfer? fee (contract-principal) treasury))
                true
            )
          )

          (map-set vaults vault-id (merge v { balance: (- (get balance v) amount) }))
          (print { event: "emergency-withdrawn", vault-id: vault-id, amount: amount, fee: fee })
          (ok true)
        )
      )
    )
  )
)

;; Close vault when balance is zero (owner only)
(define-public (close-vault (vault-id uint))
  (begin
    (try! (require-not-paused))
    (let ((v-opt (map-get? vaults vault-id)))
      (asserts! (is-some v-opt) (err ERR-VAULT-NOT-FOUND))
      (let ((v (unwrap-panic v-opt)))
        (try! (assert-open v))
        (asserts! (is-eq tx-sender (get owner v)) (err ERR-NOT-AUTHORIZED))
        (asserts! (is-eq (get balance v) u0) (err ERR-INSUFFICIENT-BAL))

        (map-set vaults vault-id (merge v { status: STATUS-CLOSED }))
        (print { event: "vault-closed", vault-id: vault-id })
        (ok true)
      )
    )
  )
)

;; ------------------------------
;; Read-only functions
;; ------------------------------
(define-read-only (get-vault (vault-id uint))
  (map-get? vaults vault-id)
)

(define-read-only (get-next-vault-id)
  (var-get vault-nonce)
)

(define-read-only (get-admin)
  (var-get admin)
)

(define-read-only (is-paused)
  (var-get paused)
)

(define-read-only (get-contract-balance)
  (stx-get-balance (contract-principal))
)

(define-read-only (preview-emergency-fee (amount uint))
  (calc-fee amount (var-get emergency-fee-bps))
)
