CREATE OR REPLACE VIEW public.vw_property_listing AS
 WITH ish AS (
         SELECT imovel_status_history.status_history,
            imovel_status_history.status_time,
            imovel_status_history.id,
            row_number() OVER (PARTITION BY imovel_status_history.id ORDER BY imovel_status_history.status_time) AS rn,
            row_number() OVER (PARTITION BY imovel_status_history.id, imovel_status_history.status_history ORDER BY imovel_status_history.status_time) AS rn_status
           FROM imovel_status_history
          WHERE imovel_status_history.status_history::text = ANY (ARRAY['alugado'::character varying, 'publicado'::character varying]::text[])
        ), diff_status AS (
         SELECT act.id,
            act.status_history AS status,
            act.status_time,
            nxt_status.status_history AS next_status,
            nxt_status.status_time AS next_status_time,
            nxt.status_history AS next_different_status,
            nxt.status_time AS next_different_status_time
           FROM ish act
             LEFT JOIN ish nxt_status ON act.id = nxt_status.id AND act.status_history::text = nxt_status.status_history::text AND act.rn_status = (nxt_status.rn_status - 1)
             LEFT JOIN ish nxt ON act.id = nxt.id AND act.status_history::text <> nxt.status_history::text AND act.rn = (nxt.rn - 1)
          ORDER BY act.rn
        ), check_status AS (
         SELECT diff_status.id,
            diff_status.status,
            diff_status.status_time,
            diff_status.next_status,
            diff_status.next_status_time,
            diff_status.next_different_status,
            diff_status.next_different_status_time,
            diff_status.status::text = 'alugado'::text AND diff_status.next_different_status_time IS NOT NULL AND (diff_status.next_different_status_time - diff_status.status_time) >= '45 days'::interval AS new_version_alugado,
            diff_status.status::text = 'publicado'::text AND diff_status.next_different_status IS NULL AND diff_status.next_status_time IS NOT NULL AND (diff_status.next_status_time - diff_status.status_time) >= '14 days'::interval AS new_version_publicado
           FROM diff_status
        ), times AS (
         SELECT DISTINCT check_status.id,
            check_status.status,
            row_number() OVER w AS rn,
            lag(check_status.status_time) OVER w AS min_version_time,
            max(check_status.status_time) OVER w AS max_version_time
           FROM check_status
          WHERE check_status.new_version_alugado OR check_status.new_version_publicado
          WINDOW w AS (PARTITION BY check_status.id ORDER BY check_status.status_time)
        ), history_times AS (
         SELECT i.id,
            i.status_history,
            i.status_time,
            t.min_version_time,
            t.max_version_time,
                CASE
                    WHEN t.min_version_time IS NULL AND t.max_version_time IS NULL THEN NULL::bigint
                    WHEN i.status_time > t.min_version_time OR t.min_version_time IS NULL THEN t.rn
                    ELSE t.rn + 1
                END AS version
           FROM imovel_status_history i
             LEFT JOIN times t ON t.id = i.id AND (i.status_time > t.min_version_time OR t.min_version_time IS NULL) AND (i.status_time <= t.max_version_time OR t.max_version_time IS NULL)
        ), result_version AS (
         SELECT history_times.id,
            history_times.status_history,
            history_times.status_time,
            history_times.min_version_time,
            history_times.max_version_time,
            COALESCE(history_times.version, COALESCE(max(history_times.version) OVER (PARTITION BY history_times.id ORDER BY history_times.status_time), 0::bigint) + 1) AS version
           FROM history_times
        ), prev_listing AS (
         SELECT result_version.id,
            result_version.status_history,
            result_version.status_time,
                CASE
                    WHEN result_version.version = 1 THEN NULL::timestamp without time zone
                    ELSE COALESCE(result_version.min_version_time, max(result_version.max_version_time) OVER (PARTITION BY result_version.id ORDER BY result_version.status_time))
                END AS min_version_time,
            result_version.max_version_time,
            result_version.version,
            row_number() OVER (PARTITION BY result_version.id, result_version.version ORDER BY result_version.status_time DESC) AS rn,
            min(result_version.status_time) FILTER (WHERE result_version.status_history::text = ANY (ARRAY['publicado'::character varying, 'alugado'::character varying]::text[])) OVER (PARTITION BY result_version.id, result_version.version ORDER BY result_version.status_time) AS publication_date,
            max(result_version.status_time) FILTER (WHERE result_version.status_history::text = 'publicado'::text) OVER (PARTITION BY result_version.id, result_version.version ORDER BY result_version.status_time) AS last_publication_date
           FROM result_version
        ), last_pub AS (
         SELECT pl.id,
            pl.status_history,
            pl.status_time,
            pl.min_version_time,
            pl.max_version_time,
            pl.version,
            pl.rn,
            pl.publication_date,
            pl_max.last_pub_date AS last_publication_date
           FROM prev_listing pl
             LEFT JOIN ( SELECT prev_listing.id,
                    prev_listing.version,
                    max(prev_listing.last_publication_date) AS last_pub_date
                   FROM prev_listing
                  GROUP BY prev_listing.id, prev_listing.version) pl_max ON pl.id = pl_max.id AND pl.version = pl_max.version
        ), last_version AS (
         SELECT DISTINCT last_pub.id,
            last_pub.version,
            last_pub.min_version_time,
            last_pub.max_version_time,
            last_pub.publication_date,
            last_pub.last_publication_date,
            last_value(last_pub.status_history) OVER (PARTITION BY last_pub.id, last_pub.version ORDER BY last_pub.status_time RANGE BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) AS last_status_version
           FROM last_pub
        ), prev AS (
         SELECT last_version.id,
            last_version.version,
            last_version.min_version_time,
            last_version.max_version_time,
            last_version.publication_date,
            last_version.last_publication_date,
            last_version.last_status_version,
            lag(last_version.last_status_version) OVER (PARTITION BY last_version.id ORDER BY last_version.version) AS prev_status
           FROM last_version
          WHERE last_version.publication_date IS NOT NULL
        ), rent AS (
         SELECT prev.id,
            prev.version,
            prev.min_version_time,
            prev.max_version_time,
            prev.last_status_version,
            COALESCE(prev.publication_date, prev.max_version_time) AS publication_date,
            prev.last_publication_date,
                CASE COALESCE(prev.prev_status, 'alugado'::character varying)
                    WHEN 'alugado'::text THEN 1
                    ELSE 0
                END AS prev_rented,
                CASE COALESCE(prev.last_status_version, 'alugado'::character varying)
                    WHEN 'alugado'::text THEN 1
                    ELSE 0
                END AS rented
           FROM prev
        ), relisting AS (
         SELECT DISTINCT rent.id,
            rent.version,
            rent.min_version_time,
            rent.max_version_time,
            rent.last_status_version,
            rent.publication_date,
            rent.last_publication_date,
            rent.prev_rented,
            rent.rented,
            sum(rent.prev_rented) OVER (PARTITION BY rent.id ORDER BY rent.version) AS nr_listing,
            sum(rent.rented) OVER (PARTITION BY rent.id ORDER BY rent.version) AS nr_renting
           FROM rent
        )
 SELECT relisting.id,
    relisting.version,
    relisting.min_version_time,
    relisting.max_version_time,
    relisting.last_status_version,
    relisting.nr_listing,
    relisting.nr_renting,
    min(relisting.publication_date) OVER (PARTITION BY relisting.id, relisting.nr_listing ORDER BY relisting.version) AS publication_date,
    relisting.last_publication_date
   FROM relisting
  ORDER BY relisting.id, relisting.version;