/****** Object:  Schema [L1_Curated]    Script Date: 10-11-2026 ******/
USE DB_MERCHANTINTELIGENCEPLATFORM
GO
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = N'L1_Curated')
    EXEC('CREATE SCHEMA [L1_Curated]')
GO

/****** Object:  File Format [ParquetFormat]    Script Date: 10-11-2026 ******/
IF NOT EXISTS (SELECT * FROM sys.external_file_formats WHERE name = N'ParquetFormat')
    CREATE EXTERNAL FILE FORMAT [ParquetFormat]
    WITH (
        FORMAT_TYPE = PARQUET,
        DATA_COMPRESSION = N'org.apache.hadoop.io.compress.SnappyCodec'
    )
GO

/****** Object:  Table [L1_Curated].[L1_MERCHANT_MASTER]    Script Date: 10-11-2026 ******/
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[L1_Curated].[L1_MERCHANT_MASTER]') AND type in (N'U'))
DROP EXTERNAL TABLE [L1_Curated].[L1_MERCHANT_MASTER]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE EXTERNAL TABLE [L1_Curated].[L1_MERCHANT_MASTER]
WITH (
    LOCATION    = N'merchant-intelligence/L1_data_merchant/L1_Merchant_Master/',
    DATA_SOURCE = banking_usecasesDS_v3,
    FILE_FORMAT = ParquetFormat
)
AS
WITH src AS
(
    SELECT
        LTRIM(RTRIM(m.[MerchantID]))            AS MerchantID,
        LTRIM(RTRIM(m.[MerchantName]))          AS MerchantName,
        LTRIM(RTRIM(m.[MerchantCategory]))      AS MerchantCategory,
        LTRIM(RTRIM(m.[MCC]))                   AS MCC,
        LTRIM(RTRIM(m.[MerchantSize]))          AS MerchantSize,
        m.[AnnualRevenueINR]                    AS AnnualRevenueINR,
        m.[NumberOfStores]                      AS NumberOfStores,
        LTRIM(RTRIM(m.[BusinessType]))          AS BusinessType,
        LTRIM(RTRIM(m.[OnboardingDate]))        AS OnboardingDateRaw,
        LTRIM(RTRIM(m.[RelationshipManager]))   AS RelationshipManager,
        LTRIM(RTRIM(m.[AcquiringStatus]))       AS AcquiringStatus
    FROM [L0_Raw].[L0_MERCHANT_MASTER] AS m
    WHERE m.[MerchantID] IS NOT NULL
      AND LTRIM(RTRIM(m.[MerchantID])) <> ''
),
dedup AS
(
    SELECT
        s.*,
        ROW_NUMBER() OVER (PARTITION BY s.MerchantID ORDER BY s.MerchantName) AS rn
    FROM src AS s
)
SELECT
    CAST(d.MerchantID AS varchar(10))                               AS [Merchant_ID],
    CAST(d.MerchantName AS varchar(200))                            AS [Merchant_Name],
    CAST(
        UPPER(
            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                d.MerchantName
            ,'.',''),',',''),'-',' '),'&',' '),'''',''),'  ',' ')
        ) AS varchar(200))                                          AS [Merchant_Name_Norm],
    CAST(d.MerchantCategory AS varchar(100))                        AS [Merchant_Category],
    CAST(d.MCC AS varchar(10))                                      AS [MCC_Code],
    CAST(d.MerchantSize AS varchar(50))                             AS [Merchant_Size],
    CAST(d.AnnualRevenueINR AS decimal(18,2))                       AS [Annual_Revenue_INR],
    CAST(d.NumberOfStores AS int)                                   AS [Store_Count],
    CAST(d.BusinessType AS varchar(100))                            AS [Business_Type],
    CAST(TRY_CONVERT(date, d.OnboardingDateRaw, 105) AS date)       AS [Onboarding_Date],
    CAST(DATEDIFF(MONTH,
         TRY_CONVERT(date, d.OnboardingDateRaw, 105),
         CAST(GETDATE() AS date)) AS int)                           AS [Merchant_Tenure_Months],
    CAST(d.RelationshipManager AS varchar(100))                     AS [Relationship_Manager],
    CAST(
        CASE
            WHEN UPPER(d.AcquiringStatus) = 'ACTIVE'   THEN 'Active'
            WHEN UPPER(d.AcquiringStatus) = 'INACTIVE' THEN 'Inactive'
            WHEN UPPER(d.AcquiringStatus) = 'PROSPECT' THEN 'Prospect'
            ELSE 'Unknown'
        END AS varchar(50))                                         AS [Acquiring_Status],
    CAST('BATCH_' + CONVERT(varchar(8), GETDATE(), 112) AS varchar(40)) AS [Batch_ID],
    CAST(GETDATE() AS datetime2(3))                                 AS [Load_TS],
    CAST(CONVERT(varchar(64),
         HASHBYTES('SHA2_256',
            CONCAT(d.MerchantID,'|',d.MerchantName,'|',d.MerchantCategory,'|',
                   d.MCC,'|',d.MerchantSize,'|',CAST(d.AnnualRevenueINR AS varchar(30)),'|',
                   CAST(d.NumberOfStores AS varchar(10)),'|',d.BusinessType,'|',
                   d.OnboardingDateRaw,'|',d.RelationshipManager,'|',d.AcquiringStatus)
         ), 2) AS varchar(64))                                      AS [Row_Hash],
    CAST(
        CASE
            WHEN d.MerchantID NOT LIKE 'M[0-9][0-9][0-9]'                       THEN 'FAIL_DQ01_ID_FORMAT'
            WHEN TRY_CONVERT(date, d.OnboardingDateRaw, 105) IS NULL            THEN 'FAIL_DQ04_DATE_PARSE'
            WHEN UPPER(d.AcquiringStatus) NOT IN ('ACTIVE','INACTIVE','PROSPECT') THEN 'FAIL_DQ05_STATUS_DOMAIN'
            WHEN d.AnnualRevenueINR IS NULL OR d.AnnualRevenueINR < 0           THEN 'FAIL_DQ06_AMOUNT'
            ELSE 'PASS'
        END AS varchar(30))                                         AS [DQ_Status]
FROM dedup AS d
WHERE d.rn = 1
GO