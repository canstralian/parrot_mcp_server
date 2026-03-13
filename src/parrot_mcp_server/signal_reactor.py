"""Signal Reactor — the nervous system of the Parrot MCP Server.

Async event bus: signals flow from emitters through the reactor to registered
module hooks.  All hooks run concurrently via asyncio.gather; a single slow
hook never blocks the others.

Signal flow:
    [Emitter] --> {SignalReactor.emit(signal, data)}
                        |
              [registered hooks]
              /         |         \\
         [Hook A]  [Hook B]  [SecurityCore]
                                   |
                           {ImmunityCheck}
                           PASS / QUARANTINE
"""
from __future__ import annotations

import asyncio
import logging
import time
from collections.abc import Callable, Coroutine
from typing import Any, Optional

logger = logging.getLogger(__name__)

# Type alias: hooks must be async callables that accept arbitrary data.
HookFn = Callable[[Any], Coroutine[Any, Any, None]]


class SignalReactor:
    """Non-blocking event bus.

    Usage:
        reactor = SignalReactor()
        reactor.connect("tool_call", my_async_handler)
        await reactor.emit("tool_call", payload)
    """

    def __init__(self, timeout_ms: int = 500, max_concurrency: Optional[int] = None) -> None:
        self._hooks: dict[str, list[HookFn]] = {}
        # Per-signal timeout in seconds; prevents a runaway hook stalling emit.
        self._timeout_s: float = timeout_ms / 1000.0
        # Optional concurrency limit for hook execution; when unset or <= 0
        # all hooks for a signal are fanned out concurrently.
        self._max_concurrency: Optional[int] = (
            max_concurrency if isinstance(max_concurrency, int) and max_concurrency > 0 else None
        )
        if self._max_concurrency is not None:
            # Semaphore enforces the maximum number of hooks running at once.
            self._semaphore: asyncio.Semaphore | None = asyncio.Semaphore(self._max_concurrency)
        else:
            self._semaphore = None

    # ------------------------------------------------------------------
    # Wiring API
    # ------------------------------------------------------------------

    def connect(self, signal: str, callback: HookFn) -> None:
        """Wire *callback* into *signal*.  Idempotent per (signal, callback) pair."""
        bucket = self._hooks.setdefault(signal, [])
        if callback not in bucket:
            bucket.append(callback)
            callback_name = getattr(callback, "__qualname__", repr(callback))
            logger.debug(
                "[msgid:%d] SignalReactor: connected %s -> %s",
                time.time_ns(),
                signal,
                callback_name,
            )

    def disconnect(self, signal: str, callback: HookFn) -> None:
        """Remove *callback* from *signal*.  No-op if not registered."""
        if signal in self._hooks:
            self._hooks[signal] = [h for h in self._hooks[signal] if h is not callback]

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
            logger.debug("[msgid:%d] SignalReactor: no hooks for signal '%s'", time.time_ns(), signal)
            return

        # If no concurrency limit is configured, preserve the existing behavior
        # of fanning out all hooks at once. When a limit is set, use a semaphore
        # to cap the number of hooks executing concurrently.
        if self._semaphore is None:
            tasks = [self._guarded(hook, signal, data) for hook in hooks]
        else:
            tasks = [self._run_with_semaphore(hook, signal, data) for hook in hooks]

        await asyncio.gather(*tasks)

    async def _run_with_semaphore(self, hook: HookFn, signal: str, data: Any) -> None:
        """Acquire the concurrency semaphore before running a hook."""
        # _run_with_semaphore is only used when self._semaphore is not None.
        assert self._semaphore is not None
        async with self._semaphore:
            await self._guarded(hook, signal, data)

    async def _guarded(self, hook: HookFn, signal: str, data: Any) -> None:
        """Run *hook* with a timeout; log but never propagate exceptions."""
        msgid = time.time_ns()
        hook_name = getattr(hook, "__qualname__", repr(hook))
        try:
            await asyncio.wait_for(hook(data), timeout=self._timeout_s)
        except TimeoutError:
            logger.warning(
                "[msgid:%d] SignalReactor: hook %s timed out on signal '%s' (%.3fs)",
                msgid,
                hook_name,
                signal,
                self._timeout_s,
            )
        except Exception:
            logger.exception(
                "[msgid:%d] SignalReactor: hook %s raised on signal '%s'",
                msgid,
                hook_name,
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
        return len(self._hooks.get(signal, []))
