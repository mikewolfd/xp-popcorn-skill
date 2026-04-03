"""Tests for service module."""

from datetime import datetime, timedelta

import pytest

from src.models import CouponCode, DiscountRule, Order, Product
from src.service import apply_coupon, apply_order_discount, calculate_discount


def test_apply_order_discount_basic():
    order = Order(
        products=[Product("Widget", 100.0, "gadgets")],
        created_at=datetime.now(),
        customer_id="cust-1",
    )
    result = apply_order_discount(order, 10.0)
    assert result == 90.0


def test_apply_order_discount_below_minimum():
    order = Order(
        products=[Product("Tiny", 5.0, "gadgets")],
        created_at=datetime.now(),
        customer_id="cust-2",
    )
    result = apply_order_discount(order, 50.0)
    assert result == 5.0  # No discount applied


def test_calculate_discount_basic():
    """Test that a single valid rule applies correctly."""
    price = 100.0
    rule = DiscountRule(
        name="Summer Sale",
        percentage=10.0,
        priority=1,
        expires_at=datetime.now() + timedelta(days=1),
    )
    result = calculate_discount(price, [rule])
    assert result == 90.0


def test_calculate_discount_highest_priority_wins():
    """Test that the highest priority rule is applied when multiple rules are valid."""
    price = 100.0
    rules = [
        DiscountRule(
            name="Low Priority Sale",
            percentage=5.0,
            priority=1,
            expires_at=datetime.now() + timedelta(days=1),
        ),
        DiscountRule(
            name="High Priority Sale",
            percentage=20.0,
            priority=10,
            expires_at=datetime.now() + timedelta(days=1),
        ),
        DiscountRule(
            name="Medium Priority Sale",
            percentage=15.0,
            priority=5,
            expires_at=datetime.now() + timedelta(days=1),
        ),
    ]
    result = calculate_discount(price, rules)
    # 20% discount from the highest priority rule
    assert result == 80.0


def test_calculate_discount_expired_filtered():
    """Test that expired rules are skipped."""
    price = 100.0
    rules = [
        DiscountRule(
            name="Expired Sale",
            percentage=50.0,
            priority=10,
            expires_at=datetime.now() - timedelta(days=1),
        ),
        DiscountRule(
            name="Active Sale",
            percentage=10.0,
            priority=1,
            expires_at=datetime.now() + timedelta(days=1),
        ),
    ]
    result = calculate_discount(price, rules)
    # Should apply the active rule, ignoring the expired one
    assert result == 90.0


def test_calculate_discount_no_valid_rules():
    """Test that original price is returned when all rules are expired."""
    price = 100.0
    rules = [
        DiscountRule(
            name="Expired Sale 1",
            percentage=50.0,
            priority=10,
            expires_at=datetime.now() - timedelta(days=1),
        ),
        DiscountRule(
            name="Expired Sale 2",
            percentage=25.0,
            priority=5,
            expires_at=datetime.now() - timedelta(hours=1),
        ),
    ]
    result = calculate_discount(price, rules)
    assert result == 100.0


def test_calculate_discount_empty_rules():
    """Test that original price is returned when no rules are provided."""
    price = 100.0
    result = calculate_discount(price, [])
    assert result == 100.0


def test_calculate_discount_no_expiration():
    """Test that rules with expires_at=None are always considered valid."""
    price = 100.0
    rule = DiscountRule(
        name="Permanent Discount",
        percentage=15.0,
        priority=1,
        expires_at=None,
    )
    result = calculate_discount(price, [rule])
    assert result == 85.0


def test_calculate_discount_zero_percentage():
    """Test edge case: 0% discount returns original price."""
    price = 100.0
    rule = DiscountRule(
        name="No Discount",
        percentage=0.0,
        priority=1,
        expires_at=datetime.now() + timedelta(days=1),
    )
    result = calculate_discount(price, [rule])
    assert result == 100.0


def test_calculate_discount_full_discount():
    """Test edge case: 100% discount returns 0."""
    price = 100.0
    rule = DiscountRule(
        name="Free",
        percentage=100.0,
        priority=1,
        expires_at=datetime.now() + timedelta(days=1),
    )
    result = calculate_discount(price, [rule])
    assert result == 0.0


def test_calculate_discount_same_priority():
    """Test that when multiple rules have the same priority, the first in sorted order is applied."""
    price = 100.0
    rules = [
        DiscountRule(
            name="Same Priority A",
            percentage=10.0,
            priority=5,
            expires_at=datetime.now() + timedelta(days=1),
        ),
        DiscountRule(
            name="Same Priority B",
            percentage=20.0,
            priority=5,
            expires_at=datetime.now() + timedelta(days=1),
        ),
    ]
    result = calculate_discount(price, rules)
    # When priorities are equal, Python's sort is stable, so order matters
    # The first rule in the original list is the first in sorted order (both have same priority)
    # This will apply the first rule's percentage
    assert result == 90.0


