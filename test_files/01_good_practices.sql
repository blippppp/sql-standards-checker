-- =============================================================================
-- File: 01_good_practices.sql
-- Purpose: Demonstrates well-written SQL following best practices and standards.
-- Database: Google BigQuery Standard SQL
-- Scenario: E-commerce / business application queries
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Example 1: Explicit column selection with meaningful aliases
-- Avoids SELECT *, names are descriptive, consistent snake_case
-- -----------------------------------------------------------------------------
SELECT
    u.user_id,
    u.first_name,
    u.last_name,
    u.email,
    COUNT(o.order_id)   AS total_orders,
    SUM(o.total_amount) AS lifetime_value
FROM users AS u
INNER JOIN orders AS o
    ON u.user_id = o.user_id
WHERE
    u.is_active = TRUE
    AND u.created_at >= '2023-01-01'
GROUP BY
    u.user_id,
    u.first_name,
    u.last_name,
    u.email
HAVING COUNT(o.order_id) > 0
ORDER BY lifetime_value DESC
LIMIT 100;

-- -----------------------------------------------------------------------------
-- Example 2: Parameterised query (BigQuery style)
-- Protects against SQL injection; uses @parameter_name placeholders
-- -----------------------------------------------------------------------------
-- BigQuery parameterised query using named parameters
SELECT
    o.order_id,
    o.order_date,
    o.status,
    o.total_amount
FROM orders AS o
WHERE o.user_id = @user_id
  AND o.order_date BETWEEN @start_date AND @end_date
ORDER BY o.order_date DESC;

-- Alternative: Positional parameters using ?
-- SELECT
--     o.order_id,
--     o.order_date,
--     o.status,
--     o.total_amount
-- FROM orders AS o
-- WHERE o.user_id = ?
--   AND o.order_date BETWEEN ? AND ?
-- ORDER BY o.order_date DESC;

-- -----------------------------------------------------------------------------
-- Example 3: Proper use of LEFT JOIN with NULL check
-- Finds customers who have never placed an order
-- -----------------------------------------------------------------------------
SELECT
    c.customer_id,
    c.first_name,
    c.last_name,
    c.email
FROM customers AS c
LEFT JOIN orders AS o
    ON c.customer_id = o.customer_id
WHERE o.order_id IS NULL
ORDER BY c.last_name, c.first_name;

-- -----------------------------------------------------------------------------
-- Example 4: CTE for readability (replaces deeply nested subqueries)
-- Calculates monthly revenue with a clear, readable structure
-- -----------------------------------------------------------------------------
WITH monthly_revenue AS (
    SELECT
        DATE_TRUNC(order_date, MONTH) AS revenue_month,
        SUM(total_amount)             AS revenue
    FROM orders
    WHERE status = 'completed'
    GROUP BY DATE_TRUNC(order_date, MONTH)
),
revenue_with_growth AS (
    SELECT
        revenue_month,
        revenue,
        LAG(revenue) OVER (ORDER BY revenue_month) AS prev_month_revenue
    FROM monthly_revenue
)
SELECT
    revenue_month,
    revenue,
    prev_month_revenue,
    ROUND(
        (revenue - prev_month_revenue) / NULLIF(prev_month_revenue, 0) * 100,
        2
    ) AS month_over_month_pct
FROM revenue_with_growth
ORDER BY revenue_month;

-- -----------------------------------------------------------------------------
-- Example 5: Proper use of window functions
-- Ranks products by sales within each category
-- -----------------------------------------------------------------------------
SELECT
    p.product_id,
    p.product_name,
    c.category_name,
    SUM(oi.quantity * oi.unit_price) AS total_sales,
    RANK() OVER (
        PARTITION BY c.category_id
        ORDER BY SUM(oi.quantity * oi.unit_price) DESC
    ) AS sales_rank
FROM products AS p
INNER JOIN categories AS c
    ON p.category_id = c.category_id
INNER JOIN order_items AS oi
    ON p.product_id = oi.product_id
INNER JOIN orders AS o
    ON oi.order_id = o.order_id
WHERE o.status = 'completed'
GROUP BY
    p.product_id,
    p.product_name,
    c.category_id,
    c.category_name
ORDER BY c.category_name, sales_rank;

