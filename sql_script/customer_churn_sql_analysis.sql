-- PROJECT: TELECOM CUSTOMER CHURN & REVENUE RISK ANALYTICS
-- ENGINE: POSTGRESQL
-- ARCHITECTURE: 
--   1. DATA DEFINITION & INGESTION LAYER (Range : Lines 10 - 100)
--   2. EDA (Exploratory Data Analysis)   (Range : Lines 102 - 276)
--   3. BUSINESS DEEP-DIVE                (Range : Lines 278 - 559)
--   4. STAKEHOLDER SUMMARY               (Range : Lines 561 - 640)
--   5. POWER BI DATA LAYER               (Range : Lines 642 - 783)

-- ====================================================================================================
									-- PART 1. SETUP & VALIDATION
-- ====================================================================================================

-- -------------------------------------------------------------------------
-- 1.1. Schema setup
-- Explicit DDL with constraints. Run this once, before the first load.
-- -------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS customers (
    customer_id         VARCHAR(20)   PRIMARY KEY,
    gender              VARCHAR(10),
    senior_citizen      VARCHAR(5)    NOT NULL CHECK (senior_citizen IN ('Yes', 'No')),
    partner             VARCHAR(5)    NOT NULL CHECK (partner IN ('Yes', 'No')),
    dependents          VARCHAR(5)    NOT NULL CHECK (dependents IN ('Yes', 'No')),
    tenure              INTEGER       NOT NULL CHECK (tenure >= 0),
    phone_service       VARCHAR(5)    NOT NULL CHECK (phone_service IN ('Yes', 'No')),
    multiple_lines      VARCHAR(20),
    internet_service    VARCHAR(20),
    online_security     VARCHAR(20),
    online_backup       VARCHAR(20),
    device_protection   VARCHAR(20),
    tech_support        VARCHAR(20),
    streaming_tv        VARCHAR(20),
    streaming_movies    VARCHAR(20),
    contract            VARCHAR(20)   NOT NULL,
    paperless_billing   VARCHAR(5)    NOT NULL CHECK (paperless_billing IN ('Yes', 'No')),
    payment_method      VARCHAR(30)   NOT NULL,
    monthly_charges     NUMERIC(8,2)  NOT NULL CHECK (monthly_charges >= 0),
    total_charges       NUMERIC(10,2) NOT NULL CHECK (total_charges >= 0),
    churn               VARCHAR(5)    NOT NULL CHECK (churn IN ('Yes', 'No'))
);

-- Load data from Jupyter Notebook with: 
-- df.to_sql('customers', engine, if_exists='replace', index=False)

-- -------------------------------------------------------------------------
-- 1.2. Load verification
-- Confirms the transfer landed the expected row count and schema.
-- -------------------------------------------------------------------------

SELECT COUNT(*) FROM customers;   -- expect 7043

SELECT
    column_name,
    data_type,
    is_nullable,
    character_maximum_length,
    udt_name
FROM information_schema.columns
WHERE table_name = 'customers';

SELECT * FROM customers LIMIT 5;

-- -------------------------------------------------------------------------
-- 1.3. Null / blank audit
-- -------------------------------------------------------------------------

WITH null_audit AS (
    -- Cast all key columns to TEXT to safely catch NULLs, empty strings (''), and hidden whitespaces
    SELECT 
		'customer_id' AS column_name, 
		customer_id::TEXT AS val 
	FROM customers
    UNION ALL SELECT 'gender', gender::TEXT FROM customers
    UNION ALL SELECT 'senior_citizen', senior_citizen::TEXT FROM customers
    UNION ALL SELECT 'partner', partner::TEXT FROM customers
    UNION ALL SELECT 'dependents', dependents::TEXT FROM customers
    UNION ALL SELECT 'tenure', tenure::TEXT FROM customers
    UNION ALL SELECT 'internet_service', internet_service::TEXT FROM customers
    UNION ALL SELECT 'contract', contract::TEXT FROM customers
    UNION ALL SELECT 'paperless_billing', paperless_billing::TEXT FROM customers
    UNION ALL SELECT 'monthly_charges', monthly_charges::TEXT FROM customers
    UNION ALL SELECT 'total_charges', total_charges::TEXT FROM customers
)
SELECT
    column_name,
    -- True SQL NULLs
    COUNT(*) FILTER (WHERE val IS NULL) AS true_null_count,
    -- Empty strings or whitespace-only entries (e.g. '', ' ')
    COUNT(*) FILTER (WHERE val IS NOT NULL AND LENGTH(TRIM(val)) = 0) AS blank_or_whitespace_count,
    -- Combined missing entries
    COUNT(*) FILTER (WHERE val IS NULL OR LENGTH(TRIM(val)) = 0) AS total_missing_count,
    -- Percentage out of full customer base
    ROUND(
        COUNT(*) FILTER (WHERE val IS NULL OR LENGTH(TRIM(val)) = 0) * 100.0 / COUNT(*),
        2
    ) AS pct_missing
