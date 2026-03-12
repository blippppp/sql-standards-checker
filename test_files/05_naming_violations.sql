-- =============================================================================
-- File: 05_naming_violations.sql
-- Purpose: Demonstrates common SQL naming convention violations.
-- Each issue is labelled with a [NAME] comment explaining the problem.
-- Convention target: lowercase snake_case for all identifiers.
-- Database: PostgreSQL (compatible with minor modifications for MySQL/SQL Server)
-- Scenario: E-commerce / business application queries
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Naming Violation 1: Inconsistent casing — camelCase mixed with snake_case
-- [NAME] Mixing naming styles within the same schema makes queries harder to
--        read, requires quoting in some databases, and creates confusion.
-- -----------------------------------------------------------------------------

-- [NAME] camelCase column names — inconsistent with the rest of the schema
CREATE TABLE UserProfiles (          -- [NAME] PascalCase table name
    userId          SERIAL PRIMARY KEY,  -- [NAME] camelCase
    firstName       VARCHAR(100),        -- [NAME] camelCase
    lastName        VARCHAR(100),        -- [NAME] camelCase
    emailAddress    VARCHAR(255),        -- [NAME] camelCase
    dateOfBirth     DATE,                -- [NAME] camelCase
    createdAt       TIMESTAMPTZ,         -- [NAME] camelCase
    isActive        BOOLEAN              -- [NAME] camelCase
);

-- [NAME] Mixed casing within a single query
SELECT
    u.userId,             -- [NAME] camelCase reference
    u.firstName,          -- [NAME] camelCase reference
    o.OrderDate,          -- [NAME] PascalCase reference
    o.TotalAmount         -- [NAME] PascalCase reference
FROM UserProfiles u       -- [NAME] PascalCase table
JOIN Orders o             -- [NAME] PascalCase table
    ON u.userId = o.UserId;

-- -----------------------------------------------------------------------------
-- Naming Violation 2: Reserved keywords used as identifiers
-- [NAME] Using reserved words forces quoting everywhere they appear and
--        causes portability issues across different SQL dialects.
-- -----------------------------------------------------------------------------

-- [NAME] 'order', 'user', 'table', 'select', 'group' are reserved keywords
CREATE TABLE "order" (         -- [NAME] reserved word as table name
    "select"   INT,            -- [NAME] reserved word as column name
    "table"    VARCHAR(50),    -- [NAME] reserved word as column name
    "group"    VARCHAR(50),    -- [NAME] reserved word as column name
    "from"     VARCHAR(100),   -- [NAME] reserved word as column name
    "where"    NUMERIC(10,2),  -- [NAME] reserved word as column name
    "index"    INT             -- [NAME] reserved word as column name
);

-- [NAME] Querying the table requires quoting everywhere — error-prone
SELECT "select", "from", "where"
FROM "order"
WHERE "group" = 'retail';

-- -----------------------------------------------------------------------------
-- Naming Violation 3: Non-descriptive names (single letters, numbered suffixes)
-- [NAME] Meaningless names like t1, col1, x make queries impossible to
--        understand or maintain without extensive documentation.
-- -----------------------------------------------------------------------------

-- [NAME] Single-letter table aliases hiding complex JOIN logic
SELECT t1.a, t1.b, t2.c, t3.d
FROM t1
JOIN t2 ON t1.x = t2.x
JOIN t3 ON t2.y = t3.y
WHERE t1.z = 1;

-- [NAME] Numbered column names
CREATE TABLE temp_data (
    col1  VARCHAR(255),   -- [NAME] what is col1?
    col2  INTEGER,        -- [NAME] what is col2?
    col3  NUMERIC(10,2),  -- [NAME] what is col3?
    col4  DATE,           -- [NAME] what is col4?
    col5  BOOLEAN         -- [NAME] what is col5?
);

-- [NAME] Single-letter variable names in stored procedure
CREATE OR REPLACE FUNCTION f(a INT, b DATE, c DATE)
RETURNS TABLE(x INT, y NUMERIC) AS $$   -- [NAME] cryptic parameter and return names
BEGIN
    RETURN QUERY
    SELECT p, q
    FROM t
    WHERE r = a
      AND s BETWEEN b AND c;
END;
$$ LANGUAGE plpgsql;

-- -----------------------------------------------------------------------------
-- Naming Violation 4: Overly long / verbose names
-- [NAME] Excessively long names are impractical to type and harder to read
--        in queries. Aim for descriptive but concise identifiers.
-- -----------------------------------------------------------------------------