-- -----------------------------------------------------------------------------
-- Example 6: Proper transaction with error handling
-- Transfers inventory between warehouses safely using MERGE for upsert.
-- BigQuery uses multi-statement transactions with BEGIN/COMMIT/ROLLBACK.
-- In application code, this logic would be wrapped in a transaction block.
-- -----------------------------------------------------------------------------
-- BEGIN TRANSACTION;
--
-- -- Deduct from source warehouse (only if enough stock exists)
-- UPDATE warehouse_inventory
-- SET quantity_on_hand = quantity_on_hand - 10
-- WHERE warehouse_id = 1
--   AND product_id = 42
--   AND quantity_on_hand >= 10;  -- guard against negative stock
--
-- -- Check if the update succeeded (application logic would verify rows affected)
-- -- If @@ROWCOUNT = 0, ROLLBACK and raise error
--
-- -- Add to destination warehouse using MERGE (upsert)
-- MERGE INTO warehouse_inventory AS target
-- USING (SELECT 2 AS warehouse_id, 42 AS product_id, 10 AS quantity) AS source
-- ON target.warehouse_id = source.warehouse_id
--   AND target.product_id = source.product_id
-- WHEN MATCHED THEN
--   UPDATE SET quantity_on_hand = target.quantity_on_hand + source.quantity
-- WHEN NOT MATCHED THEN
--   INSERT (warehouse_id, product_id, quantity_on_hand)
--   VALUES (source.warehouse_id, source.product_id, source.quantity);
--
-- -- Record the transfer for audit
-- INSERT INTO inventory_transfers (
--     source_warehouse_id,
--     dest_warehouse_id,
--     product_id,
--     quantity,
--     transferred_at
-- )
-- VALUES (1, 2, 42, 10, CURRENT_TIMESTAMP());
--
-- COMMIT TRANSACTION;

-- -----------------------------------------------------------------------------
-- Example 7: EXISTS instead of IN for correlated lookups (more efficient)
-- Finds active products that have been ordered in the last 30 days
-- -----------------------------------------------------------------------------
SELECT
    p.product_id,
    p.product_name,
    p.unit_price
FROM products AS p
WHERE
    p.is_active = TRUE
    AND EXISTS (
        SELECT 1
        FROM order_items AS oi
        INNER JOIN orders AS o ON oi.order_id = o.order_id
        WHERE
            oi.product_id = p.product_id
            AND o.order_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
    )
ORDER BY p.product_name;

-- -----------------------------------------------------------------------------
-- Example 8: UNION ALL for combining result sets (explicit about duplicates)
-- Generates a combined audit log from two tables
-- -----------------------------------------------------------------------------
SELECT
    'order'       AS event_type,
    order_id      AS entity_id,
    created_at    AS event_time,
    created_by    AS actor
FROM orders
WHERE created_at >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)

UNION ALL

SELECT
    'payment'     AS event_type,
    payment_id    AS entity_id,
    processed_at  AS event_time,
    processed_by  AS actor
FROM payments
WHERE processed_at >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)

ORDER BY event_time DESC;

-- -----------------------------------------------------------------------------
-- Example 9: Proper table creation with constraints
-- CREATE TABLE with appropriate constraints (BigQuery syntax)
-- -----------------------------------------------------------------------------
/*
CREATE TABLE order_items (
    order_item_id  INT64           NOT NULL,
    order_id       INT64           NOT NULL,
    product_id     INT64           NOT NULL,
    quantity       INT64           NOT NULL,
    unit_price     NUMERIC(10, 2)  NOT NULL,
    created_at     TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP()
);

-- Note: BigQuery doesn't support traditional indexes or foreign keys
-- Instead, use clustering and partitioning for query optimization
-- Example: Partition by created_at, cluster by order_id and product_id

CREATE TABLE order_items_partitioned (
    order_item_id  INT64           NOT NULL,
    order_id       INT64           NOT NULL,
    product_id     INT64           NOT NULL,
    quantity       INT64           NOT NULL,
    unit_price     NUMERIC(10, 2)  NOT NULL,
    created_at     TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP()
)
PARTITION BY DATE(created_at)
CLUSTER BY order_id, product_id;
*/

-- -----------------------------------------------------------------------------
-- Example 10: IN list instead of multiple ORs
-- -----------------------------------------------------------------------------
SELECT
    order_id,
    status,
    total_amount
FROM orders
WHERE status IN ('pending', 'processing', 'shipped')
ORDER BY order_id;