FROM null_audit
GROUP BY column_name
ORDER BY total_missing_count DESC, column_name ASC;

-- ====================================================================================================
									-- PART 2. EDA
				-- Mirrors the notebook's Exploratory Data Analysis section.
-- ====================================================================================================

-----------------------------------------
-- 2.1. Churn split (overall baseline)
-----------------------------------------

SELECT
    churn,
    COUNT(*) AS total,
    ROUND((COUNT(*) * 100) / (SUM(COUNT(*)) OVER()), 2) AS pct_of_total
FROM customers
GROUP BY churn
ORDER BY pct_of_total DESC;

----------------------------------------------------
-- 2.2. Churn by categorical features: demographics
----------------------------------------------------

WITH unpivoted_demographics AS (
    SELECT 
		'gender' AS feature, 
		gender AS category_value, 
		churn FROM customers
    UNION ALL SELECT 'partner', partner, churn FROM customers
    UNION ALL SELECT 'dependents', dependents, churn FROM customers
    UNION ALL SELECT 'senior_citizen', senior_citizen, churn FROM customers
)
SELECT
    feature,
    category_value,
    COUNT(*) AS total,
    -- share of the TOTAL customer base within this feature (adds to 100% per feature)
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY feature), 2) AS pct_of_total,
    -- churn rate WITHIN this segment 
    ROUND((SUM(CASE WHEN churn = 'Yes' THEN 1.0 ELSE 0.0 END) * 100.0) / COUNT(*), 2) AS churn_rate
FROM unpivoted_demographics
GROUP BY feature, category_value
ORDER BY feature ASC, churn_rate DESC;

----------------------------------------------------------
-- 2.3. Churn by categorical features: accounts & service
----------------------------------------------------------

WITH unpivoted_accounts AS (
    SELECT 
		' phone_service' AS feature, 
		phone_service AS category_value, 
		churn FROM customers
    UNION ALL SELECT 'internet_service', internet_service, churn FROM customers
    UNION ALL SELECT ' contract ', contract, churn FROM customers
    UNION ALL SELECT 'paperless_billing', paperless_billing, churn FROM customers
    UNION ALL SELECT 'payment_method', payment_method, churn FROM customers
)
SELECT
    feature,
    category_value,
    COUNT(*) AS total,
    -- share of the TOTAL customer base within this feature (adds to 100% per feature)
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY feature), 2) AS pct_of_total,
    -- churn rate WITHIN this segment 
    ROUND((SUM(CASE WHEN churn = 'Yes' THEN 1.0 ELSE 0.0 END) * 100.0) / COUNT(*), 2) AS churn_rate
FROM unpivoted_accounts
GROUP BY feature, category_value
ORDER BY feature ASC, churn_rate DESC;

-- -------------------------------------------------------------------------
-- 2.4. Churn rate by contract and internet service (segment cross-tab)
-- -------------------------------------------------------------------------

SELECT
    contract,
    internet_service,
    COUNT(*) AS total,
    ROUND(
		(SUM(CASE WHEN churn = 'Yes' THEN 1.0 ELSE 0.0 END) * 100.0) / 
		COUNT(*)
	, 2) AS churn_rate
FROM customers
GROUP BY contract, internet_service
ORDER BY contract, churn_rate DESC;

-- -------------------------------------------------------------------------
-- 2.5. Churn rate by tenure group
-- A separate, finer-grained window is used later (Part 3.4) specifically
-- for the early-onboarding analysis, where more granularity is useful.
-- -------------------------------------------------------------------------

SELECT
    CASE
        WHEN tenure <= 12 THEN '0-1 Year'
        WHEN tenure <= 24 THEN '1-2 Years'
        WHEN tenure <= 48 THEN '2-4 Years'
        ELSE '4+ Years'
    END AS tenure_group,
    COUNT(*) AS total_customers,
    SUM(CASE WHEN churn = 'Yes' THEN 1 ELSE 0 END) AS total_churned,
    ROUND(
		(SUM(CASE WHEN churn = 'Yes' THEN 1.0 ELSE 0.0 END) * 100.0) / 
		COUNT(*)
	, 2) AS churn_rate
