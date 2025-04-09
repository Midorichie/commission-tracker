;; Sales Commission Tracker - Enhanced Version
;; A smart contract for tracking sales and distributing commissions on the Stacks blockchain
;; Author: YourName

;; Error codes
(define-constant ERR_UNAUTHORIZED u100)
(define-constant ERR_INVALID_AMOUNT u101)
(define-constant ERR_SALESPERSON_NOT_FOUND u102)
(define-constant ERR_PAYOUT_FAILED u103)
(define-constant ERR_TIER_NOT_FOUND u104)
(define-constant ERR_INVALID_INPUT u105)
(define-constant ERR_DISPUTE_EXISTS u106)
(define-constant ERR_DISPUTE_NOT_FOUND u107)
(define-constant ERR_METRIC_NOT_FOUND u108)
(define-constant ERR_EXTERNAL_CALL_FAILED u109)
(define-constant ERR_ADMIN_LIST_FULL u110)

;; Data variables
(define-data-var contract-owner principal tx-sender)
(define-data-var admin-list (list 10 principal) (list))
(define-data-var total-sales uint u0)
(define-data-var commission-token (optional principal) none)
(define-data-var dispute-resolution-period uint u7) ;; 7 days for dispute resolution
(define-data-var next-dispute-id uint u1)
(define-data-var next-transaction-id uint u1)

;; Data maps
(define-map salespeople { address: principal } { 
  name: (string-ascii 50), 
  active: bool, 
  total-sales: uint,
  pending-commission: uint,
  performance-score: uint,  ;; 0-100 score based on various metrics
  last-updated: uint        ;; block height when last updated
})

(define-map commission-tiers { tier-id: uint } {
  name: (string-ascii 50),
  min-sales: uint,
  commission-rate: uint,    ;; Represented as basis points (1/100 of 1%), 500 = 5%
  performance-bonus: uint   ;; Additional basis points per 10 performance points
})

;; Performance metrics map
(define-map performance-metrics { address: principal, metric-name: (string-ascii 20) } {
  value: uint,
  weight: uint,      ;; How much this metric affects the overall score (out of 100)
  last-updated: uint ;; block height when last updated
})

;; Sales transactions map for audit and dispute resolution
(define-map sales-transactions { tx-id: uint } {
  salesperson: principal,
  amount: uint,
  commission-amount: uint,
  tier-id: uint,
  block-height: uint,
  confirmed: bool
})

;; Disputes map
(define-map disputes { dispute-id: uint } {
  tx-id: uint,
  disputed-by: principal,
  reason: (string-ascii 200),
  status: (string-ascii 20),     ;; "pending", "resolved", "rejected"
  created-at: uint,              ;; block height when created
  resolution-note: (string-ascii 200),
  original-commission: uint,
  adjusted-commission: uint
})

;; CRM integration info
(define-map crm-integrations { crm-name: (string-ascii 50) } {
  api-endpoint: (string-ascii 200),
  authorized: bool,
  last-sync: uint            ;; block height of last sync
})

;; Read-only functions

(define-read-only (get-salesperson (address principal))
  (map-get? salespeople { address: address })
)

(define-read-only (get-commission-tier (tier-id uint))
  (map-get? commission-tiers { tier-id: tier-id })
)

(define-read-only (calculate-commission (sale-amount uint) (tier-id uint) (performance-score uint))
  (match (get-commission-tier tier-id)
    tier (let (
      (base-rate (get commission-rate tier))
      (performance-bonus (get performance-bonus tier))
      (performance-multiplier (/ performance-score u10))
      (bonus-rate (* performance-multiplier performance-bonus))
      (total-rate (+ base-rate bonus-rate))
    )
      (/ (* sale-amount total-rate) u10000))
    u0)  ;; Return 0 if tier not found
)

