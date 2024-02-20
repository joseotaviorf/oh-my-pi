WITH cte_union_dimensions AS (
  (
    WITH cte_contract_cancellation_reason AS (
      SELECT
        cancellation_reason AS desc_funnel_step_drop_reason
      FROM
        datalake_ebdb_contract.contract
      WHERE
        cancellation_reason IS NOT NULL
    )
    SELECT
      'Contract Cancellation Reason' AS desc_drop_origin,
      ROW_NUMBER() OVER(
        ORDER BY
          desc_funnel_step_drop_reason ASC
      ) AS id_lvl_1,
      desc_funnel_step_drop_reason
    FROM
      cte_contract_cancellation_reason
    GROUP BY
      desc_funnel_step_drop_reason
  )
  UNION ALL
    (
      WITH cte_offer_rejection_reason AS (
        SELECT
          rejection_reason AS desc_funnel_step_drop_reason
        FROM
          datalake_offer.offer
        WHERE
          rejection_reason IS NOT NULL
      )
      SELECT
        'Offer Rejection Reason' AS desc_drop_origin,
        ROW_NUMBER() OVER(
          ORDER BY
            desc_funnel_step_drop_reason ASC
        ) AS id_lvl_1,
        desc_funnel_step_drop_reason
      FROM
        cte_offer_rejection_reason
      GROUP BY
        desc_funnel_step_drop_reason
    )
  UNION ALL
    (
      WITH cte_proposal_rejection_reason AS (
        SELECT
          rejection_reason AS desc_funnel_step_drop_reason
        FROM
          datalake_proposal.proposal
        WHERE
          rejection_reason IS NOT NULL
      )
      SELECT
        'Proposal Rejection Reason' AS desc_drop_origin,
        ROW_NUMBER() OVER(
          ORDER BY
            desc_funnel_step_drop_reason ASC
        ) AS id_lvl_1,
        desc_funnel_step_drop_reason
      FROM
        cte_proposal_rejection_reason
      GROUP BY
        desc_funnel_step_drop_reason
    )
  UNION ALL
    (
      WITH cte_booking_cancellation_reason AS (
        SELECT
          cancellation_reason AS desc_funnel_step_drop_reason
        FROM
          datalake_booking.booking
        WHERE
          cancellation_reason IS NOT NULL
      )
      SELECT
        'Booking Cancellation Reason' AS desc_drop_origin,
        ROW_NUMBER() OVER(
          ORDER BY
            desc_funnel_step_drop_reason ASC
        ) AS id_lvl_1,
        desc_funnel_step_drop_reason
      FROM
        cte_booking_cancellation_reason
      GROUP BY
        desc_funnel_step_drop_reason
    )
),
cte_id_master_type AS (
  SELECT
    ROW_NUMBER() OVER(
      ORDER BY
        c.desc_drop_origin ASC
    ) AS id_master_type,
    c.desc_drop_origin
  FROM
    cte_union_dimensions AS c
  GROUP BY
    2
),
get_categories AS (
  SELECT
    ROW_NUMBER() OVER(
      ORDER BY
        cmt.id_master_type,
        c.id_lvl_1 ASC
    ) AS id,
    cmt.id_master_type AS id_drop_origin,
    c.id_lvl_1 AS id_original_drop_reason,
    c.desc_drop_origin,
    CASE
      WHEN LOWER(c.desc_funnel_step_drop_reason) LIKE '%agent%' THEN 'AGENT'
      WHEN LOWER(c.desc_funnel_step_drop_reason) LIKE '%photographer%' THEN 'AGENT'
      WHEN LOWER(c.desc_funnel_step_drop_reason) LIKE '%inspector%' THEN 'AGENT'
      WHEN LOWER(c.desc_funnel_step_drop_reason) LIKE '%owner%' THEN 'OWNER'
      WHEN LOWER(c.desc_funnel_step_drop_reason) LIKE '%tenant%' THEN 'TENANT'
      WHEN LOWER(c.desc_funnel_step_drop_reason) LIKE '%client%' THEN 'TENANT'
      WHEN LOWER(c.desc_funnel_step_drop_reason) LIKE '%house%' THEN 'LISTING'
      WHEN LOWER(c.desc_funnel_step_drop_reason) LIKE '%property%' THEN 'LISTING'
      ELSE '5A'
    END AS desc_persona,
    CASE
      WHEN LOWER(c.desc_funnel_step_drop_reason) LIKE '%stalled%' THEN 'STALLED'
      WHEN LOWER(c.desc_funnel_step_drop_reason) LIKE '%canceled%' THEN 'CANCELLATION'
      WHEN LOWER(c.desc_funnel_step_drop_reason) LIKE '%cancelled%' THEN 'CANCELLATION'
      WHEN LOWER(c.desc_funnel_step_drop_reason) LIKE '%gaveup%' THEN 'WITHDRAWAL'
      WHEN LOWER(c.desc_funnel_step_drop_reason) LIKE '%gave_up%' THEN 'WITHDRAWAL'
      WHEN c.desc_funnel_step_drop_reason IN ('TenantNewOffer', 'TenantRented5A') THEN 'WITHDRAWAL'
      WHEN LOWER(c.desc_funnel_step_drop_reason) LIKE '%rejected%' THEN 'REJECTED'
      WHEN LOWER(c.desc_funnel_step_drop_reason) LIKE '%agree%' THEN 'DISAGREEMENT'
      WHEN LOWER(c.desc_funnel_step_drop_reason) LIKE '%delay%' THEN 'DELAYS'
      WHEN LOWER(c.desc_funnel_step_drop_reason) LIKE '%nocontact%' THEN 'NO CONTACT'
      WHEN c.desc_funnel_step_drop_reason IN ('UNREACHABLE') THEN 'NO CONTACT'
      WHEN c.desc_funnel_step_drop_reason IN ('TenantNoReserved') THEN 'NO RESERVED'
      WHEN c.desc_funnel_step_drop_reason IN (
        'PropertyRented5A',
        'PROPERTY_UNPUBLISHED',
        'UnpublishedHouse',
        'OwnerSoldHouse',
        'OwnerSoldApartment',
        'TENANT_UNABLE_TO_LEAVE',
        'OWNER_UNABLE_TO_LEAVE'
      ) THEN 'PROPERTY UNAVAILABLE'
      WHEN c.desc_funnel_step_drop_reason IN (
        'HouseReserved',
        'OwnerRentedForAnotherTenant5A',
        'TenantRentedAnother5A',
        'TenantRentedAnother5A'
      ) THEN 'DEMAND CONCENTRATION'
      WHEN c.desc_funnel_step_drop_reason IN (
        'TENANT_PREFERS_OTHER',
        'OWNER_PREFERS_OTHER',
        'TenantRentedAnotherOutside',
        'TENANT_RENTING_WITH_OTHER_COMPANY',
        'OWNER_RENTING_WITH_OTHER_COMPANY',
        'OwnerRentedForAnotherTenantOutside'
      ) THEN 'EXTERNAL COMPETITION'
      WHEN c.desc_funnel_step_drop_reason IN (
        'INCORRECT_INFO',
        'PRICE_MODIFICATION',
        'EXPECTED_TERMINATION_DATE_CHANGE'
      ) THEN 'INCORRECT OR MODIFIED DATA'
      WHEN c.desc_funnel_step_drop_reason IN (
        'OWNER_SELLING_HOUSE',
        'TENANT_BUYING_HOUSE'
      ) THEN 'PROPERTY FOR SALE'
      WHEN c.desc_funnel_step_drop_reason IN (
        'SIG_DEADLINE_EXPIRED',
        'VALIDITY_DATES'
      ) THEN 'CONTRACT ISSUES'
      ELSE 'OTHER'
    END AS desc_drop_reason,
    c.desc_funnel_step_drop_reason AS desc_original_drop_reason
    FROM
        cte_union_dimensions AS c
    LEFT JOIN
        cte_id_master_type AS cmt
            ON cmt.desc_drop_origin = c.desc_drop_origin
)
SELECT
  id,
  id_drop_origin,
  id_original_drop_reason,
  desc_drop_origin,
  desc_persona,
  desc_drop_reason,
  desc_original_drop_reason
FROM
  get_categories
ORDER BY
  id ASC