FROM customers
GROUP BY 1
ORDER BY MIN(tenure);

-- -------------------------------------------------------------------------
-- 2.6. Correlation with churn
-- -------------------------------------------------------------------------

WITH numeric_dataset AS (
-- Convert binary categorical columns into numeric flags (0 or 1)
    SELECT
        tenure,
        monthly_charges,
        total_charges,
        CASE WHEN senior_citizen = 'Yes' THEN 1 ELSE 0 END AS is_senior,
        CASE WHEN partner = 'Yes' THEN 1 ELSE 0 END AS has_partner,
        CASE WHEN dependents = 'Yes' THEN 1 ELSE 0 END AS has_dependents,
        CASE WHEN phone_service = 'Yes' THEN 1 ELSE 0 END AS has_phone,
        CASE WHEN paperless_billing = 'Yes' THEN 1 ELSE 0 END AS billed_paperless,
        CASE WHEN churn = 'Yes' THEN 1 ELSE 0 END AS has_churned
    FROM customers
),
unpivoted_numeric AS (
-- Unpivot feature columns alongside the target variable, has_churned
    SELECT 
		'tenure' AS feature, 
		tenure::NUMERIC AS val, 
		has_churned 
	FROM numeric_dataset
    UNION ALL SELECT 'monthly_charges', monthly_charges::NUMERIC, has_churned FROM numeric_dataset
    UNION ALL SELECT 'total_charges', total_charges::NUMERIC, has_churned FROM numeric_dataset
    UNION ALL SELECT 'senior_citizen', is_senior::NUMERIC, has_churned FROM numeric_dataset
    UNION ALL SELECT 'partner', has_partner::NUMERIC, has_churned FROM numeric_dataset
    UNION ALL SELECT 'dependents', has_dependents::NUMERIC, has_churned FROM numeric_dataset
    UNION ALL SELECT 'phone_service', has_phone::NUMERIC, has_churned FROM numeric_dataset
    UNION ALL SELECT 'paperless_billing', billed_paperless::NUMERIC, has_churned FROM numeric_dataset
)
SELECT
    feature,
    ROUND(CORR(val, has_churned)::NUMERIC, 3) AS correlation_with_churn
FROM unpivoted_numeric
GROUP BY feature
-- Rank by strength of association regardless of direction.
ORDER BY ABS(ROUND(CORR(val, has_churned)::NUMERIC, 3)) DESC;

-- -------------------------------------------------------------------------
-- 2.7. Numeric summary statistics by churn
-- -------------------------------------------------------------------------

WITH unpivoted_numerical_stats AS (
    SELECT 
		'tenure' AS feature, 
		tenure AS val, 
		churn 
	FROM customers
    UNION ALL SELECT 'monthly_charges', monthly_charges, churn FROM customers
    UNION ALL SELECT 'total_charges', total_charges, churn FROM customers
)
SELECT
    feature,
    churn,
    COUNT(*) AS count,
    ROUND(AVG(val)::NUMERIC, 2) AS mean,
    ROUND(STDDEV(val)::NUMERIC, 2) AS std,
    MIN(val) AS min,
    ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY val)::NUMERIC, 2) AS "25%",
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY val)::NUMERIC, 2) AS "50%",
    ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY val)::NUMERIC, 2) AS "75%",
    MAX(val) AS max
FROM unpivoted_numerical_stats
GROUP BY 1, 2
ORDER BY 1, 2 DESC;

-- ====================================================================================================
									-- PART 3. BUSINESS DEEP-DIVE
				-- SQL-native additions that go beyond the notebook: revenue exposure,
				-- lifecycle risk windows, ROI framing, and segment prioritization.
-- ====================================================================================================

-- -------------------------------------------------------------------------
-- 3.1. Revenue at risk
-- -------------------------------------------------------------------------

WITH revenue_impact AS (
    SELECT
        churn,
        COUNT(*) AS customers,
        ROUND(SUM(monthly_charges)::NUMERIC, 2) AS total_monthly_revenue,
        ROUND(SUM(total_charges)::NUMERIC, 2) AS total_lifetime_revenue,
        ROUND(AVG(monthly_charges)::NUMERIC, 2) AS avg_monthly,
        ROUND(AVG(total_charges)::NUMERIC, 2) AS avg_lifetime
    FROM customers
    GROUP BY churn
)
SELECT
    churn,
    customers,
    total_monthly_revenue,
    total_lifetime_revenue,
    avg_monthly,
    avg_lifetime,
	-- Monthly revenue contribution
    ROUND(total_monthly_revenue * 100.0 / SUM(total_monthly_revenue) OVER(), 2) AS monthly_revenue_pct,
    -- Lifetime revenue contribution
	ROUND(total_lifetime_revenue * 100.0 / SUM(total_lifetime_revenue) OVER(), 2) AS lifetime_revenue_pct
