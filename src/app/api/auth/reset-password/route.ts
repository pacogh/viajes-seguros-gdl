import { NextRequest } from "next/server";
import { z } from "zod";
import { hashPassword } from "@/lib/auth/passwords";
import { tokenHash } from "@/lib/auth/tokens";
import { errorResponse, json, requireSameOrigin } from "@/lib/auth/http";
import { withTransaction } from "@/lib/db/pool";
export async function POST(req: NextRequest) {
  try {
    requireSameOrigin(req); const { token, password } = z.object({ token: z.string().min(10), password: z.string().min(8).max(128) }).parse(await req.json()); const hash = await hashPassword(password); const digest = tokenHash(token);
    await withTransaction(async c => { const { rows } = await c.query("SELECT user_id FROM viajes.auth_email_tokens WHERE token_hash=$1 AND purpose='reset_password' AND consumed_at IS NULL AND expires_at>now() FOR UPDATE", [digest]); if (!rows[0]) throw new Error("Enlace inválido o expirado"); await c.query("UPDATE viajes.auth_email_tokens SET consumed_at=now() WHERE token_hash=$1", [digest]); await c.query("UPDATE viajes.users SET password_hash=$2,updated_at=now() WHERE user_id=$1", [rows[0].user_id, hash]); await c.query("UPDATE viajes.sessions SET revoked_at=now() WHERE user_id=$1 AND revoked_at IS NULL", [rows[0].user_id]); });
    return json({ ok: true });
  } catch (e) { return errorResponse(e); }
}
