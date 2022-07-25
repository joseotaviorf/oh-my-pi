-- returns distance in meters between a pair of lat/lon points
-- parameters are lat1, lng1, lat2, lng2
CREATE OR REPLACE FUNCTION f_geodesical_distance (Float, Float, Float, Float)
   RETURNS FLOAT
 IMMUTABLE
 AS $$
   SELECT
 	  2 * 6373000 * ASIN( SQRT( ( SIN( RADIANS(($3 - $1) / 2) ) ) ^ 2 + COS(RADIANS($1)) * COS(RADIANS($3)) * (SIN(RADIANS(($4 - $2) / 2))) ^ 2))
 $$ LANGUAGE sql