def test_calculate_discount_fractional_percentage():
    """Test that fractional percentages are applied correctly."""
    price = 100.0
    rule = DiscountRule(
        name="Fractional Discount",
        percentage=33.333,
        priority=1,
        expires_at=datetime.now() + timedelta(days=1),
    )
    result = calculate_discount(price, [rule])
    expected = 100.0 * (1 - 33.333 / 100)
    assert abs(result - expected) < 0.001  # Allow for floating-point rounding


def test_calculate_discount_negative_percentage():
    """Test edge case: negative percentage increases price (markup instead of discount)."""
    price = 100.0
    rule = DiscountRule(
        name="Markup",
        percentage=-10.0,
        priority=1,
        expires_at=datetime.now() + timedelta(days=1),
    )
    result = calculate_discount(price, [rule])
    # -10% discount is a 10% markup
    assert abs(result - 110.0) < 0.000001


def test_calculate_discount_very_small_price():
    """Test with very small price values."""
    price = 0.01
    rule = DiscountRule(
        name="Test",
        percentage=50.0,
        priority=1,
        expires_at=datetime.now() + timedelta(days=1),
    )
    result = calculate_discount(price, [rule])
    assert abs(result - 0.005) < 0.000001


def test_calculate_discount_very_large_price():
    """Test with very large price values."""
    price = 1000000.0
    rule = DiscountRule(
        name="Test",
        percentage=10.0,
        priority=1,
        expires_at=datetime.now() + timedelta(days=1),
    )
    result = calculate_discount(price, [rule])
    assert result == 900000.0


# --- apply_coupon tests ---


def _make_order(total_price: float) -> Order:
    """Helper to create an order with a single product at the given price."""
    return Order(
        products=[Product("Item", total_price, "general")],
        created_at=datetime.now(),
        customer_id="cust-test",
    )


def _make_coupon(percentage: float = 10.0, max_uses: int = 5, current_uses: int = 0,
                 active: bool = True, expires_at=None) -> CouponCode:
    """Helper to create a coupon with sensible defaults."""
    if expires_at is None:
        expires_at = datetime.now() + timedelta(days=30)
    return CouponCode(
        code="SAVE10",
        discount_rule=DiscountRule(
            name="Test Discount",
            percentage=percentage,
            priority=1,
            expires_at=expires_at,
        ),
        max_uses=max_uses,
        current_uses=current_uses,
        active=active,
    )


def test_apply_coupon_basic():
    """Test basic coupon application returns discounted total."""
    order = _make_order(100.0)
    coupon = _make_coupon(percentage=10.0)
    result = apply_coupon(order, coupon)
    assert result == 90.0


def test_apply_coupon_increments_usage():
    """Test that apply_coupon increments current_uses."""
    order = _make_order(100.0)
    coupon = _make_coupon(percentage=10.0, max_uses=5, current_uses=0)
    apply_coupon(order, coupon)
    assert coupon.current_uses == 1


def test_apply_coupon_inactive_raises():
    """Test that an inactive coupon raises ValueError."""
    order = _make_order(100.0)
    coupon = _make_coupon(active=False)
    with pytest.raises(ValueError, match="not active"):
        apply_coupon(order, coupon)


def test_apply_coupon_max_uses_reached_raises():
    """Test that a fully-used coupon raises ValueError."""
    order = _make_order(100.0)
    coupon = _make_coupon(max_uses=3, current_uses=3)
    with pytest.raises(ValueError, match="maximum number of uses"):
        apply_coupon(order, coupon)


def test_apply_coupon_expired_rule_raises():
    """Test that a coupon with an expired discount rule raises ValueError (cascading validation)."""
    order = _make_order(100.0)
    coupon = _make_coupon(
        percentage=50.0,
        expires_at=datetime.now() - timedelta(days=1),
    )
    with pytest.raises(ValueError, match="expired"):
        apply_coupon(order, coupon)


def test_apply_coupon_full_discount():
    """Test 100% coupon discount returns 0."""
    order = _make_order(100.0)
    coupon = _make_coupon(percentage=100.0)
    result = apply_coupon(order, coupon)
    assert result == 0.0


def test_apply_coupon_zero_discount():
    """Test 0% coupon discount returns original total."""
    order = _make_order(100.0)
    coupon = _make_coupon(percentage=0.0)
    result = apply_coupon(order, coupon)
    assert result == 100.0


def test_apply_coupon_empty_code_raises():
    """Test that a coupon with empty code raises ValueError."""
    order = _make_order(100.0)
    coupon = CouponCode(
        code="",
        discount_rule=DiscountRule("Discount", 10.0, 1, datetime.now() + timedelta(days=1)),
        max_uses=5,
    )
    with pytest.raises(ValueError, match="empty"):
        apply_coupon(order, coupon)
