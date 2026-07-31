(function () {
  "use strict";

  const SUPABASE_CONFIG = {
    url: "https://pzhzdjsjfdzbzkhnaxmc.supabase.co",
    anonKey: "sb_publishable_3Ox2JIQXVLwusT-xzIMJ4g_YXTR5q8e"
  };

  const client = window.supabase?.createClient(
    SUPABASE_CONFIG.url,
    SUPABASE_CONFIG.anonKey
  );
  const moneyFormatter = new Intl.NumberFormat("en-CA", {
    style: "currency",
    currency: "CAD",
    minimumFractionDigits: 2,
    maximumFractionDigits: 2
  });
  const numberFormatter = new Intl.NumberFormat("en-CA", {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2
  });

  function byId(id) {
    return document.getElementById(id);
  }

  function toNumber(value, fallback = 0) {
    const parsed = Number.parseFloat(String(value ?? "").replace(/,/g, "").trim());
    return Number.isFinite(parsed) ? parsed : fallback;
  }

  function round(value, digits = 2) {
    const factor = 10 ** digits;
    return Math.round((toNumber(value) + Number.EPSILON) * factor) / factor;
  }

  function formatMoney(value) {
    return moneyFormatter.format(toNumber(value));
  }

  function formatNumber(value, suffix = "") {
    return `${numberFormatter.format(toNumber(value))}${suffix}`;
  }

  function escapeHtml(value = "") {
    return String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;");
  }

  function isoDate(date = new Date()) {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, "0");
    const day = String(date.getDate()).padStart(2, "0");
    return `${year}-${month}-${day}`;
  }

  function safeDate(value) {
    const date = value instanceof Date ? new Date(value) : new Date(`${value}T00:00:00`);
    return Number.isNaN(date.getTime()) ? null : date;
  }

  function shiftDate(value, amount) {
    const date = safeDate(value) || new Date();
    date.setDate(date.getDate() + amount);
    return isoDate(date);
  }

  function formatDate(value, options = {}) {
    const date = safeDate(value);
    if (!date) return "";
    return new Intl.DateTimeFormat("ko-KR", {
      month: "long",
      day: "numeric",
      weekday: options.weekday === false ? undefined : "short",
      year: options.year ? "numeric" : undefined
    }).format(date);
  }

  function formatRange(start, end) {
    const startDate = safeDate(start);
    const endDate = safeDate(end);
    if (!startDate || !endDate) return "";
    const sameYear = startDate.getFullYear() === endDate.getFullYear();
    const startLabel = new Intl.DateTimeFormat("ko-KR", {
      year: sameYear ? undefined : "numeric",
      month: "numeric",
      day: "numeric"
    }).format(startDate);
    const endLabel = new Intl.DateTimeFormat("ko-KR", {
      year: "numeric",
      month: "numeric",
      day: "numeric"
    }).format(endDate);
    return `${startLabel} - ${endLabel}`;
  }

  function setStatus(element, message = "", type = "") {
    if (!element) return;
    element.textContent = message;
    element.className = `status-line${type ? ` is-${type}` : ""}`;
  }

  function isMissingSchemaError(error) {
    const message = String(error?.message || "").toLowerCase();
    return (
      message.includes("settlement_") ||
      message.includes("schema cache") ||
      message.includes("could not find the function")
    );
  }

  function getErrorMessage(error, fallback = "요청을 처리하지 못했습니다.") {
    if (isMissingSchemaError(error)) {
      return "Supabase에 settlement-install.sql을 먼저 실행해야 합니다.";
    }
    return error?.message || fallback;
  }

  window.EhwaSettlement = {
    client,
    byId,
    toNumber,
    round,
    formatMoney,
    formatNumber,
    escapeHtml,
    isoDate,
    safeDate,
    shiftDate,
    formatDate,
    formatRange,
    setStatus,
    getErrorMessage
  };
})();
