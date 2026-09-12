/*
===============================================================================
ros_02_cleaning.sql
-------------------------------------------------------------------------------
Purpose : Take staging.online_retail_raw (everything as text, exactly as it
          came from the file) and produce a typed, filtered table that's safe
          to build RFM features on top of.

Depends on : ros_01_staging.sql having been run successfully.

What this script does, in order:
  1. Casts text columns to real types (int, decimal, datetime2), quarantining
     any row that fails to cast instead of silently dropping it.
  2. Removes cancellations (invoice numbers starting with 'C') and other
     non-purchase rows -- these don't represent completed transactions and
     would inflate or distort Monetary if left in.
  3. Splits rows with a missing customer_id into their own table, since they
     can't be attributed to a customer and don't belong in customer-level
     RFM/churn analysis, but might still be useful for product-level analysis
     later.
  4. All countries are kept (not filtered to UK-only) so country can be used
     as a feature downstream.
===============================================================================
*/

USE RetailChurnCapstone;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'clean')
    EXEC('CREATE SCHEMA clean');
GO

-- ros_note: we quarantine cast failures instead of using TRY_CAST silently,
-- because a silent NULL on a bad cast looks identical to a genuinely missing
-- value downstream. Separating "failed to parse" from "was blank" lets us
-- actually see how much of a problem it is before deciding whether to fix or
-- drop those rows.
IF OBJECT_ID('clean.cast_failures', 'U') IS NOT NULL
    DROP TABLE clean.cast_failures;
GO

SELECT *
INTO clean.cast_failures
FROM staging.online_retail_raw
WHERE TRY_CAST(quantity AS INT) IS NULL
   OR TRY_CAST(unit_price AS DECIMAL(10,2)) IS NULL
   OR TRY_CAST(invoice_date AS DATETIME2) IS NULL;
GO

SELECT COUNT(*) AS cast_failure_count FROM clean.cast_failures;
GO

-- ros_note: this is the main typed table. We only carry forward rows that
-- passed every cast above -- clean.cast_failures holds the rest for review.
IF OBJECT_ID('clean.online_retail_typed', 'U') IS NOT NULL
    DROP TABLE clean.online_retail_typed;
GO

SELECT
    invoice_no,
    stock_code,
    description,
    CAST(quantity AS INT)                  AS quantity,
    CAST(invoice_date AS DATETIME2)        AS invoice_date,
    CAST(unit_price AS DECIMAL(10,2))      AS unit_price,
    NULLIF(LTRIM(RTRIM(customer_id)), '')  AS customer_id,
    country,
    source_sheet,
    -- ros_note: flagging cancellations here rather than deleting them lets us
    -- report "X% of orders were cancelled" in the EDA notebook before they
    -- disappear from the pipeline for good.
    CASE WHEN invoice_no LIKE 'C%' THEN 1 ELSE 0 END AS is_cancellation
INTO clean.online_retail_typed
FROM staging.online_retail_raw
WHERE TRY_CAST(quantity AS INT) IS NOT NULL
  AND TRY_CAST(unit_price AS DECIMAL(10,2)) IS NOT NULL
  AND TRY_CAST(invoice_date AS DATETIME2) IS NOT NULL;
GO

-- ros_note: this is the table RFM features get built on. It excludes
-- cancellations and non-positive quantity/price rows (a handful of test
-- transactions and £0 promotional lines survive the cast but aren't real
-- purchases). Rows with a missing customer_id stay in here for now --
-- they're still valid transactions, just not attributable to a customer,
-- so we filter them out at the RFM step rather than here.
IF OBJECT_ID('clean.online_retail_valid', 'U') IS NOT NULL
    DROP TABLE clean.online_retail_valid;
GO

SELECT *
INTO clean.online_retail_valid
FROM clean.online_retail_typed
WHERE is_cancellation = 0
  AND quantity > 0
  AND unit_price > 0;
GO

-- Sanity checks -- run every time, to catch drift if the source file changes.
SELECT
    (SELECT COUNT(*) FROM staging.online_retail_raw)   AS raw_row_count,
    (SELECT COUNT(*) FROM clean.cast_failures)          AS cast_failure_count,
    (SELECT COUNT(*) FROM clean.online_retail_typed)    AS typed_row_count,
    (SELECT COUNT(*) FROM clean.online_retail_typed WHERE is_cancellation = 1) AS cancellation_count,
    (SELECT COUNT(*) FROM clean.online_retail_valid)    AS valid_row_count,
    (SELECT COUNT(*) FROM clean.online_retail_valid WHERE customer_id IS NULL) AS valid_but_no_customer_id;

SELECT country, COUNT(*) AS row_count
FROM clean.online_retail_valid
GROUP BY country
ORDER BY row_count DESC;