"""Time-bound memoization for evaluation caching.

Provides temporal memoization with timestamp-based cache invalidation.
Unlike step-based caching, this uses wall clock time which is ideal for:
- Game tree evaluations that become stale over real time
- Preventing unbounded memory growth in long sessions
- Caching expensive computations within frame boundaries

Pattern adopted from metta common/src/metta/common/util/memoization.py
"""

from __future__ import annotations

import time
from collections.abc import Awaitable, Callable, Hashable
from functools import wraps
from typing import Any, Generic, ParamSpec, TypeVar

P = ParamSpec("P")
T = TypeVar("T")
K = TypeVar("K", bound=Hashable)
V = TypeVar("V")

# Default cache parameters
DEFAULT_MAX_AGE = 1.0  # Default max age for cache entries (1 second)
DEFAULT_CLEANUP_INTERVAL = 5.0  # How often to purge expired entries
FRAME_CACHE_MAX_AGE = 0.02  # ~50 FPS frame time


def memoize(max_age: float) -> Callable[[Callable[P, Awaitable[T]]], Callable[P, Awaitable[T]]]:
    """Async time-bound memoization decorator.

    Caches function results with timestamp-based cache invalidation.
    Entries older than max_age seconds are considered stale.

    Args:
        max_age: Maximum age in seconds before cache entries expire.

    Returns:
        Decorator that wraps async functions with time-bound caching.

    Example:
        @memoize(max_age=1.0)
        async def expensive_evaluation(state_hash: int) -> float:
            # ... expensive computation ...
            return result
    """

    def decorator(func: Callable[P, Awaitable[T]]) -> Callable[P, Awaitable[T]]:
        cache: dict[tuple[Any, ...], tuple[T, float]] = {}

        @wraps(func)
        async def wrapper(*args: P.args, **kwargs: P.kwargs) -> T:
            key = (args, tuple(sorted(kwargs.items())))
            current_time = time.time()

            if key in cache:
                value, timestamp = cache[key]
                if current_time - timestamp < max_age:
                    return value

            result = await func(*args, **kwargs)
            cache[key] = (result, current_time)
            return result

        return wrapper

    return decorator


def memoize_sync(max_age: float) -> Callable[[Callable[P, T]], Callable[P, T]]:
    """Synchronous time-bound memoization decorator.

    Same as memoize() but for synchronous functions.

    Args:
        max_age: Maximum age in seconds before cache entries expire.

    Returns:
        Decorator that wraps sync functions with time-bound caching.

    Example:
        @memoize_sync(max_age=0.5)
        def score_enemy(agent_id: int, enemy_id: int) -> float:
            # ... expensive scoring ...
            return score
    """

    def decorator(func: Callable[P, T]) -> Callable[P, T]:
        cache: dict[tuple[Any, ...], tuple[T, float]] = {}

        @wraps(func)
        def wrapper(*args: P.args, **kwargs: P.kwargs) -> T:
            key = (args, tuple(sorted(kwargs.items())))
            current_time = time.time()

            if key in cache:
                value, timestamp = cache[key]
                if current_time - timestamp < max_age:
                    return value

            result = func(*args, **kwargs)
            cache[key] = (result, current_time)
            return result

        return wrapper

    return decorator


