WITH property_prefered_agent AS (
  SELECT
    hlra.id_house_listing_relation,
    hlra.id_house,
    hlra.id_listing_business_context,
    hlra.id_related,
    u.id AS id_user_agent,
    u.id_agent,
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
)
SELECT
    id_house_listing_relation,
    id_house,
    id_user_agent AS id_user_related_agent,
    id_agent AS id_related_agent,
    id_listing_business_context,
    business_context,
    CASE
      WHEN
        ROW_NUMBER() OVER(PARTITION BY id_house, id_related ORDER BY id_house_listing_relation) = 1
            AND ts_relation_started = DATE('2025-06-03')
            AND ts_business_context_house_first_listing BETWEEN DATE('2025-02-12') AND DATE('2025-06-03')
        THEN ts_business_context_house_first_listing
      WHEN
        ROW_NUMBER() OVER(PARTITION BY id_house, id_related ORDER BY id_house_listing_relation) = 1
            AND ts_relation_started = DATE('2025-06-03')
            AND ts_business_context_house_first_listing < DATE('2025-02-12')
        THEN DATE('2025-02-12')
      ELSE ts_relation_started
    END AS ts_relation_started,
    ts_relation_ended
FROM
    property_prefered_agent
