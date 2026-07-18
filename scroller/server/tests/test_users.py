def test_returns_401_when_me_without_auth(client) -> None:
    response = client.get("/users/me")

    assert response.status_code == 401


def test_returns_verified_user_when_me_is_requested(client, verified_auth_headers) -> None:
    response = client.get("/users/me", headers=verified_auth_headers)

    assert response.status_code == 200
    payload = response.json()
    assert payload["display_name"] == "Verified"
    assert payload["email"] == "verified@example.com"
    assert payload["email_verified"] is True


def test_updates_display_name_when_profile_is_patched(client, verified_auth_headers) -> None:
    response = client.patch(
        "/users/me",
        headers=verified_auth_headers,
        json={"display_name": "Joseph"},
    )

    assert response.status_code == 200
    assert response.json()["display_name"] == "Joseph"

    me = client.get("/users/me", headers=verified_auth_headers).json()
    assert me["display_name"] == "Joseph"
