;; Sales Commission Tracker
;; A smart contract for tracking sales and distributing commissions on the Stacks blockchain
;; Author: YourName

;; Error codes
(define-constant ERR_UNAUTHORIZED u100)
(define-constant ERR_INVALID_AMOUNT u101)
(define-constant ERR_SALESPERSON_NOT_FOUND u102)
(define-constant ERR_PAYOUT_FAILED u103)
(define-constant ERR_TIER_NOT_FOUND u104)
(define-constant ERR_INVALID_INPUT u105)

;; Data variables
(define-data-var contract-owner principal tx-sender)
(define-data-var total-sales uint u0)
(define-data-var commission-token (optional principal) none)

;; Data maps
(define-map salespeople { address: principal } { 
  name: (string-ascii 50), 
  active: bool, 
  total-sales: uint,
  pending-commission: uint 
})

(define-map commission-tiers { tier-id: uint } {
  name: (string-ascii 50),
  min-sales: uint,
  commission-rate: uint  ;; Represented as basis points (1/100 of 1%), 500 = 5%
})

;; Read-only functions

(define-read-only (get-salesperson (address principal))
  (map-get? salespeople { address: address })
)

(define-read-only (get-commission-tier (tier-id uint))
  (map-get? commission-tiers { tier-id: tier-id })
)

(define-read-only (calculate-commission (sale-amount uint) (tier-id uint))
  (match (get-commission-tier tier-id)
    tier (/ (* sale-amount (get commission-rate tier)) u10000)
    u0)  ;; Return 0 if tier not found
)

(define-read-only (get-tier-for-sales (sales-amount uint))
  (let ((tier-1 (default-to { name: "", min-sales: u0, commission-rate: u0 } 
                           (map-get? commission-tiers { tier-id: u1 })))
       (tier-2 (default-to { name: "", min-sales: u0, commission-rate: u0 } 
                          (map-get? commission-tiers { tier-id: u2 })))
       (tier-3 (default-to { name: "", min-sales: u0, commission-rate: u0 } 
                          (map-get? commission-tiers { tier-id: u3 }))))
    (if (>= sales-amount (get min-sales tier-3))
      u3
      (if (>= sales-amount (get min-sales tier-2))
        u2
        u1
      )
    )
  )
)

;; Public functions

;; Initialize commission tiers
(define-public (initialize-tiers)
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR_UNAUTHORIZED))
    
    ;; Set up three default tiers
    (map-set commission-tiers { tier-id: u1 } 
      { name: "Bronze", min-sales: u0, commission-rate: u300 })  ;; 3%
    
    (map-set commission-tiers { tier-id: u2 } 
      { name: "Silver", min-sales: u10000, commission-rate: u500 })  ;; 5%
    
    (map-set commission-tiers { tier-id: u3 } 
      { name: "Gold", min-sales: u50000, commission-rate: u700 })  ;; 7%
    
    (ok true)
  )
)

;; Register a new salesperson
(define-public (register-salesperson (address principal) (name (string-ascii 50)))
  (begin
    ;; Validate inputs
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR_UNAUTHORIZED))
    (asserts! (not (is-eq address tx-sender)) (err ERR_INVALID_INPUT)) ;; Simple validation
    (asserts! (> (len name) u0) (err ERR_INVALID_INPUT))
    
    ;; Create new salesperson with validated data
    (map-set salespeople { address: address } 
      { name: name, active: true, total-sales: u0, pending-commission: u0 })
    
    (ok true)
  )
)

;; Record a sale and update commissions
(define-public (record-sale (salesperson principal) (amount uint))
  (begin
    ;; Validate inputs
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR_UNAUTHORIZED))
    (asserts! (> amount u0) (err ERR_INVALID_AMOUNT))
    
    (match (get-salesperson salesperson)
      sp 
        (let (
          (new-total-sales (+ (get total-sales sp) amount))
          (tier-id (get-tier-for-sales new-total-sales))
          (commission-amount (calculate-commission amount tier-id))
          (new-pending-commission (+ (get pending-commission sp) commission-amount))
        )
          
          ;; Update salesperson data with validated salesperson address
          (map-set salespeople { address: salesperson }
            (merge sp {
              total-sales: new-total-sales,
              pending-commission: new-pending-commission
            }))
          
          ;; Update global total sales
          (var-set total-sales (+ (var-get total-sales) amount))
          
          (ok commission-amount)
        )
      (err ERR_SALESPERSON_NOT_FOUND)
    )
  )
)

;; Set the token to use for commission payouts
(define-public (set-commission-token (token-contract (optional principal)))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR_UNAUTHORIZED))
    
    ;; Validate token-contract if it's some
    (match token-contract
      token (asserts! (not (is-eq token tx-sender)) (err ERR_INVALID_INPUT))
      true
    )
    
    (var-set commission-token token-contract)
    (ok true)
  )
)

;; Payout pending commissions
;; Note: In a real implementation, you would integrate with the actual token contract
(define-public (payout-commission (salesperson principal))
  ;; Validate salesperson exists first
  (match (get-salesperson salesperson)
    sp
      (let ((pending-amount (get pending-commission sp)))
        (asserts! (> pending-amount u0) (err ERR_INVALID_AMOUNT))
        
        ;; In a production contract, you would call the token contract to transfer tokens
        ;; For this example, we'll just reset the pending amount
        
        (map-set salespeople { address: salesperson }
          (merge sp { pending-commission: u0 }))
        
        ;; Return the amount that was paid out
        (ok pending-amount)
      )
    (err ERR_SALESPERSON_NOT_FOUND)
  )
)

;; Transfer ownership of the contract
(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR_UNAUTHORIZED))
    (asserts! (not (is-eq new-owner tx-sender)) (err ERR_INVALID_INPUT))
    
    (var-set contract-owner new-owner)
    (ok true)
  )
)
