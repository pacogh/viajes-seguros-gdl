import { NextRequest } from "next/server";
import { z } from "zod";
import { makeToken } from "@/lib/auth/tokens";
import { errorResponse, json, requireSameOrigin } from "@/lib/auth/http";
import { query } from "@/lib/db/queries";
import { sendEmail } from "@/lib/mail/sender";
export async function POST(req: NextRequest) {
  try {
    requireSameOrigin(req); const { email } = z.object({ email: z.email() }).parse(await req.json());
    const { rows } = await query<{user_id:string}>("SELECT user_id FROM viajes.users WHERE email_normalized=$1 AND account_status='active'", [email.trim().toLowerCase()]);
    if (rows[0]) { const { token, hash } = makeToken(); await query("INSERT INTO viajes.auth_email_tokens(user_id,token_hash,purpose,expires_at) VALUES($1,$2,'reset_password',now()+interval '1 hour')", [rows[0].user_id, hash]); await sendEmail({ to: email, subject: "Restablece tu contraseña", text: `Abre el enlace para cambiar tu contraseña: ${process.env.APP_URL}/reset-password?token=${encodeURIComponent(token)}` }); }
    return json({ message: "Si existe una cuenta activa con ese correo, enviaremos un enlace." });
  } catch (e) { return errorResponse(e); }
}
