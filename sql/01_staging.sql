/*
===============================================================================
ros_01_staging.sql
-------------------------------------------------------------------------------
Purpose : Load the raw Online Retail II data into a staging table with zero
          transformation. We keep this layer "dumb" on purpose -- every column
          comes in as-is (mostly varchar/nvarchar) so a bad row in the source
          file fails loudly here instead of silently corrupting downstream
          calculations in the cleaning script.

Source  : Online Retail II (UCI Machine Learning Repository)
          https://archive.ics.uci.edu/dataset/502/online+retail+ii
          Two sheets combined: Year 2009-2010 and Year 2010-2011.

Notes   : - We did not type InvoiceDate as datetime yet, even though the source
            has real dates, because Excel-exported CSVs from this dataset are
            known to have inconsistent date formats between the two sheets.
            Casting happens explicitly in ros_02_cleaning.sql where we can see
            and handle failures row by row.
          - Customer ID stays as a string here (not int) because a meaningful
            share of rows have it blank, and we don't want SQL Server silently
            coercing blank strings to 0.
===============================================================================
*/

USE RetailChurnCapstone;
GO

-- We drop and recreate every table in this script on each run because this
-- layer is meant to be fully disposable -- rerunning the load should never
-- require manual cleanup first.
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'staging')
    EXEC('CREATE SCHEMA staging');
GO

-- ros_note: this table's column count and order must match the CSV exactly,
-- because BULK INSERT maps columns positionally with no way to specify a
-- column list. We load into this "shape-matched" table first, then tag and
-- move rows into the combined table below -- trying to add source_sheet
-- directly to the BULK INSERT target was the original bug: SQL Server tried
-- to read a 9th column that doesn't exist in an 8-column file.
IF OBJECT_ID('staging.online_retail_load', 'U') IS NOT NULL
    DROP TABLE staging.online_retail_load;
GO

CREATE TABLE staging.online_retail_load (
    invoice_no      NVARCHAR(20),
    stock_code      NVARCHAR(20),
    description     NVARCHAR(200),
    quantity        NVARCHAR(20),   -- kept as text at this layer, see notes above
    invoice_date    NVARCHAR(30),   -- kept as text, cast happens in cleaning layer
    unit_price      NVARCHAR(20),
    customer_id     NVARCHAR(20),
    country         NVARCHAR(100)
);
GO

IF OBJECT_ID('staging.online_retail_raw', 'U') IS NOT NULL
    DROP TABLE staging.online_retail_raw;
GO

CREATE TABLE staging.online_retail_raw (
    invoice_no      NVARCHAR(20),
    stock_code      NVARCHAR(20),
    description     NVARCHAR(200),
    quantity        NVARCHAR(20),
    invoice_date    NVARCHAR(30),
    unit_price      NVARCHAR(20),
    customer_id     NVARCHAR(20),
    country         NVARCHAR(100),
    source_sheet    NVARCHAR(20)    -- '2009-2010' or '2010-2011', for traceability
);
GO

-- Load each sheet separately so we can tag its origin. We did this because
-- the two sheets have slightly different data quality profiles in the
-- original dataset documentation, and keeping source_sheet lets us check
-- that in EDA rather than assuming it.
--
-- ros_note: FORMAT = 'CSV' with FIELDQUOTE = '"' tells SQL Server to treat
-- commas inside double-quoted fields as literal text, not delimiters. Without
-- this, a description like "PARTY BUNTING, RETRO SPOT" gets split into two
-- columns and every column after it shifts by one -- that was the second bug
-- behind the earlier error on quantity. ROWTERMINATOR stays as a plain '0x0a'
-- here on purpose: once FORMAT = 'CSV' is set, SQL Server's CSV parser
-- handles the \r itself, and pairing FORMAT = 'CSV' with an explicit CRLF
-- terminator ('0x0d0x0a') is what caused the IID_IColumnsInfo error.
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

INSERT INTO staging.online_retail_raw
SELECT *, '2009-2010'
FROM staging.online_retail_load;

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

-- Quick sanity checks -- we run these every time we reload, not just once,
-- so a schema drift in the source file gets caught immediately.
SELECT source_sheet, COUNT(*) AS row_count
FROM staging.online_retail_raw
GROUP BY source_sheet;

SELECT TOP 20 * FROM staging.online_retail_raw;

SELECT COUNT(*) AS null_customer_id_count
FROM staging.online_retail_raw
WHERE customer_id IS NULL OR LTRIM(RTRIM(customer_id)) = '';