FROM revenue_impact
ORDER BY churn DESC;

-- -------------------------------------------------------------------------
-- 3.2. Customer lifetime value (CLV) by contract
-- -------------------------------------------------------------------------

WITH clv_calc AS (
    SELECT
        contract,
        churn,
        COUNT(*) AS customers,
        ROUND(AVG(total_charges)::NUMERIC, 2) AS avg_clv,
        ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_charges)::NUMERIC, 2) AS median_clv
    FROM customers
    GROUP BY contract, churn
)
SELECT
    contract,
    churn,
    customers,
    avg_clv,
    median_clv,
    ROUND(avg_clv * customers::NUMERIC, 2) AS total_segment_value
FROM clv_calc
ORDER BY contract, churn;

-- -------------------------------------------------------------------------
-- 3.3. Churn triggers 
-- -------------------------------------------------------------------------

WITH metric_averages AS (
    SELECT
        ROUND(AVG(tenure) FILTER (WHERE churn = 'No')::NUMERIC, 1) AS retained_tenure,
        ROUND(AVG(tenure) FILTER (WHERE churn = 'Yes')::NUMERIC, 1) AS churned_tenure,
        ROUND(AVG(monthly_charges) FILTER (WHERE churn = 'No')::NUMERIC, 2) AS retained_monthly,
        ROUND(AVG(monthly_charges) FILTER (WHERE churn = 'Yes')::NUMERIC, 2) AS churned_monthly,
        ROUND(AVG(total_charges) FILTER (WHERE churn = 'No')::NUMERIC, 2) AS retained_total,
        ROUND(AVG(total_charges) FILTER (WHERE churn = 'Yes')::NUMERIC, 2) AS churned_total
    FROM customers
)
SELECT 
	'Tenure (months)' AS metric, 
	retained_tenure AS retained_avg, 
	churned_tenure AS churned_avg,
    ROUND(retained_tenure - churned_tenure, 1) AS churn_gap
FROM metric_averages
UNION ALL
SELECT 'Monthly Charges ($)', retained_monthly, churned_monthly,
       ROUND(churned_monthly - retained_monthly, 2)
FROM metric_averages
UNION ALL
SELECT 'Total Charges ($)', retained_total, churned_total,
       ROUND(retained_total - churned_total, 2)
FROM metric_averages;

-- -------------------------------------------------------------------------
-- 3.4. Early warning signs (onboarding window)
-- Deliberately more granular than the standard tenure_group (Part 2.5)
-- This view exists specifically to pinpoint where in the first two years
-- churn risk is highest, which the 4-band version is too coarse to show.
-- -------------------------------------------------------------------------

SELECT
    CASE
        WHEN tenure <= 3 THEN '0-3 months'
        WHEN tenure <= 6 THEN '4-6 months'
        WHEN tenure <= 12 THEN '7-12 months'
        WHEN tenure <= 24 THEN '13-24 months'
        ELSE '24+ months'
    END AS tenure_window,
    COUNT(*) AS total_customers,
    COUNT(*) FILTER (WHERE churn = 'Yes') AS churned,
    ROUND(COUNT(*) FILTER (WHERE churn = 'Yes') * 100.0 / COUNT(*), 2) AS churn_rate,
    ROUND(AVG(monthly_charges)::NUMERIC, 2) AS avg_monthly,
    ROUND(AVG(monthly_charges)::NUMERIC * COUNT(*) FILTER (WHERE churn = 'Yes'), 2) AS revenue_at_risk
FROM customers
GROUP BY 1
ORDER BY MIN(tenure) ASC;

-- -------------------------------------------------------------------------
-- 3.5. Retention investment scenarios
-- Frames churn reduction in terms even a non-technical stakeholder can
-- act on: what is 1 point of churn reduction worth per month / year?
-- -------------------------------------------------------------------------

