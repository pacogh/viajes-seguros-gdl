import { NextRequest } from "next/server";
import { errorResponse, json, requireSameOrigin } from "@/lib/auth/http";
import { requireRole } from "@/lib/auth/sessions";
import { query } from "@/lib/db/queries";
import { flushTripEmails } from "@/lib/mail/sender";
import { z } from "zod";
const address=z.string().trim().max(500).nullable().optional();
export async function GET() { try { const user=await requireRole("passenger"); const {rows}=await query("SELECT trip_id,starts_at,ends_at,status,origin_address,destination_address,created_at FROM viajes.trips WHERE passenger_id=$1 ORDER BY starts_at DESC",[user.user_id]); return json({trips:rows}); } catch(e) { return errorResponse(e); } }
export async function POST(req:NextRequest) { try { requireSameOrigin(req); const user=await requireRole("passenger"); const b=z.object({startsAt:z.string().datetime(),origin:address,destination:address}).parse(await req.json()); const originAddress=b.origin?.trim()||null,destinationAddress=b.destination?.trim()||null; const {rows}=await query("SELECT * FROM viajes.create_trip_request($1,$2::timestamptz,$3,$4::geometry(Point,4326),$5,$6::geometry(Point,4326))",[user.user_id,b.startsAt,originAddress,null,destinationAddress,null]); await flushTripEmails(); return json(rows[0],201); } catch(e) { return errorResponse(e); } }
