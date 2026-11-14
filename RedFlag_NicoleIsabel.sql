-- =====================================================================
-- RedFlag — Fraud Detection Submission
-- Student: Nicole Isabel | Batch: DA-DS-1
-- =====================================================================


-- PATTERN 1 · VELOCITY FRAUD
USE redflag;
SELECT
    user_id,
    DATE(txn_time) AS attack_date,
    COUNT(*)       AS daily_txn_count
FROM transactions
GROUP BY user_id, DATE(txn_time)
HAVING COUNT(*) >= 30
ORDER BY daily_txn_count DESC;



-- PATTERN 2 · ROUND-AMOUNT CLUSTERING  
SELECT
    user_id,
    COUNT(*) AS round_txn_count
FROM transactions
WHERE amount IN (100, 200, 500, 1000, 2000, 5000, 10000)
GROUP BY user_id
HAVING COUNT(*) >= 15
ORDER BY round_txn_count DESC;

-- PATTERN 3  · CARD TESTING
SELECT
    user_id,
    DATE(txn_time) AS test_date,
    COUNT(*)       AS tiny_txn_count
FROM transactions
WHERE amount < 10
GROUP BY 
user_id, 
DATE(txn_time)
HAVING COUNT(*) >= 30
ORDER BY tiny_txn_count DESC;


-- PATTERN 4 · FAILED-THEN-SUCCEEDED  
SELECT
    f.user_id,
    COUNT(*) AS failed_success_pairs
FROM transactions AS f
JOIN transactions AS s
    ON s.user_id = f.user_id
   AND s.status = 'SUCCESS'
   AND s.amount = f.amount
   AND s.txn_time > f.txn_time
   AND s.txn_time <= f.txn_time + INTERVAL 2 MINUTE
WHERE f.status = 'FAILED'
GROUP BY f.user_id
HAVING COUNT(*) >= 20
ORDER BY failed_success_pairs DESC;


-- PATTERN 5 · ODD-HOUR CONCENTRATION 
SELECT
    user_id,
    COUNT(*) AS total_txns,
    SUM(
        CASE
            WHEN HOUR(txn_time) BETWEEN 2 AND 4
            THEN 1
            ELSE 0
        END
    ) AS odd_hour_txns,
    ROUND(
        100.0 * SUM(
            CASE
                WHEN HOUR(txn_time) BETWEEN 2 AND 4
                THEN 1
                ELSE 0
            END
        ) / COUNT(*),
        2
    ) AS odd_hour_percentage
FROM transactions
GROUP BY user_id
HAVING COUNT(*) >= 30
   AND SUM(
        CASE
            WHEN HOUR(txn_time) BETWEEN 2 AND 4
            THEN 1
            ELSE 0
        END
   ) / COUNT(*) >= 0.8
ORDER BY odd_hour_percentage DESC;
-- Pattern 5 is a section assisted by AI


-- PATTERN 6 · MULE ACCOUNTS              
SELECT
    c.user_id,
    COUNT(*) AS mule_events
FROM transactions AS c
WHERE c.txn_type = 'CREDIT'
  AND c.payment_mode = 'NETBANKING'
  AND EXISTS (
        SELECT 1
        FROM transactions AS d
        WHERE d.user_id = c.user_id
          AND d.txn_type = 'DEBIT'
          AND d.payment_mode = 'UPI'
          AND d.txn_time > c.txn_time
          AND d.txn_time <= c.txn_time + INTERVAL 30 MINUTE
          AND d.amount >= 0.7 * c.amount
  )
GROUP BY c.user_id
HAVING COUNT(*) >= 5
ORDER BY mule_events DESC;


-- PATTERN 7 · REFUND ABUSE                                   
SELECT
    user_id,
    COUNT(*) AS total_txns,
    SUM(
        CASE
            WHEN txn_type = 'REFUND'
            THEN 1
            ELSE 0
        END
    ) AS refund_txns,
    ROUND(
        100.0 * SUM(
            CASE
                WHEN txn_type = 'REFUND'
                THEN 1
                ELSE 0
            END
        ) / COUNT(*),
        2
    ) AS refund_percentage
FROM transactions
GROUP BY user_id
HAVING COUNT(*) >= 20
   AND SUM(
        CASE
            WHEN txn_type = 'REFUND'
            THEN 1
            ELSE 0
        END
   ) / COUNT(*) > 0.4
