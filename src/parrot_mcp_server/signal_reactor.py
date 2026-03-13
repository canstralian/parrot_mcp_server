"""Signal Reactor — the nervous system of the Parrot MCP Server.

Async event bus: signals flow from emitters through the reactor to registered
module hooks.  All hooks run concurrently via asyncio.gather; a single slow
hook never blocks the others.

Signal flow:
    [Emitter] --> {SignalReactor.emit(signal, data)}
                        |
                [registered hooks]
               /         |         \\
         [Hook A]    [Hook B]   [SecurityCore]
                                      |
                               {ImmunityCheck}
                              PASS / QUARANTINE
"""

from __future__ import annotations

import asyncio
import logging
import time
from collections.abc import Callable, Coroutine
from typing import Any

logger = logging.getLogger(__name__)

# Type alias: hooks must be async callables that accept arbitrary data.
HookFn = Callable[[Any], Coroutine[Any, Any, None]]


class SignalReactor:
    """Non-blocking event bus.

    Uses a ``set`` per signal so that registering the same callable twice is
    idempotent — no duplicate executions on emit.

    Usage::

        reactor = SignalReactor()
        reactor.connect("tool_call", my_async_handler)
        await reactor.emit("tool_call", payload)
    """

    def __init__(self, timeout_ms: int = 500, max_concurrency: int | None = None) -> None:
        # Sets prevent duplicate hook registrations per signal.
        self._hooks: dict[str, set[HookFn]] = {}
        # Per-signal timeout in seconds; prevents a runaway hook stalling emit.
        self._timeout_s: float = timeout_ms / 1000.0
        # Optional semaphore to cap total concurrent hook executions.
        self._sem: asyncio.Semaphore | None = (
            asyncio.Semaphore(max_concurrency) if max_concurrency else None
        )

    # ------------------------------------------------------------------
    # Wiring API
    # ------------------------------------------------------------------

    def connect(self, signal: str, callback: HookFn) -> None:
        """Wire *callback* into *signal*.  Idempotent per (signal, callback) pair."""
        self._hooks.setdefault(signal, set()).add(callback)
        logger.debug(
            "[msgid:%d] SignalReactor: connected %s -> %s",
            time.time_ns(),
            signal,
            getattr(callback, "__qualname__", getattr(callback, "__name__", repr(callback))),
        )

    def disconnect(self, signal: str, callback: HookFn) -> None:
        """Remove *callback* from *signal*.  No-op if not registered."""
        if signal in self._hooks:
            self._hooks[signal].discard(callback)
        logger.debug(
            "[msgid:%d] SignalReactor: disconnected %s -> %s",
            time.time_ns(),
            signal,
            getattr(callback, "__qualname__", getattr(callback, "__name__", repr(callback))),
        )

    # ------------------------------------------------------------------
    # Dispatch
    # ------------------------------------------------------------------

    async def emit(self, signal: str, data: Any = None) -> None:
        """Dispatch *signal* to all registered hooks concurrently.

        Each hook runs inside an individual timeout guard so a single slow
        hook does not block the rest.  Exceptions are logged and swallowed
        — the reactor must not crash the caller.
        """
        hooks = self._hooks.get(signal)
        if not hooks:
            logger.debug(
                "[msgid:%d] SignalReactor: no hooks for signal '%s'",
                time.time_ns(),
                signal,
            )
            return

        tasks = [self._guarded(hook, signal, data) for hook in hooks]
        await asyncio.gather(*tasks)

    async def _guarded(self, hook: HookFn, signal: str, data: Any) -> None:
        """Run *hook* with a timeout; log but never propagate exceptions."""
        msgid = time.time_ns()
        try:
            if self._sem:
                async with self._sem:
                    await asyncio.wait_for(hook(data), timeout=self._timeout_s)
            else:
                await asyncio.wait_for(hook(data), timeout=self._timeout_s)
        except TimeoutError:
            logger.warning(
                "[msgid:%d] SignalReactor: hook %s timed out on signal '%s' (%.3fs)",
                msgid,
                hook.__qualname__,
                signal,
                self._timeout_s,
            )
        except Exception:
            logger.exception(
                "[msgid:%d] SignalReactor: hook %s raised on signal '%s'",
                msgid,
                hook.__qualname__,
                signal,
            )

    # ------------------------------------------------------------------
    # Introspection
    # ------------------------------------------------------------------

    def registered_signals(self) -> list[str]:
        """Return signals that have at least one hook registered."""
        return [s for s, hooks in self._hooks.items() if hooks]

    def hook_count(self, signal: str) -> int:
        """Return number of hooks registered for *signal*."""
        return len(self._hooks.get(signal, set()))
