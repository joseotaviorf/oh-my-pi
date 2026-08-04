WITH raw_status AS (
    SELECT
        MAKE_DATE(year, month, day) AS dt_day,
        prompt_id,
        prompt_hash,
        inference_status
    FROM
        datalake_vocs_machina_planning_raw.vocs_machina_inference_status
),
-- Bounds raw_status's own backfill window (at most ~90 days per
-- quintoml's prompts/reparos.yml backfill_days), used below to keep the
-- clean.vocs_machina scan from reading that table's entire history on
-- every run (SQL conventions #10a).
raw_status_bounds AS (
    SELECT
        MIN(dt_day) AS min_dt_day,
        MAX(dt_day) AS max_dt_day
    FROM
        raw_status
),
-- Distinct (day, prompt_id, prompt_hash) partitions the clean ingestion table
-- already has at least one row for. vocs_machina/clean is one row per
-- (id_feedback, id_prompt, prompt_hash) per partition (see
-- vocs_machina/metadata/clean/vocs_machina.yml), so this collapses it to the
-- partition grain before joining -- that DISTINCT is what keeps the join
-- below from fanning out.
--
-- clean.year/month/day is documented there as "the ingestion date", but that
-- description predates this table: load_vocs_machina_raw.py derives
-- year/month/day from the very calendar day it reads quintoml's
-- raw/year=/month=/day=/ S3 partition for (build_day_partition_uri), which is
-- the exact coordinate vocs_machina_planning's stage_inference_status_to_s3
-- checks for a _SUCCESS marker at. So joining raw_status and
-- ingested_partitions on (dt_day, prompt_id, prompt_hash) compares the same
-- underlying quintoml partition on both sides.
--
-- Bounded to raw_status_bounds' [min_dt_day, max_dt_day] range instead of
-- scanning clean.vocs_machina's entire history: raw_status only ever has
-- rows for the current backfill window, so anything outside that range can
-- never match the join below anyway.
ingested_partitions AS (
    SELECT DISTINCT
        MAKE_DATE(vm.year, vm.month, vm.day) AS dt_day,
        vm.id_prompt AS prompt_id,
        vm.prompt_hash
    FROM
        datalake_vocs_machina_clean.vocs_machina AS vm
    CROSS JOIN
        raw_status_bounds AS b
    WHERE
        MAKE_DATE(vm.year, vm.month, vm.day) BETWEEN b.min_dt_day AND b.max_dt_day
),
backfill_status AS (
    SELECT
        CONCAT(
            COALESCE(CAST(rs.dt_day AS STRING), ''),
            '|',
            COALESCE(rs.prompt_id, ''),
            '|',
            COALESCE(rs.prompt_hash, '')
        ) AS business_key,
        rs.dt_day AS day,
        rs.prompt_id,
        rs.prompt_hash,
        rs.inference_status,
        CASE
            WHEN rs.inference_status != 'done' THEN 'not_applicable'
            WHEN ip.prompt_id IS NOT NULL THEN 'ingested'
            ELSE 'pending'
        END AS ingestion_status,
        DATEDIFF(CURRENT_DATE, rs.dt_day) AS age_days
    FROM
        raw_status AS rs
    LEFT JOIN
        ingested_partitions AS ip
            ON ip.dt_day = rs.dt_day
            AND ip.prompt_id = rs.prompt_id
            AND ip.prompt_hash = rs.prompt_hash
)
-- No ROW_NUMBER()/dedup step, unlike listing_quality_sla's modeled pattern:
-- raw_status is already exactly one row per (day, prompt_id, prompt_hash) per
-- Slice 1's raw table contract, and ingested_partitions is explicitly
-- DISTINCT on that same key, so the LEFT JOIN above can produce at most one
-- output row per raw_status row -- verified, not assumed.
SELECT
    -- MD5 of business_key itself (not a separately hand-maintained
    -- concatenation of the same fields), so the two can never drift apart
    -- the way an independently-built, undelimited CONCAT once did here.
    MD5(business_key) AS id_vocs_machina_backfill_status,
    business_key,
    day,
    prompt_id,
    prompt_hash,
    inference_status,
    ingestion_status,
    age_days
FROM
    backfill_status
