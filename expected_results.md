# Expected Results — SQL Standards Checker

This document describes what the SQL Standards Checker should identify in each test file, along with suggested improvements, severity ratings, and expected issue counts per category.

**Severity scale**
- 🔴 **Critical** — data loss, security breach, or production outage risk
- 🟠 **High** — significant performance or correctness problem
- 🟡 **Medium** — maintainability or convention issue
- 🟢 **Low / Info** — style or minor improvement suggestion

---

## `01_good_practices.sql` — Expected: 0 issues

This file is a **false-positive baseline**. The SQL Standards Checker should produce no issues or warnings. If the checker flags anything in this file, review whether it is a false positive.

| # | Finding | Expected result |
|---|---------|-----------------|
| — | All queries | No issues detected |

---

## `02_anti_patterns.sql` — Expected: 12+ issues

| # | Line(s) | Issue | Severity | Suggestion |
|---|---------|-------|----------|------------|
| 1 | ~14 | `SELECT *` on `users` table | 🟡 Medium | List only required columns explicitly |
| 2 | ~17 | `SELECT *` inside a JOIN | 🟡 Medium | List required columns; ambiguous names break if schema changes |
| 3 | ~24–27 | Implicit JOIN (comma syntax) | 🟠 High | Replace with explicit `INNER JOIN … ON` |
| 4 | ~30–33 | Three-table implicit JOIN missing a condition | 🔴 Critical | Missing `AND p.supplier_id = s.supplier_id` creates Cartesian product |
| 5 | ~40 | `UPDATE orders` with no `WHERE` clause | 🔴 Critical | Add `WHERE order_date < CURRENT_DATE - INTERVAL '1 year'` or similar |
| 6 | ~41 | `DELETE FROM sessions` with no `WHERE` clause | 🔴 Critical | Add `WHERE expires_at < NOW()` or similar |
| 7 | ~43 | Unbounded `SELECT` with no `WHERE` or `LIMIT` | 🟠 High | Add appropriate filter and `LIMIT` |
| 8 | ~49–51 | `UNION` instead of `UNION ALL` for mutually exclusive sets | 🟡 Medium | Use `UNION ALL` to avoid unnecessary deduplication sort |
| 9 | ~57–60 | `NOT IN` with a nullable subquery column | 🔴 Critical | Replace with `NOT EXISTS` to handle `NULL` correctly |
| 10 | ~67 | `EXTRACT()` on indexed `order_date` in `WHERE` | 🟠 High | Use a range: `order_date >= '2024-01-01' AND order_date < '2025-01-01'` |
| 11 | ~72 | `LOWER()` on indexed `email` in `WHERE` | 🟠 High | Use a case-insensitive index (`CITEXT` or functional index) |
| 12 | ~77 | Arithmetic on indexed `unit_price` in `WHERE` | 🟠 High | Move arithmetic to the right-hand side: `unit_price > 100 / 1.1` |
| 13 | ~84–89 | Multiple `OR` conditions on same column | 🟡 Medium | Replace with `IN ('pending', 'processing', 'on_hold', …)` |
| 14 | ~95–115 | Cursor-based row-by-row `UPDATE` | 🟠 High | Replace with a single set-based `UPDATE … WHERE customer_id IN (SELECT …)` |
| 15 | ~122–127 | Correlated scalar subquery per row | 🟠 High | Replace with `LEFT JOIN … GROUP BY` |
| 16 | ~136–139 | CSV values in a column + `LIKE '%…%'` | 🟠 High | Normalise to a junction table; use indexed lookup |
| 17 | ~145–146 | Magic number literals (`status = 2`, `payment_method_id = 4`) | 🟡 Medium | Use a lookup/enum table or named constants |
| 18 | ~153–158 | `HAVING` used for non-aggregate row-level filter | 🟡 Medium | Move `customer_id > 100` to `WHERE` clause |

**Total expected issues: 18**

---

## `03_performance_issues.sql` — Expected: 12+ issues

