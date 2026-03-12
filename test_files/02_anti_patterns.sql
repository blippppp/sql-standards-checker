-- =============================================================================
-- File: 02_anti_patterns.sql
-- Purpose: Demonstrates common SQL anti-patterns and bad practices.
-- Each issue is labelled with an [ISSUE] comment explaining the problem.
-- Database: Google BigQuery Standard SQL
-- Scenario: E-commerce / business application queries
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Anti-Pattern 1: SELECT * usage
-- [ISSUE] Retrieves all columns, including unused ones; breaks if schema changes;
--         prevents index-only scans; transfers excess data over the network.
-- -----------------------------------------------------------------------------
SELECT *
FROM users;

-- [ISSUE] SELECT * in a JOIN is even worse — ambiguous column names, duplicate data
SELECT *
FROM orders o, users u
WHERE o.user_id = u.user_id;

-- -----------------------------------------------------------------------------
-- Anti-Pattern 2: Implicit JOIN (comma-separated tables)
-- [ISSUE] Old SQL-89 syntax; hard to read; easy to accidentally create a
--         Cartesian product if the WHERE clause is omitted or mis-written.
-- -----------------------------------------------------------------------------
SELECT
    o.order_id,
    u.email
FROM orders o, users u, order_items oi
WHERE o.user_id = u.user_id
  AND oi.order_id = o.order_id;

-- [ISSUE] Three-table implicit join — intent is unclear, maintenance is difficult
SELECT p.product_name, c.category_name, s.supplier_name
FROM products p, categories c, suppliers s
WHERE p.category_id = c.category_id;
-- Missing: AND p.supplier_id = s.supplier_id  → Cartesian product with suppliers!

-- -----------------------------------------------------------------------------
-- Anti-Pattern 3: Missing WHERE clause (unbounded full-table scan)
-- [ISSUE] Returns every row; dangerous on large tables; likely a bug.
-- -----------------------------------------------------------------------------
UPDATE orders
SET status = 'archived';   -- [ISSUE] Archives ALL orders, not just old ones!

DELETE FROM sessions;      -- [ISSUE] Deletes every session row!

SELECT order_id, total_amount FROM orders;  -- [ISSUE] No filter, dumps whole table

-- -----------------------------------------------------------------------------
-- Anti-Pattern 4: UNION instead of UNION ALL when duplicates are not expected
-- [ISSUE] UNION performs an expensive DISTINCT sort/hash to remove duplicates.
--         If the source tables are already distinct, this work is wasted.
-- -----------------------------------------------------------------------------
SELECT user_id FROM premium_users
UNION
SELECT user_id FROM enterprise_users;
-- [ISSUE] If the two tables are mutually exclusive, UNION ALL is cheaper.

-- -----------------------------------------------------------------------------
-- Anti-Pattern 5: NOT IN with nullable columns
-- [ISSUE] If any value in the subquery result set is NULL, NOT IN returns no rows
--         because SQL uses three-valued logic (TRUE / FALSE / UNKNOWN).
-- -----------------------------------------------------------------------------
SELECT order_id, customer_id
FROM orders
WHERE customer_id NOT IN (
    SELECT customer_id FROM blacklisted_customers   -- [ISSUE] customer_id could be NULL
);

-- -----------------------------------------------------------------------------
-- Anti-Pattern 6: Function on an indexed column in WHERE clause
-- [ISSUE] Wrapping an indexed column in a function prevents index usage,
--         causing a full table scan even when an index exists.
-- -----------------------------------------------------------------------------
-- [ISSUE] YEAR() on an indexed date column disables the index
SELECT order_id, order_date
FROM orders
WHERE EXTRACT(YEAR FROM order_date) = 2024;

-- [ISSUE] LOWER() on an indexed email column prevents index scan
SELECT user_id, email
FROM users
WHERE LOWER(email) = 'john@example.com';

-- [ISSUE] Arithmetic on indexed column prevents index usage
SELECT product_id, unit_price
FROM products
WHERE unit_price * 1.1 > 100;

-- -----------------------------------------------------------------------------
-- Anti-Pattern 7: Multiple OR conditions that could use IN
-- [ISSUE] Multiple OR conditions on the same column are harder to read and
--         may be less efficient than a single IN() predicate.
-- -----------------------------------------------------------------------------
SELECT order_id, status
FROM orders
WHERE status = 'pending'
   OR status = 'processing'
   OR status = 'on_hold'
   OR status = 'awaiting_payment'
   OR status = 'awaiting_shipment';

