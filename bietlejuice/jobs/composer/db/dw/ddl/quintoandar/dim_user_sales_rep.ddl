DROP TABLE IF EXISTS quintoandar.dim_user_sales_rep;
CREATE TABLE quintoandar.dim_user_sales_rep (
    sk_user_sales_rep BIGINT PRIMARY KEY,
    name VARCHAR,
    email VARCHAR,
    phone_number VARCHAR,
    admin_type VARCHAR,
    sales_company VARCHAR,
    is_sales_rep_active BOOLEAN,
    dt_sales_rep_started DATE,
    ts_load TIMESTAMP
);
ALTER TABLE quintoandar.dim_user_sales_rep OWNER TO airflow;
