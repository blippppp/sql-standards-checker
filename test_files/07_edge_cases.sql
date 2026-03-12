-- =============================================================================
-- File: 07_edge_cases.sql
-- Purpose: Advanced scenarios and edge cases that stress-test the SQL
--          Standards Checker, including dynamic SQL, recursive CTEs,
--          MERGE statements, temp tables, JSON, full-text search, and more.
-- Database: PostgreSQL (compatible with minor modifications for MySQL/SQL Server)
-- Scenario: E-commerce / business application
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Edge Case 1: Recursive CTE — proper vs. missing termination guard
-- -----------------------------------------------------------------------------

-- Good: recursive CTE to build a product category hierarchy
WITH RECURSIVE category_tree AS (
    -- Anchor: top-level categories
    SELECT
        category_id,
        category_name,
        parent_category_id,
        0         AS depth,
        category_name::TEXT AS path
    FROM categories
    WHERE parent_category_id IS NULL

    UNION ALL

    -- Recursive: children joined to parent
    SELECT
        c.category_id,
        c.category_name,
        c.parent_category_id,
        ct.depth + 1,
        ct.path || ' > ' || c.category_name
    FROM categories AS c
    INNER JOIN category_tree AS ct ON c.parent_category_id = ct.category_id
    WHERE ct.depth < 10   -- termination guard to prevent infinite loops on cycles
)
SELECT
    category_id,
    category_name,
    depth,
    path
FROM category_tree
ORDER BY path;

-- [EDGE] Recursive CTE WITHOUT a depth guard — dangerous on cyclic graphs
WITH RECURSIVE unsafe_tree AS (
    SELECT category_id, parent_category_id, category_name
    FROM categories
    WHERE parent_category_id IS NULL

    UNION ALL

    SELECT c.category_id, c.parent_category_id, c.category_name
    FROM categories c
    JOIN unsafe_tree t ON c.parent_category_id = t.category_id
    -- [ISSUE] No depth limit — will loop infinitely if data has cycles
)
SELECT * FROM unsafe_tree;

-- -----------------------------------------------------------------------------
-- Edge Case 2: MERGE statement (UPSERT pattern)
-- -----------------------------------------------------------------------------

-- PostgreSQL UPSERT using INSERT ... ON CONFLICT
INSERT INTO inventory (product_id, warehouse_id, quantity_on_hand, updated_at)
VALUES (:product_id, :warehouse_id, :quantity, NOW())
ON CONFLICT (product_id, warehouse_id)
DO UPDATE SET
    quantity_on_hand = EXCLUDED.quantity_on_hand,
    updated_at       = EXCLUDED.updated_at;

-- [EDGE] SQL Server-style MERGE (syntax reference — not valid PostgreSQL)
-- MERGE INTO inventory AS target
-- USING (SELECT :product_id AS product_id,
--               :warehouse_id AS warehouse_id,
--               :quantity AS qty) AS source
--     ON target.product_id = source.product_id
--    AND target.warehouse_id = source.warehouse_id
-- WHEN MATCHED THEN
--     UPDATE SET quantity_on_hand = source.qty, updated_at = NOW()
-- WHEN NOT MATCHED THEN
--     INSERT (product_id, warehouse_id, quantity_on_hand, updated_at)
--     VALUES (source.product_id, source.warehouse_id, source.qty, NOW());

-- -----------------------------------------------------------------------------
-- Edge Case 3: Dynamic SQL generation with parameterised identifiers
-- [EDGE] Using format() with %I for safe identifier quoting in PL/pgSQL
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION get_table_row_count(p_schema TEXT, p_table TEXT)
RETURNS BIGINT AS $$
DECLARE
    v_count BIGINT;
    v_sql   TEXT;
BEGIN
    -- [GOOD] Uses format() with %I to safely quote identifiers
    v_sql := format('SELECT COUNT(*) FROM %I.%I', p_schema, p_table);
    EXECUTE v_sql INTO v_count;
    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

-- [ISSUE] Unsafe dynamic table name (no quoting)
CREATE OR REPLACE FUNCTION get_table_data_unsafe(p_table TEXT)
RETURNS SETOF RECORD AS $$
BEGIN
    -- [SEC] DANGER: p_table is concatenated without quoting
    RETURN QUERY EXECUTE 'SELECT * FROM ' || p_table;
END;
$$ LANGUAGE plpgsql;

-- -----------------------------------------------------------------------------
-- Edge Case 4: Temporary tables
-- -----------------------------------------------------------------------------

-- [GOOD] Using a temp table for intermediate results in a complex batch job
CREATE TEMP TABLE tmp_high_value_customers AS
SELECT
    customer_id,
    SUM(total_amount) AS lifetime_value
FROM orders
WHERE status = 'completed'
GROUP BY customer_id
HAVING SUM(total_amount) > 1000;

CREATE INDEX idx_tmp_hvc_customer_id ON tmp_high_value_customers(customer_id);

-- Use the temp table in subsequent queries
SELECT
    c.customer_id,
    c.email,
    t.lifetime_value
FROM customers AS c
INNER JOIN tmp_high_value_customers AS t ON c.customer_id = t.customer_id
ORDER BY t.lifetime_value DESC;

DROP TABLE IF EXISTS tmp_high_value_customers;   -- cleanup

-- [EDGE] Global temp table — persists across sessions (SQL Server syntax)
-- CREATE TABLE ##global_temp_orders (
--     order_id INT,
--     total    NUMERIC(10,2)
-- );

-- -----------------------------------------------------------------------------
-- Edge Case 5: JSON / JSONB handling (PostgreSQL)
-- -----------------------------------------------------------------------------

