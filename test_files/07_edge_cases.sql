-- =============================================================================
-- File: 07_edge_cases.sql
-- Purpose: Advanced scenarios and edge cases that stress-test the SQL
--          Standards Checker, including dynamic SQL, recursive CTEs,
--          MERGE statements, temp tables, JSON, full-text search, and more.
-- Database: Google BigQuery Standard SQL
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
        CAST(category_name AS STRING) AS path
    FROM categories
    WHERE parent_category_id IS NULL

    UNION ALL

    -- Recursive: children joined to parent
    SELECT
        c.category_id,
        c.category_name,
        c.parent_category_id,
        ct.depth + 1,
        CONCAT(ct.path, ' > ', c.category_name)
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

-- BigQuery MERGE statement (Standard SQL DML)
MERGE INTO inventory AS target
USING (SELECT @product_id AS product_id,
              @warehouse_id AS warehouse_id,
              @quantity AS quantity_on_hand) AS source
    ON target.product_id = source.product_id
   AND target.warehouse_id = source.warehouse_id
WHEN MATCHED THEN
    UPDATE SET quantity_on_hand = source.quantity_on_hand,
               updated_at = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN
    INSERT (product_id, warehouse_id, quantity_on_hand, updated_at)
    VALUES (source.product_id, source.warehouse_id, source.quantity_on_hand, CURRENT_TIMESTAMP());

-- -----------------------------------------------------------------------------
-- Edge Case 3: Dynamic SQL generation with parameterised identifiers
-- [EDGE] BigQuery uses EXECUTE IMMEDIATE for dynamic SQL
-- -----------------------------------------------------------------------------

-- [GOOD] Dynamic SQL with safe identifier quoting (stored procedure)
-- CREATE OR REPLACE PROCEDURE get_table_row_count(p_dataset STRING, p_table STRING, OUT v_count INT64)
-- BEGIN
--   EXECUTE IMMEDIATE FORMAT('SELECT COUNT(*) FROM `%s.%s`', p_dataset, p_table) INTO v_count;
-- END;

-- [ISSUE] Unsafe dynamic table name (no quoting or validation)
-- CREATE OR REPLACE PROCEDURE get_table_data_unsafe(p_table STRING)
-- BEGIN
--   -- [SEC] DANGER: p_table is concatenated without proper validation
--   EXECUTE IMMEDIATE CONCAT('SELECT * FROM ', p_table);
-- END;

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

-- BigQuery temp tables don't support explicit indexes (clustering available on permanent tables)

-- Use the temp table in subsequent queries
SELECT
    c.customer_id,
    c.email,
    t.lifetime_value
FROM customers AS c
INNER JOIN tmp_high_value_customers AS t ON c.customer_id = t.customer_id
ORDER BY t.lifetime_value DESC;

DROP TABLE IF EXISTS tmp_high_value_customers;   -- cleanup

-- [EDGE] BigQuery temp tables exist only for the session/script duration
-- No global temp table concept in BigQuery

-- -----------------------------------------------------------------------------
-- Edge Case 5: JSON handling (BigQuery)
-- -----------------------------------------------------------------------------

-- [GOOD] Querying a JSON column with extraction functions
SELECT
    order_id,
    JSON_EXTRACT_SCALAR(metadata, '$.source_channel') AS acquisition_channel,
    CAST(JSON_EXTRACT_SCALAR(metadata, '$.item_count') AS INT64) AS item_count
FROM orders
WHERE
    JSON_EXTRACT_SCALAR(metadata, '$.source_channel') = 'mobile_app'
    AND status = 'completed'
ORDER BY order_id DESC
LIMIT 100;

-- [ISSUE] JSON extraction in WHERE without a supporting index
SELECT order_id
FROM orders
WHERE JSON_EXTRACT_SCALAR(metadata, '$.promo_code') = 'SAVE20';   -- [ISSUE] extraction not optimized; consider SEARCH index

-- [EDGE] Aggregating a nested JSON array
SELECT
    order_id,
    ARRAY_LENGTH(JSON_EXTRACT_ARRAY(metadata, '$.tags')) AS tag_count
FROM orders
WHERE JSON_TYPE(JSON_EXTRACT(metadata, '$.tags')) = 'array';

-- -----------------------------------------------------------------------------
-- Edge Case 6: Full-text search
-- -----------------------------------------------------------------------------

