"""Unit tests for UC <-> Glue type mapping, focused on parameterised types."""

import unittest

from bietlejuice.services.metastore_services.glue_type_mapper import (
    coerce_glue_type_for_json,
    map_glue_type_to_uc,
    map_uc_type_to_glue,
    map_uc_type_to_glue_for_json,
)


class TestMapUcTypeToGlue(unittest.TestCase):
    """Assert parameterised types survive nesting inside structs, arrays and maps."""

    def test_bare_decimal_keeps_precision_and_scale(self):
        self.assertEqual(map_uc_type_to_glue("decimal(10,7)"), "decimal(10,7)")

    def test_decimal_nested_in_struct_keeps_precision_and_scale(self):
        """Regression: the comma in decimal(10,7) was read as a field separator,
        yielding the unparseable 'latitude:string,7)' and breaking Spark-on-EMR
        reads of every affected table."""
        self.assertEqual(
            map_uc_type_to_glue(
                "struct<city:string,latitude:decimal(10,7),longitude:decimal(10,7)>"
            ),
            "struct<city:string,latitude:decimal(10,7),longitude:decimal(10,7)>",
        )

    def test_decimal_nested_in_struct_in_array(self):
        self.assertEqual(
            map_uc_type_to_glue("array<struct<amount:decimal(38,18),ccy:string>>"),
            "array<struct<amount:decimal(38,18),ccy:string>>",
        )

    def test_decimal_as_map_value(self):
        self.assertEqual(
            map_uc_type_to_glue("map<string,decimal(17,2)>"),
            "map<string,decimal(17,2)>",
        )

    def test_struct_as_map_value_still_splits_on_first_comma_only(self):
        self.assertEqual(
            map_uc_type_to_glue("map<string,struct<a:decimal(9,2),b:long>>"),
            "map<string,struct<a:decimal(9,2),b:bigint>>",
        )

    def test_multiple_decimals_alongside_other_types(self):
        self.assertEqual(
            map_uc_type_to_glue(
                "struct<n:long,a:decimal(17,2),flag:boolean,b:decimal(5,4)>"
            ),
            "struct<n:bigint,a:decimal(17,2),flag:boolean,b:decimal(5,4)>",
        )

    def test_unknown_type_still_falls_back_to_string(self):
        self.assertEqual(map_uc_type_to_glue("variant"), "string")


class TestCoerceGlueTypeForJson(unittest.TestCase):
    """Only timestamp/date are fragile under OpenX; everything else stays typed."""

    def test_timestamp_and_date_become_string(self):
        for glue_type in ("timestamp", "date", "TIMESTAMP", "Date"):
            with self.subTest(glue_type=glue_type):
                self.assertEqual(coerce_glue_type_for_json(glue_type), "string")

    def test_decimal_and_complex_stay_typed(self):
        """OpenX reads these natively -- coercing them would lose the payload."""
        for glue_type in (
            "decimal(17,2)",
            "array<string>",
            "array<struct<AddressId:string,FromDate:string>>",
            "struct<a:int>",
            "map<string,string>",
            "map<string,array<map<string,string>>>",
        ):
            with self.subTest(glue_type=glue_type):
                self.assertEqual(coerce_glue_type_for_json(glue_type), glue_type)

    def test_nested_field_name_case_is_preserved(self):
        """Struct field spelling must survive; OpenX matches JSON keys by name."""
        glue_type = "struct<AddressId:string,__FLEX_Context:string>"
        self.assertEqual(coerce_glue_type_for_json(glue_type), glue_type)

    def test_safe_scalars_and_binary_unchanged(self):
        for glue_type in (
            "string",
            "boolean",
            "int",
            "bigint",
            "double",
            "float",
            "binary",
        ):
            with self.subTest(glue_type=glue_type):
                self.assertEqual(coerce_glue_type_for_json(glue_type), glue_type)

    def test_empty_type_falls_back_to_string(self):
        self.assertEqual(coerce_glue_type_for_json(""), "string")
        self.assertEqual(coerce_glue_type_for_json(None), "string")

    def test_map_uc_type_to_glue_for_json_coerces_only_timestamp_and_date(self):
        self.assertEqual(map_uc_type_to_glue_for_json("TIMESTAMP"), "string")
        self.assertEqual(map_uc_type_to_glue_for_json("DATE"), "string")
        self.assertEqual(map_uc_type_to_glue_for_json("DECIMAL(10,2)"), "decimal(10,2)")
        self.assertEqual(map_uc_type_to_glue_for_json("ARRAY<INT>"), "array<int>")
        self.assertEqual(map_uc_type_to_glue_for_json("BIGINT"), "bigint")
        self.assertEqual(map_uc_type_to_glue_for_json("BINARY"), "binary")


class TestMapGlueTypeToUc(unittest.TestCase):
    """The reverse direction shares the splitter, so it shares the fix."""

    def test_decimal_nested_in_struct_round_trips(self):
        self.assertEqual(
            map_glue_type_to_uc("struct<city:string,latitude:decimal(10,7)>"),
            "STRUCT<city:STRING,latitude:DECIMAL(10,7)>",
        )

    def test_round_trip_uc_to_glue_to_uc_is_stable(self):
        uc = "struct<a:decimal(17,2),b:string,c:array<decimal(9,4)>>"
        self.assertEqual(
            map_uc_type_to_glue(map_glue_type_to_uc(uc).lower()),
            map_uc_type_to_glue(uc),
        )


if __name__ == "__main__":
    unittest.main()
