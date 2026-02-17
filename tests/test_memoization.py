"""Tests for time-bound memoization utilities."""

from __future__ import annotations

import asyncio
import time
from unittest.mock import Mock

import pytest

# Import directly from module to avoid heavy dependencies in __init__
import sys
from pathlib import Path

# Add parent to path for direct import
sys.path.insert(0, str(Path(__file__).parent.parent))

from tribal_village_env.memoization import (
    DEFAULT_CLEANUP_INTERVAL,
    DEFAULT_MAX_AGE,
    FRAME_CACHE_MAX_AGE,
    TimedMemoCache,
    agent_pos_key,
    cache_key,
    create_frame_cache,
    memoize,
    memoize_sync,
    pos_key,
)


class TestMemoizeSync:
    """Tests for synchronous memoization decorator."""

    def test_caches_result(self):
        call_count = 0

        @memoize_sync(max_age=1.0)
        def expensive_fn(x: int) -> int:
            nonlocal call_count
            call_count += 1
            return x * 2

        # First call computes
        result1 = expensive_fn(5)
        assert result1 == 10
        assert call_count == 1

        # Second call uses cache
        result2 = expensive_fn(5)
        assert result2 == 10
        assert call_count == 1

    def test_different_args_computed_separately(self):
        call_count = 0

        @memoize_sync(max_age=1.0)
        def expensive_fn(x: int) -> int:
            nonlocal call_count
            call_count += 1
            return x * 2

        result1 = expensive_fn(5)
        result2 = expensive_fn(10)
        assert result1 == 10
        assert result2 == 20
        assert call_count == 2

    def test_expires_after_max_age(self):
        call_count = 0

        @memoize_sync(max_age=0.05)
        def expensive_fn(x: int) -> int:
            nonlocal call_count
            call_count += 1
            return x * 2

        result1 = expensive_fn(5)
        assert call_count == 1

        # Wait for expiration
        time.sleep(0.06)

        result2 = expensive_fn(5)
        assert result2 == 10
        assert call_count == 2

    def test_kwargs_included_in_cache_key(self):
        call_count = 0

        @memoize_sync(max_age=1.0)
        def expensive_fn(x: int, multiplier: int = 1) -> int:
            nonlocal call_count
            call_count += 1
            return x * multiplier

        result1 = expensive_fn(5, multiplier=2)
        result2 = expensive_fn(5, multiplier=3)
        assert result1 == 10
        assert result2 == 15
        assert call_count == 2


class TestMemoizeAsync:
    """Tests for async memoization decorator."""

    def test_caches_result(self):
        call_count = 0

        @memoize(max_age=1.0)
        async def expensive_fn(x: int) -> int:
            nonlocal call_count
            call_count += 1
            return x * 2

        async def run_test():
            result1 = await expensive_fn(5)
            assert result1 == 10
            assert call_count == 1

            result2 = await expensive_fn(5)
            assert result2 == 10
            assert call_count == 1

        asyncio.run(run_test())

    def test_expires_after_max_age(self):
        call_count = 0

        @memoize(max_age=0.05)
        async def expensive_fn(x: int) -> int:
            nonlocal call_count
            call_count += 1
            return x * 2

        async def run_test():
            result1 = await expensive_fn(5)
            assert call_count == 1

            await asyncio.sleep(0.06)

            result2 = await expensive_fn(5)
            assert result2 == 10
            assert call_count == 2

        asyncio.run(run_test())