| # | Line(s) | Issue | Severity | Suggestion |
|---|---------|-------|----------|------------|
| 1 | ~14–19 | `DISTINCT` masking a missing JOIN condition | 🟠 High | Find root cause of duplicates; remove `DISTINCT` |
| 2 | ~26–33 | Two scalar subqueries in `SELECT` list (per-row) | 🟠 High | Replace with `LEFT JOIN … GROUP BY` aggregation |
| 3 | ~39 | `LIKE '%phone%'` leading wildcard | 🟠 High | Use full-text search (`tsvector`) or reverse-index for suffix matches |
| 4 | ~41 | `LIKE '%@gmail.com'` leading wildcard | 🟠 High | Store domain separately or use full-text search |
| 5 | ~48–51 | `SELECT` with no `LIMIT` on `orders` | 🟠 High | Add `LIMIT` or pagination |
| 6 | ~53–55 | `SELECT *` with no `LIMIT` on `audit_logs` | 🟠 High | Add column list and `LIMIT` |
| 7 | ~65–67 | Deep `OFFSET` pagination (`OFFSET 99980`) | 🟠 High | Replace with keyset/cursor pagination |
| 8 | ~75 | Cartesian product — missing JOIN condition | 🔴 Critical | Add `ON u.user_id = o.user_id` |
| 9 | ~79 | `CROSS JOIN suppliers` without filter | 🟡 Medium | Add `ON` / `WHERE` condition or justify intent |
| 10 | ~86–90 | N+1 pattern — 5 single-row lookups | 🟠 High | Batch into `WHERE order_id IN (1001,…,1005)` |
| 11 | ~100–106 | `HAVING MAX(order_date) > '2024-01-01'` on all rows | 🟡 Medium | Move date filter to `WHERE` before aggregation |
| 12 | ~114–116 | Filter on `status` — likely missing index | 🟡 Medium | Create `CREATE INDEX idx_orders_status ON orders(status)` |
| 13 | ~119–121 | Range filter on `created_at` — possibly no index | 🟡 Medium | Create index on `users(created_at)` |
| 14 | ~124–127 | Multi-column filter without composite index | 🟡 Medium | Create composite index `(status, order_date)` |
| 15 | ~133–140 | `EXTRACT()` in `GROUP BY` and `ORDER BY` recomputed | 🟢 Low | Use column alias in `GROUP BY` / `ORDER BY` (where supported) |
| 16 | ~147 | `COUNT(order_id)` instead of `COUNT(*)` | 🟢 Low | Use `COUNT(*)` for clarity when NULLs are not a concern |
| 17 | ~154–156 | `OR` across two different columns — index blocked | 🟡 Medium | Rewrite as `UNION ALL` of two separately indexed queries |

**Total expected issues: 17**

---

## `04_security_vulnerabilities.sql` — Expected: 8+ issues

| # | Line(s) | Issue | Severity | Suggestion |
|---|---------|-------|----------|------------|
| 1 | ~22–28 | Dynamic SQL with string concatenation (`search_products_unsafe`) | 🔴 Critical | Use `EXECUTE … USING $1` with parameterised `LIKE` |
| 2 | ~31–43 | Login authentication via concatenated SQL (`login_unsafe`) | 🔴 Critical | Use parameterised prepared statement; compare password hash |
| 3 | ~60–68 | `users_unsafe` table with plain-text `password` column | 🔴 Critical | Use `password_hash` (bcrypt/Argon2); never store plain text |
| 4 | ~71 | `INSERT` storing plain-text password | 🔴 Critical | Hash before inserting: `crypt(:pw, gen_salt('bf'))` |
| 5 | ~75–78 | Plain-text password comparison in `SELECT` | 🔴 Critical | Compare hashes: `crypt(:input_pw, password_hash) = password_hash` |
| 6 | ~88 | `GRANT ALL PRIVILEGES ON DATABASE` to app user | 🟠 High | Grant only necessary per-table permissions |
| 7 | ~91 | `ALTER USER … WITH SUPERUSER` for reporting user | 🔴 Critical | Never grant `SUPERUSER` to application accounts |
| 8 | ~94 | `GRANT INSERT, UPDATE, DELETE` to read-only role | 🟠 High | Read-only roles should have `SELECT` only |
| 9 | ~104–113 | View exposing SSN, full card number, and CVV | 🔴 Critical | Mask / redact PII; never store or expose CVV (PCI DSS §3) |
| 10 | ~122–130 | `orders_unsafe` — no constraints, negative amounts allowed | 🟠 High | Add `NOT NULL`, `REFERENCES`, and `CHECK` constraints |
| 11 | ~133–134 | `INSERT` allowing negative `total_amount` and `>100%` discount | 🟠 High | Enforce `CHECK (total_amount >= 0)` and `CHECK (discount_pct BETWEEN 0 AND 100)` |
| 12 | ~142–145 | Raw password concatenated into audit log | 🔴 Critical | Never log credentials; log only redacted/masked identifiers |
| 13 | ~148–149 | Full bearer token stored in `request_log` | 🟠 High | Log only token prefix/hash, not the full token |
| 14 | ~157–164 | Dynamic `ORDER BY` from user input without allowlist | 🔴 Critical | Validate `p_sort_column` against a fixed allowlist before use |

