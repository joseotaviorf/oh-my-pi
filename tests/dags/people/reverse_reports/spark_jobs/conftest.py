"""
Conftest for load_to_gsheet tests.

Mocks sys.modules for gspread, google.oauth2, and quintoandar_gsheets_api_client
before the test module imports load_to_gsheet (which requires these deps).
"""

import sys
from unittest.mock import MagicMock

sys.modules["quintoandar_gsheets_api_client"] = MagicMock()
sys.modules["quintoandar_gsheets_api_client.clients"] = MagicMock()
sys.modules["quintoandar_gsheets_api_client.producer"] = MagicMock()

MOCK_WORKSHEET_NOT_FOUND = type("WorksheetNotFound", (Exception,), {})
mock_gspread_exceptions = MagicMock()
mock_gspread_exceptions.WorksheetNotFound = MOCK_WORKSHEET_NOT_FOUND
sys.modules["gspread"] = MagicMock()
sys.modules["gspread.exceptions"] = mock_gspread_exceptions

sys.modules["google"] = MagicMock()
sys.modules["google.oauth2"] = MagicMock()
sys.modules["google.oauth2.service_account"] = MagicMock()
