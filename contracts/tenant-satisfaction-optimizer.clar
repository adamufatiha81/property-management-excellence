;; title: tenant-satisfaction-optimizer
;; version: 1.0.0
;; summary: Tenant satisfaction tracking and retention optimization system
;; description: Manages tenant profiles, feedback collection, satisfaction metrics, and retention incentives

;; constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u200))
(define-constant ERR_TENANT_NOT_FOUND (err u201))
(define-constant ERR_FEEDBACK_NOT_FOUND (err u202))
(define-constant ERR_INVALID_RATING (err u203))
(define-constant ERR_TENANT_EXISTS (err u204))
(define-constant ERR_INSUFFICIENT_POINTS (err u205))
(define-constant ERR_INVALID_REWARD (err u206))
(define-constant ERR_PROPERTY_NOT_FOUND (err u207))

;; Satisfaction rating levels
(define-constant RATING_VERY_POOR u1)
(define-constant RATING_POOR u2)
(define-constant RATING_AVERAGE u3)
(define-constant RATING_GOOD u4)
(define-constant RATING_EXCELLENT u5)

;; Feedback categories
(define-constant CATEGORY_MAINTENANCE u1)
(define-constant CATEGORY_COMMUNICATION u2)
(define-constant CATEGORY_FACILITIES u3)
(define-constant CATEGORY_MANAGEMENT u4)
(define-constant CATEGORY_GENERAL u5)

;; Reward types
(define-constant REWARD_DISCOUNT u1)
(define-constant REWARD_VOUCHER u2)
(define-constant REWARD_UPGRADE u3)
(define-constant REWARD_CASHBACK u4)

;; data vars
(define-data-var tenant-id-counter uint u0)
(define-data-var feedback-id-counter uint u0)
(define-data-var reward-id-counter uint u0)
(define-data-var total-satisfaction-points uint u0)

;; Tenant profile data structure
(define-map tenant-profiles
  principal
  {
    tenant-id: uint,
    name: (string-ascii 100),
    property-id: uint,
    move-in-date: uint,
    lease-end-date: uint,
    satisfaction-score: uint,
    total-feedback-count: uint,
    retention-points: uint,
    renewal-eligible: bool,
    last-feedback-date: uint
  }
)

;; Feedback submissions
(define-map feedback-submissions
  uint
  {
    tenant: principal,
    property-id: uint,
    category: uint,
    rating: uint,
    comment: (string-ascii 300),
    submission-date: uint,
    sentiment-score: uint,
    response-provided: bool,
    response-text: (optional (string-ascii 200))
  }
)

;; Satisfaction metrics per property
(define-map property-satisfaction
  uint
  {
    average-rating: uint,
    total-feedback: uint,
    tenant-count: uint,
    retention-rate: uint,
    last-updated: uint
  }
)

;; Retention rewards system
(define-map retention-rewards
  uint
  {
    tenant: principal,
    reward-type: uint,
    description: (string-ascii 150),
    points-cost: uint,
    value: uint,
    claimed: bool,
    claim-date: (optional uint),
    expiry-date: uint
  }
)

;; Tenant feedback history mapping
(define-map tenant-feedback-history principal (list 50 uint))

;; Tenant loyalty tier system
(define-map loyalty-tiers
  principal
  {
    tier-level: uint,
    points-threshold: uint,
    tier-name: (string-ascii 50),
    benefits: (string-ascii 200)
  }
)

;; public functions

;; Register a new tenant
(define-public (register-tenant
  (tenant principal)
  (name (string-ascii 100))
  (property-id uint)
  (lease-end-date uint)
)
  (let
    (
      (new-tenant-id (+ (var-get tenant-id-counter) u1))
    )
    (asserts! (is-none (map-get? tenant-profiles tenant)) ERR_TENANT_EXISTS)
    
    (map-set tenant-profiles tenant {
      tenant-id: new-tenant-id,
      name: name,
      property-id: property-id,
      move-in-date: block-height,
      lease-end-date: lease-end-date,
      satisfaction-score: u100,
      total-feedback-count: u0,
      retention-points: u50,
      renewal-eligible: true,
      last-feedback-date: u0
    })
    
    ;; Initialize loyalty tier
    (map-set loyalty-tiers tenant {
      tier-level: u1,
      points-threshold: u100,
      tier-name: "Bronze",
      benefits: "Basic tenant benefits and support"
    })
    
    (var-set tenant-id-counter new-tenant-id)
    (ok new-tenant-id)
  )
)

