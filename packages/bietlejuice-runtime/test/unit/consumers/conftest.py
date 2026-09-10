"""Mocks optional gsheets client deps before consumer unit tests import GsheetsConsumer."""

import sys
import types


class _GoogleSheetsReaderStub:
    """Minimal stand-in so GsheetsConsumer can subclass a real type in unit tests."""

    def __init__(self, gsheets_client):
        self.google_sheets_client = gsheets_client

    def read(self, sheet_name, sheet_id):
        return []


_gsheets_api_client = types.ModuleType("quintoandar_gsheets_api_client")
_consumer = types.ModuleType("quintoandar_gsheets_api_client.consumer")
_consumer.GoogleSheetsReader = _GoogleSheetsReaderStub
_clients = types.ModuleType("quintoandar_gsheets_api_client.clients")

sys.modules["quintoandar_gsheets_api_client"] = _gsheets_api_client
sys.modules["quintoandar_gsheets_api_client.consumer"] = _consumer
sys.modules["quintoandar_gsheets_api_client.clients"] = _clients
