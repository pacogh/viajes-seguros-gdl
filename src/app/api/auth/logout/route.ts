import { NextRequest } from "next/server";
import { errorResponse, json, requireSameOrigin } from "@/lib/auth/http";
import { revokeSession } from "@/lib/auth/sessions";
export async function POST(req: NextRequest) { try { requireSameOrigin(req); await revokeSession(); return json({ ok: true }); } catch (e) { return errorResponse(e); } }
