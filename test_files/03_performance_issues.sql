-- =============================================================================
-- File: 03_performance_issues.sql
-- Purpose: Demonstrates common SQL performance problems.
-- Each issue is labelled with a [PERF] comment explaining the bottleneck.
-- Database: PostgreSQL (compatible with minor modifications for MySQL/SQL Server)
-- Scenario: E-commerce / business application queries
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Performance Issue 1: Unnecessary DISTINCT
-- [PERF] DISTINCT triggers an expensive deduplication (sort or hash).
--        If the query is correctly JOINed there should be no duplicates.
-- -----------------------------------------------------------------------------
-- [PERF] The DISTINCT here is masking a missing JOIN condition
SELECT DISTINCT
    u.user_id,
    u.email
FROM users u
JOIN orders o ON u.user_id = o.user_id
JOIN order_items oi ON o.order_id = oi.order_id;
-- Fix: use EXISTS or aggregate; if duplicates exist, find out why.

-- -----------------------------------------------------------------------------
-- Performance Issue 2: Subquery that could be a JOIN
-- [PERF] Scalar subquery in SELECT list runs once per outer row (O(n)).
--        A JOIN computes the result set once (O(1) for the aggregation).
-- -----------------------------------------------------------------------------
SELECT
    p.product_id,
    p.product_name,
    (SELECT COUNT(*)
     FROM order_items oi
     WHERE oi.product_id = p.product_id) AS times_ordered,   -- [PERF] per-row subquery
    (SELECT AVG(r.rating)
     FROM product_reviews r
     WHERE r.product_id = p.product_id) AS avg_rating        -- [PERF] second per-row subquery
FROM products p;

-- -----------------------------------------------------------------------------
-- Performance Issue 3: LIKE with a leading wildcard
-- [PERF] A leading wildcard ('%term') prevents index usage; forces a full scan.
-- -----------------------------------------------------------------------------
SELECT product_id, product_name
FROM products
WHERE product_name LIKE '%phone%';   -- [PERF] leading wildcard, full table scan

SELECT user_id, email
FROM users
WHERE email LIKE '%@gmail.com';      -- [PERF] leading wildcard

-- -----------------------------------------------------------------------------
-- Performance Issue 4: Missing LIMIT on large result sets
-- [PERF] Returning unbounded rows wastes memory and network bandwidth.
--        Always paginate or limit administrative queries.
-- -----------------------------------------------------------------------------
SELECT
    order_id,
    customer_id,
    order_date,
    total_amount,
    status
FROM orders
ORDER BY order_date DESC;   -- [PERF] No LIMIT — could return millions of rows

SELECT *                    -- [PERF] SELECT * + no LIMIT on a large log table
FROM audit_logs
WHERE event_type = 'login';

-- -----------------------------------------------------------------------------
-- Performance Issue 5: Inefficient OFFSET pagination
-- [PERF] OFFSET N scans and discards the first N rows on every page request.
--        Performance degrades linearly as the page number grows.
-- -----------------------------------------------------------------------------
-- Page 1 — fast
SELECT order_id, order_date, total_amount
FROM orders
ORDER BY order_id
LIMIT 20 OFFSET 0;

-- Page 5000 — [PERF] scans and discards 99 980 rows before returning 20
SELECT order_id, order_date, total_amount
FROM orders
ORDER BY order_id
LIMIT 20 OFFSET 99980;

-- Better: keyset / cursor pagination
-- SELECT order_id, order_date, total_amount
-- FROM orders
-- WHERE order_id > :last_seen_order_id
-- ORDER BY order_id
-- LIMIT 20;

-- -----------------------------------------------------------------------------
-- Performance Issue 6: Cartesian product (missing JOIN condition)
-- [PERF] Two tables without a JOIN condition produce rows = |A| × |B|.
--        With 10 000 users and 100 000 orders this yields 10^9 rows.
-- -----------------------------------------------------------------------------
SELECT u.user_id, o.order_id
FROM users u, orders o;   -- [PERF] Cartesian product — no join condition!

-- Another accidental Cartesian via missing condition:
SELECT p.product_name, s.supplier_name
FROM products p
CROSS JOIN suppliers s;   -- [PERF] Intentional? Or should this be filtered?

