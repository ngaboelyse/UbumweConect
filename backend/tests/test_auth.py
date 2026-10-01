"""
Tests for authentication endpoints.
"""
import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_register_success(async_client: AsyncClient):
    """Test successful user registration."""
    response = await async_client.post("/api/v1/auth/register", json={
        "email": "new_register@example.com",
        "username": "new_register_user",
        "display_name": "New User",
        "password": "SecurePass@123",
        "preferred_language": "english"
    })
    assert response.status_code == 201
    data = response.json()
    assert "access_token" in data
    assert "refresh_token" in data
    assert data["token_type"] == "bearer"
    assert data["user"]["email"] == "new_register@example.com"
    assert data["user"]["username"] == "new_register_user"
    assert "hashed_password" not in data["user"]


@pytest.mark.asyncio
async def test_register_duplicate_email(async_client: AsyncClient):
    """Test that registering with a duplicate email fails with 409."""
    payload = {
        "email": "duplicate_test@example.com",
        "username": "dup_user_a",
        "display_name": "Dup User A",
        "password": "SecurePass@123",
        "preferred_language": "english"
    }
    first = await async_client.post("/api/v1/auth/register", json=payload)
    assert first.status_code == 201

    payload["username"] = "dup_user_b"
    second = await async_client.post("/api/v1/auth/register", json=payload)
    assert second.status_code == 409
    assert "email" in second.json()["detail"].lower()


@pytest.mark.asyncio
async def test_register_duplicate_username(async_client: AsyncClient):
    """Test that registering with a duplicate username fails with 409."""
    payload = {
        "email": "unique_email_a@example.com",
        "username": "same_username",
        "display_name": "User A",
        "password": "SecurePass@123",
        "preferred_language": "english"
    }
    await async_client.post("/api/v1/auth/register", json=payload)

    payload["email"] = "unique_email_b@example.com"
    response = await async_client.post("/api/v1/auth/register", json=payload)
    assert response.status_code == 409


@pytest.mark.asyncio
@pytest.mark.parametrize("weak_password", [
    "password",        # No uppercase, number, special char
    "12345678",        # No letters
    "ALLUPPERCASE!1",  # No lowercase
    "Short@1",         # Too short
    "nouppercase@123", # No uppercase
])
async def test_register_weak_password(async_client: AsyncClient, weak_password: str):
    """Test that weak passwords are rejected with 422."""
    response = await async_client.post("/api/v1/auth/register", json={
        "email": f"weak_{weak_password[:5]}@example.com",
        "username": f"weak_user_{weak_password[:5]}",
        "display_name": "Weak User",
        "password": weak_password,
        "preferred_language": "english"
    })
    assert response.status_code == 422, f"Expected rejection for password: {weak_password}"


@pytest.mark.asyncio
async def test_register_invalid_language(async_client: AsyncClient):
    """Test that unsupported preferred_language is rejected."""
    response = await async_client.post("/api/v1/auth/register", json={
        "email": "lang_test@example.com",
        "username": "lang_test_user",
        "display_name": "Lang Test",
        "password": "SecurePass@123",
        "preferred_language": "mandarin"  # Not supported
    })
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_login_success(async_client: AsyncClient, test_user: dict):
    """Test successful login with correct credentials."""
    response = await async_client.post("/api/v1/auth/login", json={
        "email": "testuser@example.com",
        "password": "SecurePass@123"
    })
    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert "refresh_token" in data


@pytest.mark.asyncio
async def test_login_wrong_password(async_client: AsyncClient, test_user: dict):
    """Test login with incorrect password returns 401."""
    response = await async_client.post("/api/v1/auth/login", json={
        "email": "testuser@example.com",
        "password": "WrongPassword@123"
    })
    assert response.status_code == 401


@pytest.mark.asyncio
async def test_login_unknown_email(async_client: AsyncClient):
    """Test login with non-existent email returns 401."""
    response = await async_client.post("/api/v1/auth/login", json={
        "email": "nobody@example.com",
        "password": "SecurePass@123"
    })
    assert response.status_code == 401


@pytest.mark.asyncio
async def test_get_me_authenticated(async_client: AsyncClient, auth_headers: dict):
    """Test /me endpoint returns user data for authenticated request."""
    response = await async_client.get("/api/v1/auth/me", headers=auth_headers)
    assert response.status_code == 200
    data = response.json()
    assert "id" in data
    assert "email" in data
    assert "preferred_language" in data
    assert "hashed_password" not in data


@pytest.mark.asyncio
async def test_get_me_unauthenticated(async_client: AsyncClient):
    """Test /me endpoint returns 401 without auth header."""
    response = await async_client.get("/api/v1/auth/me")
    assert response.status_code == 401


@pytest.mark.asyncio
async def test_get_me_invalid_token(async_client: AsyncClient):
    """Test /me endpoint with a tampered JWT returns 401."""
    response = await async_client.get(
        "/api/v1/auth/me",
        headers={"Authorization": "Bearer this.is.not.a.valid.jwt"}
    )
    assert response.status_code == 401


@pytest.mark.asyncio
async def test_token_refresh(async_client: AsyncClient, test_user_tokens: dict):
    """Test exchanging refresh token for new access token."""
    response = await async_client.post("/api/v1/auth/refresh", json={
        "refresh_token": test_user_tokens["refresh_token"]
    })
    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    # New token should differ from original
    assert data["access_token"] != test_user_tokens["access_token"]


@pytest.mark.asyncio
async def test_token_refresh_invalid(async_client: AsyncClient):
    """Test that invalid refresh token returns 401."""
    response = await async_client.post("/api/v1/auth/refresh", json={
        "refresh_token": "invalid-refresh-token"
    })
    assert response.status_code == 401


@pytest.mark.asyncio
async def test_logout(async_client: AsyncClient, auth_headers: dict, test_user_tokens: dict):
    """Test logout invalidates the session."""
    # Logout
    response = await async_client.post("/api/v1/auth/logout", headers=auth_headers)
    assert response.status_code == 200

    # Refresh token should now be invalid
    refresh_response = await async_client.post("/api/v1/auth/refresh", json={
        "refresh_token": test_user_tokens["refresh_token"]
    })
    assert refresh_response.status_code == 401


@pytest.mark.asyncio
async def test_register_all_supported_languages(async_client: AsyncClient):
    """Test registration with each supported language."""
    languages = ["kinyarwanda", "english", "french", "swahili"]
    for i, lang in enumerate(languages):
        response = await async_client.post("/api/v1/auth/register", json={
            "email": f"lang_test_{i}@example.com",
            "username": f"lang_test_{i}",
            "display_name": f"Lang Test {i}",
            "password": "SecurePass@123",
            "preferred_language": lang
        })
        assert response.status_code == 201, f"Failed for language: {lang}"
        assert response.json()["user"]["preferred_language"] == lang
