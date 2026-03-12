# SQL Standards Checker — Test Suite

A comprehensive collection of SQL test files designed to validate the **SQL Standards Checker** prompt. The files cover every major category of SQL quality: best practices, anti-patterns, performance issues, security vulnerabilities, naming conventions, complex mixed scenarios, and advanced edge cases.

---

## Repository Structure

```
sql-standards-checker/
├── test_files/
│   ├── 01_good_practices.sql        # Well-written SQL reference examples
│   ├── 02_anti_patterns.sql         # Common SQL anti-patterns
│   ├── 03_performance_issues.sql    # Performance bottlenecks
│   ├── 04_security_vulnerabilities.sql  # Security flaws
│   ├── 05_naming_violations.sql     # Naming convention problems
│   ├── 06_complex_mixed.sql         # Realistic mix of good and bad code
│   └── 07_edge_cases.sql            # Advanced and edge-case scenarios
├── README.md                        # This file
└── expected_results.md              # Expected checker output per file
```

---

## SQL Standards Checker Prompt

```yaml
name: 'SQL Standards Checker'
description: 'Review SQL code and ensure it adheres to best practices and standards.'
prompt: |
  You are a SQL expert. Examine the following SQL script and identify any
  deviations from common SQL standards or best practices. Provide:
  1. A list of issues or anti-patterns.
  2. Suggestions for correction or improvement.

  SQL Code: {{inputs.sqlPath}}
inputs:
  - id: 'sqlPath'
    type: 'file'
    description: 'Path to the SQL file to be reviewed.'
    required: true
```

---

## Test File Descriptions

### `01_good_practices.sql` — Well-Written SQL Examples
Demonstrates the correct way to write SQL. Use this file to verify that the checker does **not** produce false positives. Includes:
- Explicit column selection (no `SELECT *`)
- Meaningful table and column aliases in `snake_case`
- Proper `INNER JOIN` / `LEFT JOIN` with explicit `ON` conditions
- CTEs for readability
- Window functions with correct framing
- Parameterised queries for security
- `EXISTS` instead of `IN` for correlated lookups
- `UNION ALL` with explicit intent
- Transactions with rollback safety
- Proper `CHECK` constraints and index recommendations

### `02_anti_patterns.sql` — Common SQL Anti-Patterns
Contains 12 labelled anti-patterns that every SQL checker should detect:
- `SELECT *` (including inside JOINs)
- Implicit joins (comma-separated `FROM` list)
- Missing `WHERE` clause on `UPDATE`/`DELETE`
- `UNION` instead of `UNION ALL` when duplicates aren't expected
- `NOT IN` with nullable columns
- Functions on indexed columns in `WHERE`
- Multiple `OR` conditions instead of `IN`
- Cursor-based row-by-row processing
- Correlated subqueries running once per row
- Comma-separated values stored in a single column
- Magic numbers / hardcoded literals
- `HAVING` used for row-level filtering instead of `WHERE`

### `03_performance_issues.sql` — Performance Problems
Twelve performance bottlenecks found in real-world code:
- Unnecessary `DISTINCT`
- Scalar subqueries in `SELECT` list
- `LIKE` with a leading wildcard
- Missing `LIMIT` on large result sets
- Inefficient `OFFSET` pagination
- Accidental Cartesian products
- N+1 query pattern
- Aggregation without pre-filtering
- Missing index on frequently filtered columns
- Repeated function calls in `GROUP BY` / `ORDER BY`
- `COUNT(column)` vs `COUNT(*)`
- `OR` across multiple columns blocking index use

### `04_security_vulnerabilities.sql` — Security Issues
Eight security vulnerabilities with explanations:
- SQL injection via string concatenation in dynamic SQL
- Authentication bypass via injection
- Plain-text password storage and comparison
- Excessive `GRANT` permissions (`ALL PRIVILEGES`, `SUPERUSER`)
- PII / credit-card data exposed in views without masking
- Missing `CHECK` constraints enabling invalid or malicious data
- Logging sensitive credentials in audit tables
- Unsafe dynamic `ORDER BY` / table name from user input