ORDER BY refund_percentage DESC;
-- Pattern 7 is a section assisted by AI



-- PATTERN 8 · MERCHANT COLLUSION                        
WITH user_merchant AS (
    SELECT merchant_id, user_id, SUM(amount) AS user_total
    FROM transactions
    GROUP BY merchant_id, user_id
),
ranked AS (
    SELECT
        merchant_id,
        user_id,
        user_total,
        ROW_NUMBER() OVER (PARTITION BY merchant_id ORDER BY user_total DESC) AS rnk
    FROM user_merchant
),
merchant_totals AS (
    SELECT merchant_id, SUM(user_total) AS merchant_total
    FROM user_merchant
    GROUP BY merchant_id
),
top5 AS (
    SELECT merchant_id, SUM(user_total) AS top5_total
    FROM ranked
    WHERE rnk <= 5
    GROUP BY merchant_id
)
SELECT
    t.merchant_id,
    t.top5_total,
    m.merchant_total,
    ROUND(t.top5_total / m.merchant_total * 100, 2) AS top5_share_pct
FROM top5 AS t
JOIN merchant_totals AS m
  ON m.merchant_id = t.merchant_id
WHERE t.top5_total / m.merchant_total > 0.6
ORDER BY top5_share_pct DESC;


-- PATTERN 9 · JUST-UNDER-THRESHOLD         
SELECT
    user_id,
    COUNT(*) AS structuring_txn_count
FROM transactions
WHERE amount = 9999.00
GROUP BY user_id
HAVING COUNT(*) >= 10
ORDER BY structuring_txn_count DESC;



-- PATTERN 10 · DORMANT-THEN-ACTIVE                           
WITH gaps AS (
    SELECT
        user_id,
        txn_time,
        LAG(txn_time) OVER (PARTITION BY user_id ORDER BY txn_time) AS prev_time
    FROM transactions
),
returns AS (
    SELECT user_id, txn_time AS return_time
    FROM gaps
    WHERE prev_time IS NOT NULL
      AND TIMESTAMPDIFF(DAY, prev_time, txn_time) >= 90
)
SELECT
    r.user_id,
    r.return_time,
    COUNT(*) AS post_gap_txns
FROM returns AS r
JOIN transactions AS t
  ON t.user_id  = r.user_id
 AND t.txn_time >= r.return_time
GROUP BY r.user_id, r.return_time
HAVING COUNT(*) >= 15
ORDER BY post_gap_txns DESC;



-- PATTERN 11 · VELOCITY SPIKE                             
WITH monthly AS (
    SELECT
        user_id,
        DATE_FORMAT(txn_time, '%Y-%m') AS txn_month,
        COUNT(*) AS txn_count
    FROM transactions
    GROUP BY user_id, DATE_FORMAT(txn_time, '%Y-%m')
),
stats AS (
    SELECT
        user_id,
        MAX(txn_count) AS peak_month_txns,
        AVG(txn_count) AS avg_month_txns
    FROM monthly
    GROUP BY user_id
)
SELECT
    user_id,
    peak_month_txns,
    ROUND(avg_month_txns, 2) AS avg_month_txns,
    ROUND(peak_month_txns / avg_month_txns, 2) AS spike_ratio
FROM stats
WHERE peak_month_txns >= 20
  AND peak_month_txns >= 5 * avg_month_txns
ORDER BY spike_ratio DESC;




-- PATTERN 12 · GEOGRAPHIC IMPOSSIBILITY                  
WITH ordered_txns AS (
    SELECT
        user_id,
        city,
        txn_time,
        LAG(city)     OVER (PARTITION BY user_id ORDER BY txn_time) AS prev_city,
        LAG(txn_time) OVER (PARTITION BY user_id ORDER BY txn_time) AS prev_time
    FROM transactions
)
SELECT
    user_id,
    COUNT(*)      AS impossible_jumps,
    MIN(txn_time) AS first_jump_time
FROM ordered_txns
WHERE prev_city IS NOT NULL
  AND city <> prev_city
  AND TIMESTAMPDIFF(MINUTE, prev_time, txn_time) <= 60
GROUP BY user_id
ORDER BY impossible_jumps DESC;

-- the most difficult sections to make where 5 and 7 I had used the corrections made by AI 
