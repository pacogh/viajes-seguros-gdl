import { query } from "@/lib/db/queries";
type Message = { to: string; subject: string; text: string; html?: string };
export async function sendEmail(message: Message) {
  const daily = Number(process.env.MAIL_DAILY_CAP || 300), monthly = Number(process.env.MAIL_MONTHLY_CAP || 9000);
  const { rows } = await query<{allowed:boolean}>("SELECT viajes.reserve_email_quota(now(),$1,$2) AS allowed", [daily, monthly]);
  if (!rows[0]?.allowed) throw new Error("Se alcanzó el límite de correo configurado");
  const apiKey = process.env.BREVO_API_KEY;
  const senderEmail = process.env.BREVO_SENDER_EMAIL;
  const senderName = process.env.BREVO_SENDER_NAME;
  if (!apiKey || !senderEmail || !senderName) {
    if (process.env.NODE_ENV === "development") { console.info("Correo de desarrollo:", message.to, message.subject, message.text); return; }
    throw new Error("La API de Brevo y el remitente no están configurados");
  }
  const response = await fetch("https://api.brevo.com/v3/smtp/email", {
    method: "POST",
    headers: { accept: "application/json", "api-key": apiKey, "content-type": "application/json" },
    body: JSON.stringify({
      sender: { email: senderEmail, name: senderName },
      to: [{ email: message.to }],
      subject: message.subject,
      textContent: message.text,
      ...(message.html ? { htmlContent: message.html } : {}),
    }),
    signal: AbortSignal.timeout(10_000),
  });
  if (!response.ok) throw new Error(`Brevo rechazó el correo (HTTP ${response.status})`);
}
export async function flushTripEmails(limit = 20) {
  const { rows } = await query<{email_id:string;recipient:string;template_key:string;payload:Record<string,unknown>}>("WITH picked AS (SELECT email_id FROM viajes.email_outbox WHERE (status IN ('queued','failed') OR (status='sending' AND available_at<=now())) AND available_at<=now() ORDER BY queued_at LIMIT $1 FOR UPDATE SKIP LOCKED) UPDATE viajes.email_outbox e SET status='sending', attempts=attempts+1, available_at=now()+interval '10 minutes' FROM picked WHERE e.email_id=picked.email_id RETURNING e.email_id,e.recipient,e.template_key,e.payload", [limit]);
  for (const item of rows) {
    try { const { tripStatusEmail } = await import("./templates"); const message = tripStatusEmail(item.template_key, item.payload); await sendEmail({ to: item.recipient, ...message }); await query("UPDATE viajes.email_outbox SET status='sent',sent_at=now(),last_error=NULL WHERE email_id=$1", [item.email_id]); }
    catch (error) { await query("UPDATE viajes.email_outbox SET status='failed',last_error=$2,available_at=now()+interval '10 minutes' WHERE email_id=$1", [item.email_id, error instanceof Error ? error.message : "Error de correo"]); }
  }
}
