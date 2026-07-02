-- SBL Credit Risk Analysis Queries
-- Tables: workspace.default.clients, workspace.default.loans, workspace.default.collateral_holdings

-- SELECT * FROM workspace.default.clients LIMIT 10;
-- SELECT * FROM workspace.default.loans LIMIT 10;
-- SELECT * FROM workspace.default.collateral_holdings LIMIT 10;

-- SELECT COUNT(*) FROM workspace.default.clients;             -- should be 5000
-- SELECT COUNT(*) FROM workspace.default.loans;               -- should be 6000
--  SELECT COUNT(*) FROM workspace.default.collateral_holdings; -- should be ~359238

------------------------------------------------------------------------
-- Query #1: Grouping by credit_tier and counting
-------------------------------------------------------------------------
SELECT credit_tier, COUNT(*) AS client_count
FROM workspace.default.clients
GROUP BY credit_tier
ORDER BY client_count DESC;

------------------------------------------------------------------------
-- Query #2: Average loan amount by client segment (Retail / HNW / UHNW)
------------------------------------------------------------------------
SELECT c.segment, ROUND(AVG(l.loan_amount), 2) AS avg_loan_amount
FROM workspace.default.loans l
JOIN workspace.default.clients c
  ON l.client_id = c.client_id
GROUP BY c.segment
ORDER BY avg_loan_amount DESC;

------------------------------------------------------------------------
-- Query #3: Total collateral value by asset type across the whole book
------------------------------------------------------------------------
SELECT asset_type, ROUND(SUM(market_value), 2) AS total_collateral_value
FROM workspace.default.collateral_holdings
GROUP BY asset_type
ORDER BY total_collateral_value DESC;

------------------------------------------------------------------------
-- Query #4: Top 10 loans by LTV ratio (loan_amount / total collateral value)
------------------------------------------------------------------------
SELECT
  l.loan_id,
  l.client_id,
  l.credit_tier,
  l.loan_amount,
  ROUND(SUM(ch.market_value), 2) AS total_collateral_value,
  ROUND(l.loan_amount / SUM(ch.market_value), 4) AS ltv_ratio
FROM workspace.default.loans l
JOIN workspace.default.collateral_holdings ch
  ON l.loan_id = ch.loan_id
GROUP BY l.loan_id, l.client_id, l.credit_tier, l.loan_amount
ORDER BY ltv_ratio DESC
LIMIT 10;

------------------------------------------------------------------------
-- Query #5a: Create tier rules reference table (run once)
------------------------------------------------------------------------
CREATE OR REPLACE TEMP VIEW tier_rules AS
SELECT 'Tier_A' AS credit_tier, 0.70 AS max_ltv, 0.80 AS maintenance_ltv
UNION ALL
SELECT 'Tier_B', 0.65, 0.75
UNION ALL
SELECT 'Tier_C', 0.60, 0.70;

------------------------------------------------------------------------
-- Query #5: Full LTV breach/margin-call flagging by credit tier (single snapshot, 2025-06-01)
------------------------------------------------------------------------
SELECT
  l.loan_id,
  l.client_id,
  l.credit_tier,
  l.loan_amount,
  ROUND(SUM(ch.market_value), 2) AS collateral_value,
  ROUND(l.loan_amount / SUM(ch.market_value), 4) AS ltv_ratio,
  r.max_ltv,
  r.maintenance_ltv,
  CASE
    WHEN l.loan_amount / SUM(ch.market_value) > r.maintenance_ltv THEN 'MARGIN CALL'
    WHEN l.loan_amount / SUM(ch.market_value) > r.max_ltv THEN 'BREACH - MAX LTV'
    ELSE 'OK'
  END AS risk_status
FROM workspace.default.loans l
JOIN workspace.default.collateral_holdings ch
  ON l.loan_id = ch.loan_id
JOIN tier_rules r
  ON l.credit_tier = r.credit_tier
WHERE ch.snapshot_date = '2025-06-01'
GROUP BY l.loan_id, l.client_id, l.credit_tier, l.loan_amount, r.max_ltv, r.maintenance_ltv
ORDER BY ltv_ratio DESC;

------------------------------------------------------------------------
-- Query #6: Month-over-month change in total collateral value per loan (uses LAG window function)
------------------------------------------------------------------------
WITH monthly_collateral AS (
  SELECT
    loan_id,
    snapshot_date,
    ROUND(SUM(market_value), 2) AS total_collateral_value
  FROM workspace.default.collateral_holdings
  GROUP BY loan_id, snapshot_date
)
SELECT
  loan_id,
  snapshot_date,
  total_collateral_value,
  LAG(total_collateral_value) OVER (PARTITION BY loan_id ORDER BY snapshot_date) AS prev_month_value,
  ROUND(
    total_collateral_value - LAG(total_collateral_value) OVER (PARTITION BY loan_id ORDER BY snapshot_date),
    2
  ) AS mom_change,
  ROUND(
    100.0 * (total_collateral_value - LAG(total_collateral_value) OVER (PARTITION BY loan_id ORDER BY snapshot_date))
    / LAG(total_collateral_value) OVER (PARTITION BY loan_id ORDER BY snapshot_date),
    2
  ) AS mom_pct_change
FROM monthly_collateral
ORDER BY loan_id, snapshot_date;

------------------------------------------------------------------------
-- Query #7: Which region has the highest % of loans breaching max_ltv (single snapshot, 2025-06-01)
------------------------------------------------------------------------
WITH loan_ltv AS (
  SELECT
    l.loan_id,
    c.region,
    l.credit_tier,
    ROUND(l.loan_amount / SUM(ch.market_value), 4) AS ltv_ratio
  FROM workspace.default.loans l
  JOIN workspace.default.clients c
    ON l.client_id = c.client_id
  JOIN workspace.default.collateral_holdings ch
    ON l.loan_id = ch.loan_id
  WHERE ch.snapshot_date = '2025-06-01'
  GROUP BY l.loan_id, c.region, l.credit_tier, l.loan_amount
),
flagged AS (
  SELECT
    ll.region,
    CASE WHEN ll.ltv_ratio > r.max_ltv THEN 1 ELSE 0 END AS is_breach
  FROM loan_ltv ll
  JOIN tier_rules r
    ON ll.credit_tier = r.credit_tier
)
SELECT
  region,
  ROUND(100.0 * SUM(is_breach) / COUNT(*), 2) AS pct_loans_breaching,
  COUNT(*) AS total_loans
FROM flagged
GROUP BY region
ORDER BY pct_loans_breaching DESC;