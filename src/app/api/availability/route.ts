import { NextRequest } from "next/server";
import { errorResponse, json } from "@/lib/auth/http";
import { requireRole } from "@/lib/auth/sessions";
import { query } from "@/lib/db/queries";
export async function GET(req:NextRequest) { try { await requireRole("passenger"); const from=req.nextUrl.searchParams.get("from"); const through=req.nextUrl.searchParams.get("through"); if(!from||!through) return json({error:"from y through son requeridos"},400); const {rows}=await query("SELECT slot_start,slot_end,to_char((slot_start AT TIME ZONE 'America/Mexico_City')::date,'YYYY-MM-DD') AS slot_day FROM viajes.get_available_slots($1::date,$2::date,now())",[from,through]); const config=await query<{trip_duration_minutes:number}>("SELECT trip_duration_minutes FROM viajes.app_settings WHERE singleton"); return json({slots:rows,durationMinutes:config.rows[0]?.trip_duration_minutes??60}); } catch(e) { return errorResponse(e); } }
