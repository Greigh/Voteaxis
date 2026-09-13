import { describe, expect, test } from "bun:test";
import {
  CONTRIBUTE_OFFERS,
  DEFAULT_CONTRIBUTE_SKU,
  isContributeSku,
  offerForSku,
} from "../lib/contribute";

describe("contribute catalog", () => {
  test("default amount is the typical one-time offer", () => {
    expect(DEFAULT_CONTRIBUTE_SKU).toBe("tip_15");
    expect(offerForSku("tip_15").amountCents).toBe(1500);
  });

  test("one-time amounts and yearly Sustainer are defined", () => {
    expect(CONTRIBUTE_OFFERS.map((row) => row.sku)).toEqual([
      "tip_5",
      "tip_15",
      "tip_30",
      "sustainer_year",
    ]);
    expect(offerForSku("tip_5").amountCents).toBe(500);
    expect(offerForSku("tip_30").amountCents).toBe(3000);
    expect(offerForSku("sustainer_year")).toMatchObject({
      amountCents: 2500,
      mode: "subscription",
      interval: "year",
    });
  });

  test("rejects unknown skus", () => {
    expect(isContributeSku("tip_15")).toBe(true);
    expect(isContributeSku("cycle_pass")).toBe(false);
    expect(isContributeSku("pro")).toBe(false);
  });
});
