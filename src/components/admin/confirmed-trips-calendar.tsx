"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { dateKeyAddMonths, formatMexicoDate, monthLabel, mexicoMonthStart, TZ } from "@/lib/date-time";

type ConfirmedTrip = { trip_id: string; starts_at: string; ends_at: string; full_name: string; phone_e164: string };
const weekdays = ["D", "L", "M", "M", "J", "V", "S"];
const timeFormatter = new Intl.DateTimeFormat("es-MX", { timeZone: TZ, hour: "2-digit", minute: "2-digit", hourCycle: "h23" });

export function ConfirmedTripsCalendar() {
  const [month, setMonth] = useState(mexicoMonthStart());
  const [trips, setTrips] = useState<ConfirmedTrip[]>([]);
  const [selectedDay, setSelectedDay] = useState<string | null>(null);
  const [error, setError] = useState("");
  const closeButtonRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    async function load() {
      try {
        const response = await fetch("/api/admin/trips/confirmed-schedule");
        const data = await response.json();
        if (!response.ok) throw new Error(data.error || "No se pudo cargar el calendario.");
        setTrips(data.trips || []);
        setError("");
      } catch (cause) {
        setError(cause instanceof Error ? cause.message : "No se pudo cargar el calendario.");
      }
    }
    void load();
    const refresh = () => { void load(); };
    window.addEventListener("admin-trips-updated", refresh);
    return () => window.removeEventListener("admin-trips-updated", refresh);
  }, []);

  useEffect(() => {
    if (!selectedDay) return;
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") setSelectedDay(null);
    };
    window.addEventListener("keydown", closeOnEscape);
    closeButtonRef.current?.focus();
    return () => window.removeEventListener("keydown", closeOnEscape);
  }, [selectedDay]);

  const confirmed = trips;
  const confirmedByDay = useMemo(() => {
    const grouped = new Map<string, ConfirmedTrip[]>();
    for (const trip of confirmed) {
      const parts = new Intl.DateTimeFormat("en-CA", { timeZone: TZ, year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(new Date(trip.starts_at));
      const date = Object.fromEntries(parts.map(part => [part.type, part.value]));
      const key = `${date.year}-${date.month}-${date.day}`;
      grouped.set(key, [...(grouped.get(key) || []), trip]);
    }
    return grouped;
  }, [confirmed]);

  const [year, monthNumber] = month.split("-").map(Number);
  const dayCount = new Date(Date.UTC(year, monthNumber, 0)).getUTCDate();
  const firstWeekday = new Date(Date.UTC(year, monthNumber - 1, 1)).getUTCDay();
  const calendarDays = [
    ...Array(firstWeekday).fill(""),
    ...Array.from({ length: dayCount }, (_, index) => `${month.slice(0, 8)}${String(index + 1).padStart(2, "0")}`),
  ];
  const selectedTrips = selectedDay ? confirmedByDay.get(selectedDay) || [] : [];
  const selectedDateLabel = selectedDay ? formatMexicoDate(`${selectedDay}T12:00:00Z`) : "";

  return <section className="card admin-confirmed-calendar">
    <div className="heading-row">
      <div><span className="eyebrow">Agenda administrativa</span><h2>Viajes confirmados</h2></div>
      <div className="month-navigation admin-calendar-month">
        <button type="button" className="secondary" aria-label="Mes anterior" onClick={() => setMonth(dateKeyAddMonths(month, -1))}>←</button>
        <strong>{monthLabel(month)}</strong>
        <button type="button" className="secondary" aria-label="Mes siguiente" onClick={() => setMonth(dateKeyAddMonths(month, 1))}>→</button>
      </div>
    </div>
    {error && <div className="notice error" role="alert">{error}</div>}
    <div className="admin-month-grid" aria-label={`Calendario de ${monthLabel(month)}`}>
      {weekdays.map((day, index) => <span className="admin-weekday" key={`${day}-${index}`}>{day}</span>)}
      {calendarDays.map((day, index) => day
        ? <button type="button" key={day} className={`admin-calendar-day ${confirmedByDay.has(day) ? "has-confirmed" : ""}`} onClick={() => setSelectedDay(day)} aria-label={`${Number(day.slice(-2))} de ${monthLabel(month)}: ${(confirmedByDay.get(day) || []).length} viajes confirmados`}>
          <span>{Number(day.slice(-2))}</span>
          {confirmedByDay.has(day) && <span className="admin-day-count">{confirmedByDay.get(day)!.length} viaje{confirmedByDay.get(day)!.length === 1 ? "" : "s"}</span>}
        </button>
        : <span className="admin-calendar-empty" key={`blank-${index}`} />)}
    </div>
    <small className="admin-calendar-legend"><span aria-hidden="true" />Día con viajes confirmados. Selecciona cualquier fecha para consultar sus horarios.</small>

    {selectedDay && <div className="confirmation-backdrop" role="presentation" onMouseDown={event => { if (event.target === event.currentTarget) setSelectedDay(null); }}>
      <section className="schedule-modal" role="dialog" aria-modal="true" aria-labelledby="confirmed-day-title">
        <button ref={closeButtonRef} className="confirmation-close" type="button" aria-label="Cerrar horarios" onClick={() => setSelectedDay(null)}>×</button>
        <div className="schedule-icon" aria-hidden="true">◷</div>
        <h2 id="confirmed-day-title">Horarios confirmados</h2>
        <p className="muted">{selectedDateLabel}</p>
        {selectedTrips.length
          ? <ul className="confirmed-time-list">{selectedTrips.map(trip => <li key={trip.trip_id}><strong>{timeFormatter.format(new Date(trip.starts_at))}–{timeFormatter.format(new Date(trip.ends_at))}</strong><span>{trip.full_name} ({trip.phone_e164})</span></li>)}</ul>
          : <p className="schedule-empty">No hay viajes confirmados para este día.</p>}
        <button type="button" onClick={() => setSelectedDay(null)}>Cerrar</button>
      </section>
    </div>}
  </section>;
}
