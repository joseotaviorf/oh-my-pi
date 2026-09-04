import pytest

from identity import IdentityError, trino_user_from_oauth_token
from tests.jwt_util import make_jwt


def test_email_claim_wins():
    token = make_jwt(
        {
            "email": "ada@quintoandar.com.br",
            "preferred_username": "other",
            "sub": "uuid",
        }
    )
    assert trino_user_from_oauth_token(token) == "ada@quintoandar.com.br"


def test_preferred_username_when_no_email():
    token = make_jwt({"preferred_username": "ada@quintoandar.com.br", "sub": "uuid"})
    assert trino_user_from_oauth_token(token) == "ada@quintoandar.com.br"


def test_upn_when_no_email_or_preferred_username():
    token = make_jwt({"upn": "ada@quintoandar.com.br", "sub": "uuid"})
    assert trino_user_from_oauth_token(token) == "ada@quintoandar.com.br"


def test_email_like_sub():
    token = make_jwt({"sub": "ada@quintoandar.com.br"})
    assert trino_user_from_oauth_token(token) == "ada@quintoandar.com.br"


def test_opaque_token_is_error():
    with pytest.raises(IdentityError, match="not a JWT"):
        trino_user_from_oauth_token("opaque-token")


def test_sub_not_email_without_other_claims():
    token = make_jwt({"sub": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"})
    with pytest.raises(IdentityError, match="no usable identity claim"):
        trino_user_from_oauth_token(token)