;; Submit tenant feedback
(define-public (submit-feedback
  (property-id uint)
  (category uint)
  (rating uint)
  (comment (string-ascii 300))
)
  (let
    (
      (new-feedback-id (+ (var-get feedback-id-counter) u1))
      (tenant-info (unwrap! (map-get? tenant-profiles tx-sender) ERR_TENANT_NOT_FOUND))
      (sentiment-score (calculate-sentiment-score rating comment))
    )
    (asserts! (and (>= rating RATING_VERY_POOR) (<= rating RATING_EXCELLENT)) ERR_INVALID_RATING)
    (asserts! (and (>= category CATEGORY_MAINTENANCE) (<= category CATEGORY_GENERAL)) ERR_INVALID_RATING)
    (asserts! (is-eq property-id (get property-id tenant-info)) ERR_PROPERTY_NOT_FOUND)
    
    ;; Create feedback record
    (map-set feedback-submissions new-feedback-id {
      tenant: tx-sender,
      property-id: property-id,
      category: category,
      rating: rating,
      comment: comment,
      submission-date: block-height,
      sentiment-score: sentiment-score,
      response-provided: false,
      response-text: none
    })
    
    ;; Update tenant feedback history
    (match (map-get? tenant-feedback-history tx-sender)
      feedback-list (map-set tenant-feedback-history tx-sender 
                      (unwrap! (as-max-len? (append feedback-list new-feedback-id) u50) ERR_UNAUTHORIZED))
      (map-set tenant-feedback-history tx-sender (list new-feedback-id))
    )
    
    ;; Update tenant profile
    (map-set tenant-profiles tx-sender
      (merge tenant-info {
        total-feedback-count: (+ (get total-feedback-count tenant-info) u1),
        last-feedback-date: block-height,
        retention-points: (+ (get retention-points tenant-info) (calculate-feedback-points rating))
      })
    )
    
    (var-set feedback-id-counter new-feedback-id)
    (ok new-feedback-id)
  )
)

;; Calculate tenant satisfaction score
(define-public (calculate-satisfaction-score (tenant principal))
  (let
    (
      (tenant-info (unwrap! (map-get? tenant-profiles tenant) ERR_TENANT_NOT_FOUND))
      (feedback-history (default-to (list) (map-get? tenant-feedback-history tenant)))
      (total-feedback (get total-feedback-count tenant-info))
    )
    (if (> total-feedback u0)
      (let
        (
          (average-rating (fold calculate-average-rating feedback-history u0))
          (satisfaction-score (if (> average-rating u0) 
                               (/ (* average-rating u20) u1) u100))
        )
        (map-set tenant-profiles tenant
          (merge tenant-info { satisfaction-score: (if (> satisfaction-score u100) u100 satisfaction-score) })
        )
        (ok satisfaction-score)
      )
      (ok u100)
    )
  )
)