(define-read-only (get-tier-for-sales (sales-amount uint))
  (let ((tier-1 (default-to { name: "", min-sales: u0, commission-rate: u0, performance-bonus: u0 } 
                           (map-get? commission-tiers { tier-id: u1 })))
       (tier-2 (default-to { name: "", min-sales: u0, commission-rate: u0, performance-bonus: u0 } 
                          (map-get? commission-tiers { tier-id: u2 })))
       (tier-3 (default-to { name: "", min-sales: u0, commission-rate: u0, performance-bonus: u0 } 
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

(define-read-only (get-transaction (tx-id uint))
  (map-get? sales-transactions { tx-id: tx-id })
)

(define-read-only (get-dispute (dispute-id uint))
  (map-get? disputes { dispute-id: dispute-id })
)

(define-read-only (get-performance-metric (address principal) (metric-name (string-ascii 20)))
  (map-get? performance-metrics { address: address, metric-name: metric-name })
)

(define-read-only (calculate-performance-score (address principal))
  (match (get-performance-metric address "overall")
    metric (get value metric)
    u0)  ;; Return 0 if metric not found
)

;; Helper function to safely add an admin to the list
(define-private (add-admin-to-list (admin principal) (current-list (list 10 principal)))
  (let 
    ((list-length (len current-list)))
    (if (>= list-length u10)
      ;; List is full, return the original list
      current-list
      ;; Check if admin already exists in the list
      (if (is-some (index-of current-list admin))
        ;; Admin already exists, return the original list
        current-list
        ;; Admin doesn't exist and there's room, create and return a new list with admin added
        (unwrap-panic (as-max-len? (append current-list admin) u10))
      )
    )
  )
)

;; Admin functions
(define-public (add-admin (admin principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR_UNAUTHORIZED))
    (asserts! (not (is-eq admin tx-sender)) (err ERR_INVALID_INPUT))
    
    ;; Check if admin list is already at max capacity
    (let ((current-list (var-get admin-list)))
      (asserts! (< (len current-list) u10) (err ERR_ADMIN_LIST_FULL))
      
      ;; Check if admin is already in the list
      (if (is-some (index-of current-list admin))
        (ok true) ;; Admin already exists, nothing to do
        (begin
          ;; Use our safe add function to add the admin
          (var-set admin-list (add-admin-to-list admin current-list))
          (ok true)
        )
      )
    )
  )
)

(define-public (is-admin (address principal))
  (ok (or (is-eq address (var-get contract-owner)) 
          (is-some (index-of (var-get admin-list) address)))))
          
;; Initialize commission tiers with performance bonuses
(define-public (initialize-tiers)
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR_UNAUTHORIZED))
    
    ;; Set up three default tiers with performance bonuses
    (map-set commission-tiers { tier-id: u1 } 
      { name: "Bronze", min-sales: u0, commission-rate: u300, performance-bonus: u50 })  ;; 3% + up to 0.5% bonus
    
    (map-set commission-tiers { tier-id: u2 } 
      { name: "Silver", min-sales: u10000, commission-rate: u500, performance-bonus: u100 })  ;; 5% + up to 1% bonus
    
    (map-set commission-tiers { tier-id: u3 } 
      { name: "Gold", min-sales: u50000, commission-rate: u700, performance-bonus: u150 })  ;; 7% + up to 1.5% bonus
    
    (ok true)
  )
)

;; Replace "customer_satisfaction" to "cust_satisfaction" to fit the (string-ascii 20) limit.
;; Register salesperson with updated metric names
(define-public (register-salesperson (address principal) (name (string-ascii 50)))
  (begin
    ;; Validate inputs
    (asserts! (is-authorized) (err ERR_UNAUTHORIZED))
    (asserts! (not (is-eq address tx-sender)) (err ERR_INVALID_INPUT))
    (asserts! (> (len name) u0) (err ERR_INVALID_INPUT))
    
    ;; Create new salesperson with validated data
    (map-set salespeople { address: address } 
      { name: name, 
        active: true, 
        total-sales: u0, 
        pending-commission: u0,
        performance-score: u50,  ;; Default middle score
        last-updated: block-height
      })
    
    ;; Initialize default metrics
    (map-set performance-metrics { address: address, metric-name: "sales_velocity" } 
      { value: u50, weight: u30, last-updated: block-height })
    
    (map-set performance-metrics { address: address, metric-name: "cust_satisfaction" } 
      { value: u50, weight: u40, last-updated: block-height })
    
    (map-set performance-metrics { address: address, metric-name: "deal_size" } 
      { value: u50, weight: u30, last-updated: block-height })
    
    ;; Initialize overall metric with default value
    (map-set performance-metrics { address: address, metric-name: "overall" } 
      { value: u50, weight: u100, last-updated: block-height })
    
    (ok true)
  )
)

;; Helper function to check if caller is authorized
(define-private (is-authorized)
  (or (is-eq tx-sender (var-get contract-owner))
      (is-some (index-of (var-get admin-list) tx-sender)))
)

;; Record a sale and update commissions with performance metrics
(define-public (record-sale (salesperson principal) (amount uint))
  (begin
    ;; Validate inputs
    (asserts! (is-authorized) (err ERR_UNAUTHORIZED))
    (asserts! (> amount u0) (err ERR_INVALID_AMOUNT))
    
    (match (get-salesperson salesperson)
      sp 
        (let (
          (new-total-sales (+ (get total-sales sp) amount))
          (tier-id (get-tier-for-sales new-total-sales))
          (performance-score (get performance-score sp))
          (commission-amount (calculate-commission amount tier-id performance-score))
          (new-pending-commission (+ (get pending-commission sp) commission-amount))
          (current-tx-id (var-get next-transaction-id))
        )
          
          ;; Update salesperson data with validated salesperson address
          (map-set salespeople { address: salesperson }
            (merge sp {
              total-sales: new-total-sales,
              pending-commission: new-pending-commission,
              last-updated: block-height
            }))
          
          ;; Record the transaction for audit and dispute resolution
          (map-set sales-transactions { tx-id: current-tx-id }
            { 
              salesperson: salesperson,
              amount: amount,
              commission-amount: commission-amount,
              tier-id: tier-id,
              block-height: block-height,
              confirmed: true
            })
          
          ;; Update global total sales
          (var-set total-sales (+ (var-get total-sales) amount))
          
          ;; Increment transaction ID for next sale
          (var-set next-transaction-id (+ current-tx-id u1))
          
          (ok commission-amount)
        )
      (err ERR_SALESPERSON_NOT_FOUND)
    )
  )
)

;; Update performance metrics for a salesperson
(define-public (update-performance-metric (salesperson principal) 
                                        (metric-name (string-ascii 20)) 
                                        (value uint))
  (begin
    (asserts! (is-authorized) (err ERR_UNAUTHORIZED))
    (asserts! (<= value u100) (err ERR_INVALID_INPUT))
    
    (match (get-salesperson salesperson)
      sp
        (match (get-performance-metric salesperson metric-name)
          metric
            (begin
              ;; Update the specific metric
              (map-set performance-metrics 
                { address: salesperson, metric-name: metric-name }
                { 
                  value: value, 
                  weight: (get weight metric), 
                  last-updated: block-height 
                })
              
              ;; Recalculate the overall score using existing helper
              (update-overall-performance-score salesperson)
            )
          (err ERR_METRIC_NOT_FOUND)
        )
      (err ERR_SALESPERSON_NOT_FOUND)
    )
  )
)

;; Private helper to recalculate overall performance score using existing metrics
(define-private (update-overall-performance-score (salesperson principal))
  (let (
    (sales-velocity (match (get-performance-metric salesperson "sales_velocity")
                      metric (get value metric)
                      u0))
    (customer-satisfaction (match (get-performance-metric salesperson "cust_satisfaction")
                             metric (get value metric)
                             u0))
    (deal-size (match (get-performance-metric salesperson "deal_size")
                  metric (get value metric)
                  u0))
    (sv-weight (match (get-performance-metric salesperson "sales_velocity")
                  metric (get weight metric)
                  u0))
    (cs-weight (match (get-performance-metric salesperson "cust_satisfaction")
                  metric (get weight metric)
                  u0))
    (ds-weight (match (get-performance-metric salesperson "deal_size")
                  metric (get weight metric)
                  u0))
    (total-weight (+ sv-weight cs-weight ds-weight))
    (weighted-score (if (> total-weight u0)
                        (/ (+ (* sales-velocity sv-weight) 
                              (* customer-satisfaction cs-weight) 
                              (* deal-size ds-weight)) 
                           total-weight)
                        u50)) ;; Default to 50 if no weights
  )
    ;; Update the overall score in performance metrics
    (map-set performance-metrics 
      { address: salesperson, metric-name: "overall" }
      { 
        value: weighted-score, 
        weight: u100, 
        last-updated: block-height 
      })
    
    ;; Update the salesperson's performance score in their record
    (match (get-salesperson salesperson)
      sp
        (map-set salespeople 
          { address: salesperson }
          (merge sp 
            { 
              performance-score: weighted-score,
              last-updated: block-height 
            }))
      false
    )
    
    (ok weighted-score)
  )
)

;; ==================================================
;; NEW FUNCTIONS: Calculate and Sync CRM-based Performance Metrics
;; ==================================================

;; Private function to calculate overall performance including CRM metrics.
;; It aggregates existing performance metrics ("sales_velocity", "cust_satisfaction", "deal_size")
;; and new CRM-related metrics ("crm_sales", "crm_leads", "crm_conversion") using their weights.
(define-private (calculate-overall-performance (salesperson principal))
  (let (
    (sv (match (get-performance-metric salesperson "sales_velocity")
             metric (get value metric)
             u50))
    (svw (match (get-performance-metric salesperson "sales_velocity")
              metric (get weight metric)
              u0))
    (cs (match (get-performance-metric salesperson "cust_satisfaction")
             metric (get value metric)
             u50))
    (csw (match (get-performance-metric salesperson "cust_satisfaction")
              metric (get weight metric)
              u0))
    (ds (match (get-performance-metric salesperson "deal_size")
             metric (get value metric)
             u50))
    (dsw (match (get-performance-metric salesperson "deal_size")
              metric (get weight metric)
              u0))
    (crm-sales (match (get-performance-metric salesperson "crm_sales")
                    metric (get value metric)
                    u50))
    (crm-sales-w (match (get-performance-metric salesperson "crm_sales")
                      metric (get weight metric)
                      u0))
    (crm-leads (match (get-performance-metric salesperson "crm_leads")
                    metric (get value metric)
                    u50))
    (crm-leads-w (match (get-performance-metric salesperson "crm_leads")
                      metric (get weight metric)
                      u0))
    (crm-conv (match (get-performance-metric salesperson "crm_conversion")
                   metric (get value metric)
                   u50))
    (crm-conv-w (match (get-performance-metric salesperson "crm_conversion")
                     metric (get weight metric)
                     u0))
    (total-weight (+ svw csw dsw crm-sales-w crm-leads-w crm-conv-w))
  )
    (let ((weighted-score (if (> total-weight u0)
                                (/ (+ (* sv svw) (* cs csw) (* ds dsw)
                                      (* crm-sales crm-sales-w) (* crm-leads crm-leads-w) (* crm-conv crm-conv-w))
                                   total-weight)
                                u50)))
      ;; Update the overall metric in the performance metrics map
      (map-set performance-metrics { address: salesperson, metric-name: "overall" }
        { value: weighted-score, weight: u100, last-updated: block-height })
      ;; Update the salesperson's performance score in their record
      (match (get-salesperson salesperson)
        sp (map-set salespeople { address: salesperson }
              (merge sp { performance-score: weighted-score, last-updated: block-height }))
        false
      )
      (ok weighted-score)
    )
  )
)

;; Public function to sync CRM metrics.
;; It accepts new CRM metric values, updates/creates CRM performance metrics,
;; then re-calculates the overall performance for the salesperson.
(define-public (sync-crm-metrics (salesperson principal) (crm-sales uint) (crm-leads uint) (crm-conversion uint))
  (begin
    ;; Update CRM-related performance metrics with predetermined weights.
    (map-set performance-metrics { address: salesperson, metric-name: "crm_sales" }
      { value: crm-sales, weight: u40, last-updated: block-height })
    (map-set performance-metrics { address: salesperson, metric-name: "crm_leads" }
      { value: crm-leads, weight: u30, last-updated: block-height })
    (map-set performance-metrics { address: salesperson, metric-name: "crm_conversion" }
      { value: crm-conversion, weight: u30, last-updated: block-height })
    
    ;; Recalculate and update the overall performance score incorporating the new CRM metrics.
    (calculate-overall-performance salesperson)
  )
)

;; File a dispute for a transaction
(define-public (file-dispute (tx-id uint) (reason (string-ascii 200)))
  (begin
    (match (get-transaction tx-id)
      tx 
        (let (
          (dispute-id (var-get next-dispute-id))
          (sp (get salesperson tx))
        )
          ;; Only the salesperson or contract admins can file disputes
          (asserts! (or (is-authorized) (is-eq tx-sender sp)) (err ERR_UNAUTHORIZED))
          
          ;; Create the dispute
          (map-set disputes { dispute-id: dispute-id }
            {
              tx-id: tx-id,
              disputed-by: tx-sender,
              reason: reason,
              status: "pending",
              created-at: block-height,
              resolution-note: "",
              original-commission: (get commission-amount tx),
              adjusted-commission: (get commission-amount tx)
            })
          
          ;; Increment dispute ID
          (var-set next-dispute-id (+ dispute-id u1))
          
          (ok dispute-id)
        )
      (err ERR_TIER_NOT_FOUND)
    )
  )
)

;; Resolve a dispute
(define-public (resolve-dispute (dispute-id uint) 
                             (status (string-ascii 20)) 
                             (resolution-note (string-ascii 200))
                             (adjusted-commission uint))
  (begin
    (asserts! (is-authorized) (err ERR_UNAUTHORIZED))
    (asserts! (or (is-eq status "resolved") (is-eq status "rejected")) (err ERR_INVALID_INPUT))
    
    (match (get-dispute dispute-id)
      dispute
        (let (
          (tx-id (get tx-id dispute))
          (original-commission (get original-commission dispute))
        )
          (match (get-transaction tx-id)
            tx
              (let ((salesperson (get salesperson tx)))
                ;; Update the dispute
                (map-set disputes { dispute-id: dispute-id }
                  (merge dispute 
                    {
                      status: status,
                      resolution-note: resolution-note,
                      adjusted-commission: adjusted-commission
                    }))
                
                ;; If resolved, update the salesperson's commission
                (if (is-eq status "resolved")
                  (match (get-salesperson salesperson)
                    sp
                      (let (
                        (commission-diff (- adjusted-commission original-commission))
                        (new-pending-commission (+ (get pending-commission sp) commission-diff))
                      )
                        ;; Update the salesperson's pending commission
                        (map-set salespeople { address: salesperson }
                          (merge sp { pending-commission: new-pending-commission }))
                        
                        ;; Update the transaction record
                        (map-set sales-transactions { tx-id: tx-id }
                          (merge tx { commission-amount: adjusted-commission }))
                      )
                    false
                  )
                  false
                )
                
                (ok true)
              )
            (err ERR_TIER_NOT_FOUND)
          )
        )
      (err ERR_DISPUTE_NOT_FOUND)
    )
  )
)

;; Register a new CRM integration
(define-public (register-crm-integration (crm-name (string-ascii 50)) (api-endpoint (string-ascii 200)))
  (begin
    (asserts! (is-authorized) (err ERR_UNAUTHORIZED))
    (asserts! (> (len crm-name) u0) (err ERR_INVALID_INPUT))
    (asserts! (> (len api-endpoint) u0) (err ERR_INVALID_INPUT))
    
    (map-set crm-integrations { crm-name: crm-name }
      {
        api-endpoint: api-endpoint,
        authorized: true,
        last-sync: block-height
      })
    
    (ok true)
  )
)

;; Update CRM sync status using if-some to ensure consistent return types.
(define-public (update-crm-sync (crm-name (string-ascii 50)))
  (begin
    (asserts! (is-authorized) (err ERR_UNAUTHORIZED))
    
    (if (is-some (map-get? crm-integrations { crm-name: crm-name }))
      (begin
        (map-set crm-integrations { crm-name: crm-name }
          (merge (unwrap-panic (map-get? crm-integrations { crm-name: crm-name }))
                 { last-sync: block-height }))
        (ok true)
      )
      (err ERR_INVALID_INPUT)
    )
  )
)

;; Record a sale from an external CRM system
(define-public (record-crm-sale (crm-name (string-ascii 50)) 
                             (salesperson principal) 
                             (amount uint) 
                             (crm-reference (string-ascii 50)))
  (begin
    (asserts! (is-authorized) (err ERR_UNAUTHORIZED))
    
    ;; Verify CRM is registered and authorized
    (match (map-get? crm-integrations { crm-name: crm-name })
      crm
        (begin
          (asserts! (get authorized crm) (err ERR_UNAUTHORIZED))
          
          ;; Call the regular record-sale function with FIXED match syntax
          (match (record-sale salesperson amount)
            commission-amount
              (let ((tx-id (- (var-get next-transaction-id) u1)))
                ;; Add an extra field for CRM reference
                (print { event: "crm-sale-recorded", 
                         crm-name: crm-name, 
                         reference: crm-reference,
                         tx-id: tx-id })
                
                (ok commission-amount)
              )
            error-code (err error-code)
          )
        )
      (err ERR_INVALID_INPUT)
    )
  )
)

;; Set the token to use for commission payouts
(define-public (set-commission-token (token-contract (optional principal)))
  (begin
    (asserts! (is-authorized) (err ERR_UNAUTHORIZED))
    
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

;; Set the dispute resolution period
(define-public (set-dispute-resolution-period (days uint))
  (begin
    (asserts! (is-authorized) (err ERR_UNAUTHORIZED))
    (asserts! (> days u0) (err ERR_INVALID_INPUT))
    
    (var-set dispute-resolution-period days)
    (ok true)
  )
)