class TestTimedMemoCache:
    """Tests for TimedMemoCache class."""

    def test_get_caches_result(self):
        cache: TimedMemoCache[int, int] = TimedMemoCache(max_age=1.0)
        compute = Mock(return_value=42)

        result1 = cache.get(1, compute)
        result2 = cache.get(1, compute)

        assert result1 == 42
        assert result2 == 42
        assert compute.call_count == 1

    def test_get_expires_after_max_age(self):
        cache: TimedMemoCache[int, int] = TimedMemoCache(max_age=0.05)
        compute = Mock(return_value=42)

        result1 = cache.get(1, compute)
        assert compute.call_count == 1

        time.sleep(0.06)

        result2 = cache.get(1, compute)
        assert result2 == 42
        assert compute.call_count == 2

    def test_get_with_arg(self):
        cache: TimedMemoCache[int, int] = TimedMemoCache(max_age=1.0)

        def compute(x: int) -> int:
            return x * 2

        result = cache.get_with_arg(5, 10, compute)
        assert result == 20

    def test_get_with_2_args(self):
        cache: TimedMemoCache[int, int] = TimedMemoCache(max_age=1.0)

        def compute(x: int, y: int) -> int:
            return x + y

        result = cache.get_with_2_args(5, 10, 20, compute)
        assert result == 30

    def test_invalidate(self):
        cache: TimedMemoCache[int, int] = TimedMemoCache(max_age=1.0)
        compute = Mock(return_value=42)

        cache.get(1, compute)
        assert compute.call_count == 1

        cache.invalidate(1)
        cache.get(1, compute)
        assert compute.call_count == 2

    def test_clear(self):
        cache: TimedMemoCache[int, int] = TimedMemoCache(max_age=1.0)
        compute = Mock(return_value=42)

        cache.get(1, compute)
        cache.get(2, compute)
        assert len(cache) == 2

        cache.clear()
        assert len(cache) == 0

    def test_contains_checks_expiration(self):
        cache: TimedMemoCache[int, int] = TimedMemoCache(max_age=0.05)
        cache.get(1, lambda: 42)

        assert 1 in cache
        time.sleep(0.06)
        assert 1 not in cache

    def test_cleanup_removes_expired(self):
        cache: TimedMemoCache[int, int] = TimedMemoCache(
            max_age=0.05, cleanup_interval=0.01
        )
        cache.get(1, lambda: 42)
        cache.get(2, lambda: 43)

        assert len(cache) == 2
        time.sleep(0.06)
        cache.cleanup()
        assert len(cache) == 0

    def test_max_age_property(self):
        cache: TimedMemoCache[int, int] = TimedMemoCache(max_age=1.0)
        assert cache.max_age == 1.0

        cache.max_age = 2.0
        assert cache.max_age == 2.0


class TestCreateFrameCache:
    """Tests for frame cache factory."""

    def test_creates_short_lived_cache(self):
        cache = create_frame_cache()
        assert cache.max_age == FRAME_CACHE_MAX_AGE
        assert cache.max_age < 0.1  # Should be very short


class TestCacheKeyHelpers:
    """Tests for cache key helper functions."""

    def test_pos_key(self):
        key1 = pos_key(10, 20)
        key2 = pos_key(10, 20)
        key3 = pos_key(20, 10)

        assert key1 == key2
        assert key1 != key3

    def test_pos_key_handles_negative(self):
        key1 = pos_key(-10, -20)
        key2 = pos_key(-10, -20)
        key3 = pos_key(10, 20)

        assert key1 == key2
        assert key1 != key3

    def test_agent_pos_key(self):
        key1 = agent_pos_key(0, 10, 20)
        key2 = agent_pos_key(0, 10, 20)
        key3 = agent_pos_key(1, 10, 20)
        key4 = agent_pos_key(0, 20, 10)

        assert key1 == key2
        assert key1 != key3
        assert key1 != key4

    def test_cache_key(self):
        key1 = cache_key(1, "a", (2, 3))
        key2 = cache_key(1, "a", (2, 3))
        key3 = cache_key(1, "b", (2, 3))

        assert key1 == key2
        assert key1 != key3
        assert isinstance(key1, tuple)


class TestDefaultConstants:
    """Tests for module constants."""

    def test_default_max_age(self):
        assert DEFAULT_MAX_AGE == 1.0

    def test_default_cleanup_interval(self):
        assert DEFAULT_CLEANUP_INTERVAL == 5.0

    def test_frame_cache_max_age(self):
        assert FRAME_CACHE_MAX_AGE == 0.02
