-- Build customer RFM features and a 90-day churn label.
-- Use purchases before the cutoff for features and purchases after it
-- to check whether each customer returned.

USE RetailChurnCapstone;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'features')
    EXEC('CREATE SCHEMA features');
GO

IF OBJECT_ID('features.customer_rfm', 'U') IS NOT NULL
    DROP TABLE features.customer_rfm;
GO

IF OBJECT_ID('tempdb..#history') IS NOT NULL
    DROP TABLE #history;

IF OBJECT_ID('tempdb..#future') IS NOT NULL
    DROP TABLE #future;

IF OBJECT_ID('tempdb..#customer_country') IS NOT NULL
    DROP TABLE #customer_country;

-- Reserve the final 90 days to measure whether customers return.
DECLARE @snapshot_date DATETIME2;
DECLARE @cutoff_date DATETIME2;

SELECT @snapshot_date = DATEADD(DAY, 1, MAX(invoice_date))
FROM clean.online_retail_valid;

SET @cutoff_date = DATEADD(DAY, -90, @snapshot_date);

SELECT
    @snapshot_date AS snapshot_date,
    @cutoff_date AS cutoff_date;

SELECT *
INTO #history
FROM clean.online_retail_valid
WHERE customer_id IS NOT NULL
  AND invoice_date < @cutoff_date;

SELECT *
INTO #future
FROM clean.online_retail_valid
WHERE customer_id IS NOT NULL
  AND invoice_date >= @cutoff_date
  AND invoice_date < @snapshot_date;

-- Assign each customer their most frequent country by invoice count.
SELECT customer_id, country
INTO #customer_country
FROM (
    SELECT
        customer_id,
        country,
        COUNT(DISTINCT invoice_no) AS invoice_count,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY COUNT(DISTINCT invoice_no) DESC
        ) AS rn
    FROM #history
    GROUP BY customer_id, country
) ranked
WHERE rn = 1;

-- Include only customers who purchased before the cutoff.
-- Churned = 1 means no purchase during the following 90 days.
SELECT
    h.customer_id,
    cc.country,
    DATEDIFF(DAY, MAX(h.invoice_date), @cutoff_date) AS recency_days,
    COUNT(DISTINCT h.invoice_no) AS frequency,
    SUM(h.quantity * h.unit_price) AS monetary,
    CASE
        WHEN f.customer_id IS NULL THEN 1
        ELSE 0
    END AS churned
INTO features.customer_rfm
FROM #history h
INNER JOIN #customer_country cc
    ON cc.customer_id = h.customer_id
LEFT JOIN (
    SELECT DISTINCT customer_id
    FROM #future
) f
    ON f.customer_id = h.customer_id
GROUP BY h.customer_id, cc.country, f.customer_id;
GO

ALTER TABLE features.customer_rfm
ADD rfm_score VARCHAR(3) NULL;

ALTER TABLE features.customer_rfm
ADD rfm_segment VARCHAR(20) NULL;
GO

-- Score each feature from 1 to 5.
-- Lower recency and higher frequency/spend receive higher scores.
WITH scored AS (
    SELECT
        customer_id,
        NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency ASC) AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC) AS m_score
    FROM features.customer_rfm
)
UPDATE cr
SET
    rfm_score = CAST(s.r_score AS VARCHAR(1))
              + CAST(s.f_score AS VARCHAR(1))
              + CAST(s.m_score AS VARCHAR(1)),
    rfm_segment = CASE
        WHEN s.r_score >= 4
         AND s.f_score >= 4
         AND s.m_score >= 4 THEN 'Champions'

        WHEN s.r_score >= 4
         AND s.f_score <= 2 THEN 'New Customers'

        WHEN s.r_score <= 2
         AND s.f_score >= 4 THEN 'At Risk'

        WHEN s.r_score <= 2
         AND s.f_score <= 2
         AND s.m_score <= 2 THEN 'Lost'

        ELSE 'Needs Attention'
    END
FROM features.customer_rfm cr
INNER JOIN scored s
    ON s.customer_id = cr.customer_id;
GO

-- Check the overall churn rate.
SELECT
    COUNT(*) AS total_customers,
    SUM(churned) AS churned_count,
    CAST(SUM(churned) AS FLOAT) / COUNT(*) AS churn_rate
FROM features.customer_rfm;

-- Compare customer counts and average spend across segments.
SELECT
    rfm_segment,
    COUNT(*) AS customer_count,
    AVG(monetary) AS avg_monetary
FROM features.customer_rfm
GROUP BY rfm_segment
ORDER BY customer_count DESC;

SELECT TOP 20 *
FROM features.customer_rfm
ORDER BY monetary DESC;