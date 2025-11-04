WITH property_prefered_agent AS (
  SELECT
    hlra.id_house_listing_relation,
    hlra.id_house,
    hlra.id_listing_business_context,
    hlra.id_related,
    u.id AS id_user_agent,
    u.id_agent,
    XXHASH64(hlra.id_house, hlra.id_listing_business_context, DATE_FORMAT(r.ts_revision, 'yyyy-MM-dd HH:mm:ss')) AS id_simultaneous_house_listing_relation,
    CASE
      WHEN lbc.is_rent_context = TRUE THEN 'RENT'
      WHEN lbc.is_sale_context = TRUE THEN 'SALE'
    END AS business_context,
    hlra.related_as,
    lbc.ts_first_listing AS ts_business_context_house_first_listing,
    r.ts_revision AS ts_relation_started,
    LEAD(r.ts_revision) OVER(PARTITION BY hlra.id_house_listing_relation ORDER BY hlra.rev) AS ts_relation_ended
  FROM
    datalake_ebdb_clean.house_listing_relation_aud AS hlra
  INNER JOIN
    datalake_ebdb_clean.house_listing_relation_aud AS ppa_rc
      ON hlra.id_house_listing_relation = ppa_rc.id_house_listing_relation
        AND ppa_rc.related_as = 'PREFERRED_PROPERTY_AGENT'
        AND ppa_rc.rev_type = 0
  LEFT JOIN
    datalake_ebdb_user.user_revision_entity AS r
      ON hlra.rev = r.id
  LEFT JOIN
    datalake_ebdb_listing.listing_business_context AS lbc
      ON lbc.id = hlra.id_listing_business_context
  LEFT JOIN
    datalake_ebdb_user.user AS u
      ON u.uuid_person = hlra.id_related
  WHERE
    hlra.mod_related_as = true
    AND (
      hlra.rev_type = 0
      OR hlra.rev_type = 2
    )
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY hlra.id_house_listing_relation ORDER BY hlra.rev) = 1
),
duplicates_listing_relation AS (
    SELECT
      id_simultaneous_house_listing_relation,
      COUNT(*) AS total_duplicates
    FROM
      property_prefered_agent
    GROUP BY ALL
    HAVING total_duplicates > 1
),
deduplication_house_listing_relation AS (
    SELECT
      ppa.id_house_listing_relation,
      ppa.id_house,
      ppa.id_agent,
      ppa.id_listing_business_context,
      ppa.ts_relation_started,
      ppa.ts_relation_ended
    FROM
      property_prefered_agent AS ppa
    JOIN
      duplicates_listing_relation AS di
          ON ppa.id_simultaneous_house_listing_relation = di.id_simultaneous_house_listing_relation
    QUALIFY
      LEAD(ppa.ts_relation_started) OVER(
          PARTITION BY ppa.id_simultaneous_house_listing_relation
          ORDER BY ppa.id_house_listing_relation
      ) < IFNULL(ppa.ts_relation_ended, NOW())
),
preferred_property_agent_relations AS (
  SELECT
    ppa.id_house_listing_relation,
    ppa.id_house,
    ppa.id_user_agent AS id_user_related_agent,
    ppa.id_agent AS id_related_agent,
    XXHASH64(ppa.id_house, ppa.id_listing_business_context) AS id_paralel_relations,
    ppa.id_listing_business_context,
    ppa.business_context,
    CASE
      WHEN
        ROW_NUMBER() OVER(PARTITION BY ppa.id_house, ppa.id_related ORDER BY ppa.id_house_listing_relation) = 1
          AND DATE(ppa.ts_relation_started) = DATE('2025-06-03')
          AND ppa.ts_business_context_house_first_listing BETWEEN DATE('2025-02-12') AND DATE('2025-06-03')
        THEN ppa.ts_business_context_house_first_listing
      WHEN
        ROW_NUMBER() OVER(PARTITION BY ppa.id_house, ppa.id_related ORDER BY ppa.id_house_listing_relation) = 1
          AND DATE(ppa.ts_relation_started) = DATE('2025-06-03')
          AND ppa.ts_business_context_house_first_listing < DATE('2025-02-12')
        THEN DATE('2025-02-12')
      ELSE ppa.ts_relation_started
    END AS ts_relation_started,
    ppa.ts_relation_ended
  FROM
    property_prefered_agent AS ppa
  LEFT JOIN
    deduplication_house_listing_relation AS dups
      ON dups.id_house_listing_relation = ppa.id_house_listing_relation
  WHERE
    dups.id_house_listing_relation IS NULL
),
paralel_house_listing_relations_fix AS (
  SELECT
    id_house_listing_relation,
    id_paralel_relations,
    CASE
        WHEN
            LEAD(ts_relation_started) OVER(
                PARTITION BY id_paralel_relations
                ORDER BY id_house_listing_relation
            ) < COALESCE(ts_relation_ended, NOW())
        THEN
            LEAD(ts_relation_started) OVER(
                PARTITION BY id_paralel_relations
                ORDER BY id_house_listing_relation
            ) - INTERVAL '1' SECOND
        ELSE ts_relation_ended
    END AS ts_relation_ended_revised
  FROM
    preferred_property_agent_relations
  QUALIFY
    LEAD(ts_relation_started) OVER(
        PARTITION BY id_paralel_relations
        ORDER BY id_house_listing_relation
    ) < COALESCE(ts_relation_ended, NOW())
)
  SELECT
    ppa.id_house_listing_relation,
    ppa.id_house,
    ppa.id_user_related_agent,
    ppa.id_related_agent,
    ppa.id_listing_business_context,
    ppa.business_context,
    ppa.ts_relation_started,
    COALESCE(paralel.ts_relation_ended_revised, ppa.ts_relation_ended) AS ts_relation_ended
  FROM
    preferred_property_agent_relations AS ppa
  LEFT JOIN
    paralel_house_listing_relations_fix AS paralel
      ON paralel.id_house_listing_relation = ppa.id_house_listing_relation
