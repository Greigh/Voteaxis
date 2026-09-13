import { describe, expect, test } from "bun:test";
import {
  ALPHABET,
  CODE_LENGTH,
  normalizeCode,
  normalizeToken,
  randomCode,
  randomToken,
} from "../src/codes";

describe("friend codes", () => {
  test("alphabet has no 0 O 1 I L", () => {
    expect(ALPHABET).not.toMatch(/[01IOL]/);
    expect(CODE_LENGTH).toBe(6);
  });

  test("randomCode is six unambiguous characters", () => {
    const code = randomCode();
    expect(code).toHaveLength(6);
    expect(normalizeCode(code)).toBe(code);
  });

  test("normalizeCode uppercases and strips separators", () => {
    expect(normalizeCode("a2-b3-c4")).toBe("A2B3C4");
    expect(normalizeCode("ab-c12z")).toBeNull();
    expect(normalizeCode("A2B3C")).toBeNull();
    expect(normalizeCode("A2B3C0")).toBeNull();
  });

  test("randomToken is 48 hex chars", () => {
    expect(randomToken()).toMatch(/^[0-9a-f]{48}$/);
  });

  test("normalizeToken accepts only server-shaped hex", () => {
    const minted = randomToken();
    expect(normalizeToken(minted)).toBe(minted);
    expect(normalizeToken(minted.toUpperCase())).toBe(minted);
    expect(normalizeToken("aaaaaaaaaaaaaaaa")).toBeUndefined();
    expect(normalizeToken("not-a-token")).toBeUndefined();
    expect(normalizeToken(`${minted}ff`)).toBeUndefined();
  });
});
