-- Create the customer RFM view used by Python and Power BI.
-- Run after 03_rfm_features.sql.

USE RetailChurnCapstone;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'export')
    EXEC('CREATE SCHEMA export');
GO

IF OBJECT_ID('export.customer_rfm_final', 'V') IS NOT NULL
    DROP VIEW export.customer_rfm_final;
GO

-- Keep monetary values at two decimal places for export.
CREATE VIEW export.customer_rfm_final AS
SELECT
    customer_id,
    country,
    recency_days,
    frequency,
    CAST(monetary AS DECIMAL(12,2)) AS monetary,
    rfm_score,
    rfm_segment,
    churned
FROM features.customer_rfm;
GO

-- The row count should match features.customer_rfm.
SELECT COUNT(*) AS export_row_count
FROM export.customer_rfm_final;

SELECT TOP 10 *
FROM export.customer_rfm_final;

-- Full result for export.
SELECT *
FROM export.customer_rfm_final;