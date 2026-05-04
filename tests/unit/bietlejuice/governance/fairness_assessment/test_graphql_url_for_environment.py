import unittest

from bietlejuice.governance.fairness_assessment.constants import (
    DATAHUB_GRAPHQL_URL_FORNO,
    DATAHUB_GRAPHQL_URL_PROD,
    graphql_url_for_environment,
)


class TestGraphqlUrlForEnvironment(unittest.TestCase):
    def test_forno(self):
        self.assertEqual(
            graphql_url_for_environment("forno"), DATAHUB_GRAPHQL_URL_FORNO
        )
        self.assertEqual(
            graphql_url_for_environment("  ForNo  "), DATAHUB_GRAPHQL_URL_FORNO
        )

    def test_prod_default(self):
        self.assertEqual(graphql_url_for_environment("prod"), DATAHUB_GRAPHQL_URL_PROD)
        self.assertEqual(graphql_url_for_environment(""), DATAHUB_GRAPHQL_URL_PROD)
        self.assertEqual(
            graphql_url_for_environment("staging"), DATAHUB_GRAPHQL_URL_PROD
        )
