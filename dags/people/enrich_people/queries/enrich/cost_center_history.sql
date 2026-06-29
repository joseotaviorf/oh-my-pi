WITH
-- Step 1: compute gapless periods from hr_organization + all_organization_units + codex_log only.
-- assignment_responsibility (HRBP) is intentionally excluded from GREATEST/LEAST so that
-- late HRBP assignments or gaps between consecutive HRBPs do not punch holes in coverage.
core_periods_raw AS (
    SELECT
        a.cost_center_code,
        o.id_organization,
        o.name AS cost_center_name,
        c.business,
        c.product,
        c.brand,
        c.vertical,
        c.structure,
        c.team,
        c.chapter,
        c.line,
        c.owner_l1_name,
        c.owner_l2_name,
        c.owner_l3_name,
        c.headcount_type,
        o.status = 'A' AS is_active,
        COALESCE(
            a.dt_effective_started,
            o.dt_effective_started
        ) AS dt_dff_effective_started,
        GREATEST(
            o.dt_effective_started,
            COALESCE(a.dt_effective_started, o.dt_effective_started),
            COALESCE(c.dt_valid_from, o.dt_effective_started)
        ) AS dt_valid_from,
        LEAST(
            COALESCE(o.dt_effective_ended, DATE '9999-12-31'),
            COALESCE(a.dt_effective_ended, DATE '9999-12-31'),
            COALESCE(c.dt_valid_to, DATE '9999-12-31')
        ) AS dt_valid_to,
        o.ts_created,
        ROW_NUMBER() OVER (
            PARTITION BY
                o.id_organization,
                o.dt_effective_started,
                COALESCE(a.dt_effective_started, o.dt_effective_started),
                COALESCE(c.dt_valid_from, o.dt_effective_started)
            ORDER BY
                c.dt_valid_from DESC NULLS LAST,
                c.dt_valid_to DESC NULLS LAST
        ) AS rn
    FROM
        datalake_pin_core_clean.hr_organization AS o
    LEFT JOIN
        datalake_pin_core_clean.all_organization_units AS a
            ON a.id_organization = o.id_organization
            AND a.cost_center_code IS NOT NULL
            AND o.dt_effective_started <= a.dt_effective_ended
            AND (
                a.dt_effective_ended = DATE('9999-12-31')
                OR a.dt_effective_ended >= o.dt_effective_started
            )
    LEFT JOIN
        datalake_people.codex_log AS c
            ON a.cost_center_code = c.cost_center_code
            AND c.dt_valid_from <= LEAST(
                COALESCE(o.dt_effective_ended, DATE '9999-12-31'),
                COALESCE(a.dt_effective_ended, DATE '9999-12-31')
            )
            AND (
                c.dt_valid_to IS NULL
                OR c.dt_valid_to >= GREATEST(
                    o.dt_effective_started,
                    COALESCE(a.dt_effective_started, o.dt_effective_started)
                )
            )
    WHERE
        o.classification_code = 'DEPARTMENT'
        AND a.cost_center_code IS NOT NULL
        AND GREATEST(
            o.dt_effective_started,
            COALESCE(a.dt_effective_started, o.dt_effective_started),
            COALESCE(c.dt_valid_from, o.dt_effective_started)
        ) <= LEAST(
            COALESCE(o.dt_effective_ended, DATE '9999-12-31'),
            COALESCE(a.dt_effective_ended, DATE '9999-12-31'),
            COALESCE(c.dt_valid_to, DATE '9999-12-31')
        )
),
core_periods AS (
    SELECT
        cost_center_code,
        id_organization,
        cost_center_name,
        business,
        product,
        brand,
        vertical,
        structure,
        team,
        chapter,
        line,
        owner_l1_name,
        owner_l2_name,
        owner_l3_name,
        headcount_type,
        is_active,
        dt_dff_effective_started,
        dt_valid_from,
        dt_valid_to,
        ts_created
    FROM
        core_periods_raw
    WHERE
        rn = 1
),
-- Step 2: enforce single-active-HRBP-per-org invariant. When a new HRBP starts without the
-- previous one being explicitly closed, auto-close the previous at new_start - 1. This prevents
-- the LEFT JOIN in `base` from returning two rows for the same boundary date, which would make
-- the LEAD computation non-deterministic and produce inverted periods (dt_valid_to < dt_valid_from).
normalized_hrbp AS (
    SELECT
        id_organization,
        id_assignment,
        id_person,
        id_template,
        dt_started,
        LEAST(
            dt_ended,
            LEAD(dt_started) OVER (
                PARTITION BY id_organization
                ORDER BY dt_started
            ) - 1
        ) AS dt_ended
    FROM
        datalake_pin_core_clean.assignment_responsibility
    WHERE
        id_template IS NOT NULL
),
-- Step 3: collect every date boundary that HRBP transitions introduce within each core period.
-- This produces the split points used to generate HRBP-aware sub-periods in the next CTE.
all_boundaries AS (
    -- Core period start is always a boundary
    SELECT
        cp.id_organization,
        cp.dt_valid_from AS boundary_date,
        cp.dt_valid_from AS core_dt_valid_from,
        COALESCE(cp.dt_valid_to, DATE '9999-12-31') AS core_dt_valid_to
    FROM
        core_periods AS cp
    UNION
    -- HRBP start date, clamped to the core period start (in case HRBP predates the core period)
    SELECT
        cp.id_organization,
        GREATEST(r.dt_started, cp.dt_valid_from) AS boundary_date,
        cp.dt_valid_from AS core_dt_valid_from,
        COALESCE(cp.dt_valid_to, DATE '9999-12-31') AS core_dt_valid_to
    FROM
        core_periods AS cp
    INNER JOIN
        normalized_hrbp AS r
            ON r.id_organization = cp.id_organization
            AND r.dt_started <= COALESCE(cp.dt_valid_to, DATE '9999-12-31')
            AND COALESCE(r.dt_ended, DATE '9999-12-31') >= cp.dt_valid_from
    UNION
    -- Day after HRBP ends — opens the sub-period with no HRBP (or the next HRBP)
    SELECT
        cp.id_organization,
        r.dt_ended + 1 AS boundary_date,
        cp.dt_valid_from AS core_dt_valid_from,
        COALESCE(cp.dt_valid_to, DATE '9999-12-31') AS core_dt_valid_to
    FROM
        core_periods AS cp
    INNER JOIN
        normalized_hrbp AS r
            ON r.id_organization = cp.id_organization
            AND r.dt_ended IS NOT NULL
            AND r.dt_ended + 1 <= COALESCE(cp.dt_valid_to, DATE '9999-12-31')
            AND r.dt_ended >= cp.dt_valid_from
),
-- Step 4: generate sub-periods between consecutive boundaries within each core period,
-- then join HRBP as an attribute (nullable) for each sub-period.
base_raw AS (
    SELECT
        cp.cost_center_code,
        cp.id_organization,
        r.id_assignment AS sk_business_partner_assignment,
        r.id_person AS sk_business_partner,
        cp.cost_center_name,
        cp.business,
        cp.product,
        cp.brand,
        cp.vertical,
        cp.structure,
        cp.team,
        cp.chapter,
        cp.line,
        cp.owner_l1_name,
        cp.owner_l2_name,
        cp.owner_l3_name,
        cp.headcount_type,
        cp.is_active,
        cp.dt_dff_effective_started,
        ab.boundary_date AS dt_valid_from,
        COALESCE(
            LEAD(ab.boundary_date) OVER (
                PARTITION BY ab.id_organization, ab.core_dt_valid_from
                ORDER BY ab.boundary_date
            ) - 1,
            ab.core_dt_valid_to
        ) AS dt_valid_to,
        cp.ts_created,
        ROW_NUMBER() OVER (
            PARTITION BY ab.id_organization, ab.core_dt_valid_from, ab.boundary_date
            ORDER BY r.dt_started DESC NULLS LAST, r.id_assignment
        ) AS rn
    FROM
        all_boundaries AS ab
    INNER JOIN
        core_periods AS cp
            ON cp.id_organization = ab.id_organization
            AND cp.dt_valid_from = ab.core_dt_valid_from
    LEFT JOIN
        normalized_hrbp AS r
            ON r.id_organization = ab.id_organization
            AND r.dt_started <= ab.boundary_date
            AND COALESCE(r.dt_ended, DATE '9999-12-31') >= ab.boundary_date
),
base AS (
    SELECT
        cost_center_code,
        id_organization,
        sk_business_partner_assignment,
        sk_business_partner,
        cost_center_name,
        business,
        product,
        brand,
        vertical,
        structure,
        team,
        chapter,
        line,
        owner_l1_name,
        owner_l2_name,
        owner_l3_name,
        headcount_type,
        is_active,
        dt_dff_effective_started,
        dt_valid_from,
        dt_valid_to,
        ts_created
    FROM
        base_raw
    WHERE
        rn = 1
),
base_with_primary AS (
    SELECT
        base.cost_center_code,
        base.id_organization,
        base.sk_business_partner_assignment,
        base.sk_business_partner,
        base.cost_center_name,
        base.business,
        base.product,
        base.brand,
        base.vertical,
        base.structure,
        base.team,
        base.chapter,
        base.line,
        base.owner_l1_name,
        base.owner_l2_name,
        base.owner_l3_name,
        base.headcount_type,
        base.is_active,
        base.dt_valid_from,
        base.dt_valid_to,
        base.ts_created,
        ROW_NUMBER() OVER (
            PARTITION BY
                TRIM(base.cost_center_code),
                base.dt_valid_from
            ORDER BY
                base.is_active DESC,
                base.dt_dff_effective_started DESC NULLS LAST,
                base.id_organization DESC,
                base.sk_business_partner_assignment DESC NULLS LAST,
                base.sk_business_partner DESC NULLS LAST
        ) = 1 AS is_primary_organization
    FROM
        base
),
with_prev_dt_valid_to AS (
    SELECT
        *,
        LAG(dt_valid_to) OVER (
            PARTITION BY
                id_organization,
                cost_center_code,
                sk_business_partner_assignment,
                sk_business_partner,
                cost_center_name,
                business,
                product,
                brand,
                vertical,
                structure,
                team,
                chapter,
                line,
                owner_l1_name,
                owner_l2_name,
                owner_l3_name,
                headcount_type,
                is_active
            ORDER BY
                dt_valid_from
        ) AS prev_dt_valid_to
    FROM
        base_with_primary
),
contiguous_validity_periods AS (
    SELECT
        *,
        SUM(
            CASE
                WHEN prev_dt_valid_to IS NULL
                    OR dt_valid_from > prev_dt_valid_to + 1
                THEN 1
                ELSE 0
            END
        ) OVER (
            PARTITION BY
                id_organization,
                cost_center_code,
                sk_business_partner_assignment,
                sk_business_partner,
                cost_center_name,
                business,
                product,
                brand,
                vertical,
                structure,
                team,
                chapter,
                line,
                owner_l1_name,
                owner_l2_name,
                owner_l3_name,
                headcount_type,
                is_active
            ORDER BY
                dt_valid_from
        ) AS validity_period_group_id
    FROM
        with_prev_dt_valid_to
),
grouped_versions AS (
    SELECT
        MD5(
            CONCAT(
                CAST(id_organization AS STRING),
                '|',
                CAST(MIN(dt_valid_from) AS STRING)
            )
        ) AS sk_cost_center_version,
        id_organization,
        cost_center_code,
        sk_business_partner_assignment,
        sk_business_partner,
        cost_center_name,
        business,
        product,
        brand,
        vertical,
        structure,
        team,
        chapter,
        line,
        owner_l1_name,
        owner_l2_name,
        owner_l3_name,
        headcount_type,
        is_active,
        BOOL_OR(is_primary_organization) AS is_primary_organization,
        MIN(dt_valid_from) AS dt_valid_from,
        COALESCE(
            MAX(dt_valid_to),
            DATE '9999-12-31'
        ) AS dt_valid_to,
        MIN(ts_created) AS ts_created,
        NOW() AS ts_load
    FROM
        contiguous_validity_periods
    GROUP BY
        id_organization,
        cost_center_code,
        sk_business_partner_assignment,
        sk_business_partner,
        cost_center_name,
        business,
        product,
        brand,
        vertical,
        structure,
        team,
        chapter,
        line,
        owner_l1_name,
        owner_l2_name,
        owner_l3_name,
        headcount_type,
        is_active,
        validity_period_group_id
),
with_future_flag AS (
    SELECT
        *,
        dt_valid_from > DATE('{load_start_date}') AS is_future_version
    FROM
        grouped_versions
)
SELECT
    sk_cost_center_version,
    id_organization,
    cost_center_code,
    sk_business_partner_assignment,
    sk_business_partner,
    cost_center_name,
    business,
    product,
    brand,
    vertical,
    structure,
    team,
    chapter,
    line,
    owner_l1_name,
    owner_l2_name,
    owner_l3_name,
    headcount_type,
    is_active,
    is_primary_organization,
    is_future_version,
    ROW_NUMBER() OVER (
        PARTITION BY
            id_organization,
            cost_center_code
        ORDER BY
            is_active DESC,
            is_future_version ASC,
            dt_valid_from DESC,
            dt_valid_to DESC,
            sk_cost_center_version DESC
    ) = 1 AS is_current,
    dt_valid_from,
    dt_valid_to,
    ts_created,
    ts_load
FROM
    with_future_flag