-- -----------------------------------------------------------------------------
-- Anti-Pattern 8: Cursor-based row-by-row processing
-- [ISSUE] Cursors process one row at a time (RBAR – Row-By-Agonising-Row).
--         Most cursor logic can and should be replaced with set-based operations.
-- -----------------------------------------------------------------------------
-- [ISSUE] Cursor to update discount per customer — should be a single UPDATE
-- BigQuery doesn't support procedural cursors in Standard SQL
-- Multi-statement script example (anti-pattern - use set-based UPDATE instead):
-- BEGIN TRANSACTION;
-- DECLARE v_customer_id INT64;
-- DECLARE v_total_orders INT64;
-- -- Loop through customers (anti-pattern - use set-based UPDATE instead)
-- FOR record IN (SELECT customer_id FROM customers) DO
--     SET v_customer_id = record.customer_id;
--     SET v_total_orders = (SELECT COUNT(*) FROM orders WHERE customer_id = v_customer_id);
--     IF v_total_orders > 10 THEN
--         UPDATE customers SET discount_tier = 'gold' WHERE customer_id = v_customer_id;
--     END IF;
-- END FOR;
-- COMMIT TRANSACTION;

-- Better set-based equivalent:
-- UPDATE customers
-- SET discount_tier = 'gold'
-- WHERE customer_id IN (
--     SELECT customer_id FROM orders
--     GROUP BY customer_id
--     HAVING COUNT(*) > 10
-- );

-- -----------------------------------------------------------------------------
-- Anti-Pattern 9: Correlated subquery executed once per row
-- [ISSUE] The subquery runs for every row in the outer query.
--         Should be replaced with a JOIN or window function.
-- -----------------------------------------------------------------------------
SELECT
    p.product_id,
    p.product_name,
    (
        SELECT SUM(oi.quantity)           -- [ISSUE] Runs once per product row
        FROM order_items oi
        WHERE oi.product_id = p.product_id
    ) AS total_sold
FROM products p;

-- -----------------------------------------------------------------------------
-- Anti-Pattern 10: Storing comma-separated values in a column
-- [ISSUE] Violates 1NF; makes querying, indexing, and referential integrity
--         impossible without application-side parsing.
-- -----------------------------------------------------------------------------
-- [ISSUE] Tags stored as a comma-delimited string
SELECT product_id, product_name, tags   -- tags = 'electronics,sale,new-arrival'
FROM products
WHERE tags LIKE '%electronics%';        -- [ISSUE] Cannot use an index on tags

-- -----------------------------------------------------------------------------
-- Anti-Pattern 11: Hardcoded magic numbers
-- [ISSUE] Numeric literals with no explanation are unclear and unmaintainable.
-- -----------------------------------------------------------------------------
SELECT order_id, total_amount
FROM orders
WHERE status = 2              -- [ISSUE] What does status 2 mean?
  AND payment_method_id = 4;  -- [ISSUE] What is payment method 4?

-- -----------------------------------------------------------------------------
-- Anti-Pattern 12: Using HAVING to filter individual rows (should use WHERE)
-- [ISSUE] HAVING is evaluated after GROUP BY; using it for row-level filters
--         that could be expressed in WHERE forces unnecessary aggregation.
-- -----------------------------------------------------------------------------
SELECT
    customer_id,
    SUM(total_amount) AS total_spent
FROM orders
GROUP BY customer_id
HAVING customer_id > 100;   -- [ISSUE] This should be a WHERE clause filter

-- -----------------------------------------------------------------------------
-- BigQuery-Specific Anti-Patterns
-- -----------------------------------------------------------------------------

-- [ISSUE] Not using partition pruning on partitioned tables
-- Anti-Pattern 13: Query on partitioned table without filtering partition column
SELECT
    order_id,
    customer_id,
    total_amount
FROM orders_partitioned  -- partitioned by order_date
WHERE customer_id = 12345;  -- [ISSUE] Missing order_date filter = full table scan across all partitions

-- Better: Add partition filter to enable pruning
-- SELECT order_id, customer_id, total_amount
-- FROM orders_partitioned
-- WHERE customer_id = 12345
--   AND order_date >= '2024-01-01'  -- [GOOD] Partition pruning enabled

-- [ISSUE] Scanning unpartitioned column instead of using clustering
-- Anti-Pattern 14: Query does not leverage clustering keys
SELECT *
FROM orders_clustered  -- clustered by customer_id
WHERE status = 'pending'  -- [ISSUE] Not using clustered column = inefficient scan
LIMIT 100;

-- [ISSUE] Using EXACT COUNT DISTINCT on very large datasets
-- Anti-Pattern 15: COUNT(DISTINCT ...) on billions of rows
SELECT
    COUNT(DISTINCT customer_id) AS unique_customers
FROM orders
WHERE order_date >= '2020-01-01';  -- [ISSUE] Exact distinct is expensive; use APPROX_COUNT_DISTINCT

-- [ISSUE] Not materializing repeated expensive aggregations
-- Anti-Pattern 16: Repeatedly computing the same aggregation
SELECT
    (SELECT SUM(total_amount) FROM orders WHERE status = 'completed') AS total_revenue,
    (SELECT COUNT(*) FROM orders WHERE status = 'completed') AS completed_orders,
    customer_id
FROM customers;  -- [ISSUE] Subqueries execute for every customer row; use CTE or materialized view
