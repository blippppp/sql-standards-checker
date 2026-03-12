-- =============================================================================
-- File: 06_complex_mixed.sql
-- Purpose: Realistic mix of good and bad SQL practices in a single file.
--          Mirrors what you would find in a typical production codebase.
-- Issues are labelled with [ISSUE], good sections with [GOOD].
-- Database: Google BigQuery Standard SQL
-- Scenario: E-commerce reporting and order management
-- =============================================================================

-- =============================================================================
-- SECTION A: Reporting queries — mixed quality
-- =============================================================================

-- [GOOD] Well-structured CTE for daily sales summary
WITH daily_sales AS (
    SELECT
        CAST(order_date AS DATE)       AS sale_date,
        COUNT(DISTINCT order_id)       AS order_count,
        COUNT(DISTINCT customer_id)    AS unique_customers,
        SUM(total_amount)              AS gross_revenue,
        SUM(discount_amount)           AS total_discounts,
        SUM(total_amount - discount_amount) AS net_revenue
    FROM orders
    WHERE
        status = 'completed'
        AND order_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
    GROUP BY CAST(order_date AS DATE)
),
-- [GOOD] Second CTE chains cleanly onto first
rolling_avg AS (
    SELECT
        sale_date,
        order_count,
        net_revenue,
        AVG(net_revenue) OVER (
            ORDER BY sale_date
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ) AS seven_day_avg_revenue
    FROM daily_sales
)
SELECT
    sale_date,
    order_count,
    net_revenue,
    ROUND(seven_day_avg_revenue, 2) AS seven_day_avg_revenue
FROM rolling_avg
ORDER BY sale_date DESC;

-- -----------------------------------------------------------------------------

-- [ISSUE] Poor CTE that duplicates work unnecessarily and mixes concerns
WITH all_data AS (
    SELECT *   -- [ISSUE] SELECT * in CTE — pulls every column
    FROM orders
    JOIN order_items ON orders.order_id = order_items.order_id  -- [ISSUE] no table alias
    JOIN products ON order_items.product_id = products.product_id
    JOIN users ON orders.user_id = users.user_id
),
filtered AS (
    SELECT * FROM all_data  -- [ISSUE] SELECT * again — doubled width
    WHERE status = 'completed'
),
more_filtered AS (
    SELECT * FROM filtered  -- [ISSUE] Third CTE just adds one more filter
    WHERE total_amount > 0  -- [ISSUE] total_amount > 0 could be in first CTE's WHERE
)
SELECT *                    -- [ISSUE] SELECT * to the caller as well
FROM more_filtered;

-- =============================================================================
-- SECTION B: Customer segmentation — mostly good
-- =============================================================================

-- [GOOD] Well-written customer segmentation using window functions
SELECT
    customer_id,
    total_orders,
    total_spent,
    NTILE(4) OVER (ORDER BY total_spent DESC) AS spending_quartile,
    CASE NTILE(4) OVER (ORDER BY total_spent DESC)
        WHEN 1 THEN 'platinum'
        WHEN 2 THEN 'gold'
        WHEN 3 THEN 'silver'
        ELSE        'bronze'
    END AS customer_tier
FROM (
    SELECT
        customer_id,
        COUNT(order_id)   AS total_orders,
        SUM(total_amount) AS total_spent
    FROM orders
    WHERE status = 'completed'
    GROUP BY customer_id
) AS customer_summary
ORDER BY total_spent DESC;

-- =============================================================================
-- SECTION C: Inventory management — contains issues
-- =============================================================================

-- [ISSUE] Implicit join + missing WHERE guard on UPDATE
UPDATE products
SET stock_quantity = stock_quantity - order_items.quantity  -- [ISSUE] ambiguous without alias
FROM order_items, orders                                     -- [ISSUE] implicit join
WHERE order_items.product_id = products.product_id;
-- [ISSUE] Missing: AND orders.order_id = order_items.order_id AND orders.status = 'new'
-- This will decrement stock for ALL order_items, not just new orders!

-- [GOOD] Corrected version of the same UPDATE
UPDATE products AS p
SET stock_quantity = p.stock_quantity - oi.quantity
FROM order_items AS oi
INNER JOIN orders AS o ON oi.order_id = o.order_id
WHERE
    oi.product_id = p.product_id
    AND o.status  = 'confirmed'
    AND p.stock_quantity >= oi.quantity;   -- [GOOD] guard against negative stock

