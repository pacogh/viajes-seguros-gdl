import { NextRequest } from "next/server";
import { createHash } from "node:crypto";
import { z } from "zod";
import { errorResponse, json, requireSameOrigin } from "@/lib/auth/http";
import { verifyPassword } from "@/lib/auth/passwords";
import { createSession } from "@/lib/auth/sessions";
import { query } from "@/lib/db/queries";
const schema = z.object({ identifier: z.string().trim().min(3).max(320), password: z.string().min(1).max(128) });
export async function POST(req: NextRequest) {
  try {
    requireSameOrigin(req); const { identifier, password } = schema.parse(await req.json());
    const normalized = identifier.toLowerCase(); const digits=normalized.replace(/\D/g,""); const phoneNormalized=digits.length>=10&&!normalized.includes("@")?"+52"+digits.slice(-10):normalized; const ip = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || "unknown";
    const key = createHash("sha256").update(`${normalized}|${ip}`).digest("hex");
    const allowed = await query<{allowed:boolean}>("SELECT viajes.is_login_allowed($1) allowed", [key]);
    if (!allowed.rows[0]?.allowed) return json({ error: "Demasiados intentos. Intenta más tarde." }, 429);
    const { rows } = await query<{user_id:string;password_hash:string;account_status:string}>("SELECT user_id,password_hash,account_status FROM viajes.users WHERE email_normalized=$1 OR phone_e164=$2 LIMIT 1", [normalized, phoneNormalized]);
    const user = rows[0];
    if (!user || user.account_status !== "active" || !(await verifyPassword(password, user.password_hash))) {
      await query("SELECT viajes.record_login_failure($1,$2,$3)", [key, Number(process.env.LOGIN_LIMIT || 10), Number(process.env.LOGIN_WINDOW_MINUTES || 15)]);
      return json({ error: user?.account_status === "pending_email" ? "Verifica tu correo antes de entrar." : "Correo/teléfono o contraseña incorrectos." }, 401);
    }
    await query("SELECT viajes.clear_login_failures($1)", [key]); await createSession(user.user_id);
    return json({ ok: true });
  } catch (e) { return errorResponse(e); }
}
