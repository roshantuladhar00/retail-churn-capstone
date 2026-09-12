-- Load both Online Retail II CSV files into staging.
-- Source: https://archive.ics.uci.edu/dataset/502/online+retail+ii

USE RetailChurnCapstone;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'staging')
    EXEC('CREATE SCHEMA staging');
GO

-- Recreate the staging tables for a fresh load.
IF OBJECT_ID('staging.online_retail_load', 'U') IS NOT NULL
    DROP TABLE staging.online_retail_load;
GO

-- This table matches the eight columns in each CSV.
CREATE TABLE staging.online_retail_load (
    invoice_no   NVARCHAR(20),
    stock_code   NVARCHAR(20),
    description  NVARCHAR(200),
    quantity     NVARCHAR(20),
    invoice_date NVARCHAR(30),
    unit_price   NVARCHAR(20),
    customer_id  NVARCHAR(20),
    country      NVARCHAR(100)
);
GO

IF OBJECT_ID('staging.online_retail_raw', 'U') IS NOT NULL
    DROP TABLE staging.online_retail_raw;
GO

CREATE TABLE staging.online_retail_raw (
    invoice_no   NVARCHAR(20),
    stock_code   NVARCHAR(20),
    description  NVARCHAR(200),
    quantity     NVARCHAR(20),
    invoice_date NVARCHAR(30),
    unit_price   NVARCHAR(20),
    customer_id  NVARCHAR(20),
    country      NVARCHAR(100),
    source_sheet NVARCHAR(20)
);
GO

-- Load 2009-2010. CSV quoting preserves commas inside descriptions.
TRUNCATE TABLE staging.online_retail_load;

BULK INSERT staging.online_retail_load
FROM 'C:\Users\rosha\Desktop\retail-churn-capstone\data\raw\online_retail_2009_2010.csv'
WITH (
    FIRSTROW = 2,
    FORMAT = 'CSV',
    FIELDQUOTE = '"',
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    CODEPAGE = '65001',
    TABLOCK
);

-- Add the source year when moving rows into the combined table.
INSERT INTO staging.online_retail_raw
SELECT *, '2009-2010'
FROM staging.online_retail_load;

-- Reuse the load table for 2010-2011.
TRUNCATE TABLE staging.online_retail_load;

BULK INSERT staging.online_retail_load
FROM 'C:\Users\rosha\Desktop\retail-churn-capstone\data\raw\online_retail_2010_2011.csv'
WITH (
    FIRSTROW = 2,
    FORMAT = 'CSV',
    FIELDQUOTE = '"',
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    CODEPAGE = '65001',
    TABLOCK
);

INSERT INTO staging.online_retail_raw
SELECT *, '2010-2011'
FROM staging.online_retail_load;
GO

-- Check row counts for both source files.
SELECT source_sheet, COUNT(*) AS row_count
FROM staging.online_retail_raw
GROUP BY source_sheet;

SELECT TOP 20 *
FROM staging.online_retail_raw;

-- Count missing customer IDs before cleaning.
SELECT COUNT(*) AS null_customer_id_count
FROM staging.online_retail_raw
WHERE customer_id IS NULL
   OR LTRIM(RTRIM(customer_id)) = '';