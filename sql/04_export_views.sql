/*
===============================================================================
ros_04_export_views.sql
-------------------------------------------------------------------------------
Purpose : Expose a single, stable view for Python and Power BI to read from.
          Neither of them should ever need to know about staging tables,
          temp tables, or schema internals -- they read this view, full stop.
          If we ever change how features.customer_rfm gets built internally,
          this view is the only thing that has to keep its shape.

Depends on : ros_03_rfm_features.sql having been run successfully.
===============================================================================
*/

USE RetailChurnCapstone;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'export')
    EXEC('CREATE SCHEMA export');
GO

IF OBJECT_ID('export.customer_rfm_final', 'V') IS NOT NULL
    DROP VIEW export.customer_rfm_final;
GO

-- ros_note: we cast monetary and avg-style columns to DECIMAL(12,2) here
-- rather than leaving them as whatever SUM() inferred, so Power BI's data
-- types are predictable on import instead of guessed from a sample.
CREATE VIEW export.customer_rfm_final AS
SELECT
    customer_id,
    country,
    recency_days,
    frequency,
    CAST(monetary AS DECIMAL(12,2))    AS monetary,
    rfm_score,
    rfm_segment,
    churned
FROM features.customer_rfm;
GO

-- Sanity check -- row count here must match features.customer_rfm exactly,
-- since this view does no filtering, only column selection and casting.
SELECT COUNT(*) AS export_row_count FROM export.customer_rfm_final;
SELECT TOP 10 * FROM export.customer_rfm_final;

SELECT * FROM export.customer_rfm_final