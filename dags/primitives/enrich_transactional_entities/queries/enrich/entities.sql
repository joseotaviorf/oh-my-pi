WITH visit AS (
    WITH visit_base AS (
        SELECT
            id_visit AS id_entity,
            id_house,
            CAST(NULL AS BIGINT) AS id_contract,
            id_owner,
            id_visitor,
            id_agent,
            'VISIT' AS entity,
            business_context,
            TO_JSON(
                STRUCT(
                    computed_status AS computed_status
                )
            ) AS properties,
            CASE
                WHEN computed_status IN ('CANCELED', 'DONE', 'REQUEST_CANCELED', 'UNSUCCESSFUL', 'STALLED') THEN FALSE
                WHEN computed_status IN ('CONFIRMED', 'REQUESTED') THEN TRUE
                ELSE NULL
            END AS is_active,
            ts_created,
            ts_updated
        FROM
            core_visit.visit
    )
    SELECT
        id_entity,
        id_house,
        id_contract,
        id_owner AS id_user,
        entity,
        'OWNER' AS persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        visit_base
    UNION ALL
    SELECT
        id_entity,
        id_house,
        id_contract,
        id_visitor AS id_user,
        entity,
        CASE
            WHEN business_context = 'RENT' THEN 'TENANT_PROSPECT'
            WHEN business_context = 'SALE' THEN 'BUYER_PROSPECT'
        END AS persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        visit_base
    UNION ALL
    SELECT
        id_entity,
        id_house,
        id_contract,
        id_agent AS id_user,
        entity,
        'AGENT_BROKER' AS persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        visit_base
    WHERE
        id_agent IS NOT NULL
),
offer AS (
    WITH offer_base AS (
        SELECT
            id_offer AS id_entity,
            id_house,
            CAST(NULL AS BIGINT) AS id_contract,
            id_tenant,
            id_owner,
            'FR_OFFER' AS entity,
            'RENT' AS business_context,
            TO_JSON(
                STRUCT(
                    status AS status
                )
            ) AS properties,
            CASE
                WHEN status = 'PROPOSED' THEN TRUE
                WHEN status IN ('ACCEPTED', 'DISMISSED', 'REJECTED') THEN FALSE
                ELSE NULL
            END AS is_active,
            ts_created,
            ts_updated
        FROM
            core_offer.offer
    )
    SELECT
        id_entity,
        id_house,
        id_contract,
        id_tenant AS id_user,
        entity,
        'TENANT_PROSPECT' AS persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        offer_base
    UNION ALL
    SELECT
        id_entity,
        id_house,
        id_contract,
        id_owner AS id_user,
        entity,
        'OWNER' AS persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        offer_base
),
contract AS (
    WITH contract_base AS (
        SELECT
            id_contract AS id_entity,
            id_house,
            id_contract,
            id_owner,
            id_tenant,
            'FR_CONTRACT' AS entity,
            'RENT' AS business_context,
            TO_JSON(
                STRUCT(
                    status AS status
                )
            ) AS properties,
            CASE
                WHEN status IN ('Cancelado', 'Finalizado') THEN FALSE
                WHEN status IN ('Ativo', 'Minuta', 'PreAssinaturas') THEN TRUE
                ELSE NULL
            END AS is_active,
            ts_signed,
            ts_created,
            ts_updated
        FROM
            core_contract.contract
    )
    SELECT
        id_entity,
        id_house,
        id_contract,
        id_owner AS id_user,
        entity,
        'OWNER' AS persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        contract_base
    UNION ALL
    SELECT
        id_entity,
        id_house,
        id_contract,
        id_tenant AS id_user,
        entity,
        CASE
            WHEN ts_signed IS NOT NULL THEN 'TENANT'
            ELSE 'TENANT_PROSPECT'
        END AS persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        contract_base
),
termination AS (
  WITH termination_base AS (
    SELECT
      id AS id_entity,
      id_contract,
      'FR_TERMINATION' AS entity,
      'RENT' AS business_context,
      TO_JSON(
        STRUCT(
          status AS status
        )
      ) AS properties,
      CASE
          WHEN status IN ('DONE', 'CANCELED') THEN FALSE
          WHEN status IN (
            'REQUESTED',
            'INSPECTION_UNDER_REVIEW',
            'INSPECTION_SCHEDULED',
            'INSPECTION_OPTED_OUT',
            'INSPECTION_EXECUTED',
            'INSPECTION_CANCELED'
          ) THEN TRUE
          ELSE NULL
      END AS is_active,
      ts_created,
      ts_updated
    FROM datalake_terminator_clean.termination
  )
  SELECT
        tb.id_entity,
        c.id_house,
        c.id_owner AS id_user,
        c.id_contract AS id_contract,
        tb.entity,
        'OWNER' AS persona,
        tb.business_context,
        tb.properties,
        tb.is_active,
        tb.ts_created,
        tb.ts_updated
  FROM
        termination_base tb
  INNER JOIN
        core_contract.contract c
        ON tb.id_contract = c.id_contract
  UNION ALL
  SELECT
    tb.id_entity,
    c.id_house,
    c.id_tenant AS id_user,
    c.id_contract AS id_contract,
    tb.entity,
    'TENANT' AS persona,
    tb.business_context,
    tb.properties,
    tb.is_active,
    tb.ts_created,
    tb.ts_updated
  FROM
        termination_base tb
  INNER JOIN
        core_contract.contract c
        ON tb.id_contract = c.id_contract
),
listing AS (
    WITH last_contract AS (
        SELECT
            id_house,
            id_contract
        FROM
            core_contract.contract
        QUALIFY
            ROW_NUMBER() OVER(PARTITION BY id_house ORDER BY ts_created DESC) = 1
    ),
    listing_base AS (
        SELECT
            lbc.id AS id_entity,
            lbc.id_house,
            IF(lbc.business_context = 'RENT', c.id_contract, NULL) AS id_contract,
            h.id_user AS id_owner,
            'LISTING' AS entity,
            lbc.business_context,
            TO_JSON(
                STRUCT(
                    lbc.status AS status,
                    lbc.status_reason AS status_reason
                )
            ) AS properties,
            CASE
                WHEN lbc.status IN ('PUBLISHED', 'EDITING')
                    OR (lbc.status = 'SUSPENDED'
                        AND lbc.status_reason NOT IN ('OWNER_GAVE_UP_RENTING', 'OwnerConsequencesManagement', 'OwnerReforming', 'OwnerTemporarilySuspended', 'OwnerTraveling')) THEN TRUE
                WHEN lbc.status IN ('OPTED_OUT', 'UNPUBLISHED')
                    OR (lbc.status = 'SUSPENDED'
                        AND lbc.status_reason IN ('OWNER_GAVE_UP_RENTING', 'OwnerConsequencesManagement', 'OwnerReforming', 'OwnerTemporarilySuspended', 'OwnerTraveling')) THEN FALSE
                ELSE NULL
            END AS is_active,
            lbc.ts_created,
            lbc.ts_updated
        FROM
            datalake_ebdb_clean.listing_business_context AS lbc
        LEFT JOIN
            datalake_ebdb_clean.house AS h
                ON h.id = lbc.id_house
        LEFT JOIN
            last_contract AS c
                ON c.id_house = lbc.id_house
    )
    SELECT
        lb.id_entity,
        lb.id_house,
        lb.id_contract,
        lb.id_owner AS id_user,
        lb.entity,
        'OWNER' AS persona,
        lb.business_context,
        lb.properties,
        lb.is_active,
        lb.ts_created,
        lb.ts_updated
    FROM
        listing_base AS lb
),
inspection AS (
  WITH inspection_base AS (
    SELECT
      id as id_entity,
      id_contract,
      id_user_inspector,
      'FR_INSPECTION' AS entity,
      'RENT' AS business_context,
       TO_JSON(
        STRUCT(
          status AS status
        )
      ) AS properties,
      CASE
        WHEN status IN ('Finalizada', 'Cancelada', 'ContratoCancelado') THEN FALSE
        WHEN status IN ('Agendada', 'Comentada', 'EmAcordo', 'EmRevisao', 'Nova', 'Revisada') THEN TRUE
        ELSE NULL
      END AS is_active,
      ts_created,
      ts_updated
      FROM datalake_ebdb_test_clean.inspection
  )
  SELECT
          ib.id_entity,
          c.id_house,
          c.id_owner AS id_user,
          c.id_contract AS id_contract,
          ib.entity,
          'OWNER' AS persona,
          ib.business_context,
          ib.properties,
          ib.is_active,
          ib.ts_created,
          ib.ts_updated
    FROM
          inspection_base ib
    INNER JOIN
          core_contract.contract c
          ON ib.id_contract = c.id_contract
    UNION ALL
    SELECT
      ib.id_entity,
      c.id_house,
      c.id_tenant AS id_user,
      c.id_contract AS id_contract,
      ib.entity,
      'TENANT' AS persona,
      ib.business_context,
      ib.properties,
      ib.is_active,
      ib.ts_created,
      ib.ts_updated
    FROM
          inspection_base ib
    INNER JOIN
          core_contract.contract c
          ON ib.id_contract = c.id_contract
    UNION ALL
    SELECT
      ib.id_entity,
      c.id_house,
      ib.id_user_inspector AS id_user,
      c.id_contract AS id_contract,
      ib.entity,
      'AGENT_INSPECTOR' AS persona,
      ib.business_context,
      ib.properties,
      ib.is_active,
      ib.ts_created,
      ib.ts_updated
    FROM
          inspection_base ib
    INNER JOIN
          core_contract.contract c
          ON ib.id_contract = c.id_contract
),
base AS (
    SELECT
        {sk_entity} AS sk_entity,
        id_entity,
        id_house,
        id_contract,
        id_user,
        entity,
        persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        visit
    UNION ALL
    SELECT
        {sk_entity} AS sk_entity,
        id_entity,
        id_house,
        id_contract,
        id_user,
        entity,
        persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        offer
    UNION ALL
    SELECT
        {sk_entity} AS sk_entity,
        id_entity,
        id_house,
        id_contract,
        id_user,
        entity,
        persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        contract
    UNION ALL
    SELECT
        {sk_entity} AS sk_entity,
        id_entity,
        id_house,
        id_contract,
        id_user,
        entity,
        persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        termination
    UNION ALL
    SELECT
        {sk_entity} AS sk_entity,
        id_entity,
        id_house,
        id_contract,
        id_user,
        entity,
        persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        listing
    UNION ALL
    SELECT
        {sk_entity} AS sk_entity,
        id_entity,
        id_house,
        id_contract,
        id_user,
        entity,
        persona,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        inspection
)
SELECT
    b.sk_entity,
    b.id_entity,
    b.id_house,
    b.id_contract,
    b.id_user,
    u.uuid_person,
    b.entity,
    b.persona,
    b.business_context,
    b.properties,
    {house_address} AS house_address,
    b.is_active,
    CASE
        WHEN b.is_active = FALSE THEN b.ts_updated
        ELSE NULL
    END AS ts_inactive,
    b.ts_created,
    b.ts_updated
FROM
    base AS b
LEFT JOIN
    datalake_ebdb_clean.house AS h
        ON h.id = b.id_house
LEFT JOIN
    datalake_ebdb_clean.user AS u
        ON u.id = b.id_user
WHERE
    b.id_user IS NOT NULL
    AND b.persona IS NOT NULL
