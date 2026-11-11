import { NextRequest } from "next/server";
import { z } from "zod";
import { hashPassword } from "@/lib/auth/passwords";
import { createSession } from "@/lib/auth/sessions";
import { errorResponse, json, requireSameOrigin } from "@/lib/auth/http";
import { query } from "@/lib/db/queries";
const schema = z.object({ name:z.string().trim().min(1).max(160), email:z.email(), phone:z.string().regex(/^\d{10}$/), password:z.string().min(8).max(128) });
export async function POST(req:NextRequest) { try { requireSameOrigin(req); const b=schema.parse(await req.json()); const phone="+52"+b.phone.replace(/\D/g,"").slice(-10); const hash=await hashPassword(b.password); const {rows}=await query<{user_id:string}>("SELECT viajes.claim_initial_admin($1,$2,$3,$4) user_id",[b.name,b.email.toLowerCase(),phone,hash]); await createSession(rows[0].user_id); return json({ok:true},201); } catch(e) { return errorResponse(e); } }