### `05_naming_violations.sql` — Naming Convention Issues
Eight categories of naming problems:
- `camelCase` and `PascalCase` mixed with `snake_case`
- Reserved keywords as identifiers (`order`, `select`, `from`, etc.)
- Non-descriptive single-letter / numbered names (`t1`, `col1`, `f`, `a`)
- Overly verbose names (> 50 characters)
- Special characters and spaces in identifiers
- Cryptic abbreviations (`usr_mstr`, `ord_dt`, `usr_nm`)
- Plural vs. singular table name inconsistency
- Redundant type suffixes / prefixes (`_tbl`, `_int`, `vw_`, `_bool`)

### `06_complex_mixed.sql` — Mixed Good and Bad Practices
A realistic file mirroring production code quality. Contains both good and bad sections to test the checker's ability to identify specific problems without flagging correct code:
- Well-structured CTEs with window functions ✅
- Poorly written CTEs with repeated `SELECT *` ❌
- Correct customer segmentation query ✅
- Implicit-join inventory `UPDATE` with missing guard ❌
- Stored procedure with mixed quality (good transaction handling; cursor where set-based is better) ⚠️
- Nested subqueries vs CTE refactoring comparison ❌ / ✅
- Window function used correctly and incorrectly ✅ / ❌

### `07_edge_cases.sql` — Advanced Scenarios
Ten advanced edge cases:
- Recursive CTE with and without infinite-loop guard
- `INSERT ... ON CONFLICT` (PostgreSQL UPSERT)
- Dynamic SQL with `format()` + `%I` (safe) vs. concatenation (unsafe)
- Temporary tables with proper lifecycle management
- JSONB querying with GIN-index operators vs. unindexed extraction
- Full-text search with `tsvector`/`tsquery` vs. `ILIKE` fallback
- Cross-schema queries
- Long multi-join query with many GROUP BY columns
- `LATERAL` join for top-N per group
- Partitioned table with partition-pruning filters

---

## How to Use These Files

### Option 1 — GitHub Copilot Chat
1. Open GitHub Copilot Chat in your IDE.
2. Attach any SQL file from `test_files/` using the file attachment feature.
3. Paste the prompt:
   > *You are a SQL expert. Examine the following SQL script and identify any deviations from common SQL standards or best practices. Provide: 1. A list of issues or anti-patterns. 2. Suggestions for correction or improvement.*
4. Compare the response against `expected_results.md`.

### Option 2 — GitHub Copilot Extensions / Custom Prompt
If you have the prompt registered as a GitHub Copilot Extension:
```
@sql-standards-checker /review test_files/02_anti_patterns.sql
```

### Option 3 — Manual Review
Each SQL file contains inline `[ISSUE]`, `[PERF]`, `[SEC]`, `[NAME]`, `[GOOD]`, and `[EDGE]` comments marking every intentional problem. Use these as a ground truth when comparing against checker output.

---

## Expected Results Summary

| File | Expected Issues | Categories |
|------|----------------|------------|
| `01_good_practices.sql` | 0 (false-positive test) | — |
| `02_anti_patterns.sql`  | 12+ | Anti-patterns |
| `03_performance_issues.sql` | 12+ | Performance |
| `04_security_vulnerabilities.sql` | 8+ | Security |
| `05_naming_violations.sql` | 8+ | Naming |
| `06_complex_mixed.sql` | 6–8 issues, 4–5 good sections | Mixed |
| `07_edge_cases.sql` | 4–5 issues, rest are valid edge cases | Edge cases |

See [`expected_results.md`](./expected_results.md) for detailed per-file issue lists.

---

## SQL Dialect Notes
- All files are written for **PostgreSQL 14+**.
- MySQL / SQL Server equivalents are noted in comments where syntax differs.
- `SERIAL` → `AUTO_INCREMENT` in MySQL, `IDENTITY` in SQL Server.
- `TIMESTAMPTZ` → `DATETIME` in MySQL / SQL Server.
- `::` cast operator → `CAST(x AS type)` in other dialects.
- `$1`, `$2` bind parameters → `?` in MySQL, `@p1` in SQL Server.

---

## Contributing
Pull requests adding more test scenarios or improving existing examples are welcome. Please follow the same labelling convention (`[ISSUE]`, `[GOOD]`, `[PERF]`, `[SEC]`, `[NAME]`, `[EDGE]`) in inline comments.