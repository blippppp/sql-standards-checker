-- =============================================================================
-- File: 01_good_practices.sql
-- Purpose: Demonstrates well-written SQL following best practices and standards.
-- Database: PostgreSQL (compatible with minor modifications for MySQL/SQL Server)
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
-- Example 2: Parameterised query (shown as prepared statement)
-- Protects against SQL injection; uses $1/$2 placeholders (PostgreSQL style)
-- -----------------------------------------------------------------------------
PREPARE fetch_order AS
  SELECT
      o.order_id,
      o.order_date,
      o.status,
      o.total_amount
  FROM orders AS o
  WHERE o.user_id = $1
    AND o.order_date BETWEEN $2 AND $3
  ORDER BY o.order_date DESC;
EXECUTE fetch_order(42, '2024-01-01', '2024-12-31');

-- Equivalent in application code using parameterised binding (framework-style, not psql-executable):
-- SELECT
--     o.order_id,
--     o.order_date,
--     o.status,
--     o.total_amount
-- FROM orders AS o
-- WHERE
--     o.user_id     = :user_id          -- bound parameter
--     AND o.order_date BETWEEN :start_date AND :end_date
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
        DATE_TRUNC('month', order_date) AS revenue_month,
        SUM(total_amount)               AS revenue
    FROM orders
    WHERE status = 'completed'
    GROUP BY DATE_TRUNC('month', order_date)
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
-- Transfers inventory between warehouses safely.
-- Wrapped in a PL/pgSQL DO block so EXCEPTION / ROLLBACK can be demonstrated
-- in plain psql.  In application code the same logic would live inside a
-- function or stored procedure with identical error-handling semantics.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    v_source_warehouse_id  INT  := 1;
    v_dest_warehouse_id    INT  := 2;
    v_product_id           INT  := 42;
    v_transfer_qty         INT  := 10;
    v_rows_affected        INT;
BEGIN
    -- Deduct from source warehouse (only if enough stock exists)
    UPDATE warehouse_inventory
    SET    quantity_on_hand = quantity_on_hand - v_transfer_qty
    WHERE  warehouse_id     = v_source_warehouse_id
      AND  product_id       = v_product_id
      AND  quantity_on_hand >= v_transfer_qty;  -- guard against negative stock

    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;
    IF v_rows_affected = 0 THEN
        RAISE EXCEPTION
            'Insufficient stock for product % in warehouse % (requested %)',
            v_product_id, v_source_warehouse_id, v_transfer_qty;
    END IF;

    -- Add to destination warehouse (upsert)
    INSERT INTO warehouse_inventory (warehouse_id, product_id, quantity_on_hand)
    VALUES (v_dest_warehouse_id, v_product_id, v_transfer_qty)
    ON CONFLICT (warehouse_id, product_id)
    DO UPDATE SET
        quantity_on_hand =
            warehouse_inventory.quantity_on_hand + EXCLUDED.quantity_on_hand;

    -- Record the transfer for audit
    INSERT INTO inventory_transfers (
        source_warehouse_id,
        dest_warehouse_id,
        product_id,
        quantity,
        transferred_at
    )
    VALUES (
        v_source_warehouse_id,
        v_dest_warehouse_id,
        v_product_id,
        v_transfer_qty,
        NOW()
    );

EXCEPTION
    WHEN OTHERS THEN
        -- Transaction is automatically rolled back when an exception escapes
        -- a DO block; re-raise so the caller sees the original error.
        RAISE;
END;
$$;

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
            AND o.order_date >= NOW() - INTERVAL '30 days'
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
WHERE created_at >= CURRENT_DATE - INTERVAL '7 days'

UNION ALL

SELECT
    'payment'     AS event_type,
    payment_id    AS entity_id,
    processed_at  AS event_time,
    processed_by  AS actor
FROM payments
WHERE processed_at >= CURRENT_DATE - INTERVAL '7 days'

ORDER BY event_time DESC;

-- -----------------------------------------------------------------------------
-- Example 9: Proper indexing hints in table creation
-- CREATE TABLE with appropriate constraints and index suggestions
-- -----------------------------------------------------------------------------
/*
CREATE TABLE order_items (
    order_item_id  BIGSERIAL       PRIMARY KEY,
    order_id       BIGINT          NOT NULL REFERENCES orders(order_id),
    product_id     BIGINT          NOT NULL REFERENCES products(product_id),
    quantity       INTEGER         NOT NULL CHECK (quantity > 0),
    unit_price     NUMERIC(10, 2)  NOT NULL CHECK (unit_price >= 0),
    created_at     TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

-- Index on the foreign key for JOIN performance
CREATE INDEX idx_order_items_order_id   ON order_items(order_id);
CREATE INDEX idx_order_items_product_id ON order_items(product_id);
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