CREATE TABLE customer_personal_information_and_billing_details (   -- [NAME] way too long
    the_unique_customer_identifier_for_internal_use   BIGSERIAL PRIMARY KEY,  -- [NAME] verbose
    the_customers_first_given_name                    VARCHAR(100),           -- [NAME] verbose
    the_customers_last_family_surname_name            VARCHAR(100),           -- [NAME] verbose
    customer_full_mailing_and_shipping_street_address VARCHAR(500),           -- [NAME] verbose
    the_date_and_time_when_the_customer_was_created   TIMESTAMPTZ             -- [NAME] verbose
);

-- [NAME] Overly verbose index name
-- CREATE INDEX idx_on_the_orders_table_for_the_status_column_and_order_date_for_reporting
--     ON orders(status, order_date);

-- -----------------------------------------------------------------------------
-- Naming Violation 5: Special characters and spaces in identifiers
-- [NAME] Spaces and special characters require quoting everywhere and are
--        highly error-prone. Stick to letters, digits, and underscores.
-- -----------------------------------------------------------------------------

-- [NAME] Quoted identifiers with spaces — must quote everywhere
CREATE TABLE "customer orders" (          -- [NAME] space in table name
    "order id"       SERIAL PRIMARY KEY,  -- [NAME] space in column name
    "customer-id"    INTEGER,             -- [NAME] hyphen in column name
    "order#amount"   NUMERIC(10,2),       -- [NAME] hash character
    "order.date"     DATE,                -- [NAME] period in name
    "total $"        NUMERIC(10,2)        -- [NAME] dollar sign
);

SELECT "order id", "total $"
FROM "customer orders"
WHERE "customer-id" = 42;

-- -----------------------------------------------------------------------------
-- Naming Violation 6: Ambiguous abbreviations
-- [NAME] Cryptic abbreviations like 'usr', 'ord', 'prd' reduce readability.
--        Use full words or widely understood standard abbreviations.
-- -----------------------------------------------------------------------------

CREATE TABLE usr_mstr (            -- [NAME] unclear abbreviation
    usr_id   SERIAL PRIMARY KEY,
    usr_nm   VARCHAR(100),         -- [NAME] cryptic: usr_nm = user name?
    usr_em   VARCHAR(255),         -- [NAME] cryptic: usr_em = user email?
    usr_dob  DATE,                 -- [NAME] cryptic: usr_dob = date of birth?
    usr_flg  BOOLEAN,              -- [NAME] cryptic: usr_flg = which flag?
    usr_dt   TIMESTAMPTZ           -- [NAME] cryptic: usr_dt = which date?
);

SELECT u.usr_nm, o.ord_dt, o.ord_amt
FROM usr_mstr u
JOIN ord_hdr o ON u.usr_id = o.usr_id;   -- [NAME] ord_hdr? ord_dt? ord_amt?

-- -----------------------------------------------------------------------------
-- Naming Violation 7: Plural vs. singular inconsistency
-- [NAME] Mixing plural and singular table names within the same schema is
--        confusing. Pick one convention and apply it consistently.
-- -----------------------------------------------------------------------------

-- [NAME] Some tables singular, some plural — inconsistent
CREATE TABLE customer (        -- singular
    customer_id SERIAL PRIMARY KEY,
    name        VARCHAR(200)
);

CREATE TABLE orders (          -- [NAME] plural — inconsistent with 'customer'
    order_id    SERIAL PRIMARY KEY,
    customer_id INTEGER REFERENCES customer(customer_id)
);

CREATE TABLE product (         -- singular
    product_id SERIAL PRIMARY KEY,
    name       VARCHAR(200)
);

CREATE TABLE order_items (     -- [NAME] plural — inconsistent with 'product'
    item_id    SERIAL PRIMARY KEY,
    order_id   INTEGER REFERENCES orders(order_id),
    product_id INTEGER REFERENCES product(product_id)
);

-- -----------------------------------------------------------------------------
-- Naming Violation 8: Redundant type suffixes / prefixes
-- [NAME] Adding _tbl, _vw, _int suffixes to object names is unnecessary
--        and adds noise. The database context makes the type clear.
-- -----------------------------------------------------------------------------

CREATE TABLE customers_tbl (         -- [NAME] _tbl suffix redundant
    customer_id_int  SERIAL PRIMARY KEY,  -- [NAME] _int type suffix
    name_str         VARCHAR(200),        -- [NAME] _str type suffix
    age_int          INTEGER,             -- [NAME] _int type suffix
    is_active_bool   BOOLEAN              -- [NAME] _bool type suffix
);

-- [NAME] View with _vw prefix
CREATE VIEW vw_active_customers AS    -- [NAME] vw_ prefix is noise
SELECT customer_id_int, name_str
FROM customers_tbl
WHERE is_active_bool = TRUE;
