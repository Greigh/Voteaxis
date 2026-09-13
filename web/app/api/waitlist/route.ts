import { NextResponse } from "next/server";
import { clientIp, createRateLimiter } from "@/lib/rate-limit";
import { joinWaitlist } from "@/lib/waitlist";

// Each accepted signup sends mail through the box's own Postfix and may POST
// the configured webhook, so this route is the one worth metering. Generous
// enough that a person fixing a typo never sees it.
const allow = createRateLimiter(5, 10 * 60 * 1000);

export async function POST(request: Request) {
  if (!allow(clientIp(request))) {
    return NextResponse.json(
      { ok: false, error: "Too many signups. Try again in a few minutes." },
      { status: 429, headers: { "retry-after": "600" } },
    );
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json(
      { ok: false, error: "Invalid request." },
      { status: 400 },
    );
  }

  const payload =
    typeof body === "object" && body !== null
      ? (body as { email?: unknown; roles?: unknown })
      : {};
  const email = typeof payload.email === "string" ? payload.email : "";

  const result = await joinWaitlist(email, payload.roles);
  if (!result.ok) {
    return NextResponse.json(
      { ok: false, error: result.error },
      { status: result.status },
    );
  }

  // `result.alreadyJoined` is deliberately NOT echoed. Returning it turned this
  // route into a membership oracle: anyone could POST an address and learn from
  // the response whether that person had signed up. The caller gets the same
  // answer either way; the distinction stays server-side for the mail path.
  return NextResponse.json({ ok: true });
}