-- [GOOD] Querying a JSONB column with an index-compatible operator
SELECT
    order_id,
    metadata->>'source_channel'      AS acquisition_channel,
    (metadata->>'item_count')::INT   AS item_count
FROM orders
WHERE
    metadata @> '{"source_channel": "mobile_app"}'::JSONB  -- uses GIN index
    AND status = 'completed'
ORDER BY order_id DESC
LIMIT 100;

-- [ISSUE] JSON extraction in WHERE without a supporting index
SELECT order_id
FROM orders
WHERE metadata->>'promo_code' = 'SAVE20';   -- [ISSUE] ->>'promo_code' likely not indexed

-- [EDGE] Aggregating a nested JSON array
SELECT
    order_id,
    jsonb_array_length(metadata->'tags') AS tag_count
FROM orders
WHERE jsonb_typeof(metadata->'tags') = 'array';

-- -----------------------------------------------------------------------------
-- Edge Case 6: Full-text search
-- -----------------------------------------------------------------------------

-- [GOOD] Full-text search with tsvector/tsquery and a functional index
SELECT
    product_id,
    product_name,
    ts_rank(search_vector, query) AS relevance
FROM products
CROSS JOIN to_tsquery('english', 'wireless & headphones') AS query
WHERE search_vector @@ query
ORDER BY relevance DESC
LIMIT 20;

-- [ISSUE] ILIKE used as a full-text search substitute — poor performance
SELECT product_id, product_name
FROM products
WHERE product_name ILIKE '%wireless%'    -- [ISSUE] no index, full scan
   OR description  ILIKE '%wireless%';   -- [ISSUE] same problem on description

-- -----------------------------------------------------------------------------
-- Edge Case 7: Cross-database / cross-schema queries
-- -----------------------------------------------------------------------------

-- [EDGE] Cross-schema query (PostgreSQL schema-qualified names)
SELECT
    a.order_id,
    b.customer_name,
    c.warehouse_name
FROM sales.orders          AS a
JOIN crm.customers         AS b ON a.customer_id = b.customer_id
JOIN logistics.warehouses  AS c ON a.warehouse_id = c.warehouse_id
WHERE a.order_date >= CURRENT_DATE - INTERVAL '30 days';

-- -----------------------------------------------------------------------------
-- Edge Case 8: Very long query with many conditions (readability edge case)
-- -----------------------------------------------------------------------------

SELECT
    o.order_id,
    o.order_date,
    o.total_amount,
    o.discount_amount,
    o.tax_amount,
    o.shipping_amount,
    o.status,
    o.payment_status,
    o.fulfillment_status,
    c.first_name     || ' ' || c.last_name AS customer_name,
    c.email,
    c.phone,
    sa.street_address  AS shipping_street,
    sa.city            AS shipping_city,
    sa.state_province  AS shipping_state,
    sa.postal_code     AS shipping_zip,
    sa.country_code    AS shipping_country,
    pm.payment_type,
    pm.last_four_digits,
    s.carrier_name,
    s.tracking_number,
    s.estimated_delivery_date,
    COUNT(oi.order_item_id)           AS line_item_count,
    SUM(oi.quantity)                  AS total_units,
    SUM(oi.quantity * oi.unit_price)  AS gross_merchandise_value
FROM orders                AS o
INNER JOIN customers       AS c  ON o.customer_id      = c.customer_id
INNER JOIN addresses       AS sa ON o.shipping_addr_id = sa.address_id
INNER JOIN payment_methods AS pm ON o.payment_method_id = pm.payment_method_id
LEFT  JOIN shipments       AS s  ON o.order_id         = s.order_id
INNER JOIN order_items     AS oi ON o.order_id         = oi.order_id
WHERE
    o.status           IN ('processing', 'shipped', 'delivered')
    AND o.order_date   BETWEEN :start_date AND :end_date
    AND c.country_code  = :country_code
    AND o.total_amount >= :min_order_value
GROUP BY
    o.order_id, o.order_date, o.total_amount, o.discount_amount,
    o.tax_amount, o.shipping_amount, o.status, o.payment_status,
    o.fulfillment_status, c.first_name, c.last_name, c.email, c.phone,
    sa.street_address, sa.city, sa.state_province, sa.postal_code, sa.country_code,
    pm.payment_type, pm.last_four_digits,
    s.carrier_name, s.tracking_number, s.estimated_delivery_date
HAVING SUM(oi.quantity) > 0
ORDER BY o.order_date DESC, o.order_id DESC
LIMIT 500;

-- -----------------------------------------------------------------------------
-- Edge Case 9: LATERAL join (PostgreSQL)
-- -----------------------------------------------------------------------------

-- [GOOD] LATERAL join to get the N most recent orders per customer
SELECT
    c.customer_id,
    c.email,
    recent.order_id,
    recent.order_date,
    recent.total_amount
FROM customers AS c
CROSS JOIN LATERAL (
    SELECT order_id, order_date, total_amount
    FROM orders
    WHERE customer_id = c.customer_id
    ORDER BY order_date DESC
    LIMIT 3
) AS recent
WHERE c.is_active = TRUE
ORDER BY c.customer_id, recent.order_date DESC;

-- -----------------------------------------------------------------------------
-- Edge Case 10: Partitioned table query
-- -----------------------------------------------------------------------------

-- [EDGE] Query against a range-partitioned table (PostgreSQL 10+)
-- Partition pruning works when you filter on the partition key (order_date).
SELECT
    order_id,
    customer_id,
    total_amount
FROM orders_partitioned   -- partitioned by RANGE(order_date)
WHERE
    order_date >= '2024-01-01'
    AND order_date <  '2024-04-01'   -- [GOOD] range filter enables partition pruning
    AND status    = 'completed'
ORDER BY order_date, order_id;
