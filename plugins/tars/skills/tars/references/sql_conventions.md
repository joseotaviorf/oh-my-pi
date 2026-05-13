# SQL Style Guide — Sections 1–8

> **Scope for Tars:** Sections 1–8 (formatting, naming, style) apply to all ad-hoc analysis queries. Sections 9–12 (SELECT *, partition filtering, PII storage, layer policy) are pipeline-specific and do **not** apply to data exploration.

## General SQL Principles

- **Enforce consistency**: All SQL code should follow these guidelines
- **Prioritize readability**: Code should be easy to read and understand
- **Use explicit syntax**: Always use explicit keywords (e.g., `AS` for aliases)
- **Avoid ambiguity**: Use descriptive names and avoid generic aliases

---

## 1. Column Naming and Arrangement

### Naming Conventions

- **Language**: All columns must be in English
- **Case**: Use lowercase, except for reserved words and functions (UPPERCASE)
- **Format**: Use snake_case (e.g., `column_name`)
- **Aliases**: Avoid generic aliases (e.g., `table_name AS t`)
- **Reserved words**: Avoid using reserved words as column names (e.g., `type`, `date`)
- **IDs**: Avoid ambiguous `id` - add context (e.g., `id_user`, `id_order` instead of just `id`)
- **Source-to-model alias normalization**: When source names are identifiable, normalize with explicit aliases:
  - IDs: suffix-style to prefix-style (e.g., `client_id AS id_client`, `usuario_id AS id_user`)
  - Timestamps: `ts_<past_tense_when_possible>` (e.g., `created_at AS ts_created`)
  - Dates: `dt_<past_tense_when_possible>` (e.g., `signed_date AS dt_signed`)
  - If past tense is not natural/clear, use semantic fallback (e.g., `contract_date AS dt_contract`)

### Column Arrangement Priority

Follow column arrangement priority order: IDs → UUIDs → Non-SKs (DW only) → Characteristics → Metrics → Booleans → Dates → Timestamps → Array/struct/map → Partitions.

---

## 2. Aliasing and Correlations

### Rules

- **Avoid generic aliases**: Do not use single letters or generic names (e.g., `table_name AS t`)
- **Use descriptive aliases**: Aliases should relate to the object/expression they represent
- **Avoid full names**: Don't use the whole table name as alias (becomes cluttered)
- **Always use AS**: Always include the `AS` keyword for explicit readability

**Good Example:**

```sql
SELECT
    tn1.id AS id_table,
    DATE(tn2.submission_timestamp) AS day
FROM
    table_name_1 AS tn1
JOIN
    table_name_2 AS tn2
    ON tn1.id = tn2.id
```

**Bad Example:**

```sql
SELECT
    table_name_1.id id_table,
    DATE(table_name_2.submission_timestamp) day
FROM
    table_name_1
JOIN
    table_name_2
    ON table_name_1.id = table_name_2.id
```

---

## 3. Formatting Rules

- **UPPERCASE** all reserved keywords and functions (`SELECT`, `FROM`, `WHERE`, `JOIN`, `AS`, `COUNT()`, `CASE WHEN`, `AND`, `OR`, `ON`, `IN`, `IS`, `NOT`, `NULL`)
- **Spaces** before/after operators (`=`, `>`, `<`) and after commas
- **New lines** before `AND`/`OR`/`ON`, after root keywords (`SELECT`/`FROM`/`WHERE`/`JOIN`), and after semicolons. Do not use blank lines (DBeaver incompatible).
- **Indentation**: Keywords left-aligned; columns indented by TAB or 2/4 spaces
- **Commas** at end-of-line (right comma)
- **Each column** on its own row in `SELECT`
- **DISTINCT** on the same row as `SELECT`

```sql
SELECT DISTINCT
    COUNT(*) AS total_count,
    DATE(created_at) AS dt_created
FROM
    users
WHERE
    status = 'active'
    AND created_at > '2024-01-01'
```

---

## 4. CTEs (Common Table Expressions)

### Rules

- **Use CTEs instead of subqueries**: CTEs make SQL more readable and performant
- **Placement**: CTEs should be placed at the top of the query
- **Naming**: CTE names should be concise but clear
- **Avoid generic names**: Do not use generic names like "a", "test", etc.

### Format

```sql
WITH context_1 AS (
    SELECT
        column_1,
        column_2
    FROM
        table_1
),
context_2 AS (
    SELECT
        column_3,
        column_4
    FROM
        table_2
)
SELECT
    c1.column_1,
    c2.column_3
FROM
    context_1 AS c1
JOIN
    context_2 AS c2
    ON c1.column_1 = c2.column_3
```

---

