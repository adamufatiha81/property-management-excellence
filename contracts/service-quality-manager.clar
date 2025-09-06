;; title: service-quality-manager
;; version: 1.0.0
;; summary: Property management service delivery and quality assurance system
;; description: Manages property registration, service requests, maintenance tracking, and quality scoring

;; constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_PROPERTY_NOT_FOUND (err u101))
(define-constant ERR_REQUEST_NOT_FOUND (err u102))
(define-constant ERR_INVALID_STATUS (err u103))
(define-constant ERR_INVALID_SCORE (err u104))
(define-constant ERR_PROPERTY_EXISTS (err u105))
(define-constant ERR_INVALID_PRIORITY (err u106))

;; Request status types
(define-constant STATUS_PENDING u0)
(define-constant STATUS_IN_PROGRESS u1)
(define-constant STATUS_COMPLETED u2)
(define-constant STATUS_CANCELLED u3)

;; Request priority levels
(define-constant PRIORITY_LOW u1)
(define-constant PRIORITY_MEDIUM u2)
(define-constant PRIORITY_HIGH u3)
(define-constant PRIORITY_URGENT u4)

;; data vars
(define-data-var property-id-counter uint u0)
(define-data-var service-request-id-counter uint u0)

;; Property data structure
(define-map properties 
  uint 
  {
    owner: principal,
    address: (string-ascii 100),
    property-type: (string-ascii 50),
    units: uint,
    registration-block: uint,
    quality-score: uint,
    total-requests: uint,
    completed-requests: uint,
    active: bool
  }
)

;; Service request data structure
(define-map service-requests
  uint
  {
    property-id: uint,
    tenant: principal,
    description: (string-ascii 200),
    category: (string-ascii 50),
    priority: uint,
    status: uint,
    created-block: uint,
    assigned-to: (optional principal),
    completion-block: (optional uint),
    satisfaction-score: (optional uint)
  }
)

;; Maintenance records
(define-map maintenance-records
  uint
  {
    property-id: uint,
    request-id: uint,
    technician: principal,
    work-description: (string-ascii 200),
    completion-date: uint,
    cost: uint,
    quality-rating: uint
  }
)

;; Property service quality metrics
(define-map quality-metrics
  uint
  {
    average-response-time: uint,
    completion-rate: uint,
    tenant-satisfaction: uint,
    maintenance-cost: uint,
    last-updated: uint
  }
)

;; Property ownership mapping
(define-map property-ownership principal (list 100 uint))

;; public functions

;; Register a new property
(define-public (register-property 
  (address (string-ascii 100))
  (property-type (string-ascii 50))
  (units uint)
)
  (let
    (
      (new-id (+ (var-get property-id-counter) u1))
    )
    (asserts! (is-none (map-get? properties new-id)) ERR_PROPERTY_EXISTS)
    (map-set properties new-id {
      owner: tx-sender,
      address: address,
      property-type: property-type,
      units: units,
      registration-block: block-height,
      quality-score: u100,
      total-requests: u0,
      completed-requests: u0,
      active: true
    })
    (var-set property-id-counter new-id)
    (match (map-get? property-ownership tx-sender)
      owned-properties (map-set property-ownership tx-sender (unwrap! (as-max-len? (append owned-properties new-id) u100) ERR_UNAUTHORIZED))
      (map-set property-ownership tx-sender (list new-id))
    )
    (ok new-id)
  )
)

;; Submit a service request
(define-public (submit-service-request
  (property-id uint)
  (description (string-ascii 200))
  (category (string-ascii 50))
  (priority uint)
)
  (let
    (
      (new-request-id (+ (var-get service-request-id-counter) u1))
      (property-info (unwrap! (map-get? properties property-id) ERR_PROPERTY_NOT_FOUND))
    )
    (asserts! (get active property-info) ERR_PROPERTY_NOT_FOUND)
    (asserts! (and (>= priority PRIORITY_LOW) (<= priority PRIORITY_URGENT)) ERR_INVALID_PRIORITY)
    
    ;; Create service request
    (map-set service-requests new-request-id {
      property-id: property-id,
      tenant: tx-sender,
      description: description,
      category: category,
      priority: priority,
      status: STATUS_PENDING,
      created-block: block-height,
      assigned-to: none,
      completion-block: none,
      satisfaction-score: none
    })
    
    ;; Update property request count
    (map-set properties property-id 
      (merge property-info { total-requests: (+ (get total-requests property-info) u1) })
    )
    
    (var-set service-request-id-counter new-request-id)
    (ok new-request-id)
  )
)