-- -----------------------------------------------------------------------------
-- Performance Issue 7: N+1 query pattern (shown as repeated individual queries)
-- [PERF] Fetching a list and then querying each item individually causes N+1
--        round-trips to the database. Should be batched into a single query.
-- -----------------------------------------------------------------------------
-- Application pseudo-pattern (DO NOT do this):
-- orders = SELECT order_id FROM orders WHERE status = 'pending';   -- 1 query
-- FOR EACH order IN orders:
--     SELECT * FROM order_items WHERE order_id = order.order_id;   -- N queries

-- [PERF] Simulated N+1 — single-row lookups in a loop instead of a batch JOIN
SELECT order_id, total_amount FROM orders WHERE order_id = 1001;
SELECT order_id, total_amount FROM orders WHERE order_id = 1002;
SELECT order_id, total_amount FROM orders WHERE order_id = 1003;
SELECT order_id, total_amount FROM orders WHERE order_id = 1004;
SELECT order_id, total_amount FROM orders WHERE order_id = 1005;
-- Fix: SELECT order_id, total_amount FROM orders WHERE order_id IN (1001,1002,1003,1004,1005);

-- -----------------------------------------------------------------------------
-- Performance Issue 8: Aggregation without filtering first
-- [PERF] GROUP BY across the entire table before filtering wastes CPU.
--        Push filters into WHERE so the engine aggregates fewer rows.
-- -----------------------------------------------------------------------------
-- [PERF] Aggregates all rows, then filters — should filter before grouping
SELECT
    customer_id,
    COUNT(*)           AS order_count,
    SUM(total_amount)  AS total_spent
FROM orders
GROUP BY customer_id
HAVING SUM(total_amount) > 500
   AND COUNT(*) > 2;
-- Minor issue: HAVING on aggregates is correct, but the date filter below
-- should be in WHERE, not HAVING:

SELECT
    customer_id,
    COUNT(*)          AS order_count
FROM orders
GROUP BY customer_id
HAVING MAX(order_date) > '2024-01-01';   -- [PERF] should be WHERE order_date > '2024-01-01'

-- -----------------------------------------------------------------------------
-- Performance Issue 9: Missing indexes on common query patterns
-- [PERF] These queries filter on columns that are almost certainly not indexed,
--        causing full table scans on large tables.
-- -----------------------------------------------------------------------------
-- [PERF] Filtering on a low-selectivity column without a partial/covering index
SELECT order_id, customer_id, total_amount
FROM orders
WHERE status = 'pending';   -- [PERF] status likely needs an index

-- [PERF] Range query on created_at with no index
SELECT user_id, email, created_at
FROM users
WHERE created_at BETWEEN '2024-06-01' AND '2024-06-30';

-- [PERF] Multi-column filter — composite index (status, order_date) would help
SELECT order_id, total_amount
FROM orders
WHERE status = 'completed'
  AND order_date >= '2024-01-01';

-- -----------------------------------------------------------------------------
-- Performance Issue 10: Repeated computation in ORDER BY / GROUP BY
-- [PERF] Calling a function in ORDER BY or GROUP BY recalculates it for each row.
-- -----------------------------------------------------------------------------
SELECT
    EXTRACT(YEAR FROM order_date)  AS order_year,
    EXTRACT(MONTH FROM order_date) AS order_month,
    SUM(total_amount)              AS monthly_revenue
FROM orders
GROUP BY
    EXTRACT(YEAR FROM order_date),   -- [PERF] computed twice (GROUP BY + SELECT)
    EXTRACT(MONTH FROM order_date)
ORDER BY
    EXTRACT(YEAR FROM order_date),   -- [PERF] computed again for sorting
    EXTRACT(MONTH FROM order_date);

-- -----------------------------------------------------------------------------
-- Performance Issue 11: COUNT(*) vs COUNT(column) confusion
-- [PERF] COUNT(column) skips NULLs and is slightly slower; use COUNT(*)
--        when you just want row count.
-- -----------------------------------------------------------------------------
SELECT COUNT(order_id)   -- [PERF] Equivalent to COUNT(*) here but less clear
FROM orders
WHERE status = 'completed';

-- -----------------------------------------------------------------------------
-- Performance Issue 12: OR conditions preventing index usage
-- [PERF] OR across different columns may prevent the query planner from using
--        a single index efficiently. UNION ALL of two indexed queries can be faster.
-- -----------------------------------------------------------------------------
SELECT order_id, customer_id, total_amount
FROM orders
WHERE customer_id = :cust_id
   OR shipping_address_id = :addr_id;   -- [PERF] OR across two columns — possible full scan
