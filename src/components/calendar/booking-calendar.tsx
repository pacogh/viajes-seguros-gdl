"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { dateKeyAddMonths, formatMexicoDate, localDateKey, monthEndKey, monthLabel, mexicoMonthStart, TZ } from "@/lib/date-time";

type Slot = { slot_start: string; slot_end: string; slot_day: string };
function clock(iso: string) {
  return new Intl.DateTimeFormat("es-MX", { timeZone: TZ, hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).format(new Date(iso));
}

export function BookingCalendar() {
  const [month, setMonth] = useState(mexicoMonthStart());
  const [slots, setSlots] = useState<Slot[]>([]);
  const [duration, setDuration] = useState(60);
  const [selectedDay, setSelectedDay] = useState("");
  const [selected, setSelected] = useState<Slot | null>(null);
  const [origin, setOrigin] = useState("");
  const [destination, setDestination] = useState("");
  const [notice, setNotice] = useState("");
  const [busy, setBusy] = useState(false);
  const [showSuccessModal, setShowSuccessModal] = useState(false);
  const confirmationButtonRef = useRef<HTMLButtonElement>(null);
  const router = useRouter();
  const maxMonth = dateKeyAddMonths(mexicoMonthStart(), 2);
  const successMessage = "Solicitud enviada. El horario queda reservado mientras espera confirmación.";

  useEffect(() => {
    if (!showSuccessModal) return;
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") setShowSuccessModal(false);
    };
    window.addEventListener("keydown", closeOnEscape);
    confirmationButtonRef.current?.focus();
    return () => window.removeEventListener("keydown", closeOnEscape);
  }, [showSuccessModal]);

  useEffect(() => {
    fetch(`/api/availability?from=${month}&through=${monthEndKey(month)}`)
      .then(r => r.json())
      .then(d => { setSlots(d.slots || []); setDuration(d.durationMinutes || 60); });
  }, [month]);

  const days = useMemo(() => Array.from(new Set(slots.map(s => s.slot_day))), [slots]);
  const daySlots = slots.filter(s => s.slot_day === selectedDay);
  const [year, monthNumber] = month.split("-").map(Number);
  const dayCount = new Date(Date.UTC(year, monthNumber, 0)).getUTCDate();
  const firstWeekday = new Date(Date.UTC(year, monthNumber - 1, 1)).getUTCDay();
  const calendarDays = [
    ...Array(firstWeekday).fill(""),
    ...Array.from({ length: dayCount }, (_, i) => `${month.slice(0, 8)}${String(i + 1).padStart(2, "0")}`),
  ];

  async function submit() {
    if (!selected) return;
    setBusy(true); setNotice(""); setShowSuccessModal(false);
    const r = await fetch("/api/trips", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ startsAt: selected.slot_start, origin: origin.trim() || null, destination: destination.trim() || null }) });
    const d = await r.json(); setBusy(false);
    if (!r.ok) { setNotice(d.error); return; }
    setNotice(successMessage); setShowSuccessModal(true);
    setSelected(null); setOrigin(""); setDestination("");
    const fresh = await fetch(`/api/availability?from=${month}&through=${monthEndKey(month)}`).then(x => x.json());
    setSlots(fresh.slots || []); router.refresh();
  }

  return <div className="content">
    <div className="heading-row">
      <div><span className="eyebrow">Agenda tu viaje</span><h1>Elige día y horario</h1><small>Duración: {duration} minutos · Horarios de Guadalajara.</small></div>
      <div className="month-navigation">
        <button className="secondary" disabled={month <= mexicoMonthStart()} onClick={() => { setSelectedDay(""); setSelected(null); setMonth(dateKeyAddMonths(month, -1)); }}>←</button>
        <strong>{monthLabel(month)}</strong>
        <button className="secondary" disabled={month >= maxMonth} onClick={() => { setSelectedDay(""); setSelected(null); setMonth(dateKeyAddMonths(month, 1)); }}>→</button>
      </div>
    </div>
    <div className="calendar-layout">
      <section className="card">
        <h2>Calendario</h2>
        <div className="month-grid">
          {["D", "L", "M", "M", "J", "V", "S"].map((d, i) => <span key={`${d}${i}`}>{d}</span>)}
          {calendarDays.map((day, index) => day
            ? <button key={day} disabled={!days.includes(day) || day < localDateKey()} className={`${days.includes(day) ? "has-slots" : ""} ${selectedDay === day ? "selected" : ""}`} onClick={() => { setSelectedDay(day); setSelected(null); }}>{Number(day.slice(-2))}</button>
            : <span key={`blank-${index}`} />)}
        </div>
        <small>Los días atenuados no tienen horarios disponibles.</small>
      </section>
      <section className="card">
        <h2>Horarios {selectedDay && `· ${formatMexicoDate(`${selectedDay}T12:00:00Z`)}`}</h2>
        <div className="slot-list">{daySlots.map(s => <button key={s.slot_start} className={`slot-button ${selected?.slot_start === s.slot_start ? "selected" : ""}`} onClick={() => setSelected(s)}>{clock(s.slot_start)}</button>)}</div>
        {!selectedDay && <p className="muted">Selecciona un día con horarios disponibles.</p>}
        {selectedDay && !daySlots.length && <p className="muted">No quedan horarios en este día.</p>}
      </section>
    </div>
    {selected && <section className="card content">
      <h2>Direcciones (opcionales)</h2><div className="location-fields"><label>Origen<textarea value={origin} onChange={e => setOrigin(e.target.value)} maxLength={500} rows={3} placeholder="Escribe la dirección de origen (opcional)" /></label><label>Destino<textarea value={destination} onChange={e => setDestination(e.target.value)} maxLength={500} rows={3} placeholder="Escribe la dirección de destino (opcional)" /></label></div>
      <div className="heading-row"><div><strong>{formatMexicoDate(selected.slot_start, true)}</strong><small> · Duración de {duration} minutos.</small></div><button onClick={submit} disabled={busy}>{busy ? "Enviando…" : "Solicitar horario"}</button></div>
    </section>}
    {notice && <div className={`notice ${notice.includes("error") || notice.includes("ocup") || notice.includes("fuera") ? "error" : ""}`} role="status" aria-live="polite">{notice}</div>}
    {showSuccessModal && <div className="confirmation-backdrop" role="presentation" onMouseDown={event => { if (event.target === event.currentTarget) setShowSuccessModal(false); }}>
      <section className="confirmation-modal" role="dialog" aria-modal="true" aria-labelledby="booking-confirmation-title" aria-describedby="booking-confirmation-message">
        <button className="confirmation-close" type="button" aria-label="Cerrar confirmación" onClick={() => setShowSuccessModal(false)}>×</button>
        <div className="confirmation-icon" aria-hidden="true">✓</div>
        <h2 id="booking-confirmation-title">Solicitud registrada</h2>
        <p id="booking-confirmation-message">{successMessage}</p>
        <button ref={confirmationButtonRef} type="button" onClick={() => setShowSuccessModal(false)}>Entendido</button>
      </section>
    </div>}
  </div>;
}