WITH base_metrics AS (
    SELECT
		-- Total monthly revenue from retained customers
        SUM(monthly_charges) FILTER (WHERE churn = 'No') AS retained_monthly_rev,
        -- Average lifetime total charges for retained customers
		AVG(total_charges) FILTER (WHERE churn = 'No') AS retained_avg_total_charges,
        -- Overall churn rate (i.e., 26.54%)
		COUNT(*) FILTER (WHERE churn = 'Yes') * 100.0 / COUNT(*) AS churn_rate
    FROM customers
)
SELECT
    ROUND((retained_monthly_rev * 0.01) / churn_rate, 2) AS monthly_revenue_per_1pct_churn_reduction,
    ROUND((retained_monthly_rev * 0.01 * 12) / churn_rate, 2) AS annual_revenue_per_1pct_churn_reduction,
    -- 5% of average total charges per retained customer
	ROUND(retained_avg_total_charges * 0.05, 2) AS max_annual_spend_per_customer
FROM base_metrics;

-- -------------------------------------------------------------------------
-- 3.6. Churn prevention priority matrix
-- priority_score = churn_rate x (revenue_lost / 1000): balances how
-- badly a segment is churning against how much money is actually on
-- the line, so a small segment with a scary churn rate doesn't
-- outrank a large segment quietly bleeding revenue.
-- -------------------------------------------------------------------------

SELECT
    contract,
    internet_service,
    COUNT(*) AS customers,
    COUNT(*) FILTER (WHERE churn = 'Yes') AS churned,
    -- churn_rate = (churned / customers) * 100
	ROUND(COUNT(*) FILTER (WHERE churn = 'Yes') * 100.0 / COUNT(*), 2) AS churn_rate,
    -- Sum lifetime total_charges from churned customers within a specific contract/internet tier:
	ROUND(SUM(total_charges) FILTER (WHERE churn = 'Yes')::NUMERIC, 2) AS revenue_lost,
    -- avg_loss_per_churn = revenue_lost / churned
	ROUND(
        SUM(total_charges) FILTER (WHERE churn = 'Yes')::NUMERIC /
        NULLIF(COUNT(*) FILTER (WHERE churn = 'Yes'), 0), 2
    ) AS avg_loss_per_churn,
     -- Priority score = (churn_rate) * (revenue_lost / 1000)
	ROUND(
        (COUNT(*) FILTER (WHERE churn = 'Yes') * 100.0 / COUNT(*)) *
        (SUM(total_charges) FILTER (WHERE churn = 'Yes')::NUMERIC / 1000.0), 2
    ) AS priority_score
FROM customers
GROUP BY contract, internet_service
-- Eliminate the possibility of a division-by-zero error
HAVING COUNT(*) FILTER (WHERE churn = 'Yes') > 0
ORDER BY priority_score DESC;

-- -------------------------------------------------------------------------
-- 3.7. Service bundle analysis
-- Which internet/phone combination drives the highest churn and revenue?
-- -------------------------------------------------------------------------

SELECT
    CASE
        WHEN internet_service = 'No' AND phone_service = 'Yes' THEN 'Phone Only'
        WHEN internet_service = 'No' AND phone_service = 'No' THEN 'No Services'
        WHEN internet_service = 'DSL' AND phone_service = 'Yes' THEN 'DSL + Phone'
        WHEN internet_service = 'Fiber optic' AND phone_service = 'Yes' THEN 'Fiber + Phone'
        WHEN internet_service = 'DSL' AND phone_service = 'No' THEN 'DSL Only'
        WHEN internet_service = 'Fiber optic' AND phone_service = 'No' THEN 'Fiber Only'
        ELSE 'Other'
    END AS bundle_type,
    COUNT(*) AS customers,
    COUNT(*) FILTER (WHERE churn = 'Yes') AS churned,
    ROUND(COUNT(*) FILTER (WHERE churn = 'Yes') * 100.0 / COUNT(*), 2) AS churn_rate,
    ROUND(AVG(monthly_charges)::NUMERIC, 2) AS avg_monthly,
    ROUND(SUM(monthly_charges)::NUMERIC, 2) AS total_monthly_revenue
FROM customers
GROUP BY bundle_type
ORDER BY churn_rate DESC;

-- -------------------------------------------------------------------------
-- 3.8. Service count as a satisfaction proxy
-- Macro trend only -- pair with 3.7 since raw service count alone hides which specific
-- combinations are doing the work 
-- -------------------------------------------------------------------------

