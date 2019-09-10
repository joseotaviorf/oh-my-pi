-- returns true or false if a point lies inside a polygon https://shapely.readthedocs.io/en/stable/manual.html#object.within
-- takes as parameters a well-known-text representation of a polygon geometry https://en.wikipedia.org/wiki/Well-known_text_representation_of_geometry
-- and longitude (x) latitude (y) and as float values
CREATE OR REPLACE FUNCTION public.f_within(polygon_wkt character varying, point_lng float, point_lat float)
 RETURNS character varying LANGUAGE plpythonu
 STABLE
AS $$
  from shapely.geometry import Point, Polygon
  from shapely import wkt
  polygon = Polygon(wkt.loads(polygon_wkt))
  point = Point(point_lng, point_lat)
  return point.within(polygon)
$$;
