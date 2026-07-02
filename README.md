# SBL Credit Risk & Collateral Stress-Testing Platform

Simulated JPMorgan-style Securities-Based Lending (SBL) credit risk workflow — collateral valuation, LTV monitoring, and stress-testing on Databricks.

## Overview

Securities-Based Lending allows clients to borrow against investment portfolios (equities, bonds, mutual funds) instead of liquidating them. The core risk a credit desk manages: if collateral value drops, the loan-to-value (LTV) ratio rises, and once it crosses a threshold, the client faces a **margin call** — post more collateral or the lender liquidates.

This project builds that monitoring system end-to-end: synthetic data generation → Databricks medallion pipeline (Bronze/Silver/Gold) → SQL-based LTV and breach analysis → multi-panel dashboard.

## Tech stack

`Databricks (PySpark + SQL)` `Delta Lake` `Python` `Databricks SQL Dashboards`

## Dataset

370,238 synthetic records generated to mirror a real SBL book:

| Table | Rows | Description |
|---|---|---|
| `clients` | 5,000 | client_id, segment (Retail/HNW/UHNW), region, credit_tier, onboarding_date |
| `loans` | 6,000 | loan_id, client_id, credit_tier, loan_amount, interest_rate, origination_date, status |
| `collateral_holdings` | 359,238 | monthly snapshots (Jan–Jun 2025) of equity/bond/mutual fund positions per loan |

4 credit tiers, each with its own max LTV and maintenance (margin-call) threshold:

| Tier | Max LTV | Maintenance LTV |
|---|---|---|
| Tier 1 – Prime | 70% | 75% |
| Tier 2 – Standard | 65% | 70% |
| Tier 3 – Subprime | 60% | 65% |
| Tier 4 – High Risk | 50% | 55% |

## Pipeline architecture

```
Bronze  → raw ingestion of clients / loans / collateral_holdings, null & duplicate checks
Silver  → collateral aggregated per loan per snapshot, joined with client/loan attributes,
          base LTV computed
Gold    → tier-based LTV threshold rules applied, risk_status flagged (OK / BREACH / MARGIN CALL),
          stress-test scenarios applied (-10% / -20% / -30% collateral shock,
          equities weighted 1x, funds 0.8x, bonds 0.3x)
```



## Key SQL logic

- Collateral value aggregation per loan per snapshot date
- LTV ratio calculation (`loan_amount / collateral_value`)
- Tier-based breach/margin-call flagging via `CASE WHEN`
- Month-over-month collateral value change using `LAG()` window functions
- Regional breach-rate analysis
- Stress-test shock simulation across 3 market decline scenarios

All queries: [`sql/analysis_queries.sql`](https://github.com/rachitbhatt16/SBL_Credit_Risk/blob/main/SQL_Queries)

## Dashboard

7-panel Databricks SQL dashboard (screenshot below; [live version](YOUR_DASHBOARD_LINK) requires Databricks login to view):

![Loan Portfolio Analysis Dashboard](dashboard/loan_portfolio_dashboard.png)

![Loan Portfolio Analysis Dashboard](dashboard/loan_portfolio_dashboard.png)

- Credit tier distribution
- Average loan amount by client segment
- Collateral value by asset type
- Top 10 highest-LTV loans
- LTV breach scatter (loan amount vs LTV ratio, colored by tier)
- Month-over-month collateral value trend
- Regional breach analysis

## Key findings

- At current (June 2025) collateral values, **72.6%** of the loan book sits in margin-call territory under the tier thresholds used
- Breach rates are highest in **MA** and **TX** regions
- LTV rises with loan size, consistent with larger loans drawing closer to tier limits over time

## How to reproduce

1. Run `data/generate_sbl_data.py` to regenerate the 3 CSVs (or use the ones in `/data`)
2. Upload CSVs to Databricks via **Data → Create Table**
3. Import `notebooks/sbl_databricks_pipeline.py` as a Databricks notebook, attach a cluster, run top to bottom
4. Build visualizations on the Gold tables and add to a dashboard

## Author

Rachit Bhatt — [Portfolio](https://rachitbhatt.lovable.app) | [LinkedIn](https://linkedin.com/in/rachitbhatt0016) | [GitHub](https://github.com/rachitbhatt16)
