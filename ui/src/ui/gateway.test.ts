import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { GatewayBrowserClient } from "./gateway.ts";

type CloseListener = (evt: { code: number; reason?: string }) => void;
type GenericListener = (evt?: unknown) => void;

class FakeWebSocket {
  static CONNECTING = 0;
  static OPEN = 1;
  static CLOSING = 2;
  static CLOSED = 3;
  static instances: FakeWebSocket[] = [];

  readonly url: string;
  readyState = FakeWebSocket.CONNECTING;
  private listeners = new Map<string, Set<GenericListener>>();

  constructor(url: string) {
    this.url = url;
    FakeWebSocket.instances.push(this);
  }

  addEventListener(type: string, listener: GenericListener) {
    if (!this.listeners.has(type)) {
      this.listeners.set(type, new Set());
    }
    this.listeners.get(type)?.add(listener);
  }

  send(_data: string) {
    // noop
  }

  close(code = 1000, reason = "") {
    this.readyState = FakeWebSocket.CLOSED;
    this.emitClose(code, reason);
  }

  emitClose(code: number, reason = "") {
    const listeners = this.listeners.get("close");
    if (!listeners) {
      return;
    }
    const event = { code, reason };
    for (const listener of listeners as Set<CloseListener>) {
      listener(event);
    }
  }
}

describe("GatewayBrowserClient reconnect policy", () => {
  const originalWebSocket = globalThis.WebSocket;

  beforeEach(() => {
    vi.useFakeTimers();
    FakeWebSocket.instances = [];
    Object.defineProperty(globalThis, "WebSocket", {
      configurable: true,
      writable: true,
      value: FakeWebSocket,
    });
  });

  afterEach(() => {
    vi.useRealTimers();
    Object.defineProperty(globalThis, "WebSocket", {
      configurable: true,
      writable: true,
      value: originalWebSocket,
    });
  });

  it("does not reconnect after unauthorized close", () => {
    const client = new GatewayBrowserClient({ url: "ws://127.0.0.1:18789" });
    client.start();
    expect(FakeWebSocket.instances).toHaveLength(1);

    FakeWebSocket.instances[0]?.emitClose(
      1008,
      "unauthorized: gateway token missing (open a tokenized dashboard URL)",
    );
    vi.advanceTimersByTime(20_000);

    expect(FakeWebSocket.instances).toHaveLength(1);
  });

  it("reconnects after transient close", () => {
    const client = new GatewayBrowserClient({ url: "ws://127.0.0.1:18789" });
    client.start();
    expect(FakeWebSocket.instances).toHaveLength(1);

    FakeWebSocket.instances[0]?.emitClose(1006, "abnormal closure");
    vi.advanceTimersByTime(801);

    expect(FakeWebSocket.instances).toHaveLength(2);
  });
});
