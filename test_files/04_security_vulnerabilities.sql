-- =============================================================================
-- File: 04_security_vulnerabilities.sql
-- Purpose: Demonstrates common SQL security vulnerabilities.
-- Each issue is labelled with a [SEC] comment explaining the risk.
-- NOTE: These examples are for EDUCATIONAL PURPOSES ONLY.
--       Never use these patterns in production code.
-- Database: Google BigQuery Standard SQL
-- Scenario: E-commerce / business application queries
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Security Issue 1: SQL injection via string concatenation
-- [SEC] Building queries by concatenating user-supplied input allows an attacker
--       to alter the query structure, bypass authentication, or exfiltrate data.
-- -----------------------------------------------------------------------------

-- [SEC] Dynamic SQL injection in a JavaScript UDF (BigQuery)
-- CREATE TEMP FUNCTION search_products_unsafe(p_search_term STRING)
-- RETURNS ARRAY<STRUCT<product_id INT64, product_name STRING, unit_price NUMERIC>>
-- LANGUAGE js AS """
--   // [SEC] DANGER: user input concatenated directly into SQL string
--   var query = 'SELECT product_id, product_name, unit_price FROM products WHERE product_name LIKE "%' + p_search_term + '%"';
--   // This would be executed unsafely if allowed
--   return executeQuery(query);
-- """;
-- Attack example: search_products_unsafe('''; DROP TABLE products; --')

-- [SEC] Another injection pattern: login authentication bypass
-- CREATE TEMP FUNCTION login_unsafe(p_username STRING, p_password STRING)
-- RETURNS BOOL
-- LANGUAGE js AS """
--   // [SEC] DANGER: attacker can pass "admin'--" as username to skip password check
--   var query = 'SELECT COUNT(*) FROM users WHERE username = "' + p_username +
--               '" AND password = "' + p_password + '"';
--   var result = executeQuery(query);
--   return result > 0;
-- """;

-- -----------------------------------------------------------------------------
-- Security Issue 2: Unparameterised queries (application-layer injection)
-- [SEC] Shown as raw SQL strings that an application might execute directly.
--       The fix is always to use prepared statements / parameterised queries.
-- -----------------------------------------------------------------------------

-- [SEC] Unsafe: string-interpolated user input (conceptual application code)
-- query = "SELECT * FROM users WHERE email = '" + user_input + "'";
-- Safe alternative:  SELECT * FROM users WHERE email = @email  (with named parameter)

-- Correct parameterised version (BigQuery parameterized query style):
-- Using named parameters:
--   SELECT user_id, role FROM users WHERE email = @email AND password_hash = @password_hash;
-- Or positional parameters:
--   SELECT user_id, role FROM users WHERE email = ? AND password_hash = ?;

-- -----------------------------------------------------------------------------
-- Security Issue 3: Plain-text password storage
-- [SEC] Passwords must NEVER be stored in plain text.
--       Always use a strong, salted hashing algorithm (bcrypt, Argon2, scrypt).
-- -----------------------------------------------------------------------------

-- [SEC] Table storing passwords as plain text
CREATE TABLE users_unsafe (
    user_id    INT64 NOT NULL,
    username   STRING(100) NOT NULL,
    password   STRING(100) NOT NULL,   -- [SEC] plain-text password column!
    email      STRING(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

-- [SEC] Inserting a plain-text password
INSERT INTO users_unsafe (username, password, email)
VALUES ('alice', 'MyP@ssword123', 'alice@example.com');   -- [SEC] plaintext!

-- [SEC] Comparing plain-text passwords in a query
SELECT user_id
FROM users_unsafe
WHERE username = 'alice'
  AND password = 'MyP@ssword123';   -- [SEC] plaintext comparison

-- Correct approach: store only the hash (hashing done in application layer for BigQuery)
-- INSERT INTO users (username, password_hash, email)
-- VALUES ('alice', 'hashed_password_using_bcrypt_or_argon2', 'alice@example.com');

-- -----------------------------------------------------------------------------
-- Security Issue 4: Excessive permissions in GRANT statements
-- [SEC] Granting excessive privileges to an application role violates the
--       principle of least privilege. Applications should only have the
--       minimum permissions required.
-- -----------------------------------------------------------------------------

-- [SEC] Granting OWNER role on entire dataset to app user (BigQuery IAM)
-- GRANT `roles/bigquery.dataOwner` ON DATASET ecommerce TO app_user@example.com;

-- [SEC] Granting admin role to reporting user
-- GRANT `roles/bigquery.admin` TO reporting_user@example.com;   -- [SEC] never grant admin to app accounts

-- [SEC] Granting write permissions to a read-only reporting role
-- GRANT `roles/bigquery.dataEditor` ON DATASET project.public TO reporting_role@example.com;

-- Correct approach — least privilege:
-- GRANT `roles/bigquery.dataViewer` ON TABLE project.dataset.orders TO reporting_role@example.com;
-- GRANT `roles/bigquery.dataEditor` ON TABLE project.dataset.orders TO app_role@example.com;

-- -----------------------------------------------------------------------------
-- Security Issue 5: Sensitive data exposed in views without masking
-- [SEC] Creating views that expose PII or sensitive data to broad audiences
--       without masking/redacting puts customer data at risk.
-- -----------------------------------------------------------------------------

-- [SEC] View exposes full credit card numbers and SSNs
CREATE VIEW customer_details_unsafe AS
SELECT
    c.customer_id,
    c.first_name,
    c.last_name,
    c.ssn,                   -- [SEC] Social Security Number exposed
    c.date_of_birth,
    p.card_number,           -- [SEC] Full card number exposed — PCI DSS violation
    p.card_cvv,              -- [SEC] CVV must never be stored or exposed
    p.card_expiry
FROM customers c
JOIN payment_methods p ON c.customer_id = p.customer_id;

-- Correct approach: mask sensitive fields
-- CREATE VIEW customer_details_safe AS
-- SELECT
--     c.customer_id,
--     c.first_name,
--     c.last_name,
--     CONCAT('XXX-XX-', SUBSTR(c.ssn, -4))                      AS ssn_masked,
--     CONCAT('XXXX-XXXX-XXXX-', SUBSTR(p.card_number, -4))      AS card_last_four,
--     p.card_expiry
-- FROM customers c
-- JOIN payment_methods p ON c.customer_id = p.customer_id;

-- -----------------------------------------------------------------------------
-- Security Issue 6: Missing input validation / no constraints
-- [SEC] Without CHECK constraints, invalid or malicious data can be inserted.
-- -----------------------------------------------------------------------------

-- [SEC] No validation on critical columns
CREATE TABLE orders_unsafe (
    order_id     INT64,
    customer_id  INT64,           -- [SEC] no NOT NULL, no FK constraint
    total_amount NUMERIC,         -- [SEC] no CHECK (total_amount >= 0) - BigQuery doesn't support CHECK
    status       STRING(50),      -- [SEC] no constraint — any string accepted
    discount_pct NUMERIC          -- [SEC] could accept 999 (999% discount!)
);

-- [SEC] Negative price allowed
INSERT INTO orders_unsafe (customer_id, total_amount, discount_pct)
VALUES (42, -500.00, 110);   -- [SEC] negative total and over-100% discount

-- Correct approach (validation enforced in application layer or INSERT logic for BigQuery):
-- CREATE TABLE orders (
--     order_id     INT64 NOT NULL,
--     customer_id  INT64 NOT NULL,
--     total_amount NUMERIC(12, 2) NOT NULL,
--     status       STRING(50) NOT NULL,
--     discount_pct NUMERIC(5, 2)
-- );
-- -- Validation must be done at INSERT time via WHERE clauses or application logic
-- -- INSERT INTO orders ... WHERE total_amount >= 0 AND status IN ('pending','completed','cancelled')

-- -----------------------------------------------------------------------------
-- Security Issue 7: Logging sensitive information
-- [SEC] Inserting raw user credentials or tokens into audit/log tables
--       creates a secondary attack surface.
-- -----------------------------------------------------------------------------

-- [SEC] Storing plain-text password in audit log
INSERT INTO audit_log (event_type, user_id, details, logged_at)
VALUES (
    'login_attempt',
    @user_id,
    CONCAT('Password: ', @raw_password),   -- [SEC] raw password in log!
    CURRENT_TIMESTAMP()
);

-- [SEC] Storing full bearer token in logs
INSERT INTO request_log (endpoint, auth_header, requested_at)
VALUES ('/api/orders', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...', CURRENT_TIMESTAMP());

-- -----------------------------------------------------------------------------
-- Security Issue 8: Unrestricted dynamic ORDER BY / table name
-- [SEC] Allowing user-controlled column names or sort directions in dynamic
--       SQL without an allowlist enables injection via ORDER BY or FROM clauses.
-- -----------------------------------------------------------------------------

-- [SEC] Dynamic ORDER BY from user input (JavaScript UDF in BigQuery)
-- CREATE TEMP FUNCTION get_products_sorted(p_sort_column STRING, p_sort_dir STRING)
-- RETURNS ARRAY<STRUCT<...>>
-- LANGUAGE js AS """
--   // [SEC] DANGER: p_sort_column and p_sort_dir are user-controlled
--   var query = 'SELECT * FROM products ORDER BY ' + p_sort_column + ' ' + p_sort_dir;
--   return executeQuery(query);
-- """;
-- Attack: get_products_sorted('product_id; DROP TABLE products; --', 'ASC')
--
-- Correct approach: Use an allowlist in application code before constructing query
