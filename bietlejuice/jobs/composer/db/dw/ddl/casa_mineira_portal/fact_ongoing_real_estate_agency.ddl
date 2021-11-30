DROP TABLE IF EXISTS casa_mineira_portal.fact_ongoing_real_estate_agency;
CREATE TABLE IF NOT EXISTS casa_mineira_portal.fact_ongoing_real_estate_agency (
    sk_count_evaluated_date INT,
    ongoing_real_estate_agency INT,
    dt_count_evaluated DATE,
    ts_load TIMESTAMP
);
ALTER TABLE casa_mineira_portal.fact_ongoing_real_estate_agency OWNER TO databricks;
