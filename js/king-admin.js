(function () {
  "use strict";

  const SUPABASE_CONFIG = {
    url: "https://pzhzdjsjfdzbzkhnaxmc.supabase.co",
    anonKey: "sb_publishable_3Ox2JIQXVLwusT-xzIMJ4g_YXTR5q8e"
  };

  const ADMIN_SHEET_CONFIG = {
    sheetId: "1xa9OZbctYnlbaAL8lKIgmefM5hvSw0Plk01lxp5G2fc",
    sheets: [
      { name: "Downtown Reservation", label: "다운타운", key: "downtown" },
      { name: "Uptown Reservation", label: "업타운", key: "uptown" }
    ]
  };

  const BASE_MENU_COLUMNS = [
    "id",
    "branches",
    "sort_order",
    "category",
    "label",
    "name_ko",
    "romanized_name",
    "name_en",
    "description",
    "price",
    "image_url",
    "tags",
    "ingredient",
    "is_available"
  ];

  const EXTENDED_MENU_COLUMNS = [
    "id",
    "branches",
    "sort_order",
    "all_sort_order",
    "category",
    "label",
    "name_ko",
    "romanized_name",
    "name_en",
    "description",
    "price",
    "image_url",
    "tags",
    "ingredient",
    "is_available"
  ];

  const BASE_MENU_SELECT = BASE_MENU_COLUMNS.join(",");
  const EXTENDED_MENU_SELECT = EXTENDED_MENU_COLUMNS.join(",");

  const DEFAULT_CATEGORY_ORDER = [
    "Tteokbokki",
    "Soup",
    "Pasta",
    "Pancakes",
    "Meal",
    "Main Dish",
    "Anju",
    "Special",
    "Drink"
  ];

  const DETAIL_FIELDS = [
    "branches",
    "sort_order",
    "all_sort_order",
    "category",
    "label",
    "name_ko",
    "romanized_name",
    "name_en",
    "price",
    "image_url",
    "description",
    "tags",
    "ingredient",
    "is_available"
  ];

  const ASSET_PREFIX = window.location.pathname.includes("/test/") ? "../" : "";
  const FALLBACK_IMAGE = `${ASSET_PREFIX}assets/edited/ehwa.png`;
  const SORT_BASE_STEP = 1000;
  const FALLBACK_SERVER_REFS = [
    { staff_key: "우진", name: "우진", branch_scope: "uptown", job_role: "server" },
    { staff_key: "예림", name: "예림", branch_scope: "downtown", job_role: "server" },
    { staff_key: "소정", name: "소정", branch_scope: "downtown", job_role: "server" },
    { staff_key: "영채", name: "영채", branch_scope: "both", job_role: "server" },
    { staff_key: "은성", name: "은성", branch_scope: "both", job_role: "server" },
    { staff_key: "주은", name: "주은", branch_scope: "both", job_role: "server" },
    { staff_key: "제윤", name: "제윤", branch_scope: "both", job_role: "server" },
    { staff_key: "진아", name: "진아", branch_scope: "uptown", job_role: "server" },
    { staff_key: "현영", name: "현영", branch_scope: "uptown", job_role: "server" },
    { staff_key: "서윤", name: "서윤", branch_scope: "downtown", job_role: "server" }
  ];
  const SCHEDULE_BRANCHES = [
    { key: "uptown", label: "Uptown", color: "#8f2438", bg: "#fff3ed", border: "#e6b9b0" },
    { key: "downtown", label: "Downtown", color: "#245f51", bg: "#f1fbf5", border: "#b9d8c9" }
  ];
  const ontarioHolidayCache = new Map();
  const refs = {};

  const state = {
    activeTab: "reservations",
    reservations: [],
    reservationDate: formatInputDate(new Date()),
    reservationBranch: "all",
    reservationSearch: "",
    accessRequests: [],
    employees: [],
    employeeShowInactive: false,
    menuSession: null,
    menuItems: [],
    menuSearch: "",
    menuCategory: "all",
    menuBranch: "all",
    menuMode: "visual",
    menuOrderView: "all",
    categoryOrder: [],
    supportsAllSortOrder: true,
    scheduleWeekStart: "",
    scheduleWeekWindowStart: "",
    scheduleMonthCursor: null,
    scheduleMonthSelectedDate: "",
    scheduleCalendarEvents: [],
    scheduleWeeks: [],
    scheduleAvailability: [],
    scheduleFetchToken: 0,
    scheduleDataLoaded: false,
    scheduleStaff: [],
    scheduleUsingFallbackStaff: false,
    scheduleWeek: null,
    scheduleShifts: [],
    scheduleShiftNotes: new Map(),
    scheduleSelectedStaffKey: "",
    scheduleSelectedCellKey: "",
    scheduleDetailsOpen: false,
    scheduleNoteTarget: null,
    scheduleNotePressTimer: null,
    scheduleNotePressStart: null,
    scheduleNoteSuppressClickUntil: 0,
    sortables: {
      visual: null,
      all: null,
      category: null,
      menu: null
    }
  };

  const supabaseClient = window.supabase?.createClient(SUPABASE_CONFIG.url, SUPABASE_CONFIG.anonKey);

  function escapeHtml(value = "") {
    return String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;");
  }

  function byId(id) {
    return document.getElementById(id);
  }

  function cacheRefs() {
    [
      "todayHeading",
      "metricSelectedDate",
      "metricReservations",
      "metricDowntown",
      "metricUptown",
      "reservationDateLabel",
      "reservationDayChips",
      "reservationBranchChips",
      "reservationRefreshBtn",
      "reservationStatus",
      "reservationList",
      "employeeCountLabel",
      "employeeRefreshBtn",
      "employeeShowInactiveBtn",
      "employeeStatus",
      "accessRequestList",
      "employeeList",
      "employeeEditorModal",
      "employeeEditorTitle",
      "employeeEditorForm",
      "employeeEditId",
      "employeeEditRequestId",
      "employeeEditName",
      "employeeEditRefCode",
      "employeeEditPhone",
      "employeeEditSin",
      "employeeEditBranch",
      "employeeEditStatus",
      "employeeEditorClose",
      "employeeEditorCancel",
      "menuSessionLabel",
      "menuAuthCard",
      "menuWorkspace",
      "menuAdminEmail",
      "menuAdminPassword",
      "menuSignInBtn",
      "menuSignOutBtn",
      "menuAuthStatus",
      "menuSearchInput",
      "menuCategoryFilter",
      "menuBranchFilter",
      "menuRefreshBtn",
      "menuAddBtn",
      "menuStatus",
      "menuModeTabs",
      "menuCategoryChips",
      "menuVisualPanel",
      "menuOrderPanel",
      "menuList",
      "menuOrderChips",
      "menuOrderHeading",
      "menuCategoryOrderBtn",
      "menuCategoryOrderList",
      "menuOrderList",
      "menuSaveCategoryOrderBtn",
      "menuSaveMenuOrderBtn",
      "menuCategoryOrderModal",
      "menuCategoryOrderClose",
      "menuCategoryOrderCancel",
      "menuEditorModal",
      "menuEditorTitle",
      "menuEditorForm",
      "menuDeleteBtn",
      "menuEditorClose",
      "menuEditorCancel",
      "scheduleWeekLabel",
      "scheduleWeekStart",
      "scheduleWeekPrevBtn",
      "scheduleWeekNextBtn",
      "scheduleWeekChips",
      "scheduleMonthPrevBtn",
      "scheduleMonthNextBtn",
      "scheduleMonthLabel",
      "scheduleMonthGrid",
      "scheduleWeekCalendarNotices",
      "scheduleCalendarEventForm",
      "scheduleCalendarEventDate",
      "scheduleCalendarEventTitle",
      "scheduleCalendarEventList",
      "scheduleCalendarEventStatus",
      "scheduleLoadBtn",
      "schedulePublishBtn",
      "scheduleAutoFillBtn",
      "scheduleDetailToggleBtn",
      "scheduleCopyImageBtn",
      "scheduleResetBtn",
      "scheduleStatus",
      "scheduleStaffList",
      "scheduleNoteModal",
      "scheduleNoteClose",
      "scheduleNoteCancel",
      "scheduleNoteForm",
      "scheduleNoteMeta",
      "scheduleNoteInput",
      "unavailableList",
      "preferredList",
      "scheduleBoard"
    ].forEach((id) => {
      refs[id] = byId(id);
    });
  }

  function formatInputDate(date) {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, "0");
    const day = String(date.getDate()).padStart(2, "0");
    return `${year}-${month}-${day}`;
  }

  function startOfDay(date) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate());
  }

  function startOfWeek(date) {
    const result = startOfDay(date);
    const day = result.getDay();
    const diff = day === 0 ? -6 : 1 - day;
    result.setDate(result.getDate() + diff);
    return result;
  }

  function startOfMonth(date) {
    return new Date(date.getFullYear(), date.getMonth(), 1);
  }

  function addDays(date, amount) {
    const next = new Date(date);
    next.setDate(next.getDate() + amount);
    return next;
  }

  function addWeeks(date, amount) {
    return addDays(date, amount * 7);
  }

  function isSameDate(a, b) {
    return a instanceof Date &&
      b instanceof Date &&
      a.getFullYear() === b.getFullYear() &&
      a.getMonth() === b.getMonth() &&
      a.getDate() === b.getDate();
  }

  function toSafeDate(dateString = "") {
    const match = String(dateString).trim().match(/^(\d{4})-(\d{2})-(\d{2})$/);
    if (match) {
      const [, year, month, day] = match;
      return new Date(Number(year), Number(month) - 1, Number(day));
    }
    const parsed = new Date(dateString);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }

  function formatDateLabel(value = "") {
    if (value === "all") return "전체 날짜";
    const date = toSafeDate(value);
    if (!date) return value || "날짜 없음";
    return new Intl.DateTimeFormat("ko-KR", {
      weekday: "short",
      month: "short",
      day: "numeric"
    }).format(date);
  }

  function parseTimeForSort(value = "") {
    const match = String(value).trim().match(/^(\d{1,2}):(\d{2})\s*(AM|PM)$/i);
    if (!match) return Number.MAX_SAFE_INTEGER;
    let hour = Number(match[1]);
    const minute = Number(match[2]);
    const meridiem = match[3].toUpperCase();
    if (meridiem === "PM" && hour !== 12) hour += 12;
    if (meridiem === "AM" && hour === 12) hour = 0;
    return hour * 60 + minute;
  }

  function parseGuestCount(value = "") {
    const count = Number.parseInt(String(value).replace(/\D/g, ""), 10);
    return Number.isFinite(count) ? count : 0;
  }

  function getCellText(cell) {
    if (!cell) return "";
    if (typeof cell.f === "string" && cell.f.trim()) return cell.f.trim();
    return (cell.v ?? "").toString().trim();
  }

  function parseGvizText(text = "") {
    return JSON.parse(
      text.replace("/*O_o*/", "").replace("google.visualization.Query.setResponse(", "").slice(0, -2)
    );
  }

  function normalizeReservation(cells = [], index = 0, sheetConfig) {
    const values = cells.map((cell) => getCellText(cell));
    return {
      rowNumber: index + 2,
      sheetName: sheetConfig.name,
      branch: sheetConfig.label,
      branchKey: sheetConfig.key,
      timestamp: values[0] || "",
      date: values[1] || "",
      time: values[2] || "",
      people: values[3] || "",
      name: values[4] || "",
      phone: values[5] || "",
      notes: values[6] || "",
      status: values[7] || "active"
    };
  }

  async function fetchReservations() {
    setReservationStatus("예약을 불러오는 중...");
    try {
      const groups = await Promise.all(
        ADMIN_SHEET_CONFIG.sheets.map(async (sheetConfig) => {
          const url = `https://docs.google.com/spreadsheets/d/${ADMIN_SHEET_CONFIG.sheetId}/gviz/tq?sheet=${encodeURIComponent(sheetConfig.name)}&tqx=out:json`;
          const response = await fetch(url);
          if (!response.ok) throw new Error(`${sheetConfig.label} 예약을 불러오지 못했습니다.`);
          const data = parseGvizText(await response.text());
          return (data.table?.rows || [])
            .map((row) => row.c || [])
            .map((cells, index) => normalizeReservation(cells, index, sheetConfig))
            .filter((item) => item.timestamp || item.date || item.name);
        })
      );

      state.reservations = groups.flat().sort((a, b) => {
        const dateA = toSafeDate(a.date);
        const dateB = toSafeDate(b.date);
        if (dateA && dateB && dateA.getTime() !== dateB.getTime()) return dateA - dateB;
        return parseTimeForSort(a.time) - parseTimeForSort(b.time);
      });
      renderReservations();
      setReservationStatus(`예약 ${state.reservations.length}개를 불러왔습니다.`, "success");
    } catch (error) {
      setReservationStatus(error.message || "예약을 불러오지 못했습니다.", "error");
      refs.reservationList.innerHTML = '<div class="empty-state">예약 데이터를 불러오지 못했습니다.</div>';
    }
  }

  function getReservationDays() {
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    return Array.from({ length: 10 }, (_unused, index) => {
      const date = new Date(today);
      date.setDate(today.getDate() + index);
      return formatInputDate(date);
    });
  }

  function renderReservationDayChips() {
    const days = getReservationDays();
    refs.reservationDayChips.innerHTML = [
      `<button class="chip-btn ${state.reservationDate === "all" ? "is-active" : ""}" data-reservation-date="all" type="button">전체</button>`,
      ...days.map((value, index) => {
        const date = toSafeDate(value);
        const weekdayLabel = index === 0 ? "오늘" : new Intl.DateTimeFormat("ko-KR", { weekday: "short" }).format(date);
        const dayLabel = new Intl.DateTimeFormat("ko-KR", { month: "short", day: "numeric" }).format(date);
        return `
          <button class="chip-btn day-chip ${state.reservationDate === value ? "is-active" : ""}" data-reservation-date="${value}" type="button">
            <strong>${escapeHtml(weekdayLabel)}</strong>
            <span>${escapeHtml(dayLabel)}</span>
          </button>
        `;
      })
    ].join("");
  }

  function renderReservationBranchChips() {
    refs.reservationBranchChips.querySelectorAll("[data-reservation-branch]").forEach((button) => {
      button.classList.toggle("is-active", button.dataset.reservationBranch === state.reservationBranch);
    });
  }

  function getVisibleReservations() {
    return state.reservations.filter((item) => {
      if (item.status === "removed") return false;
      if (state.reservationDate !== "all" && item.date !== state.reservationDate) return false;
      if (state.reservationBranch !== "all" && item.branchKey !== state.reservationBranch) return false;
      return true;
    });
  }

  function renderReservationMetrics(items) {
    const downtown = items.filter((item) => item.branchKey === "downtown").length;
    const uptown = items.filter((item) => item.branchKey === "uptown").length;
    refs.metricSelectedDate.textContent = formatDateLabel(state.reservationDate);
    refs.metricReservations.textContent = String(items.length);
    refs.metricDowntown.textContent = String(downtown);
    refs.metricUptown.textContent = String(uptown);
    const branchLabel = state.reservationBranch === "all" ? "전체" : formatBranchLabel(state.reservationBranch);
    refs.reservationDateLabel.textContent = `${formatDateLabel(state.reservationDate)} / ${branchLabel}`;
  }

  function renderReservationCard(item) {
    const large = parseGuestCount(item.people) >= 8;
    return `
      <article class="reservation-card ${escapeHtml(item.branchKey)}">
        <div class="reservation-top">
          <div>
            <p>${escapeHtml(formatDateLabel(item.date))}</p>
          </div>
          <div class="badge-row">
            <span class="status-badge ${escapeHtml(item.branchKey)}">${escapeHtml(item.branch)}</span>
            ${large ? '<span class="status-badge large">단체 예약</span>' : ""}
          </div>
        </div>
        <div class="reservation-focus">
          <div class="reservation-pill-row">
            <div class="reservation-time-pill">${escapeHtml(item.time || "-")}</div>
            <div class="reservation-guests-pill">${escapeHtml(item.people || "-")}</div>
          </div>
          <h4 class="reservation-name-box">${escapeHtml(item.name || "손님")}</h4>
        </div>
        <div class="reservation-meta">
          <div class="meta-box"><span>전화번호</span><strong>${escapeHtml(item.phone || "-")}</strong></div>
          <div class="meta-box"><span>지점</span><strong>${escapeHtml(formatBranchLabel(item.branchKey || item.branch) || "-")}</strong></div>
        </div>
        <div class="reservation-notes">${escapeHtml(item.notes || "메모 없음")}</div>
      </article>
    `;
  }

  function renderReservations() {
    renderReservationDayChips();
    renderReservationBranchChips();
    const items = getVisibleReservations();
    renderReservationMetrics(items);
    refs.reservationList.innerHTML = items.length
      ? items.map(renderReservationCard).join("")
      : '<div class="empty-state">현재 조건에 맞는 예약이 없습니다.</div>';
  }

  function setReservationStatus(message = "", type = "") {
    refs.reservationStatus.textContent = message;
    refs.reservationStatus.className = `status-line${type ? ` is-${type}` : ""}`;
  }

  function setEmployeeStatus(message = "", type = "") {
    refs.employeeStatus.textContent = message;
    refs.employeeStatus.className = `status-line${type ? ` is-${type}` : ""}`;
  }

  function formatDateTimeLabel(value = "") {
    const date = value ? new Date(value) : null;
    if (!date || Number.isNaN(date.getTime())) return value || "-";
    return new Intl.DateTimeFormat("ko-KR", {
      month: "short",
      day: "numeric",
      hour: "numeric",
      minute: "2-digit"
    }).format(date);
  }

  function renderAccessRequestCard(item) {
    return `
      <article class="request-card">
        <div class="request-top">
          <div>
            <p>${escapeHtml(formatDateTimeLabel(item.created_at))}</p>
            <h4>${escapeHtml(item.name || "이름 없음")}</h4>
          </div>
          <div class="badge-row">
            <span class="status-badge ${escapeHtml(item.branch_scope || "both")}">${escapeHtml(formatBranchLabel(item.branch_scope || "both"))}</span>
            <span class="status-badge hidden">${escapeHtml(item.status || "pending")}</span>
          </div>
        </div>
        <div class="reservation-meta">
          <div class="meta-box"><span>전화번호</span><strong>${escapeHtml(item.phone_number || "-")}</strong></div>
          <div class="meta-box"><span>Smart Server</span><strong>${escapeHtml(item.smart_server_number || "-")}</strong></div>
        </div>
        ${item.note ? `<div class="reservation-notes">${escapeHtml(item.note)}</div>` : ""}
        <div class="request-actions">
          <button class="pill-btn primary" type="button" data-edit-access-request="${escapeHtml(item.id)}">확인 + Edit</button>
          <button class="pill-btn danger" type="button" data-delete-access-request="${escapeHtml(item.id)}">삭제</button>
        </div>
      </article>
    `;
  }

  function getVisibleEmployees() {
    const list = state.employeeShowInactive
      ? state.employees.slice()
      : state.employees.filter((item) => item.active !== false);

    return list.sort((a, b) => {
      const inactiveA = a.active === false;
      const inactiveB = b.active === false;
      if (inactiveA !== inactiveB) return inactiveA ? -1 : 1;
      if (inactiveA && inactiveB) {
        const dateA = new Date(a.inactive_at || a.updated_at || a.created_at || 0).getTime();
        const dateB = new Date(b.inactive_at || b.updated_at || b.created_at || 0).getTime();
        return dateB - dateA;
      }
      return normalizeBranchScope(a.branch_scope).localeCompare(normalizeBranchScope(b.branch_scope))
        || String(a.staff_key || "").localeCompare(String(b.staff_key || ""));
    });
  }

  function renderEmployeeCard(item) {
    const isActive = item.active !== false;
    const name = item.staff_key || item.name || item.ref_code || "-";
    return `
      <article class="employee-card ${isActive ? "" : "is-inactive"}">
        <div class="employee-top">
          <div>
            <p>${escapeHtml(item.phone_number || "전화번호 없음")}</p>
            <h4>${escapeHtml(name)}</h4>
          </div>
          <div class="badge-row">
            <span class="status-badge ${escapeHtml(normalizeBranchScope(item.branch_scope))}">${escapeHtml(formatBranchLabel(item.branch_scope))}</span>
            <span class="status-badge ${isActive ? "active" : "hidden"}">${isActive ? "아직 서버" : "그만둠"}</span>
          </div>
        </div>
        <div class="employee-meta-grid">
          <div class="meta-box"><span>전화번호</span><strong>${escapeHtml(item.phone_number || "-")}</strong></div>
          <div class="meta-box"><span>근무 위치</span><strong>${escapeHtml(formatBranchLabel(item.branch_scope))}</strong></div>
        </div>
        ${!isActive ? `<div class="reservation-notes">근무 아님${item.inactive_at ? ` · ${escapeHtml(formatDateTimeLabel(item.inactive_at))}` : ""}</div>` : ""}
        <div class="employee-actions">
          <button class="pill-btn" type="button" data-edit-employee="${escapeHtml(item.id || item.ref_code || item.staff_key)}">Edit</button>
        </div>
      </article>
    `;
  }

  function renderEmployees() {
    const visibleEmployees = getVisibleEmployees();
    refs.employeeCountLabel.textContent = `직원 ${visibleEmployees.length}명 / 요청 ${state.accessRequests.length}개`;
    refs.employeeShowInactiveBtn.classList.toggle("is-active", state.employeeShowInactive);
    refs.employeeShowInactiveBtn.setAttribute("aria-pressed", state.employeeShowInactive ? "true" : "false");
    refs.employeeShowInactiveBtn.textContent = state.employeeShowInactive ? "근무중만 보기" : "그만둔 서버 보기";
    refs.accessRequestList.innerHTML = state.accessRequests.length
      ? state.accessRequests.map(renderAccessRequestCard).join("")
      : '<div class="empty-state">추가 요청이 없습니다.</div>';
    refs.employeeList.innerHTML = visibleEmployees.length
      ? visibleEmployees.map(renderEmployeeCard).join("")
      : '<div class="empty-state">직원 데이터가 없습니다.</div>';
  }

  async function fetchEmployees() {
    if (!supabaseClient || !state.menuSession) {
      setEmployeeStatus("관리자 로그인 후 사용할 수 있습니다.", "error");
      refs.employeeCountLabel.textContent = "로그인 필요";
      refs.accessRequestList.innerHTML = '<div class="empty-state">로그인이 필요합니다.</div>';
      refs.employeeList.innerHTML = '<div class="empty-state">로그인이 필요합니다.</div>';
      return;
    }

    setEmployeeStatus("직원 데이터를 불러오는 중...");
    const requestResult = await fetchAccessRequestRows();

    if (requestResult.error) {
      setEmployeeStatus(requestResult.error.message || "요청을 불러오지 못했습니다.", "error");
      return;
    }

    const employeeResult = await fetchEmployeeRefRows();

    if (employeeResult.error) {
      setEmployeeStatus(employeeResult.error.message || "직원 목록을 불러오지 못했습니다.", "error");
      return;
    }

    state.accessRequests = requestResult.data || [];
    state.employees = employeeResult.data || [];
    renderEmployees();
    setEmployeeStatus(
      state.employees.length
        ? "직원 데이터를 불러왔습니다."
        : "직원 데이터 0건입니다. Supabase SQL/RLS 권한을 확인해주세요.",
      state.employees.length ? "success" : ""
    );
  }

  async function fetchEmployeeRefRows() {
    const rpcResult = await supabaseClient.rpc("king_get_employee_refs");
    if (!rpcResult.error && Array.isArray(rpcResult.data) && rpcResult.data.length) return rpcResult;

    const directResult = await supabaseClient
      .from("employee_refs")
      .select("*");
    if (!directResult.error && Array.isArray(directResult.data) && directResult.data.length) return directResult;

    return rpcResult.error ? directResult : rpcResult;
  }

  async function fetchAccessRequestRows() {
    const rpcResult = await supabaseClient.rpc("king_get_access_requests");
    if (!rpcResult.error && Array.isArray(rpcResult.data) && rpcResult.data.length) return rpcResult;

    const directResult = await supabaseClient
      .from("noble_access_requests")
      .select("id,name,branch_scope,phone_number,smart_server_number,status,note,created_at")
      .in("status", ["pending", "approved"])
      .order("created_at", { ascending: false });
    if (!directResult.error && Array.isArray(directResult.data) && directResult.data.length) return directResult;

    return rpcResult.error ? directResult : rpcResult;
  }

  async function deleteAccessRequest(id = "") {
    if (!id || !supabaseClient || !state.menuSession) return;
    const ok = window.confirm("이 추가 요청을 확인 후 삭제할까요?");
    if (!ok) return;

    setEmployeeStatus("요청을 삭제하는 중...");
    const { error } = await supabaseClient
      .from("noble_access_requests")
      .delete()
      .eq("id", id);

    if (error) {
      setEmployeeStatus(error.message || "요청 삭제에 실패했습니다.", "error");
      return;
    }

    state.accessRequests = state.accessRequests.filter((item) => item.id !== id);
    renderEmployees();
    setEmployeeStatus("요청을 삭제했습니다.", "success");
  }

  function closeEmployeeEditor() {
    refs.employeeEditorModal.setAttribute("aria-hidden", "true");
    refs.employeeEditorModal.classList.remove("is-open");
    refs.employeeEditorForm.reset();
  }

  function openEmployeeEditorFromRequest(id = "") {
    const request = state.accessRequests.find((item) => item.id === id);
    if (!request) return;

    refs.employeeEditorTitle.textContent = "요청 확인 + 직원 등록";
    refs.employeeEditId.value = "";
    refs.employeeEditRequestId.value = request.id || "";
    refs.employeeEditName.value = request.name || "";
    refs.employeeEditRefCode.value = request.smart_server_number || "";
    refs.employeeEditPhone.value = request.phone_number || "";
    refs.employeeEditSin.value = request.smart_server_number || "";
    refs.employeeEditBranch.value = normalizeBranchScope(request.branch_scope || "both");
    refs.employeeEditStatus.value = "true";
    refs.employeeEditorModal.setAttribute("aria-hidden", "false");
    refs.employeeEditorModal.classList.add("is-open");
    refs.employeeEditName.focus();
  }

  function openEmployeeEditor(id = "") {
    const employee = state.employees.find((item) => {
      const values = [item.id, item.ref_code, item.staff_key].map((value) => String(value || ""));
      return values.includes(String(id || ""));
    });
    if (!employee) return;

    refs.employeeEditorTitle.textContent = "직원 편집";
    refs.employeeEditId.value = employee.id || "";
    refs.employeeEditRequestId.value = "";
    refs.employeeEditName.value = employee.staff_key || "";
    refs.employeeEditRefCode.value = employee.ref_code || "";
    refs.employeeEditPhone.value = employee.phone_number || "";
    refs.employeeEditSin.value = employee.sin_number || "";
    refs.employeeEditBranch.value = normalizeBranchScope(employee.branch_scope || "both");
    refs.employeeEditStatus.value = employee.active === false ? "false" : "true";
    refs.employeeEditorModal.setAttribute("aria-hidden", "false");
    refs.employeeEditorModal.classList.add("is-open");
    refs.employeeEditName.focus();
  }

  function getEmployeeEditorPayload() {
    const active = refs.employeeEditStatus.value !== "false";
    const current = state.employees.find((item) => String(item.id || "") === refs.employeeEditId.value);
    return {
      ref_code: refs.employeeEditRefCode.value.trim(),
      staff_key: refs.employeeEditName.value.trim(),
      job_role: "server",
      branch_scope: normalizeBranchScope(refs.employeeEditBranch.value || "both"),
      phone_number: refs.employeeEditPhone.value.trim() || null,
      sin_number: refs.employeeEditSin.value.trim() || null,
      active,
      inactive_at: active ? null : (current?.active === false && current?.inactive_at ? current.inactive_at : new Date().toISOString())
    };
  }

  async function saveEmployeeEditor(event) {
    event.preventDefault();
    if (!supabaseClient || !state.menuSession) {
      setEmployeeStatus("관리자 로그인 후 사용할 수 있습니다.", "error");
      return;
    }

    const payload = getEmployeeEditorPayload();
    if (!payload.ref_code || !payload.staff_key) {
      setEmployeeStatus("이름과 Reference Code는 필요합니다.", "error");
      return;
    }

    setEmployeeStatus("직원을 저장하는 중...");
    const employeeId = refs.employeeEditId.value;
    const requestId = refs.employeeEditRequestId.value;
    const result = employeeId
      ? await supabaseClient.from("employee_refs").update(payload).eq("id", employeeId).select("*").single()
      : await supabaseClient.from("employee_refs").insert(payload).select("*").single();

    if (result.error) {
      setEmployeeStatus(result.error.message || "직원 저장에 실패했습니다.", "error");
      return;
    }

    if (requestId) {
      const requestUpdate = await supabaseClient
        .from("noble_access_requests")
        .update({ status: "done" })
        .eq("id", requestId);
      if (requestUpdate.error) {
        setEmployeeStatus(requestUpdate.error.message || "직원은 저장됐지만 요청 상태 변경에 실패했습니다.", "error");
      }
    }

    closeEmployeeEditor();
    await fetchEmployees();
    setEmployeeStatus("직원을 저장했습니다.", "success");
  }

  function formatBranchLabel(branch = "") {
    const normalized = String(branch).trim().toLowerCase();
    if (normalized === "both") return "공통";
    if (normalized === "downtown") return "다운타운";
    if (normalized === "uptown") return "업타운";
    if (normalized === "all") return "전체";
    return branch || "-";
  }

  function formatOrderScopeLabel(value = "") {
    return value === "all" ? "전체" : value;
  }

  function formatPrice(value) {
    if (value === null || value === undefined || value === "") return "-";
    const number = Number(value);
    if (Number.isFinite(number)) return `$${number.toFixed(2)}`;
    const text = String(value).trim();
    return text.startsWith("$") ? text : `$${text}`;
  }

  function normalizeBranch(value = "") {
    const normalized = String(value || "both").trim().toLowerCase();
    return ["both", "downtown", "uptown"].includes(normalized) ? normalized : "both";
  }

  function menuMatchesBranch(item) {
    if (state.menuBranch === "all") return true;
    const branch = normalizeBranch(item.branches);
    if (state.menuBranch === "both") return branch === "both";
    return branch === "both" || branch === state.menuBranch;
  }

  function getMenuSelect() {
    return state.supportsAllSortOrder ? EXTENDED_MENU_SELECT : BASE_MENU_SELECT;
  }

  function isMissingAllSortOrderError(error) {
    const message = `${error?.code || ""} ${error?.message || ""} ${error?.details || ""}`;
    return message.includes("all_sort_order");
  }

  function normalizeMenuItem(item) {
    if (!item) return item;
    return {
      ...item,
      all_sort_order: item.all_sort_order ?? item.sort_order ?? null
    };
  }

  function getOrderValue(item, field) {
    const value = Number(item?.[field]);
    return Number.isFinite(value) ? value : Number.MAX_SAFE_INTEGER;
  }

  function compareByMenuField(field, a, b) {
    const orderA = getOrderValue(a, field);
    const orderB = getOrderValue(b, field);
    if (orderA !== orderB) return orderA - orderB;
    return Number(a.id || 0) - Number(b.id || 0);
  }

  function compareMenuItems(a, b) {
    return compareByMenuField("sort_order", a, b);
  }

  function compareAllMenuItems(a, b) {
    const orderA = getOrderValue(a, "all_sort_order");
    const orderB = getOrderValue(b, "all_sort_order");
    if (orderA !== orderB) return orderA - orderB;
    return compareMenuItems(a, b);
  }

  function getCategoryOrder(category) {
    const index = state.categoryOrder.indexOf(category);
    return index >= 0 ? index : Number.MAX_SAFE_INTEGER;
  }

  function getCategories() {
    const fromItems = [...new Set(state.menuItems.map((item) => item.category).filter(Boolean))];
    const ordered = state.categoryOrder.filter((category) => fromItems.includes(category));
    const remainder = fromItems
      .filter((category) => !ordered.includes(category))
      .sort((a, b) => a.localeCompare(b));
    return [...ordered, ...remainder];
  }

  function syncCategoryOrder() {
    const categoryStats = new Map();
    state.menuItems.forEach((item) => {
      if (!item.category) return;
      const order = Number.isFinite(Number(item.sort_order)) ? Number(item.sort_order) : Number.MAX_SAFE_INTEGER;
      if (!categoryStats.has(item.category)) {
        categoryStats.set(item.category, order);
      } else {
        categoryStats.set(item.category, Math.min(categoryStats.get(item.category), order));
      }
    });

    const discovered = [...categoryStats.entries()]
      .sort((a, b) => {
        if (a[1] !== b[1]) return a[1] - b[1];
        const preferred = DEFAULT_CATEGORY_ORDER.indexOf(a[0]) - DEFAULT_CATEGORY_ORDER.indexOf(b[0]);
        const aPreferred = DEFAULT_CATEGORY_ORDER.includes(a[0]);
        const bPreferred = DEFAULT_CATEGORY_ORDER.includes(b[0]);
        if (aPreferred && bPreferred && preferred) return preferred;
        return a[0].localeCompare(b[0]);
      })
      .map(([category]) => category);

    const current = state.categoryOrder.filter((category) => discovered.includes(category));
    const next = current.length ? [...current, ...discovered.filter((category) => !current.includes(category))] : discovered;
    state.categoryOrder = next;
    if (state.menuCategory !== "all" && !state.categoryOrder.includes(state.menuCategory)) {
      state.menuCategory = "all";
    }
    if (state.menuOrderView !== "all" && !state.categoryOrder.includes(state.menuOrderView)) {
      state.menuOrderView = "all";
    }
  }

  function getVisibleMenuItems() {
    const query = state.menuSearch.trim().toLowerCase();
    return state.menuItems
      .filter((item) => {
        if (state.menuCategory !== "all" && item.category !== state.menuCategory) return false;
        if (!menuMatchesBranch(item)) return false;
        if (!query) return true;
        return [
          item.category,
          item.label,
          item.name_ko,
          item.romanized_name,
          item.name_en,
          item.description,
          item.tags,
          item.ingredient,
          item.branches
        ].filter(Boolean).some((value) => String(value).toLowerCase().includes(query));
      })
      .sort((a, b) => {
        return state.menuCategory === "all"
          ? compareAllMenuItems(a, b)
          : compareMenuItems(a, b);
      });
  }

  function refreshCategoryControls() {
    const categories = getCategories();
    const categoryOptions = ['<option value="all">전체 카테고리</option>']
      .concat(categories.map((category) => `<option value="${escapeHtml(category)}">${escapeHtml(category)}</option>`));
    refs.menuCategoryFilter.innerHTML = categoryOptions.join("");
    refs.menuCategoryFilter.value = state.menuCategory;
    refs.menuCategoryChips.innerHTML = [
      `<button class="chip-btn ${state.menuCategory === "all" ? "is-active" : ""}" data-menu-category="all" type="button">전체</button>`,
      ...categories.map((category) => `
        <button class="chip-btn ${state.menuCategory === category ? "is-active" : ""}" data-menu-category="${escapeHtml(category)}" type="button">${escapeHtml(category)}</button>
      `)
    ].join("");
    const datalist = byId("menuCategoryOptions");
    if (datalist) {
      datalist.innerHTML = categories.map((category) => `<option value="${escapeHtml(category)}"></option>`).join("");
    }
  }

  function setMenuStatus(message = "", type = "") {
    refs.menuStatus.textContent = message;
    refs.menuStatus.className = `status-line${type ? ` is-${type}` : ""}`;
  }

  function setMenuAuthStatus(message = "", type = "") {
    refs.menuAuthStatus.textContent = message;
    refs.menuAuthStatus.className = `status-line${type ? ` is-${type}` : ""}`;
  }

  function updateMenuAuthView() {
    const signedIn = Boolean(state.menuSession?.access_token);
    refs.menuAuthCard.hidden = signedIn;
    refs.menuWorkspace.hidden = !signedIn;
    refs.menuSessionLabel.textContent = signedIn ? state.menuSession.user?.email || "로그인됨" : "로그인이 필요합니다";
  }

  async function refreshMenuSession() {
    if (!supabaseClient) {
      setMenuAuthStatus("Supabase 클라이언트를 불러오지 못했습니다.", "error");
      return;
    }
    const { data, error } = await supabaseClient.auth.getSession();
    if (error) {
      setMenuAuthStatus(error.message, "error");
      return;
    }
    state.menuSession = data.session;
    updateMenuAuthView();
    if (state.menuSession && !state.menuItems.length) await fetchMenuItems();
    if (state.menuSession) await fetchScheduleCalendarEvents();
  }

  async function signInMenuAdmin() {
    if (!supabaseClient) {
      setMenuAuthStatus("Supabase 클라이언트를 불러오지 못했습니다.", "error");
      return;
    }
    const email = refs.menuAdminEmail.value.trim();
    const password = refs.menuAdminPassword.value;
    if (!email || !password) {
      setMenuAuthStatus("이메일과 비밀번호를 입력하세요.", "error");
      return;
    }
    setMenuAuthStatus("로그인 중...");
    const { data, error } = await supabaseClient.auth.signInWithPassword({ email, password });
    if (error) {
      setMenuAuthStatus(error.message, "error");
      return;
    }
    state.menuSession = data.session;
    refs.menuAdminPassword.value = "";
    updateMenuAuthView();
    setMenuAuthStatus("로그인되었습니다.", "success");
    await fetchMenuItems();
    await fetchScheduleCalendarEvents();
  }

  async function signOutMenuAdmin() {
    if (!supabaseClient) return;
    await supabaseClient.auth.signOut();
    state.menuSession = null;
    state.menuItems = [];
    state.scheduleCalendarEvents = [];
    updateMenuAuthView();
    renderMenu();
    renderScheduleBoard();
    setMenuStatus("");
  }

  async function fetchMenuItems() {
    if (!supabaseClient) return;
    setMenuStatus("메뉴를 불러오는 중...");
    let { data, error } = await supabaseClient
      .from("menu_items")
      .select(EXTENDED_MENU_SELECT)
      .order("sort_order", { ascending: true, nullsFirst: false })
      .order("id", { ascending: true });

    if (error && isMissingAllSortOrderError(error)) {
      state.supportsAllSortOrder = false;
      ({ data, error } = await supabaseClient
        .from("menu_items")
        .select(BASE_MENU_SELECT)
        .order("sort_order", { ascending: true, nullsFirst: false })
        .order("id", { ascending: true }));
    } else if (!error) {
      state.supportsAllSortOrder = true;
    }

    if (error) {
      setMenuStatus(error.message, "error");
      return;
    }

    state.menuItems = (data || []).map(normalizeMenuItem);
    syncCategoryOrder();
    renderMenu();
    setMenuStatus(`메뉴 ${state.menuItems.length}개를 불러왔습니다.`, "success");
  }

  function getMenuById(id) {
    return state.menuItems.find((item) => String(item.id) === String(id));
  }

  function parseList(value = "") {
    return String(value || "")
      .split(",")
      .map((part) => part.trim())
      .filter(Boolean);
  }

  function getTagClass(tag = "") {
    const text = String(tag).toLowerCase();
    if (text.includes("popular")) return "popular";
    if (text.includes("spicy")) return "spicy";
    if (text.includes("vegan") || text.includes("vegetarian")) return "vegan";
    if (text.includes("seafood")) return "seafood";
    return "";
  }

  function renderTagBadgesFromValues(tagsValue, ingredientValue) {
    const tags = [...parseList(tagsValue), ...parseList(ingredientValue)].slice(0, 8);
    if (!tags.length) return "";
    return tags.map((tag) => `<span class="menu-tag ${escapeHtml(getTagClass(tag))}">${escapeHtml(tag)}</span>`).join("");
  }

  function renderTagBadges(item) {
    const badges = renderTagBadgesFromValues(item.tags, item.ingredient);
    if (!badges) return "";
    return `
      <div class="menu-meta" data-preview-tags>${badges}</div>
    `;
  }

  function getMenuOptionValues(field) {
    const values = new Set();
    state.menuItems.forEach((item) => {
      if (field === "tags" || field === "ingredient") {
        parseList(item[field]).forEach((value) => values.add(value));
      } else if (item[field]) {
        values.add(item[field]);
      }
    });
    return [...values].sort((a, b) => String(a).localeCompare(String(b)));
  }

  function renderSelectOptions(values, current = "", placeholder = "") {
    const safeCurrent = String(current || "");
    const hasCurrent = safeCurrent && !values.includes(safeCurrent);
    return [
      placeholder ? `<option value="">${escapeHtml(placeholder)}</option>` : "",
      ...values.map((value) => `<option value="${escapeHtml(value)}" ${safeCurrent === value ? "selected" : ""}>${escapeHtml(value)}</option>`),
      hasCurrent ? `<option value="${escapeHtml(safeCurrent)}" selected>${escapeHtml(safeCurrent)}</option>` : ""
    ].join("");
  }

  function renderTokenPicker(field, value = "", attrName = "data-visual-field") {
    const selected = new Set(parseList(value));
    const options = getMenuOptionValues(field);
    return `
      <div class="option-picker" data-token-group="${escapeHtml(field)}">
        <input ${attrName}="${escapeHtml(field)}" type="hidden" value="${escapeHtml(parseList(value).join(", "))}" />
        <div class="option-chip-row">
          ${options.map((option) => `
            <button class="option-chip ${selected.has(option) ? "is-selected" : ""}" data-token-toggle="${escapeHtml(option)}" type="button">${escapeHtml(option)}</button>
          `).join("")}
        </div>
        <div class="custom-token-row">
          <input data-token-custom type="text" placeholder="직접 추가" />
          <button class="pill-btn" data-token-add type="button">추가</button>
        </div>
      </div>
    `;
  }

  function renderEditorTokenPicker(containerId, field, value = "") {
    const container = byId(containerId);
    if (container) container.innerHTML = renderTokenPicker(field, value, "data-editor-field");
  }

  function branchOptions(current = "both") {
    const value = normalizeBranch(current);
    return ["both", "downtown", "uptown"]
      .map((option) => `<option value="${option}" ${value === option ? "selected" : ""}>${formatBranchLabel(option)}</option>`)
      .join("");
  }

  function renderVisualMenuCard(item) {
    const hiddenClass = item.is_available === false ? "is-hidden" : "";
    return `
      <article class="menu-preview-card ${hiddenClass}" data-menu-id="${escapeHtml(item.id)}">
        <div class="menu-preview-main">
          <div class="menu-preview-visual">
            <img class="menu-preview-image" data-preview-image src="${escapeHtml(item.image_url || FALLBACK_IMAGE)}" alt="${escapeHtml(item.name_en || item.name_ko || "메뉴 이미지")}" loading="lazy" />
            <div class="menu-preview-content">
              <p class="menu-preview-name-ko" data-preview-name-ko>${escapeHtml(item.name_ko || item.name_en || "이름 없음")}</p>
              <p class="menu-preview-name-en" data-preview-name-en>${escapeHtml(item.name_en || item.romanized_name || "")}</p>
              <p class="menu-preview-desc" data-preview-description>${escapeHtml(item.description || "설명 없음")}</p>
              <div class="menu-meta" data-preview-tags>${renderTagBadgesFromValues(item.tags, item.ingredient)}</div>
              <div class="menu-preview-price" data-preview-price>${escapeHtml(formatPrice(item.price))}</div>
            </div>
          </div>
          <div class="preview-actions">
            <button class="pill-btn" data-menu-edit="${escapeHtml(item.id)}" type="button">전체 편집</button>
            <button class="pill-btn primary" data-visual-save="${escapeHtml(item.id)}" type="button">카드 저장</button>
          </div>
        </div>
        <div class="preview-edit-grid">
          <div class="preview-field">
            <label>한국어</label>
            <input data-visual-field="name_ko" type="text" value="${escapeHtml(item.name_ko || "")}" />
          </div>
          <div class="preview-field">
            <label>영어</label>
            <input data-visual-field="name_en" type="text" value="${escapeHtml(item.name_en || "")}" />
          </div>
          <div class="preview-field">
            <label>가격</label>
            <input data-visual-field="price" type="number" step="0.01" min="0" value="${escapeHtml(item.price ?? "")}" />
          </div>
          <div class="preview-field">
            <label>카테고리</label>
            <select data-visual-field="category">${renderSelectOptions(getCategories(), item.category, "카테고리 선택")}</select>
          </div>
          <div class="preview-field full">
            <label>설명</label>
            <textarea data-visual-field="description">${escapeHtml(item.description || "")}</textarea>
          </div>
          <div class="preview-field full">
            <label>이미지 URL</label>
            <input data-visual-field="image_url" type="url" value="${escapeHtml(item.image_url || "")}" />
          </div>
        </div>
      </article>
    `;
  }

  function destroySortable(key) {
    if (state.sortables[key]) {
      state.sortables[key].destroy();
      state.sortables[key] = null;
    }
  }

  function setupSortable(key, element, handle) {
    destroySortable(key);
    if (!window.Sortable || !element || element.children.length < 2) return;
    const config = {
      animation: 160,
      forceFallback: true,
      scroll: true,
      bubbleScroll: true,
      scrollSensitivity: 90,
      scrollSpeed: 12
    };
    if (handle) config.handle = handle;
    state.sortables[key] = window.Sortable.create(element, config);
  }

  function renderVisualMenu() {
    destroySortable("all");
    destroySortable("category");
    destroySortable("menu");
    destroySortable("visual");
    const items = getVisibleMenuItems();
    refs.menuList.innerHTML = items.length
      ? items.map(renderVisualMenuCard).join("")
      : '<div class="empty-state">현재 조건에 맞는 메뉴가 없습니다.</div>';
  }

  function renderCategoryOrder() {
    refs.menuCategoryOrderList.innerHTML = state.categoryOrder.length
      ? state.categoryOrder.map((category) => {
        const count = state.menuItems.filter((item) => item.category === category).length;
        return `
          <article class="category-order-row" data-category="${escapeHtml(category)}">
            <div class="order-row-title">
              <strong>${escapeHtml(category)}</strong>
              <span>${count}개 메뉴</span>
            </div>
          </article>
        `;
      }).join("")
      : '<div class="empty-state">불러온 카테고리가 없습니다.</div>';
    setupSortable("category", refs.menuCategoryOrderList);
  }

  function renderOrderChips() {
    const categories = getCategories();
    refs.menuOrderChips.innerHTML = [
      `<button class="chip-btn ${state.menuOrderView === "all" ? "is-active" : ""}" data-order-view="all" type="button">전체</button>`,
      ...categories.map((category) => `
        <button class="chip-btn ${state.menuOrderView === category ? "is-active" : ""}" data-order-view="${escapeHtml(category)}" type="button">${escapeHtml(category)}</button>
      `)
    ].join("");
  }

  function renderMenuOrder() {
    const isAll = state.menuOrderView === "all";
    const items = isAll
      ? [...state.menuItems].sort(compareAllMenuItems)
      : state.menuItems
        .filter((item) => item.category === state.menuOrderView)
        .sort(compareMenuItems);
    refs.menuOrderHeading.textContent = isAll ? "전체 보기 순서" : `${state.menuOrderView} 순서`;
    refs.menuOrderList.innerHTML = items.length
      ? items.map((item) => `
        <article class="menu-order-row" data-menu-id="${escapeHtml(item.id)}">
          <div class="order-row-title">
            <strong>${escapeHtml(item.name_ko || item.name_en || "이름 없음")}</strong>
            <span>${escapeHtml(item.category || "미분류")} / ${escapeHtml(item.name_en || "")} / ${escapeHtml(formatBranchLabel(item.branches || "both"))} / ${isAll ? `전체 ${escapeHtml(item.all_sort_order ?? "-")}` : `카테고리 ${escapeHtml(item.sort_order ?? "-")}`}</span>
          </div>
        </article>
      `).join("")
      : '<div class="empty-state">현재 보기에는 메뉴가 없습니다.</div>';
    setupSortable("menu", refs.menuOrderList);
  }

  function renderOrderPanel() {
    destroySortable("visual");
    renderOrderChips();
    renderMenuOrder();
  }

  function renderMenuModePanels() {
    refs.menuModeTabs.querySelectorAll("[data-menu-mode]").forEach((button) => {
      button.classList.toggle("is-active", button.dataset.menuMode === state.menuMode);
    });
    refs.menuVisualPanel.classList.toggle("is-active", state.menuMode === "visual");
    refs.menuOrderPanel.classList.toggle("is-active", state.menuMode === "order");
  }

  function renderMenu() {
    syncCategoryOrder();
    refreshCategoryControls();
    renderMenuModePanels();
    if (!state.menuSession) {
      destroySortable("visual");
      destroySortable("all");
      destroySortable("category");
      destroySortable("menu");
      return;
    }
    if (state.menuMode === "order") {
      renderOrderPanel();
    } else {
      renderVisualMenu();
    }
  }

  function nullableText(value) {
    const text = String(value ?? "").trim();
    return text || null;
  }

  function nullableNumber(value, integer = false) {
    const text = String(value ?? "").trim();
    if (!text) return null;
    const parsed = integer ? Number.parseInt(text, 10) : Number.parseFloat(text);
    return Number.isFinite(parsed) ? parsed : null;
  }

  function coerceMenuPayload(rawPayload) {
    const payload = {};
    Object.entries(rawPayload).forEach(([field, value]) => {
      if (!DETAIL_FIELDS.includes(field)) return;
      if (field === "is_available") {
        payload[field] = Boolean(value);
      } else if (field === "price") {
        payload[field] = nullableNumber(value);
      } else if (field === "sort_order" || field === "all_sort_order") {
        payload[field] = nullableNumber(value, true);
      } else if (field === "branches") {
        payload[field] = normalizeBranch(value);
      } else {
        payload[field] = nullableText(value);
      }
    });
    return payload;
  }

  function readPayloadFromContainer(container, attrName) {
    const rawPayload = {};
    container.querySelectorAll(`[${attrName}]`).forEach((field) => {
      const key = field.getAttribute(attrName);
      rawPayload[key] = field.type === "checkbox" ? field.checked : field.value;
    });
    return coerceMenuPayload(rawPayload);
  }

  async function updateMenuItem(id, payload) {
    if (!supabaseClient || !state.menuSession) {
      throw new Error("저장하려면 먼저 로그인하세요.");
    }
    const { data, error } = await supabaseClient
      .from("menu_items")
      .update(payload)
      .eq("id", id)
      .select(getMenuSelect())
      .single();
    if (error) throw error;
    const normalized = normalizeMenuItem(data);
    state.menuItems = state.menuItems.map((item) => String(item.id) === String(id) ? normalized : item);
    return normalized;
  }

  function syncVisualPreview(card) {
    const payload = readPayloadFromContainer(card, "data-visual-field");
    const nameKo = card.querySelector("[data-preview-name-ko]");
    const nameEn = card.querySelector("[data-preview-name-en]");
    const description = card.querySelector("[data-preview-description]");
    const price = card.querySelector("[data-preview-price]");
    const image = card.querySelector("[data-preview-image]");
    const tags = card.querySelector("[data-preview-tags]");
    if (nameKo) nameKo.textContent = payload.name_ko || payload.name_en || "이름 없음";
    if (nameEn) nameEn.textContent = payload.name_en || "";
    if (description) description.textContent = payload.description || "설명 없음";
    if (price) price.textContent = formatPrice(payload.price);
    if (image) image.src = payload.image_url || FALLBACK_IMAGE;
    if (tags && ("tags" in payload || "ingredient" in payload)) {
      tags.innerHTML = renderTagBadgesFromValues(payload.tags, payload.ingredient);
    }
  }

  function updateTokenGroup(group) {
    const input = group?.querySelector("[data-visual-field], [data-editor-field]");
    if (!input) return;
    input.value = [...group.querySelectorAll("[data-token-toggle].is-selected")]
      .map((button) => button.dataset.tokenToggle)
      .filter(Boolean)
      .join(", ");
  }

  function handleTokenPickerClick(event) {
    const tokenToggle = event.target.closest("[data-token-toggle]");
    if (tokenToggle) {
      const group = tokenToggle.closest("[data-token-group]");
      tokenToggle.classList.toggle("is-selected");
      updateTokenGroup(group);
      const card = tokenToggle.closest(".menu-preview-card");
      if (card) syncVisualPreview(card);
      return true;
    }

    const tokenAdd = event.target.closest("[data-token-add]");
    if (!tokenAdd) return false;

    const group = tokenAdd.closest("[data-token-group]");
    const customInput = group?.querySelector("[data-token-custom]");
    const value = customInput?.value.trim();
    if (group && customInput && value) {
      const existing = [...group.querySelectorAll("[data-token-toggle]")]
        .find((button) => button.dataset.tokenToggle.toLowerCase() === value.toLowerCase());
      if (existing) {
        existing.classList.add("is-selected");
      } else {
        const button = document.createElement("button");
        button.className = "option-chip is-selected";
        button.type = "button";
        button.dataset.tokenToggle = value;
        button.textContent = value;
        group.querySelector(".option-chip-row")?.appendChild(button);
      }
      customInput.value = "";
      updateTokenGroup(group);
      const card = tokenAdd.closest(".menu-preview-card");
      if (card) syncVisualPreview(card);
    }
    return true;
  }

  async function saveVisualCard(id) {
    const card = refs.menuList.querySelector(`[data-menu-id="${CSS.escape(String(id))}"]`);
    if (!card) return;
    setMenuStatus("메뉴 카드를 저장하는 중...");
    try {
      const data = await updateMenuItem(id, readPayloadFromContainer(card, "data-visual-field"));
      syncCategoryOrder();
      renderMenu();
      setMenuStatus(`${data.name_ko || data.name_en || "메뉴"} 저장 완료.`, "success");
    } catch (error) {
      setMenuStatus(error.message, "error");
    }
  }

  function getSortBaseForCategory(category) {
    const index = Math.max(state.categoryOrder.indexOf(category), 0);
    return (index + 1) * SORT_BASE_STEP;
  }

  async function saveSortUpdates(updates, field = "sort_order") {
    if (!supabaseClient || !state.menuSession) {
      throw new Error("순서를 저장하려면 먼저 로그인하세요.");
    }
    const results = await Promise.all(
      updates.map((item) => supabaseClient
        .from("menu_items")
        .update({ [field]: item[field] })
        .eq("id", item.id)
        .select(getMenuSelect())
        .single())
    );
    const failed = results.find((result) => result.error);
    if (failed) throw failed.error;
    const byId = new Map(results.map((result) => [String(result.data.id), normalizeMenuItem(result.data)]));
    state.menuItems = state.menuItems.map((item) => byId.get(String(item.id)) || item);
  }

  async function saveCategoryOrder() {
    const categories = [...refs.menuCategoryOrderList.querySelectorAll("[data-category]")]
      .map((row) => row.dataset.category)
      .filter(Boolean);
    if (!categories.length) return;
    const updates = [];
    categories.forEach((category, categoryIndex) => {
      state.menuItems
        .filter((item) => item.category === category)
        .sort(compareMenuItems)
        .forEach((item, itemIndex) => {
          updates.push({
            id: item.id,
            sort_order: (categoryIndex + 1) * SORT_BASE_STEP + (itemIndex + 1) * 10
          });
        });
    });
    setMenuStatus("카테고리 버튼 순서를 저장하는 중...");
    try {
      await saveSortUpdates(updates);
      state.categoryOrder = categories;
      closeCategoryOrderModal();
      renderMenu();
      setMenuStatus("카테고리 버튼 순서를 저장했습니다.", "success");
    } catch (error) {
      setMenuStatus(error.message, "error");
    }
  }

  async function saveMenuOrder() {
    const rows = [...refs.menuOrderList.querySelectorAll("[data-menu-id]")];
    const isAll = state.menuOrderView === "all";
    if (isAll && !state.supportsAllSortOrder) {
      setMenuStatus("전체 순서를 저장하려면 Supabase에 all_sort_order 컬럼을 먼저 추가하세요.", "error");
      return;
    }
    const base = isAll ? 0 : getSortBaseForCategory(state.menuOrderView);
    const field = isAll ? "all_sort_order" : "sort_order";
    const updates = rows.map((row, index) => ({
      id: row.dataset.menuId,
      [field]: base + (index + 1) * 10
    }));
    setMenuStatus(`${formatOrderScopeLabel(isAll ? "all" : state.menuOrderView)} 순서를 저장하는 중...`);
    try {
      await saveSortUpdates(updates, field);
      renderMenu();
      setMenuStatus(`${formatOrderScopeLabel(isAll ? "all" : state.menuOrderView)} 순서를 저장했습니다.`, "success");
    } catch (error) {
      setMenuStatus(error.message, "error");
    }
  }

  function openMenuEditor(item = null) {
    const isNew = !item;
    refs.menuEditorTitle.textContent = isNew ? "메뉴 추가" : "메뉴 편집";
    refs.menuEditorForm.reset();
    byId("menuEditId").value = item?.id ?? "";
    byId("menuEditNameKo").value = item?.name_ko ?? "";
    byId("menuEditNameEn").value = item?.name_en ?? "";
    byId("menuEditRomanizedName").value = item?.romanized_name ?? "";
    byId("menuEditPrice").value = item?.price ?? "";
    byId("menuEditCategory").value = item?.category ?? (state.menuCategory !== "all" ? state.menuCategory : "");
    byId("menuEditLabel").innerHTML = renderSelectOptions(getMenuOptionValues("label"), item?.label ?? "", "라벨 없음");
    byId("menuEditLabel").value = item?.label ?? "";
    byId("menuEditBranch").value = item?.branches ?? "both";
    byId("menuEditSortOrder").value = item?.sort_order ?? "";
    byId("menuEditDescription").value = item?.description ?? "";
    byId("menuEditImageUrl").value = item?.image_url ?? "";
    renderEditorTokenPicker("menuEditTagsPicker", "tags", item?.tags ?? "");
    renderEditorTokenPicker("menuEditIngredientPicker", "ingredient", item?.ingredient ?? "");
    byId("menuEditAvailable").checked = item?.is_available !== false;
    refs.menuDeleteBtn.hidden = isNew;
    refs.menuEditorModal.classList.add("is-open");
    refs.menuEditorModal.setAttribute("aria-hidden", "false");
  }

  function closeMenuEditor() {
    refs.menuEditorModal.classList.remove("is-open");
    refs.menuEditorModal.setAttribute("aria-hidden", "true");
  }

  function openCategoryOrderModal() {
    renderCategoryOrder();
    refs.menuCategoryOrderModal.classList.add("is-open");
    refs.menuCategoryOrderModal.setAttribute("aria-hidden", "false");
  }

  function closeCategoryOrderModal() {
    refs.menuCategoryOrderModal.classList.remove("is-open");
    refs.menuCategoryOrderModal.setAttribute("aria-hidden", "true");
  }

  function readMenuEditorPayload() {
    const editorTokens = readPayloadFromContainer(refs.menuEditorForm, "data-editor-field");
    return coerceMenuPayload({
      name_ko: byId("menuEditNameKo").value,
      name_en: byId("menuEditNameEn").value,
      romanized_name: byId("menuEditRomanizedName").value,
      price: byId("menuEditPrice").value,
      category: byId("menuEditCategory").value,
      label: byId("menuEditLabel").value,
      branches: byId("menuEditBranch").value,
      sort_order: byId("menuEditSortOrder").value,
      description: byId("menuEditDescription").value,
      image_url: byId("menuEditImageUrl").value,
      tags: editorTokens.tags,
      ingredient: editorTokens.ingredient,
      is_available: byId("menuEditAvailable").checked
    });
  }

  async function saveMenuEditor(event) {
    event.preventDefault();
    if (!supabaseClient || !state.menuSession) {
      setMenuStatus("저장하려면 먼저 로그인하세요.", "error");
      return;
    }
    const id = byId("menuEditId").value;
    const payload = readMenuEditorPayload();
    if (!payload.name_ko && !payload.name_en) {
      setMenuStatus("메뉴 이름을 입력하세요.", "error");
      return;
    }
    if (!payload.category) {
      setMenuStatus("카테고리를 입력하세요.", "error");
      return;
    }

    setMenuStatus("메뉴를 저장하는 중...");
    const query = id
      ? supabaseClient.from("menu_items").update(payload).eq("id", id)
      : supabaseClient.from("menu_items").insert(payload);
    const { data, error } = await query.select(getMenuSelect()).single();
    if (error) {
      setMenuStatus(error.message, "error");
      return;
    }
    if (id) {
      state.menuItems = state.menuItems.map((item) => String(item.id) === String(id) ? normalizeMenuItem(data) : item);
    } else {
      state.menuItems = [...state.menuItems, normalizeMenuItem(data)];
    }
    closeMenuEditor();
    syncCategoryOrder();
    renderMenu();
    setMenuStatus("메뉴를 저장했습니다.", "success");
  }

  async function deleteMenuItem() {
    const id = byId("menuEditId").value;
    if (!id || !supabaseClient || !state.menuSession) return;
    const item = getMenuById(id);
    const ok = window.confirm(`${item?.name_ko || item?.name_en || "이 메뉴"}를 삭제할까요?`);
    if (!ok) return;
    setMenuStatus("메뉴를 삭제하는 중...");
    const { error } = await supabaseClient.from("menu_items").delete().eq("id", id);
    if (error) {
      setMenuStatus(error.message, "error");
      return;
    }
    state.menuItems = state.menuItems.filter((menuItem) => String(menuItem.id) !== String(id));
    closeMenuEditor();
    syncCategoryOrder();
    renderMenu();
    setMenuStatus("메뉴를 삭제했습니다.", "success");
  }

  function setScheduleStatus(message = "", type = "") {
    refs.scheduleStatus.textContent = message;
    refs.scheduleStatus.className = `status-line${type ? ` is-${type}` : ""}`;
  }

  function getScheduleWeekStart() {
    const selected = toSafeDate(refs.scheduleWeekStart.value);
    return formatInputDate(startOfWeek(selected || new Date()));
  }

  function getScheduleWeekDates() {
    const weekStart = toSafeDate(state.scheduleWeekStart || getScheduleWeekStart()) || startOfWeek(new Date());
    return Array.from({ length: 7 }, (_unused, index) => addDays(weekStart, index));
  }

  function getScheduleWeekOptions() {
    const todayWeek = startOfWeek(new Date());
    const defaultBase = todayWeek;
    const base = toSafeDate(state.scheduleWeekWindowStart) || defaultBase;
    return Array.from({ length: 3 }, (_unused, index) => {
      const start = addWeeks(base, index);
      const end = addDays(start, 6);
      const weekStart = formatInputDate(start);
      const dbWeek = state.scheduleWeeks.find((week) => week.week_start === weekStart);
      return {
        weekStart,
        start,
        end,
        label: getScheduleWeekRelativeLabel(start, todayWeek),
        status: dbWeek?.status || "empty"
      };
    });
  }

  function getScheduleWeekRelativeLabel(weekStart, todayWeek = startOfWeek(new Date())) {
    const diffWeeks = Math.round((startOfDay(weekStart).getTime() - startOfDay(todayWeek).getTime()) / 604800000);
    if (diffWeeks === -1) return "저번주";
    if (diffWeeks === 0) return "이번주";
    if (diffWeeks === 1) return "다음주";
    if (diffWeeks < 0) return `${Math.abs(diffWeeks)}주 전`;
    return `${diffWeeks}주 후`;
  }

  function formatScheduleDayLabel(date) {
    return new Intl.DateTimeFormat("ko-KR", {
      weekday: "short",
      month: "numeric",
      day: "numeric"
    }).format(date);
  }

  function formatScheduleDayCompactLabel(date) {
    const weekdays = ["일", "월", "화", "수", "목", "금", "토"];
    return { day: `${date.getDate()}일`, weekday: weekdays[date.getDay()] };
  }

  function formatWeekRangeLabel(start, end) {
    return `${start.getMonth() + 1}/${start.getDate()} - ${end.getMonth() + 1}/${end.getDate()}`;
  }

  function getNthWeekdayOfMonth(year, month, weekday, occurrence) {
    const date = new Date(year, month, 1);
    const offset = (weekday - date.getDay() + 7) % 7;
    date.setDate(1 + offset + (occurrence - 1) * 7);
    return date;
  }

  function getEasterSunday(year) {
    const a = year % 19;
    const b = Math.floor(year / 100);
    const c = year % 100;
    const d = Math.floor(b / 4);
    const e = b % 4;
    const f = Math.floor((b + 8) / 25);
    const g = Math.floor((b - f + 1) / 3);
    const h = (19 * a + b - d - g + 15) % 30;
    const i = Math.floor(c / 4);
    const k = c % 4;
    const l = (32 + 2 * e + 2 * i - h - k) % 7;
    const m = Math.floor((a + 11 * h + 22 * l) / 451);
    const month = Math.floor((h + l - 7 * m + 114) / 31) - 1;
    const day = (h + l - 7 * m + 114) % 31 + 1;
    return new Date(year, month, day);
  }

  function getOntarioPublicHolidays(year) {
    if (ontarioHolidayCache.has(year)) return ontarioHolidayCache.get(year);

    const easterSunday = getEasterSunday(year);
    const goodFriday = addDays(easterSunday, -2);
    const victoriaDay = new Date(year, 4, 24);
    victoriaDay.setDate(victoriaDay.getDate() - ((victoriaDay.getDay() + 6) % 7));
    const holidays = [
      { date: new Date(year, 0, 1), title: "New Year's Day" },
      { date: getNthWeekdayOfMonth(year, 1, 1, 3), title: "Family Day" },
      { date: goodFriday, title: "Good Friday" },
      { date: victoriaDay, title: "Victoria Day" },
      { date: new Date(year, 6, 1), title: "Canada Day" },
      { date: getNthWeekdayOfMonth(year, 8, 1, 1), title: "Labour Day" },
      { date: getNthWeekdayOfMonth(year, 9, 1, 2), title: "Thanksgiving Day" },
      { date: new Date(year, 11, 25), title: "Christmas Day" },
      { date: new Date(year, 11, 26), title: "Boxing Day" }
    ].map((item) => ({
      ...item,
      date: formatInputDate(item.date),
      type: "holiday"
    }));
    const byDate = new Map(holidays.map((item) => [item.date, item]));
    ontarioHolidayCache.set(year, byDate);
    return byDate;
  }

  function getOntarioPublicHoliday(isoDate = "") {
    const date = toSafeDate(isoDate);
    if (!date) return null;
    return getOntarioPublicHolidays(date.getFullYear()).get(isoDate) || null;
  }

  function getOntarioCalendarObservances(year) {
    const easterMonday = addDays(getEasterSunday(year), 1);
    return [
      { date: formatInputDate(easterMonday), title: "Easter Monday", type: "observance" },
      { date: formatInputDate(getNthWeekdayOfMonth(year, 7, 1, 1)), title: "Civic Holiday", type: "observance" },
      { date: formatInputDate(new Date(year, 8, 30)), title: "National Day for Truth and Reconciliation", type: "observance" },
      { date: formatInputDate(new Date(year, 10, 11)), title: "Remembrance Day", type: "observance" }
    ];
  }

  function normalizeScheduleCalendarEvent(item = {}) {
    const id = String(item.id || "").trim();
    const eventDate = String(item.event_date || item.date || "").slice(0, 10);
    const title = String(item.title || "").trim().slice(0, 80);
    if (!id || !/^\d{4}-\d{2}-\d{2}$/.test(eventDate) || !title) return null;
    return {
      id,
      event_date: eventDate,
      title
    };
  }

  function getScheduleDateCalendarInfo(isoDate = "") {
    const holiday = getOntarioPublicHoliday(isoDate);
    const date = toSafeDate(isoDate);
    const observances = date
      ? getOntarioCalendarObservances(date.getFullYear()).filter((item) => item.date === isoDate)
      : [];
    const events = [
      ...observances,
      ...state.scheduleCalendarEvents.filter((item) => item.event_date === isoDate)
    ];
    const labels = [
      holiday ? `Ontario public holiday: ${holiday.title}` : "",
      ...events.map((item) => `Event: ${item.title}`)
    ].filter(Boolean);
    return { holiday, events, labels };
  }

  function renderScheduleWeekCalendarNotices() {
    if (!refs.scheduleWeekCalendarNotices) return;
    const notices = getScheduleWeekDates().flatMap((date) => {
      const isoDate = formatInputDate(date);
      const info = getScheduleDateCalendarInfo(isoDate);
      const dateLabel = `${date.getMonth() + 1}/${date.getDate()} ${formatScheduleDayCompactLabel(date).weekday}`;
      return [
        info.holiday ? { dateLabel, kind: "holiday", marker: "H", title: info.holiday.title } : null,
        ...info.events.map((item) => ({ dateLabel, kind: "event", marker: "E", title: item.title }))
      ].filter(Boolean);
    });

    refs.scheduleWeekCalendarNotices.hidden = !notices.length;
    refs.scheduleWeekCalendarNotices.innerHTML = notices.map((item) => `
      <span class="schedule-week-calendar-notice is-${item.kind}" title="${escapeHtml(`${item.dateLabel} ${item.title}`)}">
        <i aria-hidden="true">${item.marker}</i>
        <b>${escapeHtml(item.dateLabel)}</b>
        <strong>${escapeHtml(item.title)}</strong>
      </span>
    `).join("");
  }

  function setScheduleCalendarEventStatus(message = "", type = "") {
    if (!refs.scheduleCalendarEventStatus) return;
    refs.scheduleCalendarEventStatus.textContent = message;
    refs.scheduleCalendarEventStatus.className = `status-line schedule-calendar-event-status${type ? ` is-${type}` : ""}`;
  }

  function renderScheduleCalendarEventList() {
    if (!refs.scheduleCalendarEventList) return;
    const cursor = state.scheduleMonthCursor instanceof Date
      ? startOfMonth(state.scheduleMonthCursor)
      : startOfMonth(toSafeDate(state.scheduleWeekStart) || new Date());
    const monthStart = formatInputDate(cursor);
    const monthEnd = formatInputDate(new Date(cursor.getFullYear(), cursor.getMonth() + 1, 0));
    const holidayItems = Array.from(getOntarioPublicHolidays(cursor.getFullYear()).values())
      .filter((item) => item.date >= monthStart && item.date <= monthEnd);
    const observanceItems = getOntarioCalendarObservances(cursor.getFullYear())
      .filter((item) => item.date >= monthStart && item.date <= monthEnd)
      .map((item) => ({ ...item, isManual: false }));
    const eventItems = state.scheduleCalendarEvents
      .filter((item) => item.event_date >= monthStart && item.event_date <= monthEnd)
      .map((item) => ({ ...item, isManual: true }))
      .sort((a, b) => a.event_date.localeCompare(b.event_date) || a.title.localeCompare(b.title));
    const items = [
      ...holidayItems.map((item) => ({ ...item, isHoliday: true })),
      ...observanceItems.map((item) => ({ ...item, isHoliday: false })),
      ...eventItems.map((item) => ({ ...item, isHoliday: false }))
    ].sort((a, b) => {
      const aDate = a.date || a.event_date;
      const bDate = b.date || b.event_date;
      return aDate.localeCompare(bDate) || Number(b.isHoliday) - Number(a.isHoliday);
    });

    refs.scheduleCalendarEventList.innerHTML = items.length ? items.map((item) => {
      const date = item.date || item.event_date;
      const dateLabel = new Intl.DateTimeFormat("ko-KR", { month: "numeric", day: "numeric", weekday: "short" }).format(toSafeDate(date));
      return `
        <div class="schedule-calendar-event-item ${item.isHoliday ? "is-holiday" : "is-event"}">
          <span>${escapeHtml(dateLabel)}</span>
          <strong>${escapeHtml(item.title)}</strong>
          ${item.isManual ? `<button type="button" data-delete-schedule-calendar-event="${escapeHtml(item.id)}" aria-label="${escapeHtml(`${item.title} 이벤트 삭제`)}">×</button>` : ""}
        </div>
      `;
    }).join("") : '<div class="schedule-calendar-empty">이번 달 등록된 이벤트가 없습니다.</div>';
  }

  async function fetchScheduleCalendarEvents() {
    if (!supabaseClient || !state.menuSession) {
      state.scheduleCalendarEvents = [];
      renderScheduleMonthCalendar();
      return;
    }

    const { data, error } = await supabaseClient
      .from("king_schedule_calendar_events")
      .select("id,event_date,title")
      .order("event_date", { ascending: true })
      .order("created_at", { ascending: true });

    if (error) {
      state.scheduleCalendarEvents = [];
      setScheduleCalendarEventStatus(error.message, "error");
      renderScheduleMonthCalendar();
      return;
    }

    state.scheduleCalendarEvents = (data || []).map(normalizeScheduleCalendarEvent).filter(Boolean);
    renderScheduleMonthCalendar();
  }

  async function saveScheduleCalendarEvent(event) {
    event.preventDefault();
    const eventDate = refs.scheduleCalendarEventDate.value;
    const title = refs.scheduleCalendarEventTitle.value.trim().slice(0, 80);
    if (!eventDate || !title) {
      setScheduleCalendarEventStatus("날짜와 이벤트 이름을 입력하세요.", "error");
      return;
    }

    if (!supabaseClient || !state.menuSession) {
      setScheduleCalendarEventStatus("관리자 로그인 후 이벤트를 저장할 수 있습니다.", "error");
      return;
    }

    const { data, error } = await supabaseClient
      .from("king_schedule_calendar_events")
      .insert({ event_date: eventDate, title, created_by: state.menuSession.user?.id || null })
      .select("id,event_date,title")
      .single();
    if (error || !data) {
      setScheduleCalendarEventStatus(error?.message || "이벤트를 저장하지 못했습니다.", "error");
      return;
    }

    const savedItem = normalizeScheduleCalendarEvent(data);
    state.scheduleCalendarEvents = [...state.scheduleCalendarEvents, savedItem]
      .filter(Boolean)
      .sort((a, b) => a.event_date.localeCompare(b.event_date) || a.title.localeCompare(b.title));
    setScheduleCalendarEventStatus("이벤트를 저장했습니다.", "success");
    refs.scheduleCalendarEventTitle.value = "";
    renderScheduleBoard();
  }

  async function deleteScheduleCalendarEvent(id = "") {
    const target = state.scheduleCalendarEvents.find((item) => item.id === id);
    if (!target) return;
    if (!supabaseClient || !state.menuSession) {
      setScheduleCalendarEventStatus("관리자 로그인 후 이벤트를 삭제할 수 있습니다.", "error");
      return;
    }

    const { error } = await supabaseClient
      .from("king_schedule_calendar_events")
      .delete()
      .eq("id", id);
    if (error) {
      setScheduleCalendarEventStatus(error.message, "error");
      return;
    }

    state.scheduleCalendarEvents = state.scheduleCalendarEvents.filter((item) => item.id !== id);
    setScheduleCalendarEventStatus("이벤트를 삭제했습니다.", "success");
    renderScheduleBoard();
  }

  function renderScheduleWeekChips() {
    const options = getScheduleWeekOptions();
    refs.scheduleWeekChips.innerHTML = options.map((option) => {
      const isActive = option.weekStart === state.scheduleWeekStart;
      const confirmed = option.status === "published";
      const statusLabel = confirmed ? "확정" : "미작성";
      const classes = [
        "week-chip",
        isActive ? "is-active" : "",
        confirmed ? "is-confirmed" : "is-empty"
      ].filter(Boolean).join(" ");
      return `
        <button class="${classes}" type="button" data-schedule-week="${option.weekStart}">
          <strong>${escapeHtml(option.label || formatWeekRangeLabel(option.start, option.end))}</strong>
          <span>${escapeHtml(formatWeekRangeLabel(option.start, option.end))}</span>
          <span>${escapeHtml(statusLabel)}</span>
        </button>
      `;
    }).join("");
  }

  function renderScheduleMonthCalendar() {
    if (!refs.scheduleMonthGrid || !refs.scheduleMonthLabel) return;
    const selectedWeekStart = toSafeDate(state.scheduleWeekStart);
    const selectedDate = toSafeDate(state.scheduleMonthSelectedDate) || selectedWeekStart;
    const cursor = state.scheduleMonthCursor instanceof Date
      ? startOfMonth(state.scheduleMonthCursor)
      : startOfMonth(selectedWeekStart || new Date());
    const monthEnd = new Date(cursor.getFullYear(), cursor.getMonth() + 1, 0);
    const today = startOfDay(new Date());
    const leadingBlanks = (cursor.getDay() + 6) % 7;
    const cells = [];

    state.scheduleMonthCursor = cursor;
    refs.scheduleMonthLabel.textContent = new Intl.DateTimeFormat("ko-KR", {
      year: "numeric",
      month: "long"
    }).format(cursor);

    for (let index = 0; index < leadingBlanks; index += 1) {
      cells.push('<div class="calendar-day is-empty" aria-hidden="true"></div>');
    }

    for (let day = 1; day <= monthEnd.getDate(); day += 1) {
      const date = new Date(cursor.getFullYear(), cursor.getMonth(), day);
      const isoDate = formatInputDate(date);
      const calendarInfo = getScheduleDateCalendarInfo(isoDate);
      const classes = [
        "calendar-day",
        isSameDate(date, today) ? "is-today" : "",
        selectedDate && isSameDate(date, selectedDate) ? "is-selected" : "",
        calendarInfo.holiday ? "is-holiday" : "",
        calendarInfo.events.length ? "has-calendar-event" : ""
      ].filter(Boolean).join(" ");
      const dateLabel = new Intl.DateTimeFormat("ko-KR", {
        weekday: "short",
        month: "long",
        day: "numeric"
      }).format(date);

      cells.push(`
        <button class="${classes}" type="button" data-schedule-month-date="${isoDate}" aria-label="${escapeHtml(`${dateLabel} 주간 스케줄 보기`)}">
          <strong>${day}</strong>
          ${calendarInfo.labels.length ? `<span class="calendar-day-markers" aria-hidden="true">${calendarInfo.holiday ? '<i class="is-holiday">H</i>' : ""}${calendarInfo.events.length ? '<i class="is-event">E</i>' : ""}</span>` : ""}
        </button>
      `);
    }

    refs.scheduleMonthGrid.innerHTML = cells.join("");
    renderScheduleCalendarEventList();
  }

  function normalizeScheduleStaffKey(name = "") {
    return String(name || "").trim().toLowerCase().replace(/\s+/g, "");
  }

  function normalizeBranchScope(value = "") {
    const normalized = String(value || "").trim().toLowerCase();
    if (normalized.includes("down")) return "downtown";
    if (normalized.includes("up")) return "uptown";
    if (normalized === "all" || normalized === "both" || normalized.includes("both")) return "both";
    return normalized || "both";
  }

  function getDefaultServerCount(date) {
    const day = date.getDay();
    return day === 5 || day === 6 ? 3 : 2;
  }

  function normalizeStaffRef(item = {}) {
    const rawName = item.staff_name || item.name || item.display_name || item.employee_name || item.server_name || item.staff_key || item.ref_code || "";
    const staffKey = item.staff_key || item.key || item.employee_key || rawName;
    const branchScope = normalizeBranchScope(item.branch_scope || item.branches || item.branch || item.location || "both");
    const name = String(rawName || staffKey || "").trim();
    if (!name) return null;
    return {
      ...item,
      name,
      staff_key: String(staffKey || name).trim(),
      normalized: normalizeScheduleStaffKey(staffKey || name),
      branch_scope: branchScope,
      job_role: item.job_role || item.role || "server",
      preferred_branch: normalizeBranchScope(item.preferred_branch || item.preferredBranch || item.favorite_branch || ""),
      work_style: String(item.work_style || item.workStyle || item.preference_style || "").trim().toLowerCase(),
      fixed_unavailable_weekdays: normalizeWeekdayList(item.fixed_unavailable_weekdays || item.fixedUnavailableWeekdays),
      fixed_preferred_weekdays: normalizeWeekdayList(item.fixed_preferred_weekdays || item.fixedPreferredWeekdays),
      max_weekly_shifts: normalizeMaxWeeklyShifts(item.max_weekly_shifts || item.maxWeeklyShifts)
    };
  }

  function normalizeWeekdayList(value) {
    const weekdayMap = {
      sun: 0,
      sunday: 0,
      일: 0,
      mon: 1,
      monday: 1,
      월: 1,
      tue: 2,
      tuesday: 2,
      화: 2,
      wed: 3,
      wednesday: 3,
      수: 3,
      thu: 4,
      thursday: 4,
      목: 4,
      fri: 5,
      friday: 5,
      금: 5,
      sat: 6,
      saturday: 6,
      토: 6
    };
    let raw;
    if (Array.isArray(value)) {
      raw = value;
    } else if (typeof value === "string") {
      const text = value.trim();
      try {
        const parsed = JSON.parse(text);
        raw = Array.isArray(parsed) ? parsed : [parsed];
      } catch (_error) {
        raw = text
          .replace(/^[{[(]\s*|\s*[}\])]\s*$/g, "")
          .split(/[,\s|/]+/);
      }
    } else {
      raw = [value];
    }

    return Array.from(new Set(raw
      .map((item) => {
        const text = String(item).trim().toLowerCase().replace(/^["']+|["']+$/g, "");
        if (!text) return null;
        if (/^[0-6]$/.test(text)) return Number(text);
        return weekdayMap[text] ?? null;
      })
      .filter((item) => item !== null)))
      .sort((a, b) => a - b);
  }

  function normalizeMaxWeeklyShifts(value) {
    if (value === "" || value === null || value === undefined) return null;
    const number = Number.parseInt(value, 10);
    if (!Number.isFinite(number)) return null;
    return Math.max(1, Math.min(7, number));
  }

  function getScheduleStaffPool() {
    const fromRefs = state.scheduleStaff || [];
    if (fromRefs.length) return fromRefs;

    const byKey = new Map();
    state.scheduleAvailability.forEach((item) => {
      const staff = normalizeStaffRef(item);
      if (staff && !byKey.has(staff.normalized)) byKey.set(staff.normalized, staff);
    });
    return Array.from(byKey.values());
  }

  function getScheduleStaffByKey(key = "") {
    const normalized = normalizeScheduleStaffKey(key);
    if (!normalized) return null;
    return getScheduleStaffPool().find((staff) => (
      normalizeScheduleStaffKey(staff.staff_key || staff.name) === normalized ||
      normalizeScheduleStaffKey(staff.name) === normalized
    )) || null;
  }

  function getSelectedScheduleStaff() {
    return getScheduleStaffByKey(state.scheduleSelectedStaffKey);
  }

  function isStaffUnavailableOnDate(staff, isoDate) {
    if (!staff || !isoDate) return false;
    const date = toSafeDate(isoDate);
    if (!date) return false;
    return getAvailabilityForStaff(staff, isoDate)?.status === "unavailable" ||
      Boolean(staff.fixed_unavailable_weekdays?.includes(date.getDay()));
  }

  function getStaffUnavailableLabel(staff, isoDate) {
    const availability = getAvailabilityForStaff(staff, isoDate);
    if (availability?.status === "unavailable") return "일반 불가";
    return "고정 불가";
  }

  function branchMatchesStaff(staff, branch) {
    const scope = normalizeBranchScope(staff.branch_scope);
    return scope === "both" || scope === branch;
  }

  function getAvailabilityForStaff(staff, isoDate) {
    const key = normalizeScheduleStaffKey(staff.staff_key || staff.name);
    const nameKey = normalizeScheduleStaffKey(staff.name);
    return state.scheduleAvailability.find((item) => {
      if (item.availability_date !== isoDate) return false;
      const itemKey = normalizeScheduleStaffKey(item.staff_key || item.staff_name);
      const itemName = normalizeScheduleStaffKey(item.staff_name || item.staff_key);
      return itemKey === key || itemKey === nameKey || itemName === key || itemName === nameKey;
    }) || null;
  }

  function getScheduleCellKey(branch, dateValue) {
    return `${branch}|${dateValue}`;
  }

  function getScheduleShiftNoteKey(cellKey, name = "") {
    return `${cellKey}|${normalizeScheduleStaffKey(name)}`;
  }

  function getScheduleShiftNote(cellKey, name = "") {
    return String(state.scheduleShiftNotes.get(getScheduleShiftNoteKey(cellKey, name)) || "").trim();
  }

  function setScheduleShiftNote(cellKey, name = "", note = "") {
    const key = getScheduleShiftNoteKey(cellKey, name);
    const value = String(note || "").trim();
    if (value) state.scheduleShiftNotes.set(key, value);
    else state.scheduleShiftNotes.delete(key);
  }

  function removeScheduleShiftNote(cellKey, name = "") {
    state.scheduleShiftNotes.delete(getScheduleShiftNoteKey(cellKey, name));
  }

  function hydrateScheduleShiftNotes(shifts = []) {
    state.scheduleShiftNotes = new Map();
    shifts.forEach((shift) => {
      const note = String(shift.note || "").trim();
      if (!note) return;
      const cellKey = getScheduleCellKey(shift.branch, shift.shift_date);
      setScheduleShiftNote(cellKey, shift.staff_name || shift.staff_key, note);
    });
  }

  function getShiftNamesByCell() {
    const map = new Map();
    state.scheduleShifts.forEach((shift) => {
      const key = getScheduleCellKey(shift.branch, shift.shift_date);
      const list = map.get(key) || [];
      list.push(shift.staff_name || shift.staff_key || "");
      map.set(key, list.filter(Boolean));
    });
    return map;
  }

  function getScheduleNamesByCellFromBoard() {
    const map = new Map();
    refs.scheduleBoard?.querySelectorAll("[data-schedule-cell]").forEach((textarea) => {
      map.set(String(textarea.dataset.scheduleCell || ""), getCurrentNames(textarea));
    });
    return map;
  }

  function getScheduleTargetsByCellFromBoard() {
    const map = new Map();
    refs.scheduleBoard?.querySelectorAll("[data-schedule-target]").forEach((input) => {
      const target = Number.parseInt(input.value || "", 10);
      if (Number.isFinite(target)) map.set(String(input.dataset.scheduleTarget || ""), Math.max(0, target));
    });
    return map;
  }

  function getScheduleAssignmentContextFromMap(namesByCell) {
    const staffPool = getScheduleStaffPool();
    const byStaff = new Map();
    const byDate = new Map();
    namesByCell.forEach((names, cellKey) => {
      const [branch, isoDate] = String(cellKey || "").split("|");
      if (!branch || !isoDate) return;
      names.forEach((name) => {
        const staffId = getStaffIdentity(name, staffPool);
        const staffRows = byStaff.get(staffId) || [];
        staffRows.push({ branch, isoDate, name });
        byStaff.set(staffId, staffRows);

        const dateSet = byDate.get(isoDate) || new Set();
        dateSet.add(staffId);
        byDate.set(isoDate, dateSet);
      });
    });
    return { byStaff, byDate };
  }

  function getScheduleDropStatus(staff, branch, isoDate, names = [], context = getBoardAssignments()) {
    if (!staff) return { allowed: false, type: "none", label: "" };
    if (!branchMatchesStaff(staff, branch)) {
      return { allowed: false, type: "branch", label: "매장 불가" };
    }
    if (isStaffUnavailableOnDate(staff, isoDate)) {
      return { allowed: false, type: "unavailable", label: getStaffUnavailableLabel(staff, isoDate) };
    }

    const staffKey = normalizeScheduleStaffKey(staff.staff_key || staff.name);
    const nameKeys = new Set(names.map(normalizeScheduleStaffKey));
    if (nameKeys.has(staffKey) || nameKeys.has(normalizeScheduleStaffKey(staff.name))) {
      return { allowed: false, type: "assigned", label: "이미 배정됨" };
    }

    const sameDayAssignments = context.byStaff.get(staffKey) || [];
    if (sameDayAssignments.some((item) => item.isoDate === isoDate)) {
      return { allowed: false, type: "double-booked", label: "다른 매장 근무" };
    }

    const maxWeeklyShifts = normalizeMaxWeeklyShifts(staff.max_weekly_shifts);
    if (maxWeeklyShifts && new Set(sameDayAssignments.map((item) => item.isoDate)).size >= maxWeeklyShifts) {
      return { allowed: false, type: "weekly-limit", label: `주 ${maxWeeklyShifts}일 한도` };
    }

    return { allowed: true, type: "ready", label: "여기에 놓기 / 탭하여 배정" };
  }

  function renderAvailabilityList(status, target) {
    const weekDates = getScheduleWeekDates();
    const weekStart = weekDates[0] ? startOfDay(weekDates[0]).getTime() : null;
    const weekEnd = weekDates[6] ? startOfDay(weekDates[6]).getTime() : null;
    const dateItems = state.scheduleAvailability
      .filter((item) => {
        if (item.status !== status) return false;
        const date = toSafeDate(item.availability_date);
        if (!date || weekStart === null || weekEnd === null) return false;
        const time = startOfDay(date).getTime();
        return time >= weekStart && time <= weekEnd;
      });
    const fixedItems = getFixedPreferenceItems(status);
    const mergedItems = new Map();
    [...dateItems, ...fixedItems].forEach((item) => {
      const key = `${normalizeScheduleStaffKey(item.staff_key || item.staff_name)}|${item.availability_date}`;
      const existing = mergedItems.get(key);
      // A one-off entry can add a time or note to the same recurring weekday.
      mergedItems.set(key, existing ? { ...item, ...existing } : item);
    });
    const items = Array.from(mergedItems.values())
      .sort((a, b) => String(a.availability_date).localeCompare(String(b.availability_date)) || String(a.staff_name || a.staff_key).localeCompare(String(b.staff_name || b.staff_key)));

    if (!items.length) {
      target.innerHTML = '<div class="empty-state">데이터 없음</div>';
      return;
    }

    target.innerHTML = items.map((item) => {
      const date = toSafeDate(item.availability_date);
      const time = item.available_start || item.available_end
        ? `${item.available_start || "open"} - ${item.available_end || "close"}`
        : "";
      const detail = [time, item.note].filter(Boolean).join(" · ");
      return `
        <div class="availability-row is-${escapeHtml(status)}">
          <span>${escapeHtml(item.staff_name || item.staff_key || "-")}</span>
          <span class="availability-meta">
            <b>${escapeHtml(date ? formatScheduleDayLabel(date) : item.availability_date || "-")}</b>
            ${detail ? `<small>${escapeHtml(detail)}</small>` : ""}
          </span>
        </div>
      `;
    }).join("");
  }

  function getFixedPreferenceItems(status) {
    const dates = getScheduleWeekDates();
    const weekdayField = status === "unavailable" ? "fixed_unavailable_weekdays" : "fixed_preferred_weekdays";
    const items = [];

    getScheduleStaffPool().forEach((staff) => {
      const weekdays = normalizeWeekdayList(staff[weekdayField]);
      if (!weekdays.length) return;

      dates.forEach((date) => {
        if (!weekdays.includes(date.getDay())) return;
        items.push({
          staff_key: staff.staff_key,
          staff_name: staff.name,
          branch_scope: staff.branch_scope,
          availability_date: formatInputDate(date),
          status
        });
      });
    });

    return items;
  }

  function getScheduleStaffDateState(staff, isoDate) {
    const date = toSafeDate(isoDate);
    if (!staff || !date) return null;
    const availability = getAvailabilityForStaff(staff, isoDate);
    if (availability?.status === "unavailable") return { type: "unavailable", label: "일반 불가" };
    if (staff.fixed_unavailable_weekdays?.includes(date.getDay())) return { type: "unavailable", label: "고정 불가" };
    if (availability?.status === "preferred") return { type: "preferred", label: "일반 선호" };
    if (staff.fixed_preferred_weekdays?.includes(date.getDay())) return { type: "preferred", label: "고정 선호" };
    return null;
  }

  function getSelectedScheduleCellContext() {
    const cellKey = state.scheduleSelectedCellKey;
    const [branch, isoDate] = String(cellKey || "").split("|");
    const textarea = cellKey ? getScheduleTextarea(cellKey) : null;
    if (!branch || !isoDate || !textarea) return null;
    return { cellKey, branch, isoDate, names: getCurrentNames(textarea) };
  }

  function renderScheduleStaffList() {
    const staff = getScheduleStaffPool()
      .slice()
      .sort((a, b) => a.branch_scope.localeCompare(b.branch_scope) || a.name.localeCompare(b.name));
    const selectedKey = normalizeScheduleStaffKey(state.scheduleSelectedStaffKey);
    const assignmentContext = getBoardAssignments();
    const selectedCell = getSelectedScheduleCellContext();
    const selectedDate = selectedCell ? toSafeDate(selectedCell.isoDate) : null;

    if (!staff.length) {
      refs.scheduleStaffList.innerHTML = '<div class="empty-state">서버 목록이 없습니다.</div>';
      return;
    }

    refs.scheduleStaffList.innerHTML = `
      ${state.scheduleUsingFallbackStaff ? '<div class="empty-state">employee_refs가 비어 있어 임시 서버 목록을 표시 중입니다.</div>' : ""}
      ${selectedCell && selectedDate ? `
        <div class="schedule-selection-context">
          <b>${escapeHtml(`${formatScheduleDayLabel(selectedDate)} · ${formatBranchLabel(selectedCell.branch)}`)}</b>
          <span><i class="is-available">✓</i> 가능 <i class="is-preferred">★</i> 선호 <i class="is-unavailable">×</i> 불가</span>
        </div>
      ` : ""}
      ${staff.map((item) => {
        const staffId = normalizeScheduleStaffKey(item.staff_key || item.name);
        const assignedDays = new Set((assignmentContext.byStaff.get(staffId) || []).map((assignment) => assignment.isoDate)).size;
        const dayState = selectedCell ? getScheduleStaffDateState(item, selectedCell.isoDate) : null;
        const dropStatus = selectedCell
          ? getScheduleDropStatus(item, selectedCell.branch, selectedCell.isoDate, selectedCell.names, assignmentContext)
          : null;
        const isAssigned = Boolean(selectedCell && dropStatus?.type === "assigned");
        const isBlocked = Boolean(selectedCell && !dropStatus?.allowed && !isAssigned);
        const isPreferred = Boolean(selectedCell && !isBlocked && dayState?.type === "preferred");
        const isAvailable = Boolean(selectedCell && dropStatus?.allowed && !isPreferred);
        const stateLabel = isAssigned
          ? "배정됨 · 탭해서 삭제"
          : isBlocked
            ? dropStatus?.label
            : isPreferred
              ? "선호 · 가능"
              : isAvailable
                ? "가능"
                : "";
        const indicator = isBlocked ? "×" : isAssigned ? "−" : isPreferred ? "★" : isAvailable ? "✓" : "";
        const stateClass = isBlocked
          ? "is-day-unavailable"
          : isAssigned
            ? "is-day-assigned"
            : isPreferred
              ? "is-day-preferred"
              : isAvailable
                ? "is-day-available"
                : "";
        const isSelected = selectedKey === staffId;
        return `
        <button
          class="staff-pill is-${escapeHtml(normalizeBranchScope(item.branch_scope))} ${isSelected ? "is-selected" : ""} ${selectedCell ? "is-date-context" : ""} ${stateClass}"
          type="button"
          data-schedule-staff="${escapeHtml(item.staff_key || item.name)}"
          aria-pressed="${isSelected ? "true" : "false"}"
          aria-label="${escapeHtml(selectedCell ? `${item.name}: ${stateLabel || "배정 가능"}` : `${item.name}, 이번 주 ${assignedDays}일 배정`)}"
          title="${escapeHtml(selectedCell ? `${item.name}: ${stateLabel || "배정 가능"}` : `${item.name}: 이번 주 ${assignedDays}일 배정`)}"
        >
          <span class="staff-pill-name">${escapeHtml(item.name)}</span>
          <span class="staff-pill-meta">
            ${selectedCell
              ? (indicator ? `<b class="staff-pill-day-mark" aria-hidden="true">${indicator}</b>` : "")
              : `<small>${escapeHtml(formatBranchLabel(item.branch_scope))}</small><b class="staff-pill-count" aria-hidden="true">${assignedDays}일</b>`}
          </span>
        </button>
      `;
      }).join("")}
    `;
  }

  function renderScheduleBoard(options = {}) {
    const { preserveBoardEdits = true } = options;
    const branches = [
      { key: "uptown", label: "Uptown" },
      { key: "downtown", label: "Downtown" }
    ];
    const dates = getScheduleWeekDates();
    const shiftMap = getShiftNamesByCell();
    const boardNames = preserveBoardEdits ? getScheduleNamesByCellFromBoard() : new Map();
    const boardTargets = preserveBoardEdits ? getScheduleTargetsByCellFromBoard() : new Map();
    const namesByCell = new Map(shiftMap);
    boardNames.forEach((names, cellKey) => namesByCell.set(cellKey, names));
    const assignmentContext = getScheduleAssignmentContextFromMap(namesByCell);
    const selectedStaff = getSelectedScheduleStaff();
    const today = startOfDay(new Date());

    refs.scheduleWeekLabel.textContent = state.scheduleWeekStart
      ? `${formatScheduleDayLabel(dates[0])} - ${formatScheduleDayLabel(dates[6])}`
      : "주간 선택";

    if (state.scheduleWeekStart) {
      const weekStateLabel = state.scheduleWeek?.status === "published" ? "확정" : "미작성";
      refs.scheduleWeekLabel.textContent = `${formatScheduleDayLabel(dates[0])} - ${formatScheduleDayLabel(dates[6])} / ${weekStateLabel}`;
    }

    refs.scheduleBoard.innerHTML = branches.map((branch) => `
      <section class="schedule-branch is-${branch.key}">
        <h4>${escapeHtml(branch.label)}</h4>
        <div class="schedule-day-grid">
          ${dates.map((date) => {
            const dateValue = formatInputDate(date);
            const cellKey = getScheduleCellKey(branch.key, dateValue);
            const calendarInfo = getScheduleDateCalendarInfo(dateValue);
            const names = namesByCell.get(cellKey) || [];
            const targetCount = Math.max(boardTargets.get(cellKey) ?? getDefaultServerCount(date), names.length);
            const compactDayLabel = formatScheduleDayCompactLabel(date);
            const dropStatus = getScheduleDropStatus(selectedStaff, branch.key, dateValue, names, assignmentContext);
            const dayState = selectedStaff ? getScheduleStaffDateState(selectedStaff, dateValue) : null;
            const isTargetedCell = state.scheduleSelectedCellKey === cellKey;
            const isPreferred = Boolean(selectedStaff && dropStatus.allowed && dayState?.type === "preferred");
            const dropHint = selectedStaff
              ? isPreferred
                ? "선호 · 배정 가능"
                : dropStatus.label
              : "";
            const dropClasses = [
              "schedule-dropzone",
              isTargetedCell ? "is-targeted" : "",
              selectedStaff && dropStatus.allowed ? "is-ready" : "",
              isPreferred ? "is-preferred" : "",
              selectedStaff && !dropStatus.allowed && dropStatus.type !== "none" ? "is-blocked" : "",
              selectedStaff && dropStatus.type === "assigned" ? "is-assigned" : ""
            ].filter(Boolean).join(" ");
            return `
              <article class="schedule-day-card is-${branch.key} ${isSameDate(date, today) ? "is-today" : ""} ${calendarInfo.holiday ? "is-holiday" : ""} ${calendarInfo.events.length ? "has-calendar-event" : ""}" title="${escapeHtml(calendarInfo.labels.join(" · "))}">
                <div class="schedule-day-top">
                  <header>
                    <button class="schedule-day-select-trigger" type="button" data-schedule-select-cell="${escapeHtml(cellKey)}" aria-label="${escapeHtml(`${formatScheduleDayLabel(date)} ${branch.label} 선택`)}">
                      <strong aria-hidden="true">
                        <span class="schedule-day-label-full">${escapeHtml(formatScheduleDayLabel(date))}</span>
                        <span class="schedule-day-label-compact"><small>${escapeHtml(compactDayLabel.weekday)}</small>${escapeHtml(compactDayLabel.day)}</span>
                      </strong>
                    </button>
                    <span class="schedule-branch-label">${escapeHtml(branch.label)}</span>
                  </header>
                  <label class="server-count-field${state.scheduleDetailsOpen ? "" : " is-hidden"}">
                    <span>인원</span>
                    <input data-schedule-target="${escapeHtml(cellKey)}" type="number" min="0" max="8" value="${targetCount}" inputmode="numeric" />
                  </label>
                </div>
                <div
                  class="${dropClasses}"
                  data-schedule-dropzone="${escapeHtml(cellKey)}"
                  role="group"
                  tabindex="0"
                  aria-label="${escapeHtml(`${formatScheduleDayLabel(date)} ${branch.label}: ${dropStatus.label}`)}"
                >
                  <div class="schedule-assignment-list">
                    ${names.map((name) => {
                      const note = getScheduleShiftNote(cellKey, name);
                      return `
                        <button
                          class="schedule-assignment${note ? " has-note" : ""}"
                          type="button"
                          data-remove-schedule-assignment="${escapeHtml(cellKey)}"
                          data-schedule-note-cell="${escapeHtml(cellKey)}"
                          data-schedule-name="${escapeHtml(name)}"
                          aria-label="${escapeHtml(`${name}${note ? ` · ${note}` : ""}. 길게 눌러 근무 메모`)}"
                        >
                          <span class="schedule-assignment-content">
                            <span class="schedule-assignment-name">${escapeHtml(name)}</span>
                            ${note ? `<small class="schedule-assignment-note"><span class="schedule-assignment-note-text">${escapeHtml(note)}</span></small>` : ""}
                          </span>
                          <span class="schedule-assignment-remove" aria-hidden="true">×</span>
                        </button>
                      `;
                    }).join("")}
                  </div>
                  <span class="schedule-drop-hint">${escapeHtml(dropHint)}</span>
                </div>
                <textarea class="schedule-value" data-schedule-cell="${escapeHtml(cellKey)}" aria-hidden="true" tabindex="-1">${escapeHtml(names.join("\n"))}</textarea>
              </article>
            `;
          }).join("")}
        </div>
      </section>
    `).join("");

    renderScheduleWeekCalendarNotices();
    renderAvailabilityList("unavailable", refs.unavailableList);
    renderAvailabilityList("preferred", refs.preferredList);
    renderScheduleStaffList();
    renderScheduleWeekChips();
    renderScheduleMonthCalendar();
    refs.scheduleDetailToggleBtn.textContent = state.scheduleDetailsOpen ? "세부 설정 닫기" : "세부 설정";
    refs.scheduleDetailToggleBtn.classList.toggle("is-active", state.scheduleDetailsOpen);
    refs.scheduleDetailToggleBtn.setAttribute("aria-expanded", String(state.scheduleDetailsOpen));
  }

  async function fetchScheduleData() {
    if (!supabaseClient || !state.menuSession) {
      setScheduleStatus("메뉴변경 탭에서 관리자 로그인 후 사용할 수 있습니다.", "error");
      renderScheduleBoard();
      return;
    }

    const fetchToken = ++state.scheduleFetchToken;
    state.scheduleWeekStart = getScheduleWeekStart();
    const selectedWeekStart = state.scheduleWeekStart;
    refs.scheduleWeekStart.value = selectedWeekStart;
    const dates = getScheduleWeekDates();
    const weekOptions = getScheduleWeekOptions();
    const weekWindowFrom = weekOptions[0]?.weekStart || selectedWeekStart;
    const weekWindowTo = weekOptions[weekOptions.length - 1]?.weekStart || selectedWeekStart;
    const availabilityWindowEnd = formatInputDate(addDays(toSafeDate(weekWindowTo) || dates[6], 6));
    setScheduleStatus("스케줄 데이터를 불러오는 중...");
    await fetchScheduleCalendarEvents();
    if (fetchToken !== state.scheduleFetchToken) return;

    const availabilityResult = await supabaseClient
      .from("noble_staff_availability")
      .select("staff_key,staff_name,branch_scope,availability_date,status,available_start,available_end,note")
      .gte("availability_date", weekWindowFrom)
      .lte("availability_date", availabilityWindowEnd)
      .order("availability_date", { ascending: true });

    if (fetchToken !== state.scheduleFetchToken) return;
    if (availabilityResult.error) {
      setScheduleStatus(availabilityResult.error.message, "error");
      return;
    }

    const staffResult = await fetchEmployeeRefRows();

    if (fetchToken !== state.scheduleFetchToken) return;
    if (staffResult.error) {
      console.warn("Could not load employee refs", staffResult.error);
    }

    const preferencesResult = await supabaseClient
      .from("noble_staff_preferences")
      .select("*");

    if (fetchToken !== state.scheduleFetchToken) return;
    if (preferencesResult.error) {
      console.warn("Could not load staff preferences", preferencesResult.error);
    }

    const weeksResult = await supabaseClient
      .from("noble_schedule_weeks")
      .select("id,week_start,status,note")
      .gte("week_start", weekWindowFrom)
      .lte("week_start", weekWindowTo)
      .order("week_start", { ascending: true });

    if (fetchToken !== state.scheduleFetchToken) return;

    const weekResult = await supabaseClient
      .from("noble_schedule_weeks")
      .select("id,week_start,status,note")
      .eq("week_start", selectedWeekStart)
      .maybeSingle();

    if (fetchToken !== state.scheduleFetchToken) return;
    if (weekResult.error) {
      setScheduleStatus(weekResult.error.message, "error");
      return;
    }

    const preferenceByKey = new Map();
    (preferencesResult.data || [])
      .map(normalizeStaffRef)
      .filter(Boolean)
      .forEach((preference) => {
        preferenceByKey.set(normalizeScheduleStaffKey(preference.staff_key || preference.name), preference);
        preferenceByKey.set(normalizeScheduleStaffKey(preference.name), preference);
      });
    const applyStaffPreferences = (staff) => {
      const preference = preferenceByKey.get(normalizeScheduleStaffKey(staff.staff_key || staff.name))
        || preferenceByKey.get(normalizeScheduleStaffKey(staff.name));
      if (!preference) return staff;
      return normalizeStaffRef({
        ...staff,
        fixed_unavailable_weekdays: preference.fixed_unavailable_weekdays,
        fixed_preferred_weekdays: preference.fixed_preferred_weekdays,
        preferred_branch: preference.preferred_branch,
        work_style: preference.work_style,
        max_weekly_shifts: preference.max_weekly_shifts
      });
    };
    const dbStaff = (staffResult.data || [])
      .map(normalizeStaffRef)
      .filter(Boolean)
      .filter((staff) => staff.active !== false)
      .filter((staff) => normalizeScheduleStaffKey(staff.job_role) !== "kitchen")
      .map(applyStaffPreferences);

    const staffSource = dbStaff.length
      ? dbStaff
      : FALLBACK_SERVER_REFS.map(normalizeStaffRef).filter(Boolean).map(applyStaffPreferences);
    const mergedStaff = new Map();
    staffSource
      .filter(Boolean)
      .forEach((staff) => {
        mergedStaff.set(normalizeScheduleStaffKey(staff.staff_key || staff.name), staff);
      });
    const scheduleStaff = Array.from(mergedStaff.values());
    let scheduleShifts = [];

    if (weekResult.data?.id) {
      const shiftsResult = await supabaseClient
        .from("noble_schedule_shifts")
        .select("id,week_id,shift_date,branch,staff_key,staff_name,job_role,shift_label,start_time,end_time,sort_order,note")
        .eq("week_id", weekResult.data.id)
        .order("branch", { ascending: true })
        .order("shift_date", { ascending: true })
        .order("sort_order", { ascending: true });

      if (fetchToken !== state.scheduleFetchToken) return;
      if (shiftsResult.error) {
        setScheduleStatus(shiftsResult.error.message, "error");
        return;
      }
      scheduleShifts = shiftsResult.data || [];
    }

    if (fetchToken !== state.scheduleFetchToken) return;
    if (!weeksResult.error) state.scheduleWeeks = weeksResult.data || [];
    state.scheduleAvailability = availabilityResult.data || [];
    state.scheduleStaff = scheduleStaff;
    state.scheduleUsingFallbackStaff = !dbStaff.length;
    state.scheduleWeek = weekResult.data || null;
    state.scheduleShifts = scheduleShifts;
    state.scheduleDataLoaded = true;
    hydrateScheduleShiftNotes(scheduleShifts);
    renderScheduleBoard({ preserveBoardEdits: false });
    setScheduleStatus("스케줄 데이터를 불러왔습니다.", "success");
  }

  function collectScheduleRows(weekId) {
    const rows = [];
    const staffPool = getScheduleStaffPool();
    refs.scheduleBoard.querySelectorAll("[data-schedule-cell]").forEach((textarea) => {
      const [branch, shiftDate] = String(textarea.dataset.scheduleCell || "").split("|");
      if (!branch || !shiftDate) return;
      String(textarea.value || "")
        .split(/\r?\n/)
        .map((name) => name.trim())
        .filter(Boolean)
        .forEach((name, index) => {
          const staff = staffPool.find((item) => normalizeScheduleStaffKey(item.name) === normalizeScheduleStaffKey(name) || normalizeScheduleStaffKey(item.staff_key) === normalizeScheduleStaffKey(name));
          rows.push({
            week_id: weekId,
            shift_date: shiftDate,
            branch,
            staff_key: staff?.staff_key || normalizeScheduleStaffKey(name),
            staff_name: staff?.name || name,
            job_role: staff?.job_role || "server",
            sort_order: index,
            note: getScheduleShiftNote(getScheduleCellKey(branch, shiftDate), staff?.name || name) || null
          });
        });
    });
    return rows;
  }

  function collectScheduleNamesByCellFromBoard() {
    const map = new Map();
    refs.scheduleBoard.querySelectorAll("[data-schedule-cell]").forEach((textarea) => {
      map.set(String(textarea.dataset.scheduleCell || ""), getCurrentNames(textarea));
    });
    return map;
  }

  function drawRoundRect(ctx, x, y, width, height, radius) {
    const safeRadius = Math.min(radius, width / 2, height / 2);
    ctx.beginPath();
    ctx.moveTo(x + safeRadius, y);
    ctx.lineTo(x + width - safeRadius, y);
    ctx.quadraticCurveTo(x + width, y, x + width, y + safeRadius);
    ctx.lineTo(x + width, y + height - safeRadius);
    ctx.quadraticCurveTo(x + width, y + height, x + width - safeRadius, y + height);
    ctx.lineTo(x + safeRadius, y + height);
    ctx.quadraticCurveTo(x, y + height, x, y + height - safeRadius);
    ctx.lineTo(x, y + safeRadius);
    ctx.quadraticCurveTo(x, y, x + safeRadius, y);
    ctx.closePath();
  }

  function fillRoundRect(ctx, x, y, width, height, radius, fillStyle) {
    drawRoundRect(ctx, x, y, width, height, radius);
    ctx.fillStyle = fillStyle;
    ctx.fill();
  }

  function strokeRoundRect(ctx, x, y, width, height, radius, strokeStyle, lineWidth = 1) {
    drawRoundRect(ctx, x, y, width, height, radius);
    ctx.strokeStyle = strokeStyle;
    ctx.lineWidth = lineWidth;
    ctx.stroke();
  }

  function drawFittedText(ctx, text, x, y, maxWidth, options = {}) {
    const {
      size = 24,
      minSize = 13,
      weight = 800,
      color = "#2f2118",
      align = "center",
      baseline = "middle",
      ellipsis = false
    } = options;
    let fittedText = String(text);
    let fontSize = size;
    ctx.textAlign = align;
    ctx.textBaseline = baseline;
    ctx.fillStyle = color;
    do {
      ctx.font = `${weight} ${fontSize}px "Malgun Gothic", "Apple SD Gothic Neo", Arial, sans-serif`;
      if (ctx.measureText(fittedText).width <= maxWidth || fontSize <= minSize) break;
      fontSize -= 1;
    } while (fontSize > minSize);
    if (ellipsis && ctx.measureText(fittedText).width > maxWidth) {
      while (fittedText && ctx.measureText(`${fittedText}...`).width > maxWidth) {
        fittedText = fittedText.slice(0, -1);
      }
      fittedText = fittedText ? `${fittedText}...` : "";
    }
    ctx.fillText(fittedText, x, y);
  }

  function drawScheduleClipboardEntry(ctx, entry, x, y, maxWidth, color) {
    const fontFamily = '"Malgun Gothic", "Apple SD Gothic Neo", Arial, sans-serif';
    const nameSize = 24;
    const noteSize = 18;
    const noteText = entry.note ? ` - ${entry.note}` : "";

    if (!noteText) {
      drawFittedText(ctx, entry.name, x, y, maxWidth, {
        size: nameSize,
        minSize: nameSize,
        weight: 900,
        color,
        ellipsis: true
      });
      return;
    }

    ctx.textAlign = "left";
    ctx.textBaseline = "middle";
    ctx.font = `900 ${nameSize}px ${fontFamily}`;
    const nameWidth = ctx.measureText(entry.name).width;
    if (nameWidth > maxWidth) {
      drawFittedText(ctx, entry.name, x, y, maxWidth, {
        size: nameSize,
        minSize: nameSize,
        weight: 900,
        color,
        ellipsis: true
      });
      return;
    }

    const availableNoteWidth = maxWidth - nameWidth;
    ctx.font = `800 ${noteSize}px ${fontFamily}`;
    let fittedNote = noteText;
    if (ctx.measureText(fittedNote).width > availableNoteWidth) {
      let noteBody = noteText;
      while (noteBody && ctx.measureText(`${noteBody}...`).width > availableNoteWidth) {
        noteBody = noteBody.slice(0, -1);
      }
      fittedNote = noteBody ? `${noteBody}...` : "";
    }

    const noteWidth = fittedNote ? ctx.measureText(fittedNote).width : 0;
    const totalWidth = nameWidth + noteWidth;
    const startX = x - totalWidth / 2;
    ctx.fillStyle = color;
    ctx.font = `900 ${nameSize}px ${fontFamily}`;
    ctx.fillText(entry.name, startX, y);
    if (fittedNote) {
      ctx.font = `800 ${noteSize}px ${fontFamily}`;
      ctx.fillText(fittedNote, startX + nameWidth, y);
    }
  }

  function buildScheduleClipboardCanvas() {
    const dates = getScheduleWeekDates();
    const namesByCell = collectScheduleNamesByCellFromBoard();
    const branchWidth = 164;
    const dayWidth = 190;
    const margin = 44;
    const titleHeight = 96;
    const headerHeight = 62;
    const rowGap = 12;
    const entryLineHeight = 31;
    const entryGap = 8;
    const entriesByCell = new Map();
    SCHEDULE_BRANCHES.forEach((branch) => {
      dates.forEach((date) => {
        const cellKey = getScheduleCellKey(branch.key, formatInputDate(date));
        entriesByCell.set(cellKey, (namesByCell.get(cellKey) || [])
          .map((name) => ({ name, note: getScheduleShiftNote(cellKey, name) })));
      });
    });
    const maxCellContentHeight = Math.max(
      0,
      ...Array.from(entriesByCell.values()).map((entries) => (
        entries.length * entryLineHeight +
        Math.max(0, entries.length - 1) * entryGap
      ))
    );
    const rowHeight = Math.max(150, maxCellContentHeight + 36);
    const width = margin * 2 + branchWidth + dayWidth * dates.length;
    const height = margin * 2 + titleHeight + headerHeight + SCHEDULE_BRANCHES.length * rowHeight + (SCHEDULE_BRANCHES.length - 1) * rowGap + 22;
    const canvas = document.createElement("canvas");
    const scale = Math.min(Math.max(window.devicePixelRatio || 1, 1), 2);
    canvas.width = Math.round(width * scale);
    canvas.height = Math.round(height * scale);
    canvas.style.width = `${width}px`;
    canvas.style.height = `${height}px`;

    const ctx = canvas.getContext("2d");
    ctx.scale(scale, scale);
    ctx.fillStyle = "#fbf4ea";
    ctx.fillRect(0, 0, width, height);

    fillRoundRect(ctx, margin - 14, margin - 14, width - (margin - 14) * 2, height - (margin - 14) * 2, 28, "#fffaf3");
    strokeRoundRect(ctx, margin - 14, margin - 14, width - (margin - 14) * 2, height - (margin - 14) * 2, 28, "rgba(113, 88, 60, 0.18)", 2);

    const weekTitle = dates.length
      ? `${formatScheduleDayLabel(dates[0])} - ${formatScheduleDayLabel(dates[6])}`
      : "주간 스케줄";
    drawFittedText(ctx, "EHWA 스케줄", margin, margin + 16, width - margin * 2, {
      size: 36,
      minSize: 24,
      weight: 900,
      align: "left",
      baseline: "top",
      color: "#2b1b15"
    });
    drawFittedText(ctx, weekTitle, margin, margin + 60, width - margin * 2, {
      size: 24,
      minSize: 16,
      weight: 900,
      align: "left",
      baseline: "top",
      color: "#7b1f2f"
    });

    const tableX = margin;
    const headerY = margin + titleHeight;
    fillRoundRect(ctx, tableX, headerY, branchWidth, headerHeight, 16, "#f3e6d5");
    drawFittedText(ctx, "Branch", tableX + branchWidth / 2, headerY + headerHeight / 2, branchWidth - 24, {
      size: 20,
      weight: 900,
      color: "#6c4e3a"
    });

    dates.forEach((date, index) => {
      const x = tableX + branchWidth + index * dayWidth;
      fillRoundRect(ctx, x + 4, headerY, dayWidth - 8, headerHeight, 16, "#f3e6d5");
      const compactDay = formatScheduleDayCompactLabel(date);
      drawFittedText(ctx, compactDay.weekday, x + dayWidth / 2, headerY + 24, dayWidth - 24, {
        size: 23,
        minSize: 18,
        weight: 950,
        color: "#2f2118"
      });
      drawFittedText(ctx, `${date.getMonth() + 1}/${date.getDate()}`, x + dayWidth / 2, headerY + 47, dayWidth - 24, {
        size: 14,
        minSize: 12,
        weight: 850,
        color: "#6c5b52"
      });
    });

    SCHEDULE_BRANCHES.forEach((branch, branchIndex) => {
      const y = headerY + headerHeight + rowGap + branchIndex * (rowHeight + rowGap);
      fillRoundRect(ctx, tableX, y, branchWidth, rowHeight, 18, branch.bg);
      strokeRoundRect(ctx, tableX, y, branchWidth, rowHeight, 18, branch.border, 2);
      drawFittedText(ctx, branch.label, tableX + branchWidth / 2, y + rowHeight / 2, branchWidth - 22, {
        size: 25,
        weight: 900,
        color: branch.color
      });

      dates.forEach((date, index) => {
        const x = tableX + branchWidth + index * dayWidth;
        const cellKey = getScheduleCellKey(branch.key, formatInputDate(date));
        const names = namesByCell.get(cellKey) || [];
        fillRoundRect(ctx, x + 4, y, dayWidth - 8, rowHeight, 18, branch.bg);
        strokeRoundRect(ctx, x + 4, y, dayWidth - 8, rowHeight, 18, branch.border, 2);

        if (!names.length) {
          drawFittedText(ctx, "-", x + dayWidth / 2, y + rowHeight / 2, dayWidth - 30, {
            size: 22,
            weight: 800,
            color: "rgba(47, 33, 24, 0.42)"
          });
          return;
        }

        const entries = entriesByCell.get(cellKey) || [];
        const contentHeight = entries.length * entryLineHeight +
          Math.max(0, entries.length - 1) * entryGap;
        let entryY = y + (rowHeight - contentHeight) / 2;
        entries.forEach((entry, entryIndex) => {
          drawScheduleClipboardEntry(ctx, entry, x + dayWidth / 2, entryY + entryLineHeight / 2, dayWidth - 32, branch.color);
          entryY += entryLineHeight;
          if (entryIndex < entries.length - 1) entryY += entryGap;
        });
      });
    });

    return canvas;
  }

  function canvasToBlob(canvas) {
    return new Promise((resolve) => {
      canvas.toBlob((blob) => resolve(blob), "image/png");
    });
  }

  function downloadScheduleCanvas(canvas) {
    const link = document.createElement("a");
    link.download = `ehwa-schedule-${state.scheduleWeekStart || "week"}.png`;
    link.href = canvas.toDataURL("image/png");
    link.click();
  }

  async function copyScheduleImageToClipboard() {
    const hasBoard = Boolean(refs.scheduleBoard.querySelector("[data-schedule-cell]"));
    if (!hasBoard) {
      setScheduleStatus("복사할 스케줄 표가 없습니다.", "error");
      return;
    }

    setScheduleStatus("스케줄 이미지를 만드는 중...");
    const canvas = buildScheduleClipboardCanvas();
    const blob = await canvasToBlob(canvas);
    if (!blob) {
      setScheduleStatus("이미지 생성에 실패했습니다.", "error");
      return;
    }

    try {
      if (!navigator.clipboard?.write || typeof ClipboardItem === "undefined") {
        downloadScheduleCanvas(canvas);
        setScheduleStatus("이 브라우저는 이미지 클립보드를 지원하지 않아 PNG로 저장했습니다.", "success");
        return;
      }

      await navigator.clipboard.write([new ClipboardItem({ [blob.type]: blob })]);
      setScheduleStatus("스케줄 이미지를 클립보드에 복사했습니다.", "success");
    } catch (error) {
      console.warn("Schedule clipboard copy failed", error);
      downloadScheduleCanvas(canvas);
      setScheduleStatus("클립보드 복사가 막혀 PNG로 저장했습니다.", "error");
    }
  }

  function findSameDayDoubleBookings() {
    const context = getBoardAssignments();
    const conflicts = [];
    context.byStaff.forEach((assignments) => {
      const byDate = new Map();
      assignments.forEach((item) => {
        const rows = byDate.get(item.isoDate) || [];
        rows.push(item);
        byDate.set(item.isoDate, rows);
      });
      byDate.forEach((rows, isoDate) => {
        const branches = new Set(rows.map((item) => item.branch));
        if (branches.size > 1) {
          conflicts.push(`${rows[0].name} ${isoDate}`);
        }
      });
    });
    return conflicts;
  }

  function getCurrentNames(textarea) {
    return String(textarea.value || "")
      .split(/\r?\n/)
      .map((name) => name.trim())
      .filter(Boolean);
  }

  function selectScheduleStaff(staff, allowToggle = true) {
    if (!staff) return;
    const selectedCellKey = state.scheduleSelectedCellKey;
    if (selectedCellKey && getScheduleTextarea(selectedCellKey)) {
      assignScheduleStaffToCell(staff, selectedCellKey, {
        keepStaffSelected: false,
        keepCellSelected: true
      });
      return;
    }
    state.scheduleSelectedCellKey = "";
    const staffKey = normalizeScheduleStaffKey(staff.staff_key || staff.name);
    state.scheduleSelectedStaffKey = allowToggle && state.scheduleSelectedStaffKey === staffKey ? "" : staffKey;
    renderScheduleBoard();
  }

  function getScheduleTextarea(cellKey) {
    return Array.from(refs.scheduleBoard.querySelectorAll("[data-schedule-cell]"))
      .find((textarea) => textarea.dataset.scheduleCell === cellKey) || null;
  }

  function assignScheduleStaffToCell(staff, cellKey, options = {}) {
    const { keepStaffSelected = true, keepCellSelected = false } = options;
    const [branch, isoDate] = String(cellKey || "").split("|");
    const textarea = getScheduleTextarea(cellKey);
    if (!staff || !branch || !isoDate || !textarea) return;

    const names = getCurrentNames(textarea);
    const staffKeys = new Set([
      normalizeScheduleStaffKey(staff.staff_key || staff.name),
      normalizeScheduleStaffKey(staff.name)
    ]);
    const isAlreadyAssigned = names.some((name) => staffKeys.has(normalizeScheduleStaffKey(name)));
    if (isAlreadyAssigned) {
      textarea.value = names
        .filter((name) => !staffKeys.has(normalizeScheduleStaffKey(name)))
        .join("\n");
      names
        .filter((name) => staffKeys.has(normalizeScheduleStaffKey(name)))
        .forEach((name) => removeScheduleShiftNote(cellKey, name));
      state.scheduleSelectedCellKey = keepCellSelected ? cellKey : "";
      state.scheduleSelectedStaffKey = keepStaffSelected
        ? normalizeScheduleStaffKey(staff.staff_key || staff.name)
        : "";
      renderScheduleBoard();
      setScheduleStatus(`${staff.name} · ${formatScheduleDayLabel(toSafeDate(isoDate))} ${formatBranchLabel(branch)} 배정을 삭제했습니다.`, "success");
      return;
    }

    const dropStatus = getScheduleDropStatus(staff, branch, isoDate, names, getBoardAssignments());
    if (!dropStatus.allowed) {
      if (dropStatus.type === "unavailable") {
        const date = toSafeDate(isoDate);
        const confirmed = window.confirm(
          `${staff.name}님은 ${formatScheduleDayLabel(date)}에 ${dropStatus.label}로 등록되어 있습니다.\n그래도 직접 배정할까요?`
        );
        if (!confirmed) return;
      } else {
        renderScheduleBoard();
        setScheduleStatus(`${staff.name}: ${dropStatus.label}`, "error");
        return;
      }
    }

    textarea.value = [...names, staff.name].join("\n");
    state.scheduleSelectedCellKey = keepCellSelected ? cellKey : "";
    state.scheduleSelectedStaffKey = keepStaffSelected
      ? normalizeScheduleStaffKey(staff.staff_key || staff.name)
      : "";
    renderScheduleBoard();
    setScheduleStatus(`${staff.name} · ${formatScheduleDayLabel(toSafeDate(isoDate))} ${formatBranchLabel(branch)} 배정 완료`, "success");
  }

  function selectScheduleCell(cellKey) {
    if (!getScheduleTextarea(cellKey)) return;
    state.scheduleSelectedCellKey = state.scheduleSelectedCellKey === cellKey ? "" : cellKey;
    state.scheduleSelectedStaffKey = "";
    renderScheduleBoard();
  }

  function removeScheduleStaffFromCell(cellKey, name) {
    const textarea = getScheduleTextarea(cellKey);
    if (!textarea) return;
    const nameKey = normalizeScheduleStaffKey(name);
    const nextNames = getCurrentNames(textarea).filter((item) => normalizeScheduleStaffKey(item) !== nameKey);
    textarea.value = nextNames.join("\n");
    removeScheduleShiftNote(cellKey, name);
    renderScheduleBoard();
    setScheduleStatus(`${name} 배정을 삭제했습니다.`, "");
  }

  function isScheduleStaffAssignedToCell(staff, cellKey) {
    const textarea = getScheduleTextarea(cellKey);
    if (!staff || !textarea) return false;
    const staffKeys = new Set([
      normalizeScheduleStaffKey(staff.staff_key || staff.name),
      normalizeScheduleStaffKey(staff.name)
    ]);
    return getCurrentNames(textarea).some((name) => staffKeys.has(normalizeScheduleStaffKey(name)));
  }

  function openScheduleNoteModal(cellKey, name) {
    const [branch, isoDate] = String(cellKey || "").split("|");
    const date = toSafeDate(isoDate);
    if (!branch || !date || !name) return;
    state.scheduleNoteTarget = { cellKey, name };
    refs.scheduleNoteMeta.textContent = `${formatScheduleDayLabel(date)} · ${formatBranchLabel(branch)} · ${name}`;
    refs.scheduleNoteInput.value = getScheduleShiftNote(cellKey, name);
    refs.scheduleNoteModal.setAttribute("aria-hidden", "false");
    refs.scheduleNoteModal.classList.add("is-open");
    window.setTimeout(() => {
      refs.scheduleNoteInput.focus();
      refs.scheduleNoteInput.select();
    }, 0);
  }

  function closeScheduleNoteModal() {
    state.scheduleNoteTarget = null;
    refs.scheduleNoteModal.setAttribute("aria-hidden", "true");
    refs.scheduleNoteModal.classList.remove("is-open");
    refs.scheduleNoteForm.reset();
  }

  function saveScheduleNote(event) {
    event.preventDefault();
    const target = state.scheduleNoteTarget;
    if (!target) return;
    setScheduleShiftNote(target.cellKey, target.name, refs.scheduleNoteInput.value);
    renderScheduleBoard();
    closeScheduleNoteModal();
    setScheduleStatus("근무 메모를 저장했습니다. 확정하면 함께 저장됩니다.", "success");
  }

  function clearScheduleNoteLongPress() {
    window.clearTimeout(state.scheduleNotePressTimer);
    state.scheduleNotePressTimer = null;
    state.scheduleNotePressStart = null;
  }

  function startScheduleNoteLongPress(cellKey, name, event) {
    clearScheduleNoteLongPress();
    state.scheduleNotePressStart = { x: event.clientX, y: event.clientY };
    state.scheduleNotePressTimer = window.setTimeout(() => {
      state.scheduleNoteSuppressClickUntil = Date.now() + 450;
      openScheduleNoteModal(cellKey, name);
      clearScheduleNoteLongPress();
    }, 460);
  }

  function cancelScheduleNoteLongPressOnMove(event) {
    if (!state.scheduleNotePressStart) return;
    const distance = Math.hypot(
      event.clientX - state.scheduleNotePressStart.x,
      event.clientY - state.scheduleNotePressStart.y
    );
    if (distance > 10) clearScheduleNoteLongPress();
  }


  function getStaffIdentity(name, staffPool = getScheduleStaffPool()) {
    const normalized = normalizeScheduleStaffKey(name);
    const staff = staffPool.find((item) => normalizeScheduleStaffKey(item.name) === normalized || normalizeScheduleStaffKey(item.staff_key) === normalized);
    return staff ? normalizeScheduleStaffKey(staff.staff_key || staff.name) : normalized;
  }

  function getBoardAssignments() {
    const staffPool = getScheduleStaffPool();
    const byStaff = new Map();
    const byDate = new Map();
    refs.scheduleBoard.querySelectorAll("[data-schedule-cell]").forEach((textarea) => {
      const [branch, isoDate] = String(textarea.dataset.scheduleCell || "").split("|");
      if (!branch || !isoDate) return;
      getCurrentNames(textarea).forEach((name) => {
        const staffId = getStaffIdentity(name, staffPool);
        const staffRows = byStaff.get(staffId) || [];
        staffRows.push({ branch, isoDate, name });
        byStaff.set(staffId, staffRows);

        const dateSet = byDate.get(isoDate) || new Set();
        dateSet.add(staffId);
        byDate.set(isoDate, dateSet);
      });
    });
    return { byStaff, byDate };
  }

  function getTargetCountForCell(cellKey, date) {
    const input = Array.from(refs.scheduleBoard.querySelectorAll("[data-schedule-target]"))
      .find((item) => item.dataset.scheduleTarget === cellKey);
    const value = Number.parseInt(input?.value || "", 10);
    return Number.isFinite(value) ? Math.max(0, value) : getDefaultServerCount(date);
  }

  function getScheduleShortfalls() {
    const shortfalls = [];
    refs.scheduleBoard.querySelectorAll("[data-schedule-cell]").forEach((textarea) => {
      const [branch, isoDate] = String(textarea.dataset.scheduleCell || "").split("|");
      const date = toSafeDate(isoDate);
      if (!branch || !date) return;
      const target = getTargetCountForCell(textarea.dataset.scheduleCell, date);
      const missing = Math.max(0, target - getCurrentNames(textarea).length);
      if (missing) shortfalls.push({ branch, date, missing });
    });
    return shortfalls;
  }

  function seededShuffle(items = []) {
    return items
      .map((item) => ({ item, roll: Math.random() }))
      .sort((a, b) => a.roll - b.roll)
      .map(({ item }) => item);
  }

  function scoreScheduleCandidate(staff, branch, isoDate, context) {
    const staffId = normalizeScheduleStaffKey(staff.staff_key || staff.name);
    const date = toSafeDate(isoDate);
    const weekday = date ? date.getDay() : null;
    const availability = getAvailabilityForStaff(staff, isoDate);
    const currentDays = new Set((context.byStaff.get(staffId) || []).map((item) => item.isoDate));
    let score = Math.random() * 0.2;

    if (currentDays.size === 0) score += 80;
    else if (currentDays.size === 1) score += 60;
    else score += Math.max(0, 24 - currentDays.size * 4);

    if (availability?.status === "preferred") score += 32;
    if (staff.fixed_preferred_weekdays?.includes(weekday)) score += 24;
    if (normalizeBranchScope(staff.preferred_branch) === branch) score += 40;

    const workStyle = staff.work_style || "";
    const hasAdjacentDay = Array.from(currentDays).some((dateValue) => {
      const assignedDate = toSafeDate(dateValue);
      if (!assignedDate || !date) return false;
      return Math.abs((assignedDate.getTime() - date.getTime()) / 86400000) === 1;
    });
    const hasGapDay = Array.from(currentDays).every((dateValue) => {
      const assignedDate = toSafeDate(dateValue);
      if (!assignedDate || !date) return true;
      return Math.abs((assignedDate.getTime() - date.getTime()) / 86400000) > 1;
    });

    if (workStyle.includes("몰") || workStyle.includes("cluster") || workStyle.includes("together")) {
      score += hasAdjacentDay ? 12 : 0;
    }
    if (workStyle.includes("띄") || workStyle.includes("spread") || workStyle.includes("space")) {
      score += hasGapDay ? 12 : -8;
    }

    if (workStyle.includes("\uBAB0")) {
      score += hasAdjacentDay ? 12 : 0;
    }
    if (workStyle.includes("\uB760")) {
      score += hasGapDay ? 12 : -8;
    }

    return score;
  }

  function getScheduleBranchPreferenceTier(staff, branch) {
    const preferredBranch = normalizeBranchScope(staff?.preferred_branch);
    if (!preferredBranch || preferredBranch === "both") return 1;
    return preferredBranch === branch ? 2 : 0;
  }

  function getCandidatesForCell(branch, isoDate, existingNames = [], context = getBoardAssignments()) {
    const existingKeys = new Set(existingNames.map(normalizeScheduleStaffKey));
    const pool = getScheduleStaffPool();
    const alreadyWorkingThisDate = context.byDate.get(isoDate) || new Set();
    const date = toSafeDate(isoDate);
    const weekday = date ? date.getDay() : null;

    return seededShuffle(pool)
      .map((staff) => {
        const availability = getAvailabilityForStaff(staff, isoDate);
        const staffId = normalizeScheduleStaffKey(staff.staff_key || staff.name);
        const currentShiftDays = new Set((context.byStaff.get(staffId) || []).map((item) => item.isoDate)).size;
        const branchPreferenceTier = getScheduleBranchPreferenceTier(staff, branch);
        return {
          ...staff,
          availability,
          staffId,
          currentShiftDays,
          isFixedPreferredWeekday: Boolean(weekday !== null && staff.fixed_preferred_weekdays?.includes(weekday)),
          branchPreferenceTier,
          isPreferredBranchMatch: branchPreferenceTier === 2,
          isNonPreferredBranch: branchPreferenceTier === 0,
          score: scoreScheduleCandidate(staff, branch, isoDate, context)
        };
      })
      .filter((staff) => branchMatchesStaff(staff, branch))
      .filter((staff) => !existingKeys.has(normalizeScheduleStaffKey(staff.name)) && !existingKeys.has(normalizeScheduleStaffKey(staff.staff_key)))
      .filter((staff) => !alreadyWorkingThisDate.has(staff.staffId))
      .filter((staff) => staff.availability?.status !== "unavailable")
      .filter((staff) => !staff.fixed_unavailable_weekdays?.includes(weekday))
      .filter((staff) => {
        const maxWeeklyShifts = normalizeMaxWeeklyShifts(staff.max_weekly_shifts);
        if (!maxWeeklyShifts) return true;
        const currentDays = new Set((context.byStaff.get(staff.staffId) || []).map((item) => item.isoDate));
        // This is a ceiling only; ranking below still favours the lowest assigned-day count.
        return currentDays.size < maxWeeklyShifts;
      })
      .sort((a, b) => (
        Number(a.isNonPreferredBranch) - Number(b.isNonPreferredBranch) ||
        a.currentShiftDays - b.currentShiftDays ||
        Number(b.isFixedPreferredWeekday) - Number(a.isFixedPreferredWeekday) ||
        Number(b.isPreferredBranchMatch) - Number(a.isPreferredBranchMatch) ||
        b.score - a.score
      ));
  }

  function autoFillSchedule() {
    const pool = getScheduleStaffPool();
    if (!pool.length) {
      setScheduleStatus("서버 목록이 없어서 자동배정을 할 수 없습니다.", "error");
      return;
    }

    let added = 0;
    let context = getBoardAssignments();
    refs.scheduleBoard.querySelectorAll("[data-schedule-cell]").forEach((textarea) => {
      const [branch, isoDate] = String(textarea.dataset.scheduleCell || "").split("|");
      const date = toSafeDate(isoDate);
      if (!branch || !isoDate || !date) return;

      const names = getCurrentNames(textarea);
      const target = getTargetCountForCell(textarea.dataset.scheduleCell, date);
      const needed = Math.max(0, target - names.length);
      if (!needed) return;

      const candidates = getCandidatesForCell(branch, isoDate, names, context);
      const selected = candidates.slice(0, needed).map((staff) => staff.name);
      if (!selected.length) return;

      textarea.value = [...names, ...selected].join("\n");
      added += selected.length;
      context = getBoardAssignments();
    });

    renderScheduleBoard();
    setScheduleStatus(added ? `빈자리 ${added}개를 자동배정했습니다.` : "채울 수 있는 빈자리가 없습니다.", added ? "success" : "");
  }

  function autoFillScheduleV2() {
    const pool = getScheduleStaffPool();
    if (!pool.length) {
      setScheduleStatus("서버 목록이 없어서 자동배정을 할 수 없습니다.", "error");
      return;
    }

    const fillOpenSlots = ({ fixedPreferredOnly = false, context = getBoardAssignments() } = {}) => {
      let added = 0;
      let nextContext = context;

      refs.scheduleBoard.querySelectorAll("[data-schedule-cell]").forEach((textarea) => {
        const [branch, isoDate] = String(textarea.dataset.scheduleCell || "").split("|");
        const date = toSafeDate(isoDate);
        if (!branch || !isoDate || !date) return;

        const names = getCurrentNames(textarea);
        const target = getTargetCountForCell(textarea.dataset.scheduleCell, date);
        const needed = Math.max(0, target - names.length);
        if (!needed) return;

        const candidates = getCandidatesForCell(branch, isoDate, names, nextContext);
        const eligible = fixedPreferredOnly
          ? candidates.filter((staff) => staff.isFixedPreferredWeekday)
          : candidates;
        const selected = eligible.slice(0, needed).map((staff) => staff.name);
        if (!selected.length) return;

        textarea.value = [...names, ...selected].join("\n");
        added += selected.length;
        nextContext = getBoardAssignments();
      });

      return { added, context: nextContext };
    };

    // First reserve eligible open slots for fixed preferred weekdays.
    // The regular pass then balances all remaining shifts across the staff pool.
    const fixedPass = fillOpenSlots({ fixedPreferredOnly: true });
    const regularPass = fillOpenSlots({ context: fixedPass.context });
    const added = fixedPass.added + regularPass.added;

    const finalContext = getBoardAssignments();
    const shortfalls = getScheduleShortfalls();
    const underTwo = pool
      .filter((staff) => {
        const staffId = normalizeScheduleStaffKey(staff.staff_key || staff.name);
        const days = new Set((finalContext.byStaff.get(staffId) || []).map((item) => item.isoDate));
        return days.size > 0 && days.size < 2;
      })
      .map((staff) => staff.name);
    const baseMessage = added ? `빈자리 ${added}개를 자동배정했습니다.` : "필요 인원이 이미 모두 채워져 있습니다.";
    const fixedSuffix = fixedPass.added ? ` 고정 희망 ${fixedPass.added}개를 우선 반영했습니다.` : "";
    const suffix = underTwo.length ? ` 2일 미만: ${underTwo.slice(0, 5).join(", ")}` : "";
    const shortfallSuffix = shortfalls.length
      ? ` 미충족: ${shortfalls.slice(0, 3).map((item) => `${formatScheduleDayLabel(item.date)} ${formatBranchLabel(item.branch)} ${item.missing}명`).join(", ")}`
      : " 필요 인원을 모두 채웠습니다.";
    renderScheduleBoard();
    setScheduleStatus(`${baseMessage}${fixedSuffix}${suffix}${shortfallSuffix}`, shortfalls.length ? "error" : "success");
  }

  async function ensureScheduleWeek() {
    const existing = await supabaseClient
      .from("noble_schedule_weeks")
      .select("id,week_start,status,note")
      .eq("week_start", state.scheduleWeekStart)
      .maybeSingle();

    if (existing.error) throw existing.error;
    if (existing.data?.id) {
      const updated = await supabaseClient
        .from("noble_schedule_weeks")
        .update({ status: "published" })
        .eq("id", existing.data.id)
        .select("id,week_start,status,note")
        .single();
      if (updated.error) throw updated.error;
      return updated.data;
    }

    const inserted = await supabaseClient
      .from("noble_schedule_weeks")
      .insert({ week_start: state.scheduleWeekStart, status: "published" })
      .select("id,week_start,status,note")
      .single();
    if (inserted.error) throw inserted.error;
    return inserted.data;
  }

  async function saveScheduleWeek() {
    if (!supabaseClient || !state.menuSession) {
      setScheduleStatus("메뉴변경 탭에서 관리자 로그인 후 사용할 수 있습니다.", "error");
      return;
    }

    state.scheduleWeekStart = getScheduleWeekStart();
    refs.scheduleWeekStart.value = state.scheduleWeekStart;
    const conflicts = findSameDayDoubleBookings();
    if (conflicts.length) {
      setScheduleStatus(`같은 날 두 지점 배정이 있습니다: ${conflicts.slice(0, 3).join(", ")}`, "error");
      return;
    }
    setScheduleStatus("스케줄을 저장하는 중...");

    try {
      const week = await ensureScheduleWeek();
      const deleteResult = await supabaseClient
        .from("noble_schedule_shifts")
        .delete()
        .eq("week_id", week.id);
      if (deleteResult.error) throw deleteResult.error;

      const rows = collectScheduleRows(week.id);
      if (rows.length) {
        const insertResult = await supabaseClient
          .from("noble_schedule_shifts")
          .insert(rows);
        if (insertResult.error) throw insertResult.error;
      }

      state.scheduleWeek = week;
      state.scheduleWeeks = [
        ...state.scheduleWeeks.filter((item) => item.week_start !== week.week_start),
        week
      ];
      state.scheduleShifts = rows;
      renderScheduleBoard();
      setScheduleStatus("스케줄을 확정했습니다.", "success");
    } catch (error) {
      setScheduleStatus(error.message || "스케줄 저장에 실패했습니다.", "error");
    }
  }

  async function resetScheduleWeek() {
    if (!supabaseClient || !state.menuSession) {
      setScheduleStatus("메뉴변경 탭에서 관리자 로그인 후 사용할 수 있습니다.", "error");
      return;
    }

    state.scheduleWeekStart = getScheduleWeekStart();
    refs.scheduleWeekStart.value = state.scheduleWeekStart;
    const ok = window.confirm("해당 주간 스케줄을 초기화할까요? 저장된 서버 배정이 모두 지워집니다.");
    if (!ok) return;

    setScheduleStatus("주간 스케줄을 초기화하는 중...");

    try {
      if (state.scheduleWeek?.id) {
        const deleteResult = await supabaseClient
          .from("noble_schedule_shifts")
          .delete()
          .eq("week_id", state.scheduleWeek.id);
        if (deleteResult.error) throw deleteResult.error;

        const updateResult = await supabaseClient
          .from("noble_schedule_weeks")
          .update({ status: "draft" })
          .eq("id", state.scheduleWeek.id)
          .select("id,week_start,status,note")
          .single();
        if (updateResult.error) throw updateResult.error;

        state.scheduleWeek = updateResult.data;
        state.scheduleWeeks = [
          ...state.scheduleWeeks.filter((item) => item.week_start !== updateResult.data.week_start),
          updateResult.data
        ];
      }

      state.scheduleShifts = [];
      state.scheduleShiftNotes = new Map();
      refs.scheduleBoard.querySelectorAll("[data-schedule-cell]").forEach((textarea) => {
        textarea.value = "";
      });
      renderScheduleBoard();
      setScheduleStatus("해당 주간을 초기화했습니다.", "success");
    } catch (error) {
      setScheduleStatus(error.message || "주간 초기화에 실패했습니다.", "error");
    }
  }

  function setActiveTab(tabName) {
    if (state.activeTab === "schedule" && tabName !== "schedule") {
      // Do not let an in-flight background request overwrite an in-progress board.
      state.scheduleFetchToken += 1;
    }
    state.activeTab = tabName;
    document.querySelectorAll("[data-admin-tab]").forEach((button) => {
      button.classList.toggle("is-active", button.dataset.adminTab === tabName);
      button.setAttribute("aria-pressed", button.dataset.adminTab === tabName ? "true" : "false");
    });
    byId("reservationsAdminPanel").classList.toggle("is-active", tabName === "reservations");
    byId("staffAdminPanel").classList.toggle("is-active", tabName === "staff");
    byId("menuAdminPanel").classList.toggle("is-active", tabName === "menu");
    byId("scheduleAdminPanel").classList.toggle("is-active", tabName === "schedule");
    if (tabName === "menu") void refreshMenuSession();
    if (tabName === "staff") void fetchEmployees();
    if (tabName === "schedule" && !state.scheduleDataLoaded) void fetchScheduleData();
  }

  function bindEvents() {
    document.querySelectorAll("[data-admin-tab]").forEach((button) => {
      button.addEventListener("click", () => setActiveTab(button.dataset.adminTab || "reservations"));
    });

    refs.reservationDayChips.addEventListener("click", (event) => {
      const button = event.target.closest("[data-reservation-date]");
      if (!button) return;
      state.reservationDate = button.dataset.reservationDate;
      renderReservations();
    });
    refs.reservationBranchChips.addEventListener("click", (event) => {
      const button = event.target.closest("[data-reservation-branch]");
      if (!button) return;
      state.reservationBranch = button.dataset.reservationBranch;
      renderReservations();
    });
    refs.reservationRefreshBtn.addEventListener("click", () => void fetchReservations());
    refs.employeeRefreshBtn.addEventListener("click", () => void fetchEmployees());
    refs.employeeShowInactiveBtn.addEventListener("click", () => {
      state.employeeShowInactive = !state.employeeShowInactive;
      renderEmployees();
    });
    refs.accessRequestList.addEventListener("click", (event) => {
      const editButton = event.target.closest("[data-edit-access-request]");
      if (editButton) {
        openEmployeeEditorFromRequest(editButton.dataset.editAccessRequest);
        return;
      }
      const button = event.target.closest("[data-delete-access-request]");
      if (!button) return;
      void deleteAccessRequest(button.dataset.deleteAccessRequest);
    });
    refs.employeeList.addEventListener("click", (event) => {
      const button = event.target.closest("[data-edit-employee]");
      if (!button) return;
      openEmployeeEditor(button.dataset.editEmployee);
    });
    refs.employeeEditorClose.addEventListener("click", closeEmployeeEditor);
    refs.employeeEditorCancel.addEventListener("click", closeEmployeeEditor);
    refs.employeeEditorModal.addEventListener("click", (event) => {
      if (event.target === refs.employeeEditorModal) closeEmployeeEditor();
    });
    refs.employeeEditorForm.addEventListener("submit", (event) => void saveEmployeeEditor(event));
    refs.scheduleNoteClose.addEventListener("click", closeScheduleNoteModal);
    refs.scheduleNoteCancel.addEventListener("click", closeScheduleNoteModal);
    refs.scheduleNoteModal.addEventListener("click", (event) => {
      if (event.target === refs.scheduleNoteModal) closeScheduleNoteModal();
    });
    refs.scheduleNoteForm.addEventListener("submit", saveScheduleNote);
    refs.scheduleLoadBtn.addEventListener("click", () => void fetchScheduleData());
    refs.scheduleAutoFillBtn.addEventListener("click", autoFillScheduleV2);
    refs.scheduleDetailToggleBtn.addEventListener("click", () => {
      state.scheduleDetailsOpen = !state.scheduleDetailsOpen;
      renderScheduleBoard();
    });
    refs.scheduleCopyImageBtn.addEventListener("click", () => void copyScheduleImageToClipboard());
    refs.scheduleResetBtn.addEventListener("click", () => void resetScheduleWeek());
    refs.schedulePublishBtn.addEventListener("click", () => void saveScheduleWeek());
    refs.scheduleCalendarEventForm.addEventListener("submit", (event) => void saveScheduleCalendarEvent(event));
    refs.scheduleCalendarEventDate.addEventListener("change", () => {
      const date = toSafeDate(refs.scheduleCalendarEventDate.value);
      if (!date) return;
      state.scheduleMonthSelectedDate = formatInputDate(date);
      state.scheduleMonthCursor = startOfMonth(date);
      renderScheduleMonthCalendar();
    });
    refs.scheduleCalendarEventList.addEventListener("click", (event) => {
      const button = event.target.closest("[data-delete-schedule-calendar-event]");
      if (button) void deleteScheduleCalendarEvent(button.dataset.deleteScheduleCalendarEvent);
    });
    refs.scheduleStaffList.addEventListener("click", (event) => {
      const button = event.target.closest("[data-schedule-staff]");
      if (!button) return;
      if (Date.now() < state.scheduleNoteSuppressClickUntil) return;
      const staff = getScheduleStaffByKey(button.dataset.scheduleStaff);
      if (staff) selectScheduleStaff(staff);
    });
    refs.scheduleStaffList.addEventListener("pointerdown", (event) => {
      const button = event.target.closest("[data-schedule-staff]");
      const cellKey = state.scheduleSelectedCellKey;
      if (!button || !cellKey) return;
      const staff = getScheduleStaffByKey(button.dataset.scheduleStaff);
      if (!isScheduleStaffAssignedToCell(staff, cellKey)) return;
      startScheduleNoteLongPress(cellKey, staff.name, event);
    });
    refs.scheduleStaffList.addEventListener("pointermove", cancelScheduleNoteLongPressOnMove);
    ["pointerup", "pointercancel", "pointerleave"].forEach((eventName) => {
      refs.scheduleStaffList.addEventListener(eventName, clearScheduleNoteLongPress);
    });
    refs.scheduleStaffList.addEventListener("contextmenu", (event) => {
      if (state.scheduleSelectedCellKey && event.target.closest("[data-schedule-staff]")) event.preventDefault();
    });
    refs.scheduleBoard.addEventListener("click", (event) => {
      const removeButton = event.target.closest("[data-remove-schedule-assignment]");
      if (removeButton) {
        if (Date.now() < state.scheduleNoteSuppressClickUntil) return;
        if (!state.scheduleSelectedCellKey && !getSelectedScheduleStaff()) return;
        removeScheduleStaffFromCell(removeButton.dataset.removeScheduleAssignment, removeButton.dataset.scheduleName);
        return;
      }
      const cellButton = event.target.closest("[data-schedule-select-cell]");
      if (cellButton) {
        const staff = getSelectedScheduleStaff();
        if (staff) assignScheduleStaffToCell(staff, cellButton.dataset.scheduleSelectCell);
        else selectScheduleCell(cellButton.dataset.scheduleSelectCell);
        return;
      }
      const zone = event.target.closest("[data-schedule-dropzone]");
      if (!zone) return;
      const staff = getSelectedScheduleStaff();
      if (!staff) {
        selectScheduleCell(zone.dataset.scheduleDropzone);
        return;
      }
      assignScheduleStaffToCell(staff, zone.dataset.scheduleDropzone);
    });
    refs.scheduleBoard.addEventListener("pointerdown", (event) => {
      const assignment = event.target.closest("[data-schedule-note-cell]");
      if (!assignment) return;
      startScheduleNoteLongPress(assignment.dataset.scheduleNoteCell, assignment.dataset.scheduleName, event);
    });
    refs.scheduleBoard.addEventListener("pointermove", cancelScheduleNoteLongPressOnMove);
    ["pointerup", "pointercancel", "pointerleave"].forEach((eventName) => {
      refs.scheduleBoard.addEventListener(eventName, clearScheduleNoteLongPress);
    });
    refs.scheduleBoard.addEventListener("contextmenu", (event) => {
      if (event.target.closest("[data-schedule-note-cell]")) event.preventDefault();
    });
    refs.scheduleBoard.addEventListener("keydown", (event) => {
      if (event.key !== "Enter" && event.key !== " ") return;
      const zone = event.target.closest("[data-schedule-dropzone]");
      if (!zone) return;
      event.preventDefault();
      const staff = getSelectedScheduleStaff();
      if (!staff) {
        selectScheduleCell(zone.dataset.scheduleDropzone);
        return;
      }
      assignScheduleStaffToCell(staff, zone.dataset.scheduleDropzone);
    });
    refs.scheduleMonthPrevBtn.addEventListener("click", () => {
      const cursor = state.scheduleMonthCursor instanceof Date
        ? state.scheduleMonthCursor
        : toSafeDate(state.scheduleWeekStart) || new Date();
      state.scheduleMonthCursor = new Date(cursor.getFullYear(), cursor.getMonth() - 1, 1);
      renderScheduleMonthCalendar();
    });
    refs.scheduleMonthNextBtn.addEventListener("click", () => {
      const cursor = state.scheduleMonthCursor instanceof Date
        ? state.scheduleMonthCursor
        : toSafeDate(state.scheduleWeekStart) || new Date();
      state.scheduleMonthCursor = new Date(cursor.getFullYear(), cursor.getMonth() + 1, 1);
      renderScheduleMonthCalendar();
    });
    refs.scheduleMonthGrid.addEventListener("click", (event) => {
      const button = event.target.closest("[data-schedule-month-date]");
      if (!button) return;
      const date = toSafeDate(button.dataset.scheduleMonthDate);
      if (!date) return;
      refs.scheduleCalendarEventDate.value = formatInputDate(date);
      state.scheduleMonthSelectedDate = formatInputDate(date);
      const weekStart = startOfWeek(date);
      state.scheduleWeekStart = formatInputDate(weekStart);
      state.scheduleWeekWindowStart = formatInputDate(addWeeks(weekStart, -1));
      state.scheduleMonthCursor = startOfMonth(date);
      refs.scheduleWeekStart.value = state.scheduleWeekStart;
      renderScheduleWeekChips();
      void fetchScheduleData();
    });
    refs.scheduleWeekStart.addEventListener("change", () => {
      state.scheduleWeekStart = getScheduleWeekStart();
      state.scheduleMonthCursor = startOfMonth(toSafeDate(state.scheduleWeekStart) || new Date());
      refs.scheduleWeekStart.value = state.scheduleWeekStart;
      void fetchScheduleData();
    });
    refs.scheduleWeekPrevBtn.addEventListener("click", () => {
      const current = toSafeDate(state.scheduleWeekWindowStart) || startOfWeek(new Date());
      state.scheduleWeekWindowStart = formatInputDate(addWeeks(current, -3));
      const options = getScheduleWeekOptions();
      state.scheduleWeekStart = options[1]?.weekStart || options[0]?.weekStart || state.scheduleWeekStart;
      state.scheduleMonthCursor = startOfMonth(toSafeDate(state.scheduleWeekStart) || new Date());
      refs.scheduleWeekStart.value = state.scheduleWeekStart;
      renderScheduleWeekChips();
      if (state.activeTab === "schedule") void fetchScheduleData();
    });
    refs.scheduleWeekNextBtn.addEventListener("click", () => {
      const current = toSafeDate(state.scheduleWeekWindowStart) || startOfWeek(new Date());
      state.scheduleWeekWindowStart = formatInputDate(addWeeks(current, 3));
      const options = getScheduleWeekOptions();
      state.scheduleWeekStart = options[1]?.weekStart || options[0]?.weekStart || state.scheduleWeekStart;
      state.scheduleMonthCursor = startOfMonth(toSafeDate(state.scheduleWeekStart) || new Date());
      refs.scheduleWeekStart.value = state.scheduleWeekStart;
      renderScheduleWeekChips();
      if (state.activeTab === "schedule") void fetchScheduleData();
    });
    refs.scheduleWeekChips.addEventListener("click", (event) => {
      const button = event.target.closest("[data-schedule-week]");
      if (!button) return;
      state.scheduleWeekStart = button.dataset.scheduleWeek;
      state.scheduleMonthCursor = startOfMonth(toSafeDate(state.scheduleWeekStart) || new Date());
      refs.scheduleWeekStart.value = state.scheduleWeekStart;
      renderScheduleBoard();
      void fetchScheduleData();
    });

    refs.menuSignInBtn.addEventListener("click", () => void signInMenuAdmin());
    refs.menuAdminPassword.addEventListener("keydown", (event) => {
      if (event.key === "Enter") {
        event.preventDefault();
        void signInMenuAdmin();
      }
    });
    refs.menuSignOutBtn.addEventListener("click", () => void signOutMenuAdmin());
    refs.menuRefreshBtn.addEventListener("click", () => void fetchMenuItems());
    refs.menuAddBtn.addEventListener("click", () => openMenuEditor());
    refs.menuSearchInput.addEventListener("input", (event) => {
      state.menuSearch = event.target.value;
      renderMenu();
    });
    refs.menuCategoryFilter.addEventListener("change", (event) => {
      state.menuCategory = event.target.value;
      renderMenu();
    });
    refs.menuBranchFilter.addEventListener("change", (event) => {
      state.menuBranch = event.target.value;
      renderMenu();
    });
    refs.menuModeTabs.addEventListener("click", (event) => {
      const button = event.target.closest("[data-menu-mode]");
      if (!button) return;
      state.menuMode = button.dataset.menuMode;
      renderMenu();
    });
    refs.menuCategoryChips.addEventListener("click", (event) => {
      const button = event.target.closest("[data-menu-category]");
      if (!button) return;
      state.menuCategory = button.dataset.menuCategory;
      renderMenu();
    });
    refs.menuList.addEventListener("click", (event) => {
      if (handleTokenPickerClick(event)) return;
      const saveButton = event.target.closest("[data-visual-save]");
      if (saveButton) {
        void saveVisualCard(saveButton.dataset.visualSave);
        return;
      }
      const editButton = event.target.closest("[data-menu-edit]");
      if (editButton) {
        openMenuEditor(getMenuById(editButton.dataset.menuEdit));
      }
    });
    refs.menuList.addEventListener("input", (event) => {
      const card = event.target.closest(".menu-preview-card");
      if (card) syncVisualPreview(card);
    });
    refs.menuList.addEventListener("change", (event) => {
      const card = event.target.closest(".menu-preview-card");
      if (card) syncVisualPreview(card);
    });
    refs.menuOrderChips.addEventListener("click", (event) => {
      const button = event.target.closest("[data-order-view]");
      if (!button) return;
      state.menuOrderView = button.dataset.orderView || "all";
      renderOrderChips();
      renderMenuOrder();
    });
    refs.menuCategoryOrderBtn.addEventListener("click", openCategoryOrderModal);
    refs.menuSaveCategoryOrderBtn.addEventListener("click", () => void saveCategoryOrder());
    refs.menuSaveMenuOrderBtn.addEventListener("click", () => void saveMenuOrder());

    refs.menuEditorForm.addEventListener("click", (event) => {
      handleTokenPickerClick(event);
    });
    refs.menuEditorForm.addEventListener("submit", (event) => void saveMenuEditor(event));
    refs.menuDeleteBtn.addEventListener("click", () => void deleteMenuItem());
    refs.menuEditorClose.addEventListener("click", closeMenuEditor);
    refs.menuEditorCancel.addEventListener("click", closeMenuEditor);
    refs.menuEditorModal.addEventListener("click", (event) => {
      if (event.target === refs.menuEditorModal) closeMenuEditor();
    });
    refs.menuCategoryOrderClose.addEventListener("click", closeCategoryOrderModal);
    refs.menuCategoryOrderCancel.addEventListener("click", closeCategoryOrderModal);
    refs.menuCategoryOrderModal.addEventListener("click", (event) => {
      if (event.target === refs.menuCategoryOrderModal) closeCategoryOrderModal();
    });

    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape" && refs.menuEditorModal.classList.contains("is-open")) {
        closeMenuEditor();
      }
      if (event.key === "Escape" && refs.menuCategoryOrderModal.classList.contains("is-open")) {
        closeCategoryOrderModal();
      }
    });
  }

  function bootstrap() {
    cacheRefs();
    refs.todayHeading.textContent = new Intl.DateTimeFormat("ko-KR", {
      weekday: "long",
      month: "long",
      day: "numeric",
      year: "numeric"
    }).format(new Date());
    state.scheduleWeekStart = formatInputDate(addWeeks(startOfWeek(new Date()), 1));
    state.scheduleWeekWindowStart = formatInputDate(startOfWeek(new Date()));
    state.scheduleMonthSelectedDate = formatInputDate(new Date());
    state.scheduleMonthCursor = startOfMonth(toSafeDate(state.scheduleWeekStart) || new Date());
    state.scheduleStaff = FALLBACK_SERVER_REFS.map(normalizeStaffRef).filter(Boolean);
    state.scheduleUsingFallbackStaff = true;
    refs.scheduleWeekStart.value = state.scheduleWeekStart;
    refs.scheduleCalendarEventDate.value = formatInputDate(new Date());
    bindEvents();
    renderReservationDayChips();
    renderReservationBranchChips();
    renderReservationMetrics([]);
    renderEmployees();
    renderScheduleBoard();
    updateMenuAuthView();
    setActiveTab("reservations");
    if (supabaseClient) {
      supabaseClient.auth.onAuthStateChange((_event, session) => {
        state.menuSession = session;
        updateMenuAuthView();
        if (session) void fetchScheduleCalendarEvents();
        if (session && state.activeTab === "menu" && !state.menuItems.length) void fetchMenuItems();
        if (session && state.activeTab === "staff") void fetchEmployees();
      });
      void refreshMenuSession();
    } else {
      setMenuAuthStatus("Supabase 클라이언트를 불러오지 못했습니다.", "error");
    }
    void fetchScheduleCalendarEvents();
    void fetchReservations();
  }

  bootstrap();
})();
