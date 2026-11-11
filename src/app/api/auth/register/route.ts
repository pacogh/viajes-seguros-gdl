import { NextRequest } from "next/server";
import { z } from "zod";
import { hashPassword } from "@/lib/auth/passwords";
import { makeToken } from "@/lib/auth/tokens";
import { errorResponse, json, requireSameOrigin } from "@/lib/auth/http";
import { query } from "@/lib/db/queries";
import { sendEmail } from "@/lib/mail/sender";

const schema = z.object({ name: z.string().trim().min(1).max(160), email: z.email().transform(v => v.trim().toLowerCase()), phone: z.string().regex(/^\d{10}$/), password: z.string().min(8).max(128) });
export async function POST(req: NextRequest) {
  try {
    requireSameOrigin(req); const body = schema.parse(await req.json());
    const phone = "+52" + body.phone;
    const password = await hashPassword(body.password);
    const { rows } = await query<{user_id:string}>("SELECT viajes.register_passenger($1,$2,$3,$4) AS user_id", [body.name, body.email, phone, password]);
    const { token, hash } = makeToken(); const hours = Number(process.env.TOKEN_HOURS || 24);
    await query("INSERT INTO viajes.auth_email_tokens(user_id,token_hash,purpose,expires_at) VALUES($1,$2,'verify_email',now()+make_interval(hours=>$3))", [rows[0].user_id, hash, hours]);
    const url = `${process.env.APP_URL}/api/auth/verify?token=${encodeURIComponent(token)}`;
    await sendEmail({ to: body.email, subject: "Verifica tu correo", text: `Abre este enlace para activar tu cuenta: ${url}` });
    return json({ message: "Revisa tu correo para activar tu cuenta." }, 201);
  } catch (e) { return errorResponse(e); }
}