;; Update service request status (property owner or assigned technician only)
(define-public (update-request-status
  (request-id uint)
  (new-status uint)
  (assigned-technician (optional principal))
)
  (let
    (
      (request-info (unwrap! (map-get? service-requests request-id) ERR_REQUEST_NOT_FOUND))
      (property-info (unwrap! (map-get? properties (get property-id request-info)) ERR_PROPERTY_NOT_FOUND))
    )
    (asserts! (or (is-eq tx-sender (get owner property-info)) 
                  (is-eq (some tx-sender) (get assigned-to request-info))) ERR_UNAUTHORIZED)
    (asserts! (and (>= new-status STATUS_PENDING) (<= new-status STATUS_CANCELLED)) ERR_INVALID_STATUS)
    
    ;; Update request status
    (map-set service-requests request-id 
      (merge request-info {
        status: new-status,
        assigned-to: assigned-technician,
        completion-block: (if (is-eq new-status STATUS_COMPLETED) (some block-height) none)
      })
    )
    
    ;; Update property completed requests count if completed
    (if (is-eq new-status STATUS_COMPLETED)
      (map-set properties (get property-id request-info)
        (merge property-info { 
          completed-requests: (+ (get completed-requests property-info) u1)
        })
      )
      true
    )
    
    (ok true)
  )
)

;; Record maintenance work
(define-public (record-maintenance
  (request-id uint)
  (work-description (string-ascii 200))
  (cost uint)
  (quality-rating uint)
)
  (let
    (
      (request-info (unwrap! (map-get? service-requests request-id) ERR_REQUEST_NOT_FOUND))
      (property-info (unwrap! (map-get? properties (get property-id request-info)) ERR_PROPERTY_NOT_FOUND))
    )
    (asserts! (is-eq (some tx-sender) (get assigned-to request-info)) ERR_UNAUTHORIZED)
    (asserts! (and (>= quality-rating u1) (<= quality-rating u5)) ERR_INVALID_SCORE)
    
    (map-set maintenance-records request-id {
      property-id: (get property-id request-info),
      request-id: request-id,
      technician: tx-sender,
      work-description: work-description,
      completion-date: block-height,
      cost: cost,
      quality-rating: quality-rating
    })
    
    (ok true)
  )
)

;; Calculate and update property quality score
(define-public (update-quality-score (property-id uint))
  (let
    (
      (property-info (unwrap! (map-get? properties property-id) ERR_PROPERTY_NOT_FOUND))
      (completion-rate (if (> (get total-requests property-info) u0)
                        (/ (* (get completed-requests property-info) u100) (get total-requests property-info))
                        u100))
      (base-score u50)
      (completion-bonus (/ completion-rate u2))
      (final-score (+ base-score completion-bonus))
    )
    (asserts! (is-eq tx-sender (get owner property-info)) ERR_UNAUTHORIZED)
    
    (map-set properties property-id
      (merge property-info { quality-score: (if (> final-score u100) u100 final-score) })
    )
    
    (ok final-score)
  )
)

;; read only functions

;; Get property details
(define-read-only (get-property-details (property-id uint))
  (map-get? properties property-id)
)

;; Get service request details
(define-read-only (get-service-request (request-id uint))
  (map-get? service-requests request-id)
)

;; Get maintenance record
(define-read-only (get-maintenance-record (request-id uint))
  (map-get? maintenance-records request-id)
)

;; Get quality metrics for property
(define-read-only (get-quality-metrics (property-id uint))
  (map-get? quality-metrics property-id)
)

;; Get properties owned by principal
(define-read-only (get-owned-properties (owner principal))
  (default-to (list) (map-get? property-ownership owner))
)

;; Get current property counter
(define-read-only (get-property-counter)
  (var-get property-id-counter)
)

;; Get current request counter
(define-read-only (get-request-counter)
  (var-get service-request-id-counter)
)

;; Calculate property performance score
(define-read-only (calculate-property-performance (property-id uint))
  (match (map-get? properties property-id)
    property-data
    (let
      (
        (total-requests (get total-requests property-data))
        (completed-requests (get completed-requests property-data))
        (completion-rate (if (> total-requests u0) 
                          (/ (* completed-requests u100) total-requests) u0))
      )
      (some {
        completion-rate: completion-rate,
        quality-score: (get quality-score property-data),
        total-requests: total-requests,
        active-status: (get active property-data)
      })
    )
    none
  )
)