-- [GOOD] Full-text search using SEARCH function (BigQuery's native full-text capability)
-- BigQuery uses SEARCH index on STRING columns
SELECT
    product_id,
    product_name
FROM products
WHERE SEARCH(product_name, 'wireless headphones')
ORDER BY product_id
LIMIT 20;

-- [ISSUE] LIKE used as a full-text search substitute — poor performance
SELECT product_id, product_name
FROM products
WHERE product_name LIKE '%wireless%'     -- [ISSUE] no index, full scan
   OR description  LIKE '%wireless%';    -- [ISSUE] same problem on description

-- -----------------------------------------------------------------------------
-- Edge Case 7: Cross-database / cross-dataset queries
-- -----------------------------------------------------------------------------

-- [EDGE] Cross-dataset query (BigQuery project.dataset.table notation)
SELECT
    a.order_id,
    b.customer_name,
    c.warehouse_name
FROM `project.sales.orders`          AS a
JOIN `project.crm.customers`         AS b ON a.customer_id = b.customer_id
JOIN `project.logistics.warehouses`  AS c ON a.warehouse_id = c.warehouse_id
WHERE a.order_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY);

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
    AND o.order_date   BETWEEN @start_date AND @end_date
    AND c.country_code  = @country_code
    AND o.total_amount >= @min_order_value
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
-- Edge Case 9: Correlated subquery / window function (LATERAL alternative)
-- -----------------------------------------------------------------------------

-- [GOOD] BigQuery doesn't support LATERAL joins; use window functions or ARRAY_AGG
SELECT
    c.customer_id,
    c.email,
    o.order_id,
    o.order_date,
    o.total_amount
FROM customers AS c
CROSS JOIN UNNEST(
    ARRAY(
        SELECT AS STRUCT order_id, order_date, total_amount
        FROM orders
        WHERE customer_id = c.customer_id
        ORDER BY order_date DESC
        LIMIT 3
    )
) AS o
WHERE c.is_active = TRUE
ORDER BY c.customer_id, o.order_date DESC;

-- -----------------------------------------------------------------------------
-- Edge Case 10: Partitioned table query
-- -----------------------------------------------------------------------------

-- [EDGE] Query against a date-partitioned table (BigQuery native partitioning)
-- Partition pruning works when you filter on the partition column (order_date).
SELECT
    order_id,
    customer_id,
    total_amount
FROM orders_partitioned   -- partitioned by DATE(order_date)
WHERE
    order_date >= '2024-01-01'
    AND order_date <  '2024-04-01'   -- [GOOD] range filter enables partition pruning
    AND status    = 'completed'
ORDER BY order_date, order_id;

-- -----------------------------------------------------------------------------
-- Edge Case 11: ARRAY and STRUCT operations (BigQuery-specific)
-- -----------------------------------------------------------------------------

-- [GOOD] Working with ARRAY fields
SELECT
    order_id,
    customer_id,
    line_items,  -- ARRAY<STRUCT<product_id INT64, quantity INT64, price NUMERIC>>
    ARRAY_LENGTH(line_items) AS item_count
FROM orders_with_arrays
WHERE ARRAY_LENGTH(line_items) > 0;

-- [GOOD] UNNEST to flatten array into rows
SELECT
    o.order_id,
    o.customer_id,
    item.product_id,
    item.quantity,
    item.price
FROM orders_with_arrays AS o,
UNNEST(o.line_items) AS item
WHERE item.quantity > 1;

-- [GOOD] ARRAY_AGG to create arrays from grouped rows
SELECT
    customer_id,
    ARRAY_AGG(order_id ORDER BY order_date DESC LIMIT 10) AS recent_order_ids,
    ARRAY_AGG(STRUCT(order_id, order_date, total_amount) 
              ORDER BY order_date DESC LIMIT 10) AS recent_orders
FROM orders
GROUP BY customer_id;

-- [GOOD] Accessing nested STRUCT fields
SELECT
    order_id,
    shipping_address.street,      -- dot notation for STRUCT fields
    shipping_address.city,
    shipping_address.postal_code
FROM orders_with_structs
WHERE shipping_address.country = 'US';

-- -----------------------------------------------------------------------------
-- Edge Case 12: BigQuery-specific optimizations
-- -----------------------------------------------------------------------------

-- [GOOD] Using clustering keys (DDL example)
-- CREATE TABLE orders_clustered (
--     order_id INT64,
--     customer_id INT64,
--     order_date DATE,
--     status STRING,
--     total_amount NUMERIC
-- )
-- PARTITION BY order_date
-- CLUSTER BY customer_id, status;

-- [GOOD] Materialized view for repeated aggregations
-- CREATE MATERIALIZED VIEW daily_sales AS
-- SELECT
--     DATE(order_date) AS sale_date,
--     SUM(total_amount) AS total_sales,
--     COUNT(DISTINCT customer_id) AS unique_customers,
--     COUNT(*) AS order_count
-- FROM orders
-- WHERE status = 'completed'
-- GROUP BY DATE(order_date);

-- [GOOD] Using APPROX_COUNT_DISTINCT for large-scale aggregations
SELECT
    DATE(order_date) AS order_day,
    APPROX_COUNT_DISTINCT(customer_id) AS approx_customers,  -- [GOOD] faster than exact COUNT(DISTINCT)
    COUNT(*) AS total_orders
FROM orders
WHERE order_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
GROUP BY DATE(order_date)
ORDER BY order_day DESC;
