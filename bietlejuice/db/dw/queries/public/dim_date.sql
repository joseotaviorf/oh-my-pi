DROP TABLE IF EXISTS dim_date;

CREATE TABLE public.dim_date (
  sk_date INTEGER primary key,
  "date" DATE,
  year INTEGER,
  month INTEGER,
  month_name VARCHAR(15),
  day INTEGER,
  day_of_year INTEGER,
  week_day INTEGER,
  weekday_name VARCHAR(15),
  calendar_week INTEGER,
  working_days_in_month INTEGER,
  total_working_days_in_month INTEGER,
  brz_date CHAR(10),
  usa_date CHAR(10),
  universal_date CHAR(10),
  quarter VARCHAR(2),
  year_quarter VARCHAR(10),
  year_month VARCHAR(10),
  year_calendar_week VARCHAR(10),
  weekend VARCHAR(10),
  is_brz_holiday VARCHAR(10),
  working_day_month INTEGER,
  brz_season VARCHAR(10),
  week_start DATE,
  week_end DATE,
  month_start DATE,
  month_end DATE,
  last_day DATE,
  last_week DATE,
  last_2_weeks DATE,
  last_4_weeks DATE,
  last_month DATE,
  last_quarter DATE,
  last_year DATE
);

INSERT INTO public.dim_date values (-1);

-- Creates a dummy table with numbers from 1 to LIMIT
SELECT ROW_NUMBER() OVER (ORDER BY TRUE) AS n
INTO
public.temp
FROM  public.dim_user LIMIT 7305;

INSERT INTO public.dim_date
SELECT
    to_char(sk_date, 'YYYYMMDD')::INTEGER,
	sk_date,
	EXTRACT(YEAR FROM sk_date) AS YEAR,
	EXTRACT(MONTH FROM sk_date) AS MONTH,
	to_char(sk_date, 'Month') AS Month_Name,
	EXTRACT(DAY FROM sk_date) AS DAY,
	EXTRACT(doy FROM sk_date) AS Day_Of_Year,
    EXTRACT(dow FROM sk_date) as Week_Day,
	to_char(sk_date, 'Day') AS Weekday_Name,
	EXTRACT(week FROM sk_date) AS Calendar_Week,
	to_char(sk_date, 'dd/mm/yyyy') AS Brz_Date,
    to_char(sk_date, 'mm/dd/yyyy') AS Usa_Date,
    to_char(sk_date, 'yyyy/mm/dd') AS Universal_Date,
	'Q' || to_char(sk_date, 'Q') AS Quarter,
	to_char(sk_date, 'yyyy/"Q"Q') AS Year_Quarter,
	to_char(sk_date, 'yyyy/mm') AS Year_Month,
	to_char(sk_date, 'iyyy/IW') AS Year_Calendar_Week,
	-- Weekend
	CASE WHEN EXTRACT(dow FROM sk_date) IN (6, 7) THEN 'Weekend' ELSE 'Weekday' END AS Weekend,
	-- Fixed holidays
      CASE WHEN to_char(sk_date, 'MMDD') IN ('0101', '0421', '0501', '0907', '1012', '1102', '1115', '1225')
      THEN 'Holiday' ELSE 'No holiday' END
      AS Is_Brz_Holiday,
    -- weekdays in a month
    SUM(CASE WHEN
    	((CASE WHEN EXTRACT(dow FROM date) IN (6, 0) THEN 'Weekend' ELSE 'Weekday' END) = 'Weekend' OR
    	(CASE WHEN to_char(date, 'MMDD') IN ('0101', '0421', '0501', '0907', '1012', '1102', '1115', '1225') THEN 'Holiday' ELSE 'No holiday' END) = 'Holiday')
    THEN 0 ELSE 1 END) OVER(PARTITION BY date_trunc('month',date) ORDER BY EXTRACT(DAY FROM date) rows unbounded preceding) AS working_days_in_month,
	-- Some periods of the year, adjust for your organisation and country
    max(working_days_in_month) over (partition by year, month) as total_working_days_in_month,
    CASE
    	WHEN to_char(sk_date, 'MMDD') BETWEEN '0320' AND '0619' THEN 'Autumn'
        WHEN to_char(sk_date, 'MMDD') BETWEEN '0620' AND '0921' THEN 'Winter'
	    WHEN to_char(sk_date, 'MMDD') BETWEEN '0922' AND '1220' THEN 'Spring'
        ELSE 'Summer'
    END AS Brz_Season,

    date_trunc('week',sk_date) AS Week_Start,
	date_trunc('week',sk_date) + '1 week'::INTERVAL - '1 day'::interval AS Week_End,
    date_trunc('month',sk_date) AS Month_Start,
	ADD_MONTHS(date_trunc('month',sk_date),1) - '1 day'::interval AS Month_End,
    sk_date - '1 day'::interval as Last_Day,
    sk_date - '7 days'::interval as Last_Week,
    sk_date - '14 days'::interval as Last_2_Weeks,
    sk_date - '28 days'::interval as Last_4_Weeks,
    ADD_MONTHS(sk_date, -1) as Last_Month,
    ADD_MONTHS(sk_date, -3) as Last_Quarter,
    DATEADD(YEAR, -1, sk_date) as Last_Year
FROM (
	-- There are 3 leap years in this range, so calculate 365 * 10 + 3 records
	SELECT '2010-01-01'::DATE +(n||' days')::interval AS sk_date
    FROM  public.temp
     ) DQ
ORDER BY 1;

DROP TABLE public.temp;
