-- =====================================================================
-- 02_kpi_queries.sql — illustrative KPI calculations (v1.0, Soumyata Shakya)
-- Written against the ILLUSTRATIVE schema in 01_conceptual_model_ddl.sql.
-- Definitions follow 21_KPI_Framework.xlsx. Syntax checked in SQLite on
-- empty tables only — no real or Renner data was used.
-- =====================================================================

-- KPI-01 Inventory accuracy: share of SKU-locations with zero variance, per count
SELECT c.store_id, c.count_id,
       ROUND(100.0 * SUM(CASE WHEN d.variance_qty = 0 THEN 1 ELSE 0 END) / COUNT(*), 1) AS inventory_accuracy_pct
FROM stock_count c
JOIN inventory_discrepancy d ON d.count_id = c.count_id
WHERE c.count_type = 'Full' AND c.closed_at IS NOT NULL
GROUP BY c.store_id, c.count_id;
-- Note: assumes a row is written for every SKU-location counted, including zero variance.

-- KPI-02 Stockout rate (sales floor): SKUs with zero on the sales floor / active SKUs, per store
SELECT b.store_id,
       ROUND(100.0 * SUM(CASE WHEN b.qty_on_hand = 0 THEN 1 ELSE 0 END) / COUNT(*), 1) AS stockout_rate_pct
FROM inventory_balance b
JOIN location l ON l.location_id = b.location_id AND l.zone_type = 'Sales floor'
GROUP BY b.store_id;

-- KPI-03 Inventory count duration (hours) per full count
SELECT store_id, count_id,
       ROUND((julianday(closed_at) - julianday(started_at)) * 24, 2) AS count_duration_hours   -- SQLite date maths
FROM stock_count
WHERE count_type = 'Full' AND closed_at IS NOT NULL;

-- KPI-06 Inventory discrepancy rate: sum of absolute variance / sum of system units
SELECT c.store_id, c.count_id,
       ROUND(100.0 * SUM(ABS(d.variance_qty)) / NULLIF(SUM(d.system_qty), 0), 2) AS discrepancy_rate_pct
FROM stock_count c
JOIN inventory_discrepancy d ON d.count_id = c.count_id
GROUP BY c.store_id, c.count_id;

-- KPI-09 Counting frequency: closed full counts per store in a month
SELECT store_id, strftime('%Y-%m', closed_at) AS month, COUNT(*) AS full_counts
FROM stock_count
WHERE count_type = 'Full' AND closed_at IS NOT NULL
GROUP BY store_id, strftime('%Y-%m', closed_at);

-- KPI-10 Stock reconciliation time: count close to last discrepancy resolved (hours)
SELECT c.store_id, c.count_id,
       ROUND((julianday(MAX(d.resolved_at)) - julianday(c.closed_at)) * 24, 1) AS reconciliation_hours
FROM stock_count c
JOIN inventory_discrepancy d ON d.count_id = c.count_id
GROUP BY c.store_id, c.count_id, c.closed_at
HAVING SUM(CASE WHEN d.resolved_at IS NULL THEN 1 ELSE 0 END) = 0;   -- only fully reconciled counts

-- KPI-07 Checkout processing time (seconds) per store-day
SELECT substr(transaction_id, 1, 7) AS pos_prefix, date(payment_at) AS day,
       ROUND(AVG((julianday(payment_at) - julianday(first_read_at)) * 86400), 1) AS avg_checkout_seconds
FROM sales_transaction_line
WHERE line_type = 'Sale' AND first_read_at IS NOT NULL
GROUP BY substr(transaction_id, 1, 7), date(payment_at);

-- Data-quality check DQ-01: tags active on more than one item (expected: no rows)
SELECT item_id, COUNT(*) AS active_tags
FROM rfid_tag WHERE tag_status = 'Active'
GROUP BY item_id HAVING COUNT(*) > 1;

-- Control check BRULE-012: adjustments approved by the user who created the count (expected: no rows)
SELECT a.adjustment_id, a.approved_by
FROM stock_adjustment a
JOIN inventory_discrepancy d ON d.discrepancy_id = a.discrepancy_id
JOIN stock_count c ON c.count_id = d.count_id
WHERE a.approved_by = c.created_by;