WITH service_count AS (
    SELECT
        customer_id,
        churn,
        (
            COUNT(*) FILTER (WHERE phone_service = 'Yes') +
            COUNT(*) FILTER (WHERE internet_service != 'No') +
            COUNT(*) FILTER (WHERE online_security = 'Yes') +
            COUNT(*) FILTER (WHERE online_backup = 'Yes') +
            COUNT(*) FILTER (WHERE device_protection = 'Yes') +
            COUNT(*) FILTER (WHERE tech_support = 'Yes') +
            COUNT(*) FILTER (WHERE streaming_tv = 'Yes') +
            COUNT(*) FILTER (WHERE streaming_movies = 'Yes')
        ) AS num_services
    FROM customers
    GROUP BY customer_id, churn
)
SELECT
    num_services,
    COUNT(*) AS customers,
    COUNT(*) FILTER (WHERE churn = 'Yes') AS churned,
    ROUND(COUNT(*) FILTER (WHERE churn = 'Yes') * 100.0 / COUNT(*), 2) AS churn_rate
FROM service_count
GROUP BY num_services
ORDER BY num_services;

-- -------------------------------------------------------------------------
-- 3.9. Add-on service impact (protective factors)
-- -------------------------------------------------------------------------

WITH unpivoted_addons AS (
    SELECT 
		'Online Security' AS service_name, 
		online_security AS has_service, 
		churn, 
		monthly_charges 
	FROM customers
    UNION ALL SELECT 'Online Backup', online_backup, churn, monthly_charges FROM customers
    UNION ALL SELECT 'Device Protection', device_protection, churn, monthly_charges FROM customers
	UNION ALL SELECT 'Tech Support', tech_support, churn, monthly_charges FROM customers
	UNION ALL SELECT 'Streaming TV', streaming_tv, churn, monthly_charges FROM customers
	UNION ALL SELECT 'Streaming Movies', streaming_movies, churn, monthly_charges FROM customers
),
addon_metrics AS (
    SELECT
        service_name,
        ROUND(COUNT(*) FILTER (WHERE has_service = 'Yes' AND churn = 'Yes') * 100.0
            / NULLIF(COUNT(*) FILTER (WHERE has_service = 'Yes'), 0), 2) AS churn_rate_with,
        ROUND(COUNT(*) FILTER (WHERE has_service != 'Yes' AND churn = 'Yes') * 100.0
            / NULLIF(COUNT(*) FILTER (WHERE has_service != 'Yes'), 0), 2) AS churn_rate_without,
        ROUND(AVG(monthly_charges) FILTER (WHERE has_service = 'Yes')::NUMERIC, 2) AS avg_spend_with,
        ROUND(AVG(monthly_charges) FILTER (WHERE has_service != 'Yes')::NUMERIC, 2) AS avg_spend_without
    FROM unpivoted_addons
    GROUP BY service_name
)
SELECT
    service_name,
    churn_rate_with,
    churn_rate_without,
    ROUND(churn_rate_without - churn_rate_with, 2) AS churn_reduction,
    avg_spend_with,
    avg_spend_without,
    ROUND(avg_spend_with - avg_spend_without, 2) AS spend_increase
FROM addon_metrics
ORDER BY churn_reduction DESC;

-- -------------------------------------------------------------------------
-- 3.10. Payment method risk analysis
-- months_to_break_even: at the average total charges for this payment
-- method, how many months of average billing would it take to recover
-- the customer's lifetime value if they were replaced?
-- -------------------------------------------------------------------------
SELECT
    payment_method,
    COUNT(*) AS customers,
    COUNT(*) FILTER (WHERE churn = 'Yes') AS churned,
    ROUND(COUNT(*) FILTER (WHERE churn = 'Yes') * 100.0 / COUNT(*), 2) AS churn_rate,
    ROUND(AVG(tenure)::NUMERIC, 1) AS avg_tenure,
    ROUND(AVG(monthly_charges)::NUMERIC, 2) AS avg_monthly,
    ROUND(AVG(total_charges)::NUMERIC, 2) AS avg_total,
    ROUND(AVG(total_charges)::NUMERIC / NULLIF(AVG(monthly_charges)::NUMERIC, 0), 1) AS months_to_break_even
FROM customers
GROUP BY payment_method
ORDER BY churn_rate DESC;

-- ====================================================================================================
									-- PART 4. STAKEHOLDER SUMMARY
				-- Single-purpose queries built to feed report cards / Power BI visuals
-- ====================================================================================================

-- -------------------------------------------------------------------------
-- 4.1. Executive one-pager
-- One row, every headline number a stakeholder deck needs.
-- -------------------------------------------------------------------------

