from hubspot import HubSpot

from bietlejuice.jobs.composer.base.api.api_enum import APIEnum
from bietlejuice.jobs.composer.base.validation_suites.executors.api_validation_suites_executor import (
    APIValidationSuitesExecutor,
)

"""
The HubSpot API Client throws an exception whenever there is any availability problem. Therefore, we don't
need to make any assertions. As long as the methods run to the end, we know there aren't any problems.
"""


class HubSpotValidationSuite(APIValidationSuitesExecutor):
    def __init__(self, auth):
        """
        :param auth: Authentication dictionary with all auths stored in Databricks Secrets.
         This is automatically filled by Validation Engine in IntegrationsValidator.run_validation_suites
        """
        super().__init__(auth)
        self.hubspot_client = HubSpot(access_token=auth[APIEnum.HUBSPOT]["token"])

    def validate_hubspot_companies(self):
        self.hubspot_client.crm.companies.basic_api.get_page()

    def validate_hubspot_contacts(self):
        self.hubspot_client.crm.contacts.basic_api.get_page()

    def validate_hubspot_deals(self):
        self.hubspot_client.crm.deals.basic_api.get_page()

    def validate_hubspot_tickets(self):
        self.hubspot_client.crm.tickets.basic_api.get_page()

    def validate_hubspot_owners(self):
        self.hubspot_client.crm.owners.owners_api.get_page()

    def validate_hubspot_pipelines(self):
        self.hubspot_client.crm.pipelines.pipelines_api.get_all(object_type="deal")
        self.hubspot_client.crm.pipelines.pipelines_api.get_all(object_type="ticket")

    def validate_hubspot_teams(self):
        self.hubspot_client.settings.users.teams_api.get_all()
