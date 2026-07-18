import pytest

from src.retry import call_with_retries, is_transient_error


class FakeServerError(Exception):
    def __init__(self, code: int):
        super().__init__(f"{code} error")
        self.code = code


class FakeHttpStatusError(Exception):
    def __init__(self, status_code: int):
        super().__init__(f"HTTP {status_code}")

        class _Response:
            pass

        self.response = _Response()
        self.response.status_code = status_code


def test_is_transient_error_returns_true_when_code_is_503():
    assert is_transient_error(FakeServerError(503)) is True


def test_is_transient_error_returns_true_when_response_status_code_is_500():
    assert is_transient_error(FakeHttpStatusError(500)) is True


def test_is_transient_error_returns_false_when_code_is_400():
    assert is_transient_error(FakeServerError(400)) is False


def test_is_transient_error_returns_false_when_error_has_no_status():
    assert is_transient_error(ValueError("bad input")) is False


def test_returns_result_without_sleeping_when_first_attempt_succeeds():
    sleeps: list[float] = []

    result = call_with_retries(
        lambda: "ok",
        description="test call",
        sleep=sleeps.append,
    )

    assert result == "ok"
    assert sleeps == []


def test_retries_after_15_second_delay_when_transient_error_then_success():
    sleeps: list[float] = []
    attempts = {"count": 0}

    def flaky():
        attempts["count"] += 1
        if attempts["count"] == 1:
            raise FakeServerError(503)
        return "recovered"

    result = call_with_retries(flaky, description="test call", sleep=sleeps.append)

    assert result == "recovered"
    assert attempts["count"] == 2
    assert sleeps == [15]


def test_raises_last_error_after_three_retries_when_all_attempts_fail_transiently():
    sleeps: list[float] = []
    attempts = {"count": 0}

    def always_503():
        attempts["count"] += 1
        raise FakeServerError(503)

    with pytest.raises(FakeServerError):
        call_with_retries(always_503, description="test call", sleep=sleeps.append)

    assert attempts["count"] == 4  # initial attempt + 3 retries
    assert sleeps == [15, 15, 15]


def test_raises_immediately_without_retry_when_error_is_not_transient():
    attempts = {"count": 0}

    def bad_request():
        attempts["count"] += 1
        raise FakeServerError(400)

    with pytest.raises(FakeServerError):
        call_with_retries(bad_request, description="test call", sleep=lambda _: None)

    assert attempts["count"] == 1