SELECT
    COUNT(*) AS total_customers,
    COUNT(*) FILTER (WHERE churn = 'Yes') AS churned,
    ROUND(COUNT(*) FILTER (WHERE churn = 'Yes') * 100.0 / COUNT(*), 2) AS churn_rate,
    ROUND(SUM(total_charges)::NUMERIC, 2) AS total_revenue,
    ROUND(SUM(total_charges) FILTER (WHERE churn = 'Yes')::NUMERIC, 2) AS lost_revenue,
    ROUND(
        SUM(total_charges) FILTER (WHERE churn = 'Yes') * 100.0 /
        NULLIF(SUM(total_charges), 0), 2
    ) AS revenue_lost_pct,
    ROUND(AVG(tenure) FILTER (WHERE churn = 'Yes')::NUMERIC, 1) AS avg_tenure_churned,
    ROUND(AVG(tenure) FILTER (WHERE churn != 'Yes')::NUMERIC, 1) AS avg_tenure_retained,
    ROUND(AVG(monthly_charges)::NUMERIC, 2) AS avg_monthly_revenue
FROM customers;

-- ------------------------------------------------------------------------------------
-- 4.2. Top 5 revenue-risk segments (contract x internet x payment method)
-- HAVING > 10 keeps the list to segments with a statistically meaningful churn count.
-- ------------------------------------------------------------------------------------

SELECT
    contract,
    internet_service,
    payment_method,
    COUNT(*) AS customers,
    COUNT(*) FILTER (WHERE churn = 'Yes') AS churned,
    ROUND(COUNT(*) FILTER (WHERE churn = 'Yes') * 100.0 / COUNT(*), 2) AS churn_rate,
    ROUND(SUM(total_charges) FILTER (WHERE churn = 'Yes')::NUMERIC, 2) AS revenue_lost,
    ROUND(
        SUM(total_charges) FILTER (WHERE churn = 'Yes') * 100.0 /
        NULLIF(SUM(total_charges), 0), 2
    ) AS revenue_impact_pct
FROM customers
GROUP BY contract, internet_service, payment_method
HAVING COUNT(*) FILTER (WHERE churn = 'Yes') > 10
ORDER BY revenue_lost DESC
LIMIT 5;

-- -------------------------------------------------------------------------
-- 4.3. Retention campaign effectiveness simulator
-- What-if framing for a stakeholder deck: if we cut churn by 10% / 20%
-- in a given contract x internet segment, how much monthly recurring
-- revenue (MRR) would that save?
-- -------------------------------------------------------------------------

WITH churn_scenario AS (
    SELECT
        contract,
        internet_service,
        COUNT(*) AS customers,
        COUNT(*) FILTER (WHERE churn = 'Yes') AS churned,
        ROUND(SUM(monthly_charges) FILTER (WHERE churn = 'Yes')::NUMERIC, 2) AS revenue_loss,
        ROUND(SUM(monthly_charges) FILTER (WHERE churn != 'Yes')::NUMERIC, 2) AS retained_revenue
    FROM customers
    GROUP BY contract, internet_service
)
SELECT
    contract,
    internet_service,
    customers,
    churned,
    ROUND(churned * 100.0 / customers, 2) AS current_churn_rate,
    revenue_loss,
    retained_revenue,
	-- Scenarios: Saved Monthly Recurring Revenue (MRR) per 10% / 20% churn reduction
    ROUND(revenue_loss * 0.10, 2) AS saved_mrr_10pct,
    ROUND(revenue_loss * 0.20, 2) AS saved_mrr_20pct
FROM churn_scenario
WHERE churned > 5
ORDER BY revenue_loss DESC;

-- ====================================================================================================
								-- PART 5. POWER BI DATA LAYER
			-- Views built on top of `customers` to serve Power BI visualizations
-- ====================================================================================================

-- ------------------------------------------------------------------------------
-- V1. vw_customer_analytics  (PRIMARY IMPORT TABLE)
-- Row-level grain -- one row per customer. 
-- Adds the two derived columns every page needs: the standard tenure_group and
-- num_services, plus a ready-made high_risk_segment flag for the
-- composite persona (month-to-month + fiber optic + electronic check).
-- ------------------------------------------------------------------------------

DROP VIEW IF EXISTS vw_customer_analytics CASCADE;

