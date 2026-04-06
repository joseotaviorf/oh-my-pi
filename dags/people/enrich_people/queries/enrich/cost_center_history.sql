WITH
base AS (
    SELECT
        a.cost_center_code,
        o.id_organization,
        r.id_assignment AS sk_business_partner_assignment,
        r.id_person AS sk_business_partner,
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
            COALESCE(c.dt_valid_from, o.dt_effective_started),
            COALESCE(r.dt_started, o.dt_effective_started)
        ) AS dt_valid_from,
        NULLIF(
            LEAST(
                COALESCE(o.dt_effective_ended, DATE '4712-12-31'),
                COALESCE(a.dt_effective_ended, DATE '4712-12-31'),
                COALESCE(c.dt_valid_to, DATE '4712-12-31'),
                COALESCE(r.dt_ended, DATE '4712-12-31')
            ),
            DATE '4712-12-31'
        ) AS dt_valid_to,
        o.ts_created
    FROM
        datalake_pin_core_clean.hr_organization AS o
    LEFT JOIN
        datalake_pin_core_clean.all_organization_units AS a
        ON a.id_organization = o.id_organization
        AND a.cost_center_code IS NOT NULL
        AND o.dt_effective_started <= a.dt_effective_ended
        AND (
            a.dt_effective_ended IS NULL
            OR a.dt_effective_ended >= o.dt_effective_started
        )
    LEFT JOIN
        datalake_people.codex_log AS c
        ON a.cost_center_code = c.cost_center_code
        AND c.dt_valid_from <= LEAST(
            COALESCE(o.dt_effective_ended, DATE '4712-12-31'),
            COALESCE(a.dt_effective_ended, DATE '4712-12-31')
        )
        AND (
            c.dt_valid_to IS NULL
            OR c.dt_valid_to >= GREATEST(
                o.dt_effective_started,
                COALESCE(a.dt_effective_started, o.dt_effective_started)
            )
        )
    LEFT JOIN
        datalake_pin_core_clean.assignment_responsibility AS r
        ON r.id_organization = o.id_organization
        AND r.id_template IS NOT NULL
        AND r.dt_started <= LEAST(
            COALESCE(o.dt_effective_ended, DATE '4712-12-31'),
            COALESCE(a.dt_effective_ended, DATE '4712-12-31'),
            COALESCE(c.dt_valid_to, DATE '4712-12-31')
        )
        AND (
            r.dt_ended IS NULL
            OR r.dt_ended >= GREATEST(
                o.dt_effective_started,
                COALESCE(a.dt_effective_started, o.dt_effective_started),
                COALESCE(c.dt_valid_from, o.dt_effective_started)
            )
        )
    WHERE
        o.classification_code = 'DEPARTMENT'
        AND a.cost_center_code IS NOT NULL
        AND GREATEST(
            o.dt_effective_started,
            COALESCE(a.dt_effective_started, o.dt_effective_started),
            COALESCE(c.dt_valid_from, o.dt_effective_started),
            COALESCE(r.dt_started, o.dt_effective_started)
        ) <= LEAST(
            COALESCE(o.dt_effective_ended, DATE '4712-12-31'),
            COALESCE(a.dt_effective_ended, DATE '4712-12-31'),
            COALESCE(c.dt_valid_to, DATE '4712-12-31'),
            COALESCE(r.dt_ended, DATE '4712-12-31')
        )
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY
                o.id_organization,
                o.dt_effective_started,
                COALESCE(
                    a.dt_effective_started,
                    o.dt_effective_started
                ),
                COALESCE(
                    c.dt_valid_from,
                    o.dt_effective_started
                )
            ORDER BY
                r.dt_started DESC NULLS LAST,
                r.id_assignment
        ) = 1
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
)
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
    BOOL_OR(dt_valid_to IS NULL) AS is_current,
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