;; Award retention points
(define-public (award-retention-points
  (tenant principal)
  (points uint)
  (reason (string-ascii 100))
)
  (let
    (
      (tenant-info (unwrap! (map-get? tenant-profiles tenant) ERR_TENANT_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    
    (map-set tenant-profiles tenant
      (merge tenant-info { 
        retention-points: (+ (get retention-points tenant-info) points)
      })
    )
    
    ;; Update loyalty tier if applicable
    (try! (update-loyalty-tier tenant))
    
    (ok true)
  )
)

;; Create retention reward
(define-public (create-retention-reward
  (tenant principal)
  (reward-type uint)
  (description (string-ascii 150))
  (points-cost uint)
  (value uint)
  (expiry-blocks uint)
)
  (let
    (
      (new-reward-id (+ (var-get reward-id-counter) u1))
      (tenant-info (unwrap! (map-get? tenant-profiles tenant) ERR_TENANT_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (and (>= reward-type REWARD_DISCOUNT) (<= reward-type REWARD_CASHBACK)) ERR_INVALID_REWARD)
    
    (map-set retention-rewards new-reward-id {
      tenant: tenant,
      reward-type: reward-type,
      description: description,
      points-cost: points-cost,
      value: value,
      claimed: false,
      claim-date: none,
      expiry-date: (+ block-height expiry-blocks)
    })
    
    (var-set reward-id-counter new-reward-id)
    (ok new-reward-id)
  )
)

;; Claim retention reward
(define-public (claim-retention-reward (reward-id uint))
  (let
    (
      (reward-info (unwrap! (map-get? retention-rewards reward-id) ERR_FEEDBACK_NOT_FOUND))
      (tenant-info (unwrap! (map-get? tenant-profiles tx-sender) ERR_TENANT_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender (get tenant reward-info)) ERR_UNAUTHORIZED)
    (asserts! (not (get claimed reward-info)) ERR_UNAUTHORIZED)
    (asserts! (>= (get retention-points tenant-info) (get points-cost reward-info)) ERR_INSUFFICIENT_POINTS)
    (asserts! (<= block-height (get expiry-date reward-info)) ERR_UNAUTHORIZED)
    
    ;; Deduct points and mark as claimed
    (map-set tenant-profiles tx-sender
      (merge tenant-info { 
        retention-points: (- (get retention-points tenant-info) (get points-cost reward-info))
      })
    )
    
    (map-set retention-rewards reward-id
      (merge reward-info {
        claimed: true,
        claim-date: (some block-height)
      })
    )
    
    (ok true)
  )
)

;; Update loyalty tier based on points
(define-public (update-loyalty-tier (tenant principal))
  (let
    (
      (tenant-info (unwrap! (map-get? tenant-profiles tenant) ERR_TENANT_NOT_FOUND))
      (current-points (get retention-points tenant-info))
      (new-tier (determine-loyalty-tier current-points))
    )
    (map-set loyalty-tiers tenant new-tier)
    (ok (get tier-level new-tier))
  )
)

;; read only functions

;; Get tenant profile
(define-read-only (get-tenant-profile (tenant principal))
  (map-get? tenant-profiles tenant)
)

;; Get feedback details
(define-read-only (get-feedback (feedback-id uint))
  (map-get? feedback-submissions feedback-id)
)

;; Get property satisfaction metrics
(define-read-only (get-property-satisfaction (property-id uint))
  (map-get? property-satisfaction property-id)
)

;; Get retention reward
(define-read-only (get-retention-reward (reward-id uint))
  (map-get? retention-rewards reward-id)
)

;; Get tenant feedback history
(define-read-only (get-tenant-feedback-history (tenant principal))
  (default-to (list) (map-get? tenant-feedback-history tenant))
)

;; Get loyalty tier info
(define-read-only (get-loyalty-tier (tenant principal))
  (map-get? loyalty-tiers tenant)
)

;; Get current counters
(define-read-only (get-tenant-counter)
  (var-get tenant-id-counter)
)

(define-read-only (get-feedback-counter)
  (var-get feedback-id-counter)
)

(define-read-only (get-reward-counter)
  (var-get reward-id-counter)
)

;; Calculate tenant retention likelihood
(define-read-only (calculate-retention-likelihood (tenant principal))
  (match (map-get? tenant-profiles tenant)
    tenant-data
    (let
      (
        (satisfaction-score (get satisfaction-score tenant-data))
        (retention-points (get retention-points tenant-data))
        (feedback-count (get total-feedback-count tenant-data))
        (base-likelihood u50)
        (satisfaction-factor (/ satisfaction-score u5))
        (points-factor (/ retention-points u10))
        (engagement-factor (if (> feedback-count u5) u10 u0))
        (total-likelihood (+ base-likelihood satisfaction-factor points-factor engagement-factor))
      )
      (some (if (> total-likelihood u100) u100 total-likelihood))
    )
    none
  )
)

;; private functions

;; Calculate sentiment score from rating and comment
(define-private (calculate-sentiment-score (rating uint) (comment (string-ascii 300)))
  (let
    (
      (base-sentiment (* rating u20))
      (comment-length (len comment))
      (engagement-bonus (if (> comment-length u50) u5 u0))
    )
    (+ base-sentiment engagement-bonus)
  )
)

;; Calculate feedback points reward
(define-private (calculate-feedback-points (rating uint))
  (if (>= rating u4)
    u10
    (if (>= rating u3)
      u5
      u2
    )
  )
)

;; Calculate average rating from feedback list
(define-private (calculate-average-rating (feedback-id uint) (accumulator uint))
  (match (map-get? feedback-submissions feedback-id)
    feedback (+ accumulator (get rating feedback))
    accumulator
  )
)

;; Determine loyalty tier based on points
(define-private (determine-loyalty-tier (points uint))
  (if (>= points u500)
    { tier-level: u4, points-threshold: u500, tier-name: "Platinum", benefits: "Premium support, priority maintenance, exclusive events" }
    (if (>= points u300)
      { tier-level: u3, points-threshold: u300, tier-name: "Gold", benefits: "Priority support, maintenance discounts, quarterly perks" }
      (if (>= points u150)
        { tier-level: u2, points-threshold: u150, tier-name: "Silver", benefits: "Extended support hours, minor maintenance priority" }
        { tier-level: u1, points-threshold: u100, tier-name: "Bronze", benefits: "Basic tenant benefits and support" }
      )
    )
  )
)