**Total expected issues: 14**

---

## `05_naming_violations.sql` — Expected: 8+ categories of issues

| # | Line(s) | Issue | Severity | Suggestion |
|---|---------|-------|----------|------------|
| 1 | ~16–24 | `PascalCase` table (`UserProfiles`) and `camelCase` columns | 🟡 Medium | Rename to `user_profiles`, `user_id`, `first_name`, etc. |
| 2 | ~27–33 | Mixed casing in a single query | 🟡 Medium | Standardise to `snake_case` throughout |
| 3 | ~40–49 | Reserved keywords as column/table names (`order`, `select`, `from`, `group`) | 🟠 High | Rename to non-reserved equivalents: `customer_order`, `select_type`, etc. |
| 4 | ~53–56 | Single-letter aliases (`t1`, `t2`, `t3`) and column names (`a`, `b`, `c`) | 🟡 Medium | Use descriptive aliases matching the table purpose |
| 5 | ~59–65 | Numbered column names (`col1`–`col5`) | 🟡 Medium | Use descriptive names reflecting data meaning |
| 6 | ~68–75 | Single-letter function parameters and return columns | 🟡 Medium | Use `p_user_id`, `p_start_date`, `p_end_date`, etc. |
| 7 | ~81–87 | Excessively long table and column names (> 50 chars) | 🟡 Medium | Shorten to `customer_billing`, `customer_id`, `street_address`, etc. |
| 8 | ~97–104 | Spaces and special characters in identifiers (`"customer orders"`, `"total $"`) | 🟠 High | Remove spaces and special chars; use underscores |
| 9 | ~111–120 | Cryptic abbreviations (`usr_mstr`, `usr_nm`, `ord_dt`, `ord_amt`) | 🟡 Medium | Use full words: `user_master` → `users`, `usr_nm` → `username` |
| 10 | ~126–143 | Plural/singular table name inconsistency | 🟡 Medium | Choose one convention (e.g. singular) and apply consistently |
| 11 | ~150–160 | Type suffixes in column names (`_int`, `_str`, `_bool`) and `_tbl` on tables | 🟡 Medium | Remove type suffixes; the schema defines the type |
| 12 | ~163–166 | `vw_` prefix on view name | 🟢 Low | Remove prefix; views are schema objects and don't need a type prefix |

**Total expected issues: 12**

---

## `06_complex_mixed.sql` — Expected: 6–8 issues, 4–5 good sections

