-- =============================================================================
-- File: 04_security_vulnerabilities.sql
-- Purpose: Demonstrates common SQL security vulnerabilities.
-- Each issue is labelled with a [SEC] comment explaining the risk.
-- NOTE: These examples are for EDUCATIONAL PURPOSES ONLY.
--       Never use these patterns in production code.
-- Database: PostgreSQL (compatible with minor modifications for MySQL/SQL Server)
-- Scenario: E-commerce / business application queries
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Security Issue 1: SQL injection via string concatenation
-- [SEC] Building queries by concatenating user-supplied input allows an attacker
--       to alter the query structure, bypass authentication, or exfiltrate data.
-- -----------------------------------------------------------------------------

-- [SEC] Dynamic SQL injection in a stored procedure (PL/pgSQL)
CREATE OR REPLACE FUNCTION search_products_unsafe(p_search_term TEXT)
RETURNS TABLE(product_id INT, product_name TEXT, unit_price NUMERIC) AS $$
DECLARE
    v_sql TEXT;
BEGIN
    -- [SEC] DANGER: user input concatenated directly into SQL string
    v_sql := 'SELECT product_id, product_name, unit_price FROM products WHERE product_name LIKE ''%' || p_search_term || '%''';
    RETURN QUERY EXECUTE v_sql;
