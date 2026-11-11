import { NextRequest } from "next/server";
import { errorResponse, json, requireSameOrigin } from "@/lib/auth/http";
import { requireRole } from "@/lib/auth/sessions";
import { query } from "@/lib/db/queries";
import { flushTripEmails } from "@/lib/mail/sender";
export async function POST(req:NextRequest,{params}:{params:Promise<{id:string}>}) { try { requireSameOrigin(req); const u=await requireRole("passenger"); const {id}=await params; await query("SELECT viajes.cancel_pending_trip($1,$2)",[id,u.user_id]); await flushTripEmails(); return json({ok:true}); } catch(e) { return errorResponse(e); } }