-- =============================================================================
-- SECTION D: Stored procedure — mixed quality
-- =============================================================================

-- BigQuery stored procedure (multi-statement script)
-- CREATE OR REPLACE PROCEDURE process_refund(
--     p_order_id     INT64,
--     p_refund_amt   NUMERIC,
--     p_reason       STRING
-- )
-- BEGIN
--   DECLARE v_order_total NUMERIC;
--   DECLARE v_customer_id INT64;
--   
--   -- [GOOD] Fetch needed columns only; validate existence
--   SET (v_order_total, v_customer_id) = (
--     SELECT AS STRUCT total_amount, customer_id
--     FROM orders
--     WHERE order_id = p_order_id
--   );
--
--   IF v_order_total IS NULL THEN
--     RAISE USING MESSAGE = FORMAT('Order %t not found', p_order_id);
--   END IF;
--
--   -- [ISSUE] No validation that refund amount is within bounds
--   -- Should check: p_refund_amt > 0 AND p_refund_amt <= v_order_total
--
--   -- [ISSUE] Loop used where a single UPDATE would suffice
--   -- FOR record IN (SELECT order_item_id FROM order_items WHERE order_id = p_order_id)
--   -- DO
--   --   UPDATE order_items SET refunded = TRUE WHERE order_item_id = record.order_item_id;
--   -- END FOR;
--   -- [GOOD] Better: single set-based UPDATE
--   UPDATE order_items SET refunded = TRUE WHERE order_id = p_order_id;
--
--   -- [GOOD] Insert refund record within a transaction
--   INSERT INTO refunds (order_id, customer_id, amount, reason, created_at)
--   VALUES (p_order_id, v_customer_id, p_refund_amt, p_reason, CURRENT_TIMESTAMP());
--
--   -- [GOOD] Update order status atomically
--   UPDATE orders
--   SET status = 'refunded', updated_at = CURRENT_TIMESTAMP()
--   WHERE order_id = p_order_id;
-- END;

-- =============================================================================
-- SECTION E: Analytics — nested subqueries vs CTEs
-- =============================================================================

-- [ISSUE] Deeply nested subqueries — hard to read and debug
SELECT
    product_id,
    product_name,
    total_revenue
FROM (
    SELECT
        product_id,
        product_name,
        total_revenue,
        RANK() OVER (ORDER BY total_revenue DESC) AS revenue_rank
    FROM (
        SELECT
            p.product_id,
            p.product_name,
            SUM(oi.quantity * oi.unit_price) AS total_revenue
        FROM (
            SELECT product_id, product_name
            FROM products
            WHERE is_active = TRUE          -- [ISSUE] innermost subquery unnecessary
        ) p
        JOIN order_items oi ON p.product_id = oi.product_id
        JOIN orders o ON oi.order_id = o.order_id
        WHERE o.status = 'completed'
        GROUP BY p.product_id, p.product_name
    ) rev
) ranked
WHERE revenue_rank <= 10;

-- [GOOD] Same query rewritten with CTEs for readability
WITH product_revenue AS (
    SELECT
        p.product_id,
        p.product_name,
        SUM(oi.quantity * oi.unit_price) AS total_revenue
    FROM products AS p
    INNER JOIN order_items AS oi ON p.product_id = oi.product_id
    INNER JOIN orders AS o ON oi.order_id = o.order_id
    WHERE
        p.is_active  = TRUE
        AND o.status = 'completed'
    GROUP BY p.product_id, p.product_name
),
ranked_products AS (
    SELECT
        product_id,
        product_name,
        total_revenue,
        RANK() OVER (ORDER BY total_revenue DESC) AS revenue_rank
    FROM product_revenue
)
SELECT product_id, product_name, total_revenue
FROM ranked_products
WHERE revenue_rank <= 10
ORDER BY revenue_rank;

-- =============================================================================
-- SECTION F: Window functions with potential issues
-- =============================================================================

-- [ISSUE] Redundant PARTITION BY that serves no purpose
SELECT
    order_id,
    customer_id,
    total_amount,
    SUM(total_amount) OVER (PARTITION BY order_id) AS order_total  -- [ISSUE] partitioning by PK = no grouping
FROM orders;

-- [GOOD] Correct use — running total per customer
SELECT
    customer_id,
    order_date,
    total_amount,
    SUM(total_amount) OVER (
        PARTITION BY customer_id
        ORDER BY order_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_spend
FROM orders
WHERE status = 'completed'
ORDER BY customer_id, order_date;