END;
$$ LANGUAGE plpgsql;
-- Attack example: search_products_unsafe('''; DROP TABLE products; --')

-- [SEC] Another injection pattern: login authentication bypass
CREATE OR REPLACE FUNCTION login_unsafe(p_username TEXT, p_password TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    v_sql   TEXT;
    v_count INT;
BEGIN
    -- [SEC] DANGER: attacker can pass "admin'--" as username to skip password check
    v_sql := 'SELECT COUNT(*) FROM users WHERE username = ''' || p_username
             || ''' AND password = ''' || p_password || '''';
    EXECUTE v_sql INTO v_count;
    RETURN v_count > 0;
END;
$$ LANGUAGE plpgsql;

-- -----------------------------------------------------------------------------
-- Security Issue 2: Unparameterised queries (application-layer injection)
-- [SEC] Shown as raw SQL strings that an application might execute directly.
--       The fix is always to use prepared statements / parameterised queries.
-- -----------------------------------------------------------------------------

-- [SEC] Unsafe: string-interpolated user input (conceptual application code)
-- query = "SELECT * FROM users WHERE email = '" + user_input + "'";
-- Safe alternative:  SELECT * FROM users WHERE email = $1  (with bind parameter)

-- Correct parameterised version (PostgreSQL prepared statement style):
-- PREPARE login_stmt AS
--   SELECT user_id, role FROM users WHERE email = $1 AND password_hash = $2;
-- EXECUTE login_stmt('user@example.com', 'hashed_pw');

-- -----------------------------------------------------------------------------
-- Security Issue 3: Plain-text password storage
-- [SEC] Passwords must NEVER be stored in plain text.
--       Always use a strong, salted hashing algorithm (bcrypt, Argon2, scrypt).
-- -----------------------------------------------------------------------------

-- [SEC] Table storing passwords as plain text
CREATE TABLE users_unsafe (
    user_id    SERIAL PRIMARY KEY,
    username   VARCHAR(100) NOT NULL UNIQUE,
    password   VARCHAR(100) NOT NULL,   -- [SEC] plain-text password column!
    email      VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- [SEC] Inserting a plain-text password
INSERT INTO users_unsafe (username, password, email)
VALUES ('alice', 'MyP@ssword123', 'alice@example.com');   -- [SEC] plaintext!

-- [SEC] Comparing plain-text passwords in a query
SELECT user_id
FROM users_unsafe
WHERE username = 'alice'
  AND password = 'MyP@ssword123';   -- [SEC] plaintext comparison

-- Correct approach: store only the hash
-- INSERT INTO users (username, password_hash, email)
-- VALUES ('alice', crypt('MyP@ssword123', gen_salt('bf')), 'alice@example.com');

-- -----------------------------------------------------------------------------
-- Security Issue 4: Excessive permissions in GRANT statements
-- [SEC] Granting ALL PRIVILEGES to an application role violates the
--       principle of least privilege. Applications should only have the
--       minimum permissions required.
-- -----------------------------------------------------------------------------

-- [SEC] Granting ALL on entire database to app user
GRANT ALL PRIVILEGES ON DATABASE ecommerce TO app_user;

-- [SEC] Granting SUPERUSER role
ALTER USER reporting_user WITH SUPERUSER;   -- [SEC] never grant SUPERUSER to app accounts

-- [SEC] Granting write permissions to a read-only reporting role
GRANT INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO reporting_role;

-- Correct approach — least privilege:
-- GRANT SELECT ON orders, products, customers TO reporting_role;
-- GRANT SELECT, INSERT, UPDATE ON orders TO app_role;

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
--     'XXX-XX-' || RIGHT(c.ssn, 4)                 AS ssn_masked,
--     'XXXX-XXXX-XXXX-' || RIGHT(p.card_number, 4) AS card_last_four,
--     p.card_expiry
-- FROM customers c
-- JOIN payment_methods p ON c.customer_id = p.customer_id;

-- -----------------------------------------------------------------------------
-- Security Issue 6: Missing input validation / no constraints
-- [SEC] Without CHECK constraints, invalid or malicious data can be inserted.
-- -----------------------------------------------------------------------------

-- [SEC] No validation on critical columns
CREATE TABLE orders_unsafe (
    order_id     SERIAL PRIMARY KEY,
    customer_id  INTEGER,          -- [SEC] no NOT NULL, no FK constraint
    total_amount NUMERIC,          -- [SEC] no CHECK (total_amount >= 0)
    status       VARCHAR(50),      -- [SEC] no constraint — any string accepted
    discount_pct NUMERIC           -- [SEC] could accept 999 (999% discount!)
);

-- [SEC] Negative price allowed
INSERT INTO orders_unsafe (customer_id, total_amount, discount_pct)
VALUES (42, -500.00, 110);   -- [SEC] negative total and over-100% discount

-- Correct approach:
-- CREATE TABLE orders (
--     order_id     BIGSERIAL PRIMARY KEY,
--     customer_id  BIGINT         NOT NULL REFERENCES customers(customer_id),
--     total_amount NUMERIC(12, 2) NOT NULL CHECK (total_amount >= 0),
--     status       VARCHAR(50)    NOT NULL CHECK (status IN ('pending','completed','cancelled')),
--     discount_pct NUMERIC(5, 2)            CHECK (discount_pct BETWEEN 0 AND 100)
-- );

-- -----------------------------------------------------------------------------
-- Security Issue 7: Logging sensitive information
-- [SEC] Inserting raw user credentials or tokens into audit/log tables
--       creates a secondary attack surface.
-- -----------------------------------------------------------------------------

-- [SEC] Storing plain-text password in audit log
INSERT INTO audit_log (event_type, user_id, details, logged_at)
VALUES (
    'login_attempt',
    :user_id,
    'Password: ' || :raw_password,   -- [SEC] raw password in log!
    NOW()
);

-- [SEC] Storing full bearer token in logs
INSERT INTO request_log (endpoint, auth_header, requested_at)
VALUES ('/api/orders', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...', NOW());

-- -----------------------------------------------------------------------------
-- Security Issue 8: Unrestricted dynamic ORDER BY / table name
-- [SEC] Allowing user-controlled column names or sort directions in dynamic
--       SQL without an allowlist enables injection via ORDER BY or FROM clauses.
-- -----------------------------------------------------------------------------

-- [SEC] Dynamic ORDER BY from user input (PL/pgSQL)
CREATE OR REPLACE FUNCTION get_products_sorted(p_sort_column TEXT, p_sort_dir TEXT)
RETURNS SETOF products AS $$
BEGIN
    -- [SEC] DANGER: p_sort_column and p_sort_dir are user-controlled
    RETURN QUERY EXECUTE
        'SELECT * FROM products ORDER BY ' || p_sort_column || ' ' || p_sort_dir;
END;
$$ LANGUAGE plpgsql;
-- Attack: get_products_sorted('product_id; DROP TABLE products; --', 'ASC')
