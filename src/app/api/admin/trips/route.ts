import { errorResponse,json } from "@/lib/auth/http";
import { requireRole } from "@/lib/auth/sessions";
import { query } from "@/lib/db/queries";
export async function GET(){try{await requireRole("admin");const {rows}=await query("SELECT t.trip_id,t.starts_at,t.ends_at,t.status,t.origin_address,t.destination_address,t.created_at,u.full_name,u.email,u.phone_e164 FROM viajes.trips t JOIN viajes.users u ON u.user_id=t.passenger_id ORDER BY t.starts_at DESC");return json({trips:rows});}catch(e){return errorResponse(e)}}