class TimedMemoCache(Generic[K, V]):
    """Generic time-bound memoization cache.

    Entries expire after max_age seconds. Provides explicit cache management
    for cases where decorator-based memoization isn't suitable.

    This mirrors the Nim implementation in src/scripted/memoization.nim.

    Args:
        max_age: Maximum age in seconds before cache entries expire.
        cleanup_interval: How often to purge expired entries (in seconds).

    Example:
        cache: TimedMemoCache[int, float] = TimedMemoCache(max_age=1.0)

        def get_evaluation(state_hash: int) -> float:
            return cache.get(state_hash, lambda: expensive_compute(state_hash))
    """

    def __init__(
        self,
        max_age: float = DEFAULT_MAX_AGE,
        cleanup_interval: float = DEFAULT_CLEANUP_INTERVAL,
    ) -> None:
        self._cache: dict[K, tuple[V, float]] = {}
        self._max_age = max_age
        self._cleanup_interval = cleanup_interval
        self._last_cleanup = time.time()

    @property
    def max_age(self) -> float:
        """Maximum age for cache entries in seconds."""
        return self._max_age

    @max_age.setter
    def max_age(self, value: float) -> None:
        """Set the maximum age for cache entries."""
        self._max_age = value

    def cleanup(self) -> None:
        """Remove all expired entries from the cache."""
        now = time.time()
        expired_keys = [
            key
            for key, (_, timestamp) in self._cache.items()
            if now - timestamp >= self._max_age
        ]
        for key in expired_keys:
            del self._cache[key]
        self._last_cleanup = now

    def _maybe_cleanup(self, now: float) -> None:
        """Run cleanup if enough time has passed since last cleanup."""
        if now - self._last_cleanup >= self._cleanup_interval:
            self.cleanup()

    def get(self, key: K, compute: Callable[[], V]) -> V:
        """Get cached value or compute and cache if stale/missing.

        Args:
            key: Cache key.
            compute: Zero-argument callable to compute the value if needed.

        Returns:
            Cached or freshly computed value.
        """
        now = time.time()
        self._maybe_cleanup(now)

        if key in self._cache:
            value, timestamp = self._cache[key]
            if now - timestamp < self._max_age:
                return value

        result = compute()
        self._cache[key] = (result, now)
        return result

    def get_with_arg(self, key: K, arg: Any, compute: Callable[[Any], V]) -> V:
        """Get cached value or compute with one argument.

        Args:
            key: Cache key.
            arg: Argument to pass to compute function.
            compute: Single-argument callable to compute the value.

        Returns:
            Cached or freshly computed value.
        """
        now = time.time()
        self._maybe_cleanup(now)

        if key in self._cache:
            value, timestamp = self._cache[key]
            if now - timestamp < self._max_age:
                return value

        result = compute(arg)
        self._cache[key] = (result, now)
        return result

    def get_with_2_args(
        self, key: K, arg1: Any, arg2: Any, compute: Callable[[Any, Any], V]
    ) -> V:
        """Get cached value or compute with two arguments.

        Args:
            key: Cache key.
            arg1: First argument to pass to compute function.
            arg2: Second argument to pass to compute function.
            compute: Two-argument callable to compute the value.

        Returns:
            Cached or freshly computed value.
        """
        now = time.time()
        self._maybe_cleanup(now)

        if key in self._cache:
            value, timestamp = self._cache[key]
            if now - timestamp < self._max_age:
                return value

        result = compute(arg1, arg2)
        self._cache[key] = (result, now)
        return result

    def invalidate(self, key: K) -> None:
        """Manually invalidate a specific cache entry."""
        self._cache.pop(key, None)

    def clear(self) -> None:
        """Clear all entries from the cache."""
        self._cache.clear()

    def __len__(self) -> int:
        """Return the number of entries (including potentially expired ones)."""
        return len(self._cache)

    def __contains__(self, key: K) -> bool:
        """Check if key exists and is not expired."""
        if key not in self._cache:
            return False
        _, timestamp = self._cache[key]
        return time.time() - timestamp < self._max_age


def create_frame_cache() -> TimedMemoCache[Any, Any]:
    """Create a frame-scoped cache (very short max age).

    Use for expensive evaluations that don't change within a frame.
    Max age is approximately one frame at 50 FPS.

    Returns:
        TimedMemoCache configured for frame-scoped caching.
    """
    return TimedMemoCache(max_age=FRAME_CACHE_MAX_AGE, cleanup_interval=1.0)


# ---------------------------------------------------------------------------
# Convenience: Cache key helpers
# ---------------------------------------------------------------------------


def pos_key(x: int, y: int) -> int:
    """Create a cache key from a position.

    Args:
        x: X coordinate.
        y: Y coordinate.

    Returns:
        Integer cache key combining both coordinates.
    """
    return (x << 32) | (y & 0xFFFFFFFF)


def agent_pos_key(agent_id: int, x: int, y: int) -> int:
    """Create a cache key combining agent ID and position.

    Uses high bits for agentId, low bits for position hash.

    Args:
        agent_id: Agent identifier.
        x: X coordinate.
        y: Y coordinate.

    Returns:
        Integer cache key combining agent and position.
    """
    return (agent_id << 48) | (x << 24) | (y & 0xFFFFFF)


def cache_key(*args: Hashable) -> tuple[Hashable, ...]:
    """Create a composite cache key from multiple values.

    Args:
        *args: Hashable values to combine into a key.

    Returns:
        Tuple suitable for use as a dictionary key.
    """
    return args
