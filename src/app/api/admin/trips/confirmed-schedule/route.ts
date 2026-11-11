import { errorResponse, json } from "@/lib/auth/http";
import { requireRole } from "@/lib/auth/sessions";
import { query } from "@/lib/db/queries";

export async function GET() {
  try {
    await requireRole("admin");
    const { rows } = await query<{ trip_id: string; starts_at: string; ends_at: string; full_name: string; phone_e164: string }>(
      "SELECT t.trip_id, t.starts_at, t.ends_at, u.full_name, u.phone_e164 FROM viajes.trips t JOIN viajes.users u ON u.user_id = t.passenger_id WHERE t.status = 'confirmed' ORDER BY t.starts_at",
    );
    return json({ trips: rows });
  } catch (error) {
    return errorResponse(error);
  }
}
