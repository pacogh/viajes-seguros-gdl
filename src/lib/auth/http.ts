import { NextResponse } from "next/server";
export const json = (data: unknown, status = 200) => NextResponse.json(data, { status });
export function errorResponse(error: unknown) {
  if (process.env.NODE_ENV === "development") console.error("Error de API:", error);
  const message = error instanceof Error ? error.message : "Error interno";
  const code = (error as { code?: string })?.code;
  if (message === "Invalid URL") return json({ error: "La conexión a la base de datos está mal configurada. Revisa DATABASE_URL en .env.local." }, 500);
  if (message === "UNAUTHORIZED") return json({ error: "Inicia sesión para continuar" }, 401);
  if (code === "23P01") return json({ error: "Ese horario acaba de ocuparse. Actualiza la disponibilidad." }, 409);
  if (code === "23505") return json({ error: "El correo o teléfono ya está registrado" }, 409);
  if (["22P02", "23514", "22007", "22008"].includes(code || "")) return json({ error: "Revisa los datos ingresados." }, 400);
  if (message === "Solicitud de origen no permitido") return json({ error: message }, 403);
  const isDomainError = /required|invalid|must|outside|unavailable|already|match|configured|active|Only|conflict|overlap|duration|expired|cannot|not found/i.test(message);
  return json({ error: isDomainError ? message : "No pudimos completar la operación. Intenta de nuevo." }, isDomainError ? 400 : 500);
}
export function requireSameOrigin(request: Request) {
  const origin = request.headers.get("origin");
  if (!origin) throw new Error("Solicitud de origen no permitido");

  const originUrl = new URL(origin);
  const requestUrl = new URL(request.url);
  const host = request.headers.get("host") || requestUrl.host;
  const forwardedProtocol = request.headers.get("x-forwarded-proto")?.split(",")[0].trim();
  const protocol = forwardedProtocol ? `${forwardedProtocol}:` : requestUrl.protocol;
  const expectedOrigin = new URL(`${protocol}//${host}`).origin;

  if (originUrl.origin !== expectedOrigin) throw new Error("Solicitud de origen no permitido");
}
