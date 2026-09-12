/*
===============================================================================
ros_03_rfm_features.sql
-------------------------------------------------------------------------------
Purpose : Build the final customer-level table -- one row per customer, with
          Recency/Frequency/Monetary features, a quintile-based RFM segment
          label, and a time-respecting churn label. This is the table Python
          and Power BI both read from.

Depends on : ros_02_cleaning.sql having been run successfully.

Design notes (see ros_rfm_churn_logic.md for the full reasoning):
  - snapshot_date is derived from the data (MAX(invoice_date) + 1 day), not
    hardcoded, so this script still works if the source data changes.
  - cutoff_date splits the data into a "history" window (used to build RFM
    features) and a "future" window (used only to check whether the customer
    came back). Features are never built from data the churn label also
    looks at -- that's what keeps this a fair, leakage-free train/test setup.
  - Only customers with at least one purchase BEFORE cutoff_date are included.
    Customers whose first-ever purchase falls after the cutoff have no
    history to build features from, so they're excluded here (not included
    as churned=0 by default, which would be misleading).
  - Country is taken as each customer's most frequent country by invoice
    count, since a small number of customers have transactions logged under
    more than one country.
===============================================================================
*/

USE RetailChurnCapstone;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'features')
    EXEC('CREATE SCHEMA features');
GO

IF OBJECT_ID('features.customer_rfm', 'U') IS NOT NULL
    DROP TABLE features.customer_rfm;
GO

-- ros_note: recreated as real temp tables (not inline CTEs everywhere)
-- because we reuse "history" in three separate places below -- one CTE
-- chain would need history recomputed for each, and that's harder to debug
-- if a number looks wrong later.
IF OBJECT_ID('tempdb..#history') IS NOT NULL DROP TABLE #history;
IF OBJECT_ID('tempdb..#future')  IS NOT NULL DROP TABLE #future;
IF OBJECT_ID('tempdb..#customer_country') IS NOT NULL DROP TABLE #customer_country;

DECLARE @snapshot_date DATETIME2, @cutoff_date DATETIME2;
SELECT @snapshot_date = DATEADD(DAY, 1, MAX(invoice_date)) FROM clean.online_retail_valid;

-- ros_note: 90-day churn window, per the logic doc -- long enough that a
-- customer isn't just "between orders," short enough to leave data after
-- the cutoff to actually check against. Change this one line if you decide
-- to test 60 or 120 days instead; nothing else in the script depends on it.
SET @cutoff_date = DATEADD(DAY, -90, @snapshot_date);

SELECT @snapshot_date AS snapshot_date, @cutoff_date AS cutoff_date;

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

-- Each customer's most common country, by invoice count -- resolves the
-- small number of customers logged under more than one country.
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

-- Core RFM features, built only from pre-cutoff history.
SELECT
    h.customer_id,
    cc.country,
    DATEDIFF(DAY, MAX(h.invoice_date), @cutoff_date)  AS recency_days,
    COUNT(DISTINCT h.invoice_no)                        AS frequency,
    SUM(h.quantity * h.unit_price)                       AS monetary,
    CASE WHEN f.customer_id IS NULL THEN 1 ELSE 0 END    AS churned
INTO features.customer_rfm
FROM #history h
INNER JOIN #customer_country cc ON cc.customer_id = h.customer_id
LEFT JOIN (SELECT DISTINCT customer_id FROM #future) f ON f.customer_id = h.customer_id
GROUP BY h.customer_id, cc.country, f.customer_id;
GO

-- ros_note: SELECT INTO only creates columns that appear in the select list
-- above, so rfm_score/rfm_segment need to be added explicitly before the
-- UPDATE below can populate them -- otherwise this fails with "invalid
-- column name."
ALTER TABLE features.customer_rfm ADD rfm_score VARCHAR(3) NULL;
ALTER TABLE features.customer_rfm ADD rfm_segment VARCHAR(20) NULL;
GO

-- Quintile RFM scoring -- a business-readable baseline that complements
-- (and sanity-checks) the ML clustering that happens in Python later.
-- ros_note: NTILE(5) on recency_days is DESC because lower recency (more
-- recent) should score higher (5), same direction as frequency/monetary.
WITH scored AS (
    SELECT
        customer_id,
        NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency ASC)     AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC)      AS m_score
    FROM features.customer_rfm
)
UPDATE cr
SET rfm_score = CAST(s.r_score AS VARCHAR(1)) + CAST(s.f_score AS VARCHAR(1)) + CAST(s.m_score AS VARCHAR(1)),
    rfm_segment = CASE
        WHEN s.r_score >= 4 AND s.f_score >= 4 AND s.m_score >= 4 THEN 'Champions'
        WHEN s.r_score >= 4 AND s.f_score <= 2 THEN 'New Customers'
        WHEN s.r_score <= 2 AND s.f_score >= 4 THEN 'At Risk'
        WHEN s.r_score <= 2 AND s.f_score <= 2 AND s.m_score <= 2 THEN 'Lost'
        ELSE 'Needs Attention'
    END
FROM features.customer_rfm cr
INNER JOIN scored s ON s.customer_id = cr.customer_id;
GO

-- Sanity checks
SELECT COUNT(*) AS total_customers,
       SUM(churned) AS churned_count,
       CAST(SUM(churned) AS FLOAT) / COUNT(*) AS churn_rate
FROM features.customer_rfm;

SELECT rfm_segment, COUNT(*) AS customer_count, AVG(monetary) AS avg_monetary
FROM features.customer_rfm
GROUP BY rfm_segment
ORDER BY customer_count DESC;

SELECT TOP 20 * FROM features.customer_rfm ORDER BY monetary DESC;