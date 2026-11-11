export function tripStatusEmail(key: string, payload: Record<string, unknown>) {
  const labels: Record<string,string> = { trip_pending: "Solicitud recibida", trip_confirmed: "Viaje confirmado", trip_rejected: "Solicitud rechazada", trip_cancelled_by_passenger: "Solicitud cancelada", trip_cancelled_by_admin: "Viaje cancelado por administración" };
  const title = labels[key] ?? "Actualización de viaje";
  const date = new Date(String(payload.startsAt)).toLocaleString("es-MX", { timeZone: "America/Mexico_City", dateStyle: "long", timeStyle: "short" });
  const text = `${title}\nFecha y hora: ${date}\n${payload.origin ? `Origen: ${payload.origin}\n` : ""}${payload.destination ? `Destino: ${payload.destination}\n` : ""}`;
  return { subject: title, text };
}
