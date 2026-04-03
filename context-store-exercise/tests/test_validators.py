"""Tests for validators module."""

from datetime import datetime, timedelta

from src.models import DiscountRule
from src.validators import validate_discount_percent, validate_discount_rule


def test_valid_discount():
    assert validate_discount_percent(25.0) == []


def test_negative_discount():
    errors = validate_discount_percent(-5.0)
    assert len(errors) == 1
    assert "negative" in errors[0].lower()


def test_exceeds_max_discount():
    errors = validate_discount_percent(105.0)
    assert len(errors) == 1
    assert "exceed" in errors[0].lower()


def test_valid_discount_rule():
    """Test that a valid discount rule returns no errors."""
    rule = DiscountRule(
        name="Summer Sale",
        percentage=15.0,
        priority=1,
        expires_at=datetime.now() + timedelta(days=30)
    )
    assert validate_discount_rule(rule) == []


def test_expired_rule():
    """Test that a rule with expires_at in the past is invalid."""
    rule = DiscountRule(
        name="Expired Sale",
        percentage=10.0,
        priority=1,
        expires_at=datetime.now() - timedelta(days=1)
    )
    errors = validate_discount_rule(rule)
    assert len(errors) == 1
    assert "expired" in errors[0].lower()


def test_negative_percentage_rule():
    """Test that a rule with negative percentage is invalid."""
    rule = DiscountRule(
        name="Bad Discount",
        percentage=-5.0,
        priority=1,
        expires_at=datetime.now() + timedelta(days=30)
    )
    errors = validate_discount_rule(rule)
    assert len(errors) == 1
    assert "negative" in errors[0].lower()


def test_percentage_over_100_rule():
    """Test that a rule with percentage over 100 is invalid."""
    rule = DiscountRule(
        name="Extreme Discount",
        percentage=150.0,
        priority=1,
        expires_at=datetime.now() + timedelta(days=30)
    )
    errors = validate_discount_rule(rule)
    assert len(errors) == 1
    assert "exceed" in errors[0].lower()


def test_empty_name_rule():
    """Test that a rule with empty name is invalid."""
    rule = DiscountRule(
        name="",
        percentage=10.0,
        priority=1,
        expires_at=datetime.now() + timedelta(days=30)
    )
    errors = validate_discount_rule(rule)
    assert len(errors) == 1
    assert "empty" in errors[0].lower()


def test_whitespace_only_name_rule():
    """Test that a rule with whitespace-only name is invalid."""
    rule = DiscountRule(
        name="   ",
        percentage=10.0,
        priority=1,
        expires_at=datetime.now() + timedelta(days=30)
    )
    errors = validate_discount_rule(rule)
    assert len(errors) == 1
    assert "empty" in errors[0].lower()


def test_multiple_errors():
    """Test that a rule with multiple errors reports all of them."""
    rule = DiscountRule(
        name="",
        percentage=-10.0,
        priority=1,
        expires_at=datetime.now() - timedelta(days=1)
    )
    errors = validate_discount_rule(rule)
    assert len(errors) == 3
    error_text = " ".join(errors).lower()
    assert "empty" in error_text
    assert "negative" in error_text
    assert "expired" in error_text