CREATE VIEW vw_customer_analytics AS
SELECT
    customer_id,
    gender,
    senior_citizen,
    partner,
    dependents,
    tenure,
    CASE
        WHEN tenure <= 12 THEN '0-1 Year'
        WHEN tenure <= 24 THEN '1-2 Years'
        WHEN tenure <= 48 THEN '2-4 Years'
        ELSE '4+ Years'
    END AS tenure_group_detailed,
    phone_service,
    multiple_lines,
    internet_service,
    online_security,
    online_backup,
    device_protection,
    tech_support,
    streaming_tv,
    streaming_movies,
    contract,
    paperless_billing,
    payment_method,
    monthly_charges,
    total_charges,
    churn,
    (
        (phone_service = 'Yes')::INT +
        (internet_service != 'No')::INT +
        (online_security = 'Yes')::INT +
        (online_backup = 'Yes')::INT +
        (device_protection = 'Yes')::INT +
        (tech_support = 'Yes')::INT +
        (streaming_tv = 'Yes')::INT +
        (streaming_movies = 'Yes')::INT
    ) AS num_services,
    CASE
        WHEN tenure <= 12
			AND contract = 'Month to Month'
            AND internet_service = 'Fiber optic'
            AND payment_method = 'Electronic check'
        THEN 'Yes' ELSE 'No'
    END AS high_risk_segment
FROM customers;

-- -------------------------------------------------------------------------
-- V2. vw_segment_churn_summary
-- Segment-level rollup (contract x internet_service x payment_method). 
-- Kept as a dedicated view because the bubble chart needs both axes; 
-- customer count AND churn rate, paired at the same segment 
-- grain to plot correctly.
-- -------------------------------------------------------------------------
DROP VIEW IF EXISTS vw_segment_churn_summary;

CREATE VIEW vw_segment_churn_summary AS
SELECT
    contract,
    internet_service,
	payment_method,
    COUNT(*) AS customer_base,
    COUNT(*) FILTER (WHERE churn = 'Yes') AS churned_customers,
    ROUND(COUNT(*) FILTER (WHERE churn = 'Yes') * 100.0 / COUNT(*), 2) AS churn_rate,
	ROUND(AVG(monthly_charges)::NUMERIC, 2) AS avg_monthly_charges,
	ROUND(SUM(monthly_charges), 2) AS total_mrr,
    ROUND(SUM(monthly_charges) FILTER (WHERE churn = 'Yes')::NUMERIC, 2) AS lost_mrr,
	ROUND(SUM(monthly_charges) FILTER (WHERE churn = 'No')::NUMERIC, 2) AS retained_mrr
FROM customers
GROUP BY contract, internet_service, payment_method
ORDER BY churn_rate DESC;

-- -------------------------------------------------------------------
-- V3. vw_addon_impact
-- Pre-aggregates churn rates for customers with vs. without each of   
-- the significant add-on service (Tech Support, Online Security, 
-- Online Backup, Device Protection). 
-- -------------------------------------------------------------------

DROP VIEW IF EXISTS vw_addon_impact;

CREATE VIEW vw_addon_impact AS
WITH unpivoted_addons AS (
    SELECT
        'Online Security' AS service_name,
        online_security AS has_service,
        churn
    FROM customers
    UNION ALL SELECT 'Tech Support', tech_support, churn FROM customers
    UNION ALL SELECT 'Online Backup', online_backup, churn FROM customers
    UNION ALL SELECT 'Device Protection', device_protection, churn FROM customers
),
aggregated_rates AS (
    SELECT
        service_name,
        ROUND(
            COUNT(*) FILTER (WHERE has_service = 'Yes' AND churn = 'Yes') * 100.0 /
            NULLIF(COUNT(*) FILTER (WHERE has_service = 'Yes'), 0), 2
        ) AS churn_rate_with,
        ROUND(
            COUNT(*) FILTER (WHERE has_service != 'Yes' AND churn = 'Yes') * 100.0 /
            NULLIF(COUNT(*) FILTER (WHERE has_service != 'Yes'), 0), 2
        ) AS churn_rate_without
    FROM unpivoted_addons
    GROUP BY service_name
)
SELECT
    service_name,
    churn_rate_with,
    churn_rate_without
FROM aggregated_rates
ORDER BY ABS(churn_rate_without - churn_rate_with) DESC;

-- -------------------------------------------------------------------------
-- Verification
-- Confirm all views return data before connecting Power BI.
-- -------------------------------------------------------------------------

SELECT 
	'vw_customer_analytics' AS view_name, 
	COUNT(*) AS row_count 
	FROM vw_customer_analytics
UNION ALL
SELECT 'vw_segment_churn_summary', COUNT(*) FROM vw_segment_churn_summary
UNION ALL
SELECT 'vw_addon_impact', COUNT(*) FROM vw_addon_impact;