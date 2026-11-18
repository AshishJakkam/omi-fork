"""The self-host operator switch must be inert unless a deployment opts in.

`OMI_SELFHOST_UNLIMITED` exists so a backend you run reports unlimited allowances and
treats every plan as paid. That is the entire point of self-hosting: the plan catalog
belongs to whoever operates the server. These cases pin both directions, because a
switch that leaks into a deployment that did not set it would give away a product.
"""

import os

import pytest

from models.users import PlanType
from utils import subscription


@pytest.fixture(autouse=True)
def _clear_flag(monkeypatch):
    monkeypatch.delenv(subscription.SELFHOST_UNLIMITED_ENV, raising=False)


def test_flag_off_leaves_the_free_plan_metered():
    assert subscription.selfhost_unlimited_enabled() is False
    assert subscription.is_paid_plan(PlanType.basic) is False

    limits = subscription.get_plan_limits(PlanType.basic)
    assert limits.transcription_seconds == 18000
    assert limits.chat_questions_per_month == 30


def test_flag_on_unlocks_every_allowance(monkeypatch):
    monkeypatch.setenv(subscription.SELFHOST_UNLIMITED_ENV, 'true')

    assert subscription.selfhost_unlimited_enabled() is True
    # Every plan counts as paid, which is what stops the client offering an upgrade.
    assert subscription.is_paid_plan(PlanType.basic) is True

    limits = subscription.get_plan_limits(PlanType.basic)
    # None is the catalog's spelling of "unlimited", so nothing is enforced as exhausted.
    assert limits.transcription_seconds is None
    assert limits.words_transcribed is None
    assert limits.insights_gained is None
    assert limits.chat_questions_per_month is None
    assert limits.chat_cost_usd_per_month is None


@pytest.mark.parametrize('value', ['1', 'true', 'TRUE', 'yes', 'on', ' true '])
def test_truthy_spellings(monkeypatch, value):
    monkeypatch.setenv(subscription.SELFHOST_UNLIMITED_ENV, value)
    assert subscription.selfhost_unlimited_enabled() is True


@pytest.mark.parametrize('value', ['', '0', 'false', 'off', 'no', 'enabled'])
def test_everything_else_stays_off(monkeypatch, value):
    monkeypatch.setenv(subscription.SELFHOST_UNLIMITED_ENV, value)
    assert subscription.selfhost_unlimited_enabled() is False
