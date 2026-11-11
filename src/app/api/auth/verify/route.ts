import { NextRequest, NextResponse } from "next/server";
import { tokenHash } from "@/lib/auth/tokens";
import { withTransaction } from "@/lib/db/pool";
export async function GET(req: NextRequest) {
  const token = req.nextUrl.searchParams.get("token");
  if (!token) return NextResponse.redirect(new URL("/?error=token", req.url));
  try {
    await withTransaction(async c => {
      const { rows } = await c.query("SELECT user_id FROM viajes.auth_email_tokens WHERE token_hash=$1 AND purpose='verify_email' AND consumed_at IS NULL AND expires_at>now() FOR UPDATE", [tokenHash(token)]);
      if (!rows[0]) throw new Error("El enlace expiró o ya fue usado");
      await c.query("UPDATE viajes.auth_email_tokens SET consumed_at=now() WHERE token_hash=$1", [tokenHash(token)]);
      await c.query("UPDATE viajes.users SET account_status='active',email_verified_at=now(),updated_at=now() WHERE user_id=$1 AND role='passenger'", [rows[0].user_id]);
    });
    return NextResponse.redirect(new URL("/login?verified=1", req.url));
  } catch { return NextResponse.redirect(new URL("/login?error=token", req.url)); }
}