## 5. Joins

### Rules

- **Root keys**: Join keywords should have their own line
- **Table names**: Use new lines for table names
- **ON/AND**: Place `ON` and `AND` on new lines with additional indentation
- **Indentation**: Use TAB or 2/4 spaces when moving to new row

**Good Example:**

```sql
SELECT
    tn_1.column_1,
    tn_2.column_2,
    tn_3.column_3
FROM
    table_name_1 AS tn_1
LEFT JOIN
    table_name_2 AS tn_2
        ON tn_1.column_1 = tn_2.column_1
        AND tn_1.column_2 = tn_2.column_2
LEFT JOIN
    table_name_3 AS tn_3
        ON tn_1.column_3 = tn_3.column_3
```

**Bad Example:**

```sql
SELECT
    tn_1.column_1,
    tn_1.column_2,
    tn_2.column_3
FROM table_name_1 AS tn_1
LEFT JOIN 
    table_name_2 AS tn_2 
    ON tn_1.column_1 = tn_2.column_1
    AND tn_1.column_2 = tn_2.column_2
LEFT JOIN table_name_3 AS tn_3 ON tn_1.column_3 = tn_3.column_3
```

---

## 6. Case-When Statements

### Rules

- **Each WHEN**: Should be on a new indented row
- **END AS**: Should be on a new row, indented the same way as `CASE`
- **Nested CASE**: When inside another function, break it as aforementioned but at the new indentation level

**Good Example:**

```sql
SELECT
    CASE column_1
        WHEN 'a'
         OR 'aa' THEN 'first'
        WHEN 'b' THEN 'second'
        ELSE 'third'
    END AS new_column
FROM
    table_1
WHERE
    column_2 IS NOT NULL
```

**Good Example (Nested in Function):**

```sql
SELECT
    COUNT(
        CASE column_1
            WHEN 'b' THEN 1
        END
    ) > 0 AS is_bee
FROM
    table_1
WHERE
    column_2 IS NOT NULL
```

---

## 7. Long Expressions — Line Breaks

Prioritise breaking long expressions into multiple lines so that statements stay readable and fit common line-length limits.

### Rules

- **When an expression is too long:** Split it into two or more lines rather than keeping a single long line.
- **CASE WHEN:** Put the condition on one line; put `THEN`/`ELSE` and the result on the next (or on separate lines if still long).
- **Nested functions:** Break so each function or logical part is on its own line — inner call first, then outer, with consistent indentation.

**Good Example (CASE WHEN):**

```sql
SELECT
    CASE status
        WHEN 'PENDING' THEN 'Awaiting approval'
        WHEN 'APPROVED' THEN 'Active'
        ELSE 'Other'
    END AS status_label
FROM
    requests
```

**Good Example (Nested functions):**

```sql
SELECT
    ELEMENT_AT(
        FILTER(items, x -> x.is_valid = true),
        1
    ).user.data.id AS first_valid_user_id
FROM
    events
```

---

## 8. Commenting

### Rules

- **Placement**: Comments should go near the top of your query, or at least near the closest `SELECT`
- **Single line**: Use `--` syntax (necessarily at the beginning of the line)
- **Multi-line**: Use `/* */` syntax, a line above
- **Indentation**: Keep comments indented - avoid too large lines mixed with small ones
- **Length**: If the comment is too long, it probably shouldn't be there, but in the model documentation
- **No blank lines**: Do not use blank lines between comment and query

**Good Example:**

```sql
-- Single line comment goes here
SELECT
    column_1,
    column_2
FROM
    table_name
WHERE
    column_1 IS NOT NULL
```

**Good Example (Multi-line):**

```sql
/* Multi-line comment goes here. Always keep in
mind that it is not cool to have long lines. You should
try to keep them with a similar size, alright? */
SELECT
    column_1,
    column_2
FROM
    table_name
WHERE
    column_1 IS NOT NULL
```

---

## SQL Style Checklist (Sections 1–8)

- [ ] Columns are in English, lowercase, snake_case
- [ ] All reserved words and functions are UPPERCASE
- [ ] Proper spacing around operators and commas
- [ ] New lines before AND/OR/ON, after SELECT/FROM/WHERE/JOIN
- [ ] Proper indentation (TAB or 2/4 spaces)
- [ ] Commas at end-of-line (right comma)
- [ ] Each column on its own row in SELECT
- [ ] CTEs used instead of subqueries where appropriate
- [ ] Descriptive aliases with AS keyword
- [ ] Joins formatted with proper line breaks
- [ ] CASE-WHEN properly indented
- [ ] Long expressions split across multiple lines
- [ ] Comments formatted correctly (no blank lines between comment and query)
