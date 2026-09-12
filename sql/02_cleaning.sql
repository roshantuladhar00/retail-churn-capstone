-- Clean the staged Online Retail II data.
-- Keep rows with invalid numbers or dates in a separate table for review.

USE RetailChurnCapstone;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'clean')
    EXEC('CREATE SCHEMA clean');
GO

-- Separate rows that cannot be converted to the required data types.
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

SELECT COUNT(*) AS cast_failure_count
FROM clean.cast_failures;
GO

-- Convert valid rows and flag cancellation invoices.
IF OBJECT_ID('clean.online_retail_typed', 'U') IS NOT NULL
    DROP TABLE clean.online_retail_typed;
GO

SELECT
    invoice_no,
    stock_code,
    description,
    CAST(quantity AS INT) AS quantity,
    CAST(invoice_date AS DATETIME2) AS invoice_date,
    CAST(unit_price AS DECIMAL(10,2)) AS unit_price,
    NULLIF(LTRIM(RTRIM(customer_id)), '') AS customer_id,
    country,
    source_sheet,
    CASE
        WHEN invoice_no LIKE 'C%' THEN 1
        ELSE 0
    END AS is_cancellation
INTO clean.online_retail_typed
FROM staging.online_retail_raw
WHERE TRY_CAST(quantity AS INT) IS NOT NULL
  AND TRY_CAST(unit_price AS DECIMAL(10,2)) IS NOT NULL
  AND TRY_CAST(invoice_date AS DATETIME2) IS NOT NULL;
GO

-- Keep positive purchases, excluding cancellation rows.
-- Missing customer IDs stay here but are excluded when building RFM features.
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

-- Check how many rows remain after cleaning.
SELECT
    (SELECT COUNT(*)
     FROM staging.online_retail_raw) AS raw_row_count,

    (SELECT COUNT(*)
     FROM clean.cast_failures) AS cast_failure_count,

    (SELECT COUNT(*)
     FROM clean.online_retail_typed) AS typed_row_count,

    (SELECT COUNT(*)
     FROM clean.online_retail_typed
     WHERE is_cancellation = 1) AS cancellation_count,

    (SELECT COUNT(*)
     FROM clean.online_retail_valid) AS valid_row_count,

    (SELECT COUNT(*)
     FROM clean.online_retail_valid
     WHERE customer_id IS NULL) AS valid_but_no_customer_id;

-- Check the country distribution.
SELECT country, COUNT(*) AS row_count
FROM clean.online_retail_valid
GROUP BY country
ORDER BY row_count DESC;