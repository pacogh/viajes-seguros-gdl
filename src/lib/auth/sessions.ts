import { cookies } from "next/headers";
import { query } from "@/lib/db/queries";
import { makeToken, tokenHash } from "./tokens";

const cookieName = () => process.env.SESSION_COOKIE_NAME || "viajes_session";
export async function createSession(userId: string) {
  const { token, hash } = makeToken();
  const days = Number(process.env.SESSION_DAYS || 14);
  await query("INSERT INTO viajes.sessions(user_id,token_hash,expires_at) VALUES($1,$2,now()+make_interval(days=>$3))", [userId, hash, days]);
  const jar = await cookies(); jar.set(cookieName(), token, { httpOnly: true, secure: process.env.NODE_ENV === "production", sameSite: "lax", path: "/", maxAge: days * 86400 });
}
export async function getSession() {
  const jar = await cookies(); const token = jar.get(cookieName())?.value;
  if (!token) return null;
  const { rows } = await query<{user_id:string;role:string;full_name:string;email:string}>("SELECT u.user_id,u.role,u.full_name,u.email FROM viajes.sessions s JOIN viajes.users u USING(user_id) WHERE s.token_hash=$1 AND s.revoked_at IS NULL AND s.expires_at>now() AND u.account_status='active'", [tokenHash(token)]);
  return rows[0] ?? null;
}
export async function revokeSession() {
  const jar = await cookies(); const token = jar.get(cookieName())?.value;
  if (token) await query("UPDATE viajes.sessions SET revoked_at=now() WHERE token_hash=$1 AND revoked_at IS NULL", [tokenHash(token)]);
  jar.delete(cookieName());
}
export async function requireRole(role: "admin" | "passenger") { const user = await getSession(); if (!user || user.role !== role) throw new Error("UNAUTHORIZED"); return user; }
