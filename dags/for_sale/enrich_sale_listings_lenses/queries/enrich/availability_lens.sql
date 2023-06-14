WITH available_hours AS (
  SELECT 
    id_house,
    CASE 
      WHEN week_available_hours = 0 THEN '[0]'
      WHEN week_available_hours BETWEEN 1 AND 9 THEN '[1-9]'
      WHEN week_available_hours BETWEEN 10 AND 29 THEN '[10-29]'
      WHEN week_available_hours BETWEEN 30 AND 49 THEN '[30-49]'
      ELSE '[>=50]'
    END AS week_available_hours_bins,
    dt_schedule_started,
    DATE_ADD(dt_schedule_ended, -1) AS dt_schedule_ended
  FROM 
    datalake_sale_available_booking_hours.weekly_available_booking_hours  
),
key_location_by_day AS (
  SELECT
    a.id,
    a.id_authorization,
    a.id_house,
    a.rev,
    a_type.name AS key_location,
    rev.ts_revision AS ts_key_location_started
  FROM
    datalake_ebdb_clean.access_type_aud AS a
  LEFT JOIN
    datalake_ebdb_clean.access_authorization_type AS a_type
      ON a.id_authorization = a_type.id
  LEFT JOIN
    datalake_ebdb_user.user_revision_entity AS rev
      ON a.rev = rev.id
  QUALIFY 
    ROW_NUMBER() OVER (PARTITION BY id_house, DATE_TRUNC('DAY', ts_revision) ORDER BY rev DESC) = 1
),
key_location_aux AS (
  SELECT 
    id,
    id_house,
    key_location,
    ts_key_location_started
  FROM
    key_location_by_day
  QUALIFY 
    LAG(id_authorization) OVER (PARTITION BY id_house ORDER BY rev) IS DISTINCT FROM id_authorization
),
key_location AS (
  SELECT 
    id,
    id_house,
    key_location,
    ts_key_location_started,
    LEAD(ts_key_location_started) OVER (PARTITION BY id_house ORDER BY ts_key_location_started) AS ts_key_location_ended
  FROM
    key_location_aux
),
visits_canceled AS (
  SELECT 
    dt_booking AS date,
    b.id_house,
    COUNT(CASE WHEN bc.cancelled_by = 'Owner' THEN b.id END) AS vbs_canceled_by_owner,
    COUNT(CASE WHEN bc.cancelled_by != 'Owner' THEN b.id END) AS vbs_canceled_by_other
  FROM
    datalake_ebdb_clean.booking AS b
  LEFT JOIN 
    datalake_booking.booking_cancellation AS bc
      ON b.id = bc.id_booking
  WHERE 
    b.business_context = 'SALE'
    AND b.ts_created IS NOT NULL
  GROUP BY 
    1, 2
),
visits_completed AS (
  SELECT 
    TO_DATE(CAST(dt_booking AS TIMESTAMP) + FLOOR((slot_day * 15 / 60)+8) * INTERVAL 1 HOURS + ABS(slot_day * 15 % 60) * INTERVAL 1 MINUTES) AS date,
    id_house,
    COUNT(DISTINCT id) AS visits_completed
  FROM
    datalake_ebdb_clean.booking AS b
  WHERE 
    business_context = 'SALE'
    AND ts_created IS NOT NULL
    AND visit_fup IN ('NaoGostou', 'Talvez', 'VaiNegociar', 'VisitouSozinho') 
  GROUP BY 
    1, 2
),
visits_unauthorized_entry AS (
  SELECT 
    TO_DATE(CAST(dt_booking AS TIMESTAMP) + FLOOR((slot_day * 15 / 60)+8) * INTERVAL 1 HOURS + ABS(slot_day * 15 % 60) * INTERVAL 1 MINUTES) AS date,
    id_house,
    COUNT(DISTINCT id) AS visits_unauthorized_entry
  FROM
    datalake_ebdb_clean.booking AS b
  WHERE 
    business_context = 'SALE'
    AND ts_created IS NOT NULL
    AND visit_fup = 'EntradaNaoAutorizada'
  GROUP BY 
    1, 2
),
rent_contracts AS ( 
    SELECT
    id AS id_contract,
    id_house,
    dt_started AS dt_contract_started,
    LEAST(TO_DATE(ts_analyst_annulment_input), dt_termination) AS dt_contract_ended
  FROM
    datalake_ebdb_contract.contract
),
status_change_by_day AS (
  SELECT
    lbc.id_house,
    h.id_region,
    lbc.status,
    ure.ts_revision
  FROM
    datalake_ebdb_clean.listing_business_context_aud AS lbc
  JOIN
    datalake_ebdb_user.user_revision_entity AS ure
      ON lbc.rev = ure.id
  JOIN
    datalake_ebdb_clean.house AS h
      ON lbc.id_house = h.id
  WHERE
    lbc.business_context = 'SALE'
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY lbc.id_house, DATE_TRUNC('DAY', ure.ts_revision) ORDER BY ure.ts_revision DESC) = 1

),
status_changes_aux AS (
  SELECT
    id_house,
    id_region,
    status,
    ts_revision
  FROM
    status_change_by_day
  QUALIFY
    LAG(status) OVER (PARTITION BY id_house ORDER BY ts_revision) IS DISTINCT FROM status
),
status_changes AS (
  SELECT
    id_house,
    id_region,
    CASE 
      WHEN status = 'PUBLISHED' THEN status
      ELSE 'UNPUBLISHED'
    END AS status,
    ts_revision AS ts_status_started,
    LEAD(ts_revision) OVER (PARTITION BY id_house ORDER BY ts_revision) AS ts_status_ended
  FROM
    status_changes_aux
),
sale_listings_timeline AS (
  SELECT 
    lbc.id_house,
    d.date
  FROM 
    datalake_ebdb_clean.listing_business_context AS lbc
  JOIN 
    datalake_quintoandar.aux_date AS d
      ON d.date BETWEEN TO_DATE(lbc.ts_first_publication) AND CURRENT_DATE 
  WHERE 
    lbc.business_context = 'SALE'
),
dataset AS (
  SELECT 
    t.id_house,
    sc.id_region,
    sc.status,
    ah.week_available_hours_bins,
    kl.key_location,
    SUM(COALESCE(vc.visits_completed, 0)) OVER (PARTITION BY t.id_house ORDER BY t.date ROWS BETWEEN 45 PRECEDING AND CURRENT ROW) AS visits_completed_last_45_days,
    SUM(COALESCE(cl.vbs_canceled_by_owner, 0)) OVER (PARTITION BY t.id_house ORDER BY t.date ROWS BETWEEN 45 PRECEDING AND CURRENT ROW) AS visits_canceled_by_owner_last_45_days,
    SUM(COALESCE(vu.visits_unauthorized_entry, 0)) OVER (PARTITION BY t.id_house ORDER BY t.date ROWS BETWEEN 45 PRECEDING AND CURRENT ROW) AS visits_unauthorized_entry_last_45_days,
    rc.id_contract IS NOT NULL AS has_active_rental_contract,
    COUNT_IF(rc.id_contract IS NOT NULL) OVER (PARTITION BY t.id_house) > 0 AS has_house_been_rented,
    t.date
  FROM 
    sale_listings_timeline AS t
  LEFT JOIN 
    visits_completed AS vc
      ON t.id_house = vc.id_house
      AND t.date = vc.date
  LEFT JOIN 
    visits_canceled AS cl 
      ON t.id_house = cl.id_house
      AND t.date = cl.date
  LEFT JOIN 
    visits_unauthorized_entry AS vu 
      ON t.id_house = vu.id_house
      AND t.date = vu.date
  LEFT JOIN 
    available_hours AS ah 
      ON t.id_house = ah.id_house
      AND t.date BETWEEN ah.dt_schedule_started AND COALESCE(ah.dt_schedule_ended, CURRENT_DATE())
  LEFT JOIN 
    key_location AS kl
      ON t.id_house = kl.id_house 
      AND t.date BETWEEN kl.ts_key_location_started AND COALESCE(kl.ts_key_location_ended, CURRENT_DATE())
  LEFT JOIN 
    rent_contracts AS rc 
      ON t.id_house = rc.id_house
      AND t.date BETWEEN rc.dt_contract_started AND COALESCE(rc.dt_contract_ended, CURRENT_DATE())
  LEFT JOIN 
    status_changes AS sc 
      ON t.id_house = sc.id_house
      AND t.date BETWEEN sc.ts_status_started AND COALESCE(sc.ts_status_ended, CURRENT_DATE())
  WHERE 
    sc.status IS NOT NULL
),
business_logic AS (
  SELECT
    id_house,
    id_region,
    status,
    CASE 
      WHEN key_location = 'OwnerPresent' AND visits_canceled_by_owner_last_45_days >= 1 THEN -10000
      WHEN key_location = 'OwnerPresent' AND visits_canceled_by_owner_last_45_days = 0 THEN -2000
      ELSE 0
    END AS key_location_score,
    CASE 
      WHEN has_active_rental_contract = TRUE THEN -1000
      ELSE 0
    END AS has_active_rental_contract_score,
    IF(visits_canceled_by_owner_last_45_days >= 1, -3000, 0) AS cancel_by_owner_score,
    visits_unauthorized_entry_last_45_days,
    CASE 
      WHEN visits_unauthorized_entry_last_45_days >= 1 THEN -5000
      WHEN visits_unauthorized_entry_last_45_days >= 1 AND visits_completed_last_45_days = 0 THEN -100000
      ELSE 0 
    END AS cancel_by_unauthorized_entry_score,
    week_available_hours_bins,
    CASE week_available_hours_bins
      WHEN '[0]' THEN -100000
      WHEN '[1-9]' THEN -10000
      WHEN '[10-29]' THEN -1000
      WHEN '[30-49]' THEN -500
      ELSE 0
    END AS week_available_hours_score,
    CASE 
      WHEN key_location = 'OwnerPresent' AND visits_canceled_by_owner_last_45_days >= 1 THEN 'and its key location is Owner Present.'
      WHEN key_location = 'OwnerPresent' AND visits_canceled_by_owner_last_45_days = 0 THEN 'and its key location is ' || key_location 
      WHEN key_location IS NULL OR key_location = 'None' THEN 'and the key location is unknown '
      ELSE 'and its key location is ' || key_location
    END AS key_location_score_disclaimer,
    CASE 
      WHEN has_active_rental_contract = TRUE THEN 'has an active rental contract '
      ELSE 'doesnt have an active contract '
    END AS has_active_rental_contract_score_disclaimer,
    CASE 
      WHEN has_house_been_rented = TRUE THEN 'has house been rented'
      ELSE ''
    END AS has_house_been_rented_score_disclaimer, 
    visits_canceled_by_owner_last_45_days,
    CASE
      WHEN visits_canceled_by_owner_last_45_days= 0 THEN 'no visits canceled by the owner in the last 45 days, '
      WHEN visits_canceled_by_owner_last_45_days BETWEEN 1 AND 3 THEN CONCAT('has ', CAST(visits_canceled_by_owner_last_45_days AS STRING), ' visit canceled by the owner in the last 45 days, ') 
      WHEN visits_canceled_by_owner_last_45_days > 3 THEN 'more than 3 visits canceled by the owner in the last 45 days, '
    END AS cancel_by_owner_score_disclaimer,     
    CASE week_available_hours_bins
      WHEN '[0]' THEN 'The listing has no available hours this week, '
      WHEN '[1-9]' THEN 'The listing has between 1 and 9 available hours this week, '
      WHEN '[10-29]' THEN 'The listing has between 10 and 29 available hours this week, ' 
      WHEN '[30-49]' THEN 'The listing has between 30 and 49 available hours this week, ' 
      WHEN '[>=50]' THEN 'The listing has over 49 available hours this week, '  
    END AS week_available_hours_score_disclaimer,
    date
  FROM
    dataset
),
score AS (
  SELECT 
    id_house,
    id_region,
    status,
    (key_location_score + has_active_rental_contract_score + week_available_hours_score + cancel_by_owner_score + cancel_by_unauthorized_entry_score) AS availability_score,
    key_location_score,
    week_available_hours_score,
    cancel_by_owner_score,
    has_active_rental_contract_score,
    cancel_by_unauthorized_entry_score,
    key_location_score_disclaimer,
    week_available_hours_score_disclaimer,
    cancel_by_owner_score_disclaimer,
    has_active_rental_contract_score_disclaimer,
    CASE LEAST(week_available_hours_score, cancel_by_owner_score, has_active_rental_contract_score, cancel_by_unauthorized_entry_score, key_location_score)
      WHEN 0 THEN 'Everything looks Great.'
      WHEN week_available_hours_score THEN 'The house could have more available hours to visit. Currently, it has ' || week_available_hours_bins || ' available hours.'
      WHEN cancel_by_owner_score THEN 'The main reason is because the owner canceled ' || visits_canceled_by_owner_last_45_days || 'visits booked in the last 45 days.' 
      WHEN has_active_rental_contract_score THEN 'We know that having a tenant in the house is worse for VB2VC Conversion.'
      WHEN cancel_by_unauthorized_entry_score THEN 'The main reason is because the house had ' || visits_unauthorized_entry_last_45_days || ' unauthorized entries in the last 45 days.' 
      WHEN key_location_score THEN 'The owners provided key location is worse for VB2VC Conversion.'
    END AS main_detractor,
    SIZE(
      FILTER(
        ARRAY(week_available_hours_score, cancel_by_owner_score, has_active_rental_contract_score, cancel_by_unauthorized_entry_score, key_location_score), 
        x -> x == ARRAY_MIN(ARRAY(week_available_hours_score, cancel_by_owner_score, has_active_rental_contract_score, cancel_by_unauthorized_entry_score, key_location_score))
      )
    ) > 1 AS multi_detractors, 
    week_available_hours_score_disclaimer || cancel_by_owner_score_disclaimer || has_active_rental_contract_score_disclaimer || key_location_score_disclaimer AS drill_down,
    date
  FROM 
    business_logic
),
create_tiers AS (
  SELECT 
    id_house, 
    id_region,
    status, 
    availability_score,
    key_location_score,
    week_available_hours_score,
    cancel_by_owner_score,
    has_active_rental_contract_score,
    cancel_by_unauthorized_entry_score,
    key_location_score_disclaimer,
    week_available_hours_score_disclaimer,
    cancel_by_owner_score_disclaimer,
    has_active_rental_contract_score_disclaimer,
    CASE 
      WHEN status = 'UNPUBLISHED' THEN 'DISCARD'
      WHEN availability_score < -100000 THEN 'A1'
      WHEN availability_score BETWEEN -1500 AND 0 THEN 'A5'
      WHEN availability_score BETWEEN -2500 AND -1500 THEN 'A4'
      WHEN availability_score BETWEEN -4000 AND -2500 THEN 'A3'
      ELSE 'A2'
    END AS tier,
    IF(
      multi_detractors, 
      'Resume: This listing has multiple detractors with equal weight for the score, see the drill down.  | Drill Down: ' || drill_down,
      'Resume: ' || main_detractor || ' | Drill Down: ' || drill_down) AS tier_disclaimer,
    date AS ts_tier_started
  FROM
    score
),
grouping_tiers AS (
  SELECT 
    id_house, 
    id_region,
    status, 
    availability_score,
    key_location_score,
    week_available_hours_score,
    cancel_by_owner_score,
    has_active_rental_contract_score,
    key_location_score_disclaimer,
    week_available_hours_score_disclaimer,
    cancel_by_owner_score_disclaimer,
    has_active_rental_contract_score_disclaimer,
    tier,
    tier_disclaimer,
    ts_tier_started
  FROM
    create_tiers
  QUALIFY 
    ts_tier_started = MIN(IF(status = 'PUBLISHED', ts_tier_started, NULL)) OVER (PARTITION BY id_house)
    OR tier != LAG(tier) OVER (PARTITION BY id_house ORDER BY ts_tier_started)
),
aux AS (
  SELECT
    id_house,
    id_region,
    status,
    tier,
    availability_score,
    key_location_score,
    week_available_hours_score,
    cancel_by_owner_score,
    has_active_rental_contract_score,
    CASE 
      WHEN tier = 'A5' THEN 'Great availability'
      WHEN tier = 'A4' THEN 'Good availability'
      WHEN tier = 'A3' THEN 'Standard Availability'
      WHEN tier = 'A2' THEN 'Limited Availability'
      WHEN tier = 'A1' THEN 'Possibly Unavailable'
    END AS tier_name,
    tier_disclaimer,
    ROW_NUMBER() OVER (PARTITION BY id_house ORDER BY ts_tier_started DESC) = 1 AS is_last_tier,
    ts_tier_started,
    LEAD(ts_tier_started) OVER (PARTITION BY id_house ORDER BY ts_tier_started) AS ts_tier_ended
  FROM
    grouping_tiers
)
SELECT
  id_house,
  id_region,
  availability_score,
  key_location_score,
  week_available_hours_score,
  cancel_by_owner_score,
  has_active_rental_contract_score,
  tier,
  tier_name,
  tier_disclaimer,
  is_last_tier,
  status = 'PUBLISHED' AND is_last_tier AS is_active,
  ts_tier_started,
  ts_tier_ended
FROM
  aux
WHERE 
  tier != 'DISCARD'