| # | Line(s) | Status | Description | Severity |
|---|---------|--------|-------------|----------|
| 1 | ~11–43 | ✅ Good | Well-structured CTE with window function for rolling average | — |
| 2 | ~47–60 | ❌ Issue | CTE uses `SELECT *` three times; third CTE adds a trivial filter | 🟡 Medium |
| 3 | ~65–80 | ✅ Good | Customer segmentation with `NTILE` window function | — |
| 4 | ~86–92 | ❌ Issue | Implicit join in `UPDATE FROM`; missing order status filter → updates all items | 🔴 Critical |
| 5 | ~95–102 | ✅ Good | Corrected set-based `UPDATE` with guard | — |
| 6 | ~107–140 | ⚠️ Mixed | Procedure: good transaction/error handling; cursor for set-based logic | 🟠 High |
| 7 | ~114–118 | ❌ Issue | No validation of refund amount bounds in stored procedure | 🟠 High |
| 8 | ~145–168 | ❌ Issue | Three-level nested subqueries; hard to read; inner subquery unnecessary | 🟡 Medium |
| 9 | ~171–188 | ✅ Good | Same logic rewritten with CTEs for clarity | — |
| 10 | ~194–199 | ❌ Issue | Window function partitioned by primary key (`order_id`) — trivial partition | 🟡 Medium |
| 11 | ~202–211 | ✅ Good | Correct running total with meaningful `PARTITION BY customer_id` | — |

**Total expected issues: 6 | Good sections: 5**

---

## `07_edge_cases.sql` — Expected: 4–5 issues, rest valid edge cases

| # | Line(s) | Status | Description | Severity |
|---|---------|--------|-------------|----------|
| 1 | ~14–32 | ✅ Good | Recursive CTE with depth guard (`WHERE ct.depth < 10`) | — |
| 2 | ~35–43 | ❌ Issue | Recursive CTE without depth limit — infinite loop on cyclic data | 🔴 Critical |
| 3 | ~48–54 | ✅ Good | PostgreSQL `INSERT … ON CONFLICT` UPSERT | — |
| 4 | ~67–74 | ✅ Good | Dynamic SQL using `format('%I')` for safe identifier quoting | — |
| 5 | ~77–82 | ❌ Issue | Dynamic `SELECT *` from user-supplied table name via concatenation | 🔴 Critical |
| 6 | ~86–97 | ✅ Good | Temp table with index and explicit `DROP` for cleanup | — |
| 7 | ~107–113 | ✅ Good | JSONB query using GIN-compatible `@>` operator | — |
| 8 | ~116–117 | ❌ Issue | JSONB `->>` extraction in `WHERE` without supporting index | 🟠 High |
| 9 | ~127–133 | ✅ Good | Full-text search with `tsvector`/`tsquery` | — |
| 10 | ~136–138 | ❌ Issue | `ILIKE '%wireless%'` as full-text search substitute — full scan | 🟠 High |
| 11 | ~143–149 | ✅ Good | Cross-schema query with schema-qualified names | — |
| 12 | ~154–184 | ✅ Good | Long query: well-structured, parameterised, explicit columns | — |
| 13 | ~189–199 | ✅ Good | `LATERAL` join for top-N per group | — |
| 14 | ~204–211 | ✅ Good | Partitioned table query with partition-pruning range filter | — |

**Total expected issues: 5 | Good/valid sections: 9**

---

## Issue Count Summary by Category

| Category | Critical 🔴 | High 🟠 | Medium 🟡 | Low 🟢 | Total |
|----------|------------|---------|-----------|--------|-------|
| Anti-patterns (`02`) | 4 | 6 | 7 | 1 | **18** |
| Performance (`03`) | 1 | 9 | 6 | 1 | **17** |
| Security (`04`) | 8 | 5 | 0 | 1 | **14** |
| Naming (`05`) | 0 | 2 | 9 | 1 | **12** |
| Mixed (`06`) | 1 | 2 | 3 | 0 | **6** |
| Edge cases (`07`) | 2 | 2 | 0 | 1 | **5** |
| **Total** | **16** | **26** | **25** | **5** | **72** |

---

## Benchmark: Prompt Effectiveness

Use the following scoring rubric when evaluating the SQL Standards Checker:

| Score | Criteria |
|-------|----------|
| ⭐⭐⭐⭐⭐ | Detects ≥ 90% of labelled issues; zero false positives on `01_good_practices.sql` |
| ⭐⭐⭐⭐ | Detects 75–89% of issues; ≤ 2 false positives |
| ⭐⭐⭐ | Detects 60–74% of issues; ≤ 5 false positives |
| ⭐⭐ | Detects 40–59% of issues |
| ⭐ | Detects < 40% of issues |

**Minimum passing threshold: ⭐⭐⭐ (≥ 60% detection rate)**
