(function () {
  "use strict";

  const SUPABASE_CONFIG = {
    url: "https://pzhzdjsjfdzbzkhnaxmc.supabase.co",
    anonKey: "sb_publishable_3Ox2JIQXVLwusT-xzIMJ4g_YXTR5q8e"
  };

  const ADMIN_SHEET_CONFIG = {
    sheetId: "1xa9OZbctYnlbaAL8lKIgmefM5hvSw0Plk01lxp5G2fc",
    sheets: [
      { name: "Downtown Reservation", label: "Downtown", key: "downtown" },
      { name: "Uptown Reservation", label: "Uptown", key: "uptown" }
    ]
  };

  const MENU_SELECT = [
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
  ].join(",");

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
  const refs = {};

  const state = {
    activeTab: "reservations",
    reservations: [],
    reservationDate: formatInputDate(new Date()),
    reservationBranch: "all",
    reservationSearch: "",
    menuSession: null,
    menuItems: [],
    menuSearch: "",
    menuCategory: "all",
    menuBranch: "all",
    menuMode: "visual",
    menuOrderCategory: "",
    categoryOrder: [],
    sortables: {
      visual: null,
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
      "reservationSearchInput",
      "reservationRefreshBtn",
      "reservationStatus",
      "reservationList",
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
      "menuDetailPanel",
      "menuOrderPanel",
      "menuSaveVisualOrderBtn",
      "menuList",
      "menuDetailGrid",
      "menuSaveDetailBtn",
      "menuCategoryOrderList",
      "menuOrderCategory",
      "menuOrderList",
      "menuSaveCategoryOrderBtn",
      "menuSaveMenuOrderBtn",
      "menuEditorModal",
      "menuEditorTitle",
      "menuEditorForm",
      "menuDeleteBtn",
      "menuEditorClose",
      "menuEditorCancel"
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
    if (value === "all") return "All Days";
    const date = toSafeDate(value);
    if (!date) return value || "No date";
    return new Intl.DateTimeFormat("en-US", {
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
    setReservationStatus("Loading reservations...");
    try {
      const groups = await Promise.all(
        ADMIN_SHEET_CONFIG.sheets.map(async (sheetConfig) => {
          const url = `https://docs.google.com/spreadsheets/d/${ADMIN_SHEET_CONFIG.sheetId}/gviz/tq?sheet=${encodeURIComponent(sheetConfig.name)}&tqx=out:json`;
          const response = await fetch(url);
          if (!response.ok) throw new Error(`Failed to fetch ${sheetConfig.label}`);
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
      setReservationStatus(`Loaded ${state.reservations.length} reservations.`, "success");
    } catch (error) {
      setReservationStatus(error.message || "Could not load reservations.", "error");
      refs.reservationList.innerHTML = '<div class="empty-state">Could not load reservation data.</div>';
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
      ...days.map((value, index) => {
        const date = toSafeDate(value);
        const weekdayLabel = index === 0 ? "Today" : new Intl.DateTimeFormat("en-US", { weekday: "short" }).format(date);
        const dayLabel = new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric" }).format(date);
        return `
          <button class="chip-btn day-chip ${state.reservationDate === value ? "is-active" : ""}" data-reservation-date="${value}" type="button">
            <strong>${escapeHtml(weekdayLabel)}</strong>
            <span>${escapeHtml(dayLabel)}</span>
          </button>
        `;
      }),
      `<button class="chip-btn ${state.reservationDate === "all" ? "is-active" : ""}" data-reservation-date="all" type="button">All Days</button>`
    ].join("");
  }

  function renderReservationBranchChips() {
    refs.reservationBranchChips.querySelectorAll("[data-reservation-branch]").forEach((button) => {
      button.classList.toggle("is-active", button.dataset.reservationBranch === state.reservationBranch);
    });
  }

  function getVisibleReservations() {
    const query = state.reservationSearch.trim().toLowerCase();
    return state.reservations.filter((item) => {
      if (item.status === "removed") return false;
      if (state.reservationDate !== "all" && item.date !== state.reservationDate) return false;
      if (state.reservationBranch !== "all" && item.branchKey !== state.reservationBranch) return false;
      if (!query) return true;
      return [item.name, item.phone, item.notes, item.time, item.people, item.branch]
        .filter(Boolean)
        .some((value) => String(value).toLowerCase().includes(query));
    });
  }

  function renderReservationMetrics(items) {
    const downtown = items.filter((item) => item.branchKey === "downtown").length;
    const uptown = items.filter((item) => item.branchKey === "uptown").length;
    refs.metricSelectedDate.textContent = formatDateLabel(state.reservationDate);
    refs.metricReservations.textContent = String(items.length);
    refs.metricDowntown.textContent = String(downtown);
    refs.metricUptown.textContent = String(uptown);
    const branchLabel = state.reservationBranch === "all" ? "All branches" : formatBranchLabel(state.reservationBranch);
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
            ${large ? '<span class="status-badge large">Large Party</span>' : ""}
          </div>
        </div>
        <div class="reservation-focus">
          <div class="reservation-pill-row">
            <div class="reservation-time-pill">${escapeHtml(item.time || "-")}</div>
            <div class="reservation-guests-pill">${escapeHtml(item.people || "-")}</div>
          </div>
          <h4 class="reservation-name-box">${escapeHtml(item.name || "Guest")}</h4>
        </div>
        <div class="reservation-meta">
          <div class="meta-box"><span>Phone</span><strong>${escapeHtml(item.phone || "-")}</strong></div>
          <div class="meta-box"><span>Branch</span><strong>${escapeHtml(item.branch || "-")}</strong></div>
        </div>
        <div class="reservation-notes">${escapeHtml(item.notes || "No notes")}</div>
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
      : '<div class="empty-state">No reservations in this view.</div>';
  }

  function setReservationStatus(message = "", type = "") {
    refs.reservationStatus.textContent = message;
    refs.reservationStatus.className = `status-line${type ? ` is-${type}` : ""}`;
  }

  function formatBranchLabel(branch = "") {
    const normalized = String(branch).trim().toLowerCase();
    if (normalized === "both") return "Both";
    if (normalized === "downtown") return "Downtown";
    if (normalized === "uptown") return "Uptown";
    if (normalized === "all") return "All";
    return branch || "-";
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

  function compareMenuItems(a, b) {
    const orderA = Number.isFinite(Number(a.sort_order)) ? Number(a.sort_order) : Number.MAX_SAFE_INTEGER;
    const orderB = Number.isFinite(Number(b.sort_order)) ? Number(b.sort_order) : Number.MAX_SAFE_INTEGER;
    if (orderA !== orderB) return orderA - orderB;
    return Number(a.id || 0) - Number(b.id || 0);
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
    if (!state.menuOrderCategory || !state.categoryOrder.includes(state.menuOrderCategory)) {
      state.menuOrderCategory = state.categoryOrder[0] || "";
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
        const categoryCompare = getCategoryOrder(a.category) - getCategoryOrder(b.category)
          || String(a.category || "").localeCompare(String(b.category || ""));
        if (state.menuCategory === "all" && categoryCompare) return categoryCompare;
        return compareMenuItems(a, b);
      });
  }

  function refreshCategoryControls() {
    const categories = getCategories();
    const categoryOptions = ['<option value="all">All categories</option>']
      .concat(categories.map((category) => `<option value="${escapeHtml(category)}">${escapeHtml(category)}</option>`));
    refs.menuCategoryFilter.innerHTML = categoryOptions.join("");
    refs.menuCategoryFilter.value = state.menuCategory;
    refs.menuCategoryChips.innerHTML = [
      `<button class="chip-btn ${state.menuCategory === "all" ? "is-active" : ""}" data-menu-category="all" type="button">All</button>`,
      ...categories.map((category) => `
        <button class="chip-btn ${state.menuCategory === category ? "is-active" : ""}" data-menu-category="${escapeHtml(category)}" type="button">${escapeHtml(category)}</button>
      `)
    ].join("");
    refs.menuOrderCategory.innerHTML = categories
      .map((category) => `<option value="${escapeHtml(category)}">${escapeHtml(category)}</option>`)
      .join("");
    refs.menuOrderCategory.value = state.menuOrderCategory || categories[0] || "";
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
    refs.menuSessionLabel.textContent = signedIn ? state.menuSession.user?.email || "Signed in" : "Sign in required";
  }

  async function refreshMenuSession() {
    if (!supabaseClient) {
      setMenuAuthStatus("Supabase client could not load.", "error");
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
  }

  async function signInMenuAdmin() {
    if (!supabaseClient) {
      setMenuAuthStatus("Supabase client could not load.", "error");
      return;
    }
    const email = refs.menuAdminEmail.value.trim();
    const password = refs.menuAdminPassword.value;
    if (!email || !password) {
      setMenuAuthStatus("Enter email and password.", "error");
      return;
    }
    setMenuAuthStatus("Signing in...");
    const { data, error } = await supabaseClient.auth.signInWithPassword({ email, password });
    if (error) {
      setMenuAuthStatus(error.message, "error");
      return;
    }
    state.menuSession = data.session;
    refs.menuAdminPassword.value = "";
    updateMenuAuthView();
    setMenuAuthStatus("Signed in.", "success");
    await fetchMenuItems();
  }

  async function signOutMenuAdmin() {
    if (!supabaseClient) return;
    await supabaseClient.auth.signOut();
    state.menuSession = null;
    state.menuItems = [];
    updateMenuAuthView();
    renderMenu();
    setMenuStatus("");
  }

  async function fetchMenuItems() {
    if (!supabaseClient) return;
    setMenuStatus("Loading menu...");
    const { data, error } = await supabaseClient
      .from("menu_items")
      .select(MENU_SELECT)
      .order("sort_order", { ascending: true, nullsFirst: false })
      .order("id", { ascending: true });

    if (error) {
      setMenuStatus(error.message, "error");
      return;
    }

    state.menuItems = data || [];
    syncCategoryOrder();
    renderMenu();
    setMenuStatus(`Loaded ${state.menuItems.length} menu items.`, "success");
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

  function renderTagBadges(item) {
    const tags = [...parseList(item.tags), ...parseList(item.ingredient)].slice(0, 8);
    if (!tags.length) return "";
    return `
      <div class="menu-meta">
        ${tags.map((tag) => `<span class="menu-tag ${escapeHtml(getTagClass(tag))}">${escapeHtml(tag)}</span>`).join("")}
      </div>
    `;
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
            <img class="menu-preview-image" data-preview-image src="${escapeHtml(item.image_url || FALLBACK_IMAGE)}" alt="${escapeHtml(item.name_en || item.name_ko || "Menu image")}" loading="lazy" />
            <div class="menu-preview-content">
              <p class="menu-preview-name-ko" data-preview-name-ko>${escapeHtml(item.name_ko || item.name_en || "Untitled")}</p>
              <p class="menu-preview-name-en" data-preview-name-en>${escapeHtml(item.name_en || item.romanized_name || "")}</p>
              <p class="menu-preview-desc" data-preview-description>${escapeHtml(item.description || "No description")}</p>
              ${renderTagBadges(item)}
              <div class="menu-preview-price" data-preview-price>${escapeHtml(formatPrice(item.price))}</div>
            </div>
          </div>
          <div class="preview-actions">
            <button class="drag-handle" type="button" aria-label="Drag menu item">Move</button>
            <button class="pill-btn" data-menu-edit="${escapeHtml(item.id)}" type="button">Full Edit</button>
            <button class="pill-btn primary" data-visual-save="${escapeHtml(item.id)}" type="button">Save Card</button>
          </div>
        </div>
        <div class="preview-edit-grid">
          <div class="preview-field">
            <label>Korean</label>
            <input data-visual-field="name_ko" type="text" value="${escapeHtml(item.name_ko || "")}" />
          </div>
          <div class="preview-field">
            <label>English</label>
            <input data-visual-field="name_en" type="text" value="${escapeHtml(item.name_en || "")}" />
          </div>
          <div class="preview-field">
            <label>Price</label>
            <input data-visual-field="price" type="number" step="0.01" min="0" value="${escapeHtml(item.price ?? "")}" />
          </div>
          <div class="preview-field">
            <label>Branch</label>
            <select data-visual-field="branches">${branchOptions(item.branches)}</select>
          </div>
          <div class="preview-field full">
            <label>Description</label>
            <textarea data-visual-field="description">${escapeHtml(item.description || "")}</textarea>
          </div>
          <div class="preview-field full">
            <label>Image URL</label>
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
    state.sortables[key] = window.Sortable.create(element, {
      handle,
      animation: 160,
      forceFallback: true,
      scroll: true,
      bubbleScroll: true,
      scrollSensitivity: 90,
      scrollSpeed: 12
    });
  }

  function renderVisualMenu() {
    destroySortable("category");
    destroySortable("menu");
    const items = getVisibleMenuItems();
    refs.menuList.innerHTML = items.length
      ? items.map(renderVisualMenuCard).join("")
      : '<div class="empty-state">No menu items match this view.</div>';
    if (state.menuCategory !== "all" && !state.menuSearch.trim() && state.menuBranch === "all") {
      setupSortable("visual", refs.menuList, ".drag-handle");
    } else {
      destroySortable("visual");
    }
  }

  function renderDetailGrid() {
    destroySortable("visual");
    destroySortable("category");
    destroySortable("menu");
    const items = getVisibleMenuItems();
    if (!items.length) {
      refs.menuDetailGrid.innerHTML = '<div class="empty-state">No rows match this view.</div>';
      return;
    }
    const header = `
      <div class="detail-grid-row is-head">
        <div>ID</div><div>Branch</div><div>Sort</div><div>Category</div><div>Label</div><div>Korean</div><div>Romanized</div><div>English</div><div>Price</div><div>Image URL</div><div>Description</div><div>Tags</div><div>Ingredient</div><div>Visible</div>
      </div>
    `;
    const rows = items.map((item) => `
      <div class="detail-grid-row" data-menu-id="${escapeHtml(item.id)}">
        <input value="${escapeHtml(item.id)}" readonly />
        <select data-grid-field="branches">${branchOptions(item.branches)}</select>
        <input data-grid-field="sort_order" type="number" value="${escapeHtml(item.sort_order ?? "")}" />
        <input data-grid-field="category" type="text" value="${escapeHtml(item.category || "")}" />
        <input data-grid-field="label" type="text" value="${escapeHtml(item.label || "")}" />
        <input data-grid-field="name_ko" type="text" value="${escapeHtml(item.name_ko || "")}" />
        <input data-grid-field="romanized_name" type="text" value="${escapeHtml(item.romanized_name || "")}" />
        <input data-grid-field="name_en" type="text" value="${escapeHtml(item.name_en || "")}" />
        <input data-grid-field="price" type="number" step="0.01" min="0" value="${escapeHtml(item.price ?? "")}" />
        <input data-grid-field="image_url" type="url" value="${escapeHtml(item.image_url || "")}" />
        <textarea data-grid-field="description">${escapeHtml(item.description || "")}</textarea>
        <input data-grid-field="tags" type="text" value="${escapeHtml(item.tags || "")}" />
        <input data-grid-field="ingredient" type="text" value="${escapeHtml(item.ingredient || "")}" />
        <div class="preview-actions">
          <input data-grid-field="is_available" type="checkbox" ${item.is_available === false ? "" : "checked"} aria-label="Visible" />
          <button class="icon-btn primary" data-grid-save="${escapeHtml(item.id)}" type="button" aria-label="Save row">OK</button>
        </div>
      </div>
    `).join("");
    refs.menuDetailGrid.innerHTML = header + rows;
  }

  function renderCategoryOrder() {
    refs.menuCategoryOrderList.innerHTML = state.categoryOrder.length
      ? state.categoryOrder.map((category) => {
        const count = state.menuItems.filter((item) => item.category === category).length;
        return `
          <article class="category-order-row" data-category="${escapeHtml(category)}">
            <button class="drag-handle" type="button" aria-label="Drag category">Move</button>
            <div class="order-row-title">
              <strong>${escapeHtml(category)}</strong>
              <span>${count} items</span>
            </div>
            <div class="sort-actions">
              <button class="icon-btn" data-order-move="up" type="button" aria-label="Move up">Up</button>
              <button class="icon-btn" data-order-move="down" type="button" aria-label="Move down">Dn</button>
            </div>
          </article>
        `;
      }).join("")
      : '<div class="empty-state">No categories loaded.</div>';
    setupSortable("category", refs.menuCategoryOrderList, ".drag-handle");
  }

  function renderMenuOrder() {
    const category = state.menuOrderCategory || state.categoryOrder[0] || "";
    state.menuOrderCategory = category;
    refs.menuOrderCategory.value = category;
    const items = state.menuItems
      .filter((item) => item.category === category)
      .sort(compareMenuItems);
    refs.menuOrderList.innerHTML = items.length
      ? items.map((item) => `
        <article class="menu-order-row" data-menu-id="${escapeHtml(item.id)}">
          <button class="drag-handle" type="button" aria-label="Drag menu item">Move</button>
          <div class="order-row-title">
            <strong>${escapeHtml(item.name_ko || item.name_en || "Untitled")}</strong>
            <span>${escapeHtml(item.name_en || "")} / ${escapeHtml(item.branches || "both")} / current ${escapeHtml(item.sort_order ?? "-")}</span>
          </div>
          <div class="sort-actions">
            <button class="icon-btn" data-order-move="up" type="button" aria-label="Move up">Up</button>
            <button class="icon-btn" data-order-move="down" type="button" aria-label="Move down">Dn</button>
          </div>
        </article>
      `).join("")
      : '<div class="empty-state">No items in this category.</div>';
    setupSortable("menu", refs.menuOrderList, ".drag-handle");
  }

  function renderOrderPanel() {
    destroySortable("visual");
    renderCategoryOrder();
    renderMenuOrder();
  }

  function renderMenuModePanels() {
    refs.menuModeTabs.querySelectorAll("[data-menu-mode]").forEach((button) => {
      button.classList.toggle("is-active", button.dataset.menuMode === state.menuMode);
    });
    refs.menuVisualPanel.classList.toggle("is-active", state.menuMode === "visual");
    refs.menuDetailPanel.classList.toggle("is-active", state.menuMode === "detail");
    refs.menuOrderPanel.classList.toggle("is-active", state.menuMode === "order");
  }

  function renderMenu() {
    syncCategoryOrder();
    refreshCategoryControls();
    renderMenuModePanels();
    if (!state.menuSession) {
      destroySortable("visual");
      destroySortable("category");
      destroySortable("menu");
      return;
    }
    if (state.menuMode === "detail") {
      renderDetailGrid();
    } else if (state.menuMode === "order") {
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
      } else if (field === "sort_order") {
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
      throw new Error("Sign in before saving.");
    }
    const { data, error } = await supabaseClient
      .from("menu_items")
      .update(payload)
      .eq("id", id)
      .select(MENU_SELECT)
      .single();
    if (error) throw error;
    state.menuItems = state.menuItems.map((item) => String(item.id) === String(id) ? data : item);
    return data;
  }

  function syncVisualPreview(card) {
    const payload = readPayloadFromContainer(card, "data-visual-field");
    const nameKo = card.querySelector("[data-preview-name-ko]");
    const nameEn = card.querySelector("[data-preview-name-en]");
    const description = card.querySelector("[data-preview-description]");
    const price = card.querySelector("[data-preview-price]");
    const image = card.querySelector("[data-preview-image]");
    if (nameKo) nameKo.textContent = payload.name_ko || payload.name_en || "Untitled";
    if (nameEn) nameEn.textContent = payload.name_en || "";
    if (description) description.textContent = payload.description || "No description";
    if (price) price.textContent = formatPrice(payload.price);
    if (image) image.src = payload.image_url || FALLBACK_IMAGE;
  }

  async function saveVisualCard(id) {
    const card = refs.menuList.querySelector(`[data-menu-id="${CSS.escape(String(id))}"]`);
    if (!card) return;
    setMenuStatus("Saving menu card...");
    try {
      const data = await updateMenuItem(id, readPayloadFromContainer(card, "data-visual-field"));
      syncCategoryOrder();
      renderMenu();
      setMenuStatus(`Saved ${data.name_en || data.name_ko || "menu item"}.`, "success");
    } catch (error) {
      setMenuStatus(error.message, "error");
    }
  }

  async function saveDetailRow(row) {
    const id = row.dataset.menuId;
    if (!id) return null;
    return updateMenuItem(id, readPayloadFromContainer(row, "data-grid-field"));
  }

  async function saveDetailRows(rows) {
    const targetRows = rows.length ? rows : [...refs.menuDetailGrid.querySelectorAll(".detail-grid-row[data-menu-id]")];
    if (!targetRows.length) return;
    setMenuStatus(`Saving ${targetRows.length} row${targetRows.length === 1 ? "" : "s"}...`);
    try {
      await Promise.all(targetRows.map((row) => saveDetailRow(row)));
      syncCategoryOrder();
      renderMenu();
      setMenuStatus("Details saved.", "success");
    } catch (error) {
      setMenuStatus(error.message, "error");
    }
  }

  function getSortBaseForCategory(category) {
    const index = Math.max(state.categoryOrder.indexOf(category), 0);
    return (index + 1) * SORT_BASE_STEP;
  }

  async function saveSortUpdates(updates) {
    if (!supabaseClient || !state.menuSession) {
      throw new Error("Sign in before saving sort.");
    }
    const results = await Promise.all(
      updates.map((item) => supabaseClient
        .from("menu_items")
        .update({ sort_order: item.sort_order })
        .eq("id", item.id)
        .select(MENU_SELECT)
        .single())
    );
    const failed = results.find((result) => result.error);
    if (failed) throw failed.error;
    const byId = new Map(results.map((result) => [String(result.data.id), result.data]));
    state.menuItems = state.menuItems.map((item) => byId.get(String(item.id)) || item);
  }

  async function saveVisualOrder() {
    if (state.menuCategory === "all") {
      setMenuStatus("Choose one category before saving visible order.", "error");
      return;
    }
    if (state.menuSearch.trim() || state.menuBranch !== "all") {
      setMenuStatus("Clear search and set branch to All before saving visible order.", "error");
      return;
    }
    const rows = [...refs.menuList.querySelectorAll(".menu-preview-card[data-menu-id]")];
    if (!rows.length) return;
    const base = getSortBaseForCategory(state.menuCategory);
    const updates = rows.map((row, index) => ({
      id: row.dataset.menuId,
      sort_order: base + (index + 1) * 10
    }));
    setMenuStatus("Saving visible order...");
    try {
      await saveSortUpdates(updates);
      syncCategoryOrder();
      renderMenu();
      setMenuStatus("Visible order saved.", "success");
    } catch (error) {
      setMenuStatus(error.message, "error");
    }
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
    setMenuStatus("Saving category order...");
    try {
      await saveSortUpdates(updates);
      state.categoryOrder = categories;
      renderMenu();
      setMenuStatus("Category order saved.", "success");
    } catch (error) {
      setMenuStatus(error.message, "error");
    }
  }

  async function saveMenuOrder() {
    const category = state.menuOrderCategory;
    if (!category) return;
    const rows = [...refs.menuOrderList.querySelectorAll("[data-menu-id]")];
    const base = getSortBaseForCategory(category);
    const updates = rows.map((row, index) => ({
      id: row.dataset.menuId,
      sort_order: base + (index + 1) * 10
    }));
    setMenuStatus("Saving menu order...");
    try {
      await saveSortUpdates(updates);
      renderMenu();
      setMenuStatus("Menu order saved.", "success");
    } catch (error) {
      setMenuStatus(error.message, "error");
    }
  }

  function moveRow(button, direction) {
    const row = button.closest(".category-order-row, .menu-order-row");
    if (!row) return;
    if (direction === "up" && row.previousElementSibling) {
      row.parentElement.insertBefore(row, row.previousElementSibling);
    }
    if (direction === "down" && row.nextElementSibling) {
      row.parentElement.insertBefore(row.nextElementSibling, row);
    }
  }

  function openMenuEditor(item = null) {
    const isNew = !item;
    refs.menuEditorTitle.textContent = isNew ? "Add Menu" : "Edit Menu";
    refs.menuEditorForm.reset();
    byId("menuEditId").value = item?.id ?? "";
    byId("menuEditNameKo").value = item?.name_ko ?? "";
    byId("menuEditNameEn").value = item?.name_en ?? "";
    byId("menuEditRomanizedName").value = item?.romanized_name ?? "";
    byId("menuEditPrice").value = item?.price ?? "";
    byId("menuEditCategory").value = item?.category ?? (state.menuCategory !== "all" ? state.menuCategory : "");
    byId("menuEditLabel").value = item?.label ?? "";
    byId("menuEditBranch").value = item?.branches ?? "both";
    byId("menuEditSortOrder").value = item?.sort_order ?? "";
    byId("menuEditDescription").value = item?.description ?? "";
    byId("menuEditImageUrl").value = item?.image_url ?? "";
    byId("menuEditTags").value = item?.tags ?? "";
    byId("menuEditIngredient").value = item?.ingredient ?? "";
    byId("menuEditAvailable").checked = item?.is_available !== false;
    refs.menuDeleteBtn.hidden = isNew;
    refs.menuEditorModal.classList.add("is-open");
    refs.menuEditorModal.setAttribute("aria-hidden", "false");
  }

  function closeMenuEditor() {
    refs.menuEditorModal.classList.remove("is-open");
    refs.menuEditorModal.setAttribute("aria-hidden", "true");
  }

  function readMenuEditorPayload() {
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
      tags: byId("menuEditTags").value,
      ingredient: byId("menuEditIngredient").value,
      is_available: byId("menuEditAvailable").checked
    });
  }

  async function saveMenuEditor(event) {
    event.preventDefault();
    if (!supabaseClient || !state.menuSession) {
      setMenuStatus("Sign in before saving.", "error");
      return;
    }
    const id = byId("menuEditId").value;
    const payload = readMenuEditorPayload();
    if (!payload.name_ko && !payload.name_en) {
      setMenuStatus("Menu name is required.", "error");
      return;
    }
    if (!payload.category) {
      setMenuStatus("Category is required.", "error");
      return;
    }

    setMenuStatus("Saving menu...");
    const query = id
      ? supabaseClient.from("menu_items").update(payload).eq("id", id)
      : supabaseClient.from("menu_items").insert(payload);
    const { data, error } = await query.select(MENU_SELECT).single();
    if (error) {
      setMenuStatus(error.message, "error");
      return;
    }
    if (id) {
      state.menuItems = state.menuItems.map((item) => String(item.id) === String(id) ? data : item);
    } else {
      state.menuItems = [...state.menuItems, data];
    }
    closeMenuEditor();
    syncCategoryOrder();
    renderMenu();
    setMenuStatus("Menu saved.", "success");
  }

  async function deleteMenuItem() {
    const id = byId("menuEditId").value;
    if (!id || !supabaseClient || !state.menuSession) return;
    const item = getMenuById(id);
    const ok = window.confirm(`Delete ${item?.name_en || item?.name_ko || "this menu item"}?`);
    if (!ok) return;
    setMenuStatus("Deleting menu...");
    const { error } = await supabaseClient.from("menu_items").delete().eq("id", id);
    if (error) {
      setMenuStatus(error.message, "error");
      return;
    }
    state.menuItems = state.menuItems.filter((menuItem) => String(menuItem.id) !== String(id));
    closeMenuEditor();
    syncCategoryOrder();
    renderMenu();
    setMenuStatus("Menu deleted.", "success");
  }

  function setActiveTab(tabName) {
    state.activeTab = tabName;
    document.querySelectorAll("[data-admin-tab]").forEach((button) => {
      button.classList.toggle("is-active", button.dataset.adminTab === tabName);
    });
    byId("reservationsAdminPanel").classList.toggle("is-active", tabName === "reservations");
    byId("menuAdminPanel").classList.toggle("is-active", tabName === "menu");
    if (tabName === "menu") void refreshMenuSession();
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
    refs.reservationSearchInput.addEventListener("input", (event) => {
      state.reservationSearch = event.target.value;
      renderReservations();
    });
    refs.reservationRefreshBtn.addEventListener("click", () => void fetchReservations());

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
    refs.menuSaveVisualOrderBtn.addEventListener("click", () => void saveVisualOrder());
    refs.menuDetailGrid.addEventListener("click", (event) => {
      const saveButton = event.target.closest("[data-grid-save]");
      if (!saveButton) return;
      const row = saveButton.closest(".detail-grid-row[data-menu-id]");
      if (row) void saveDetailRows([row]);
    });
    refs.menuSaveDetailBtn.addEventListener("click", () => void saveDetailRows([]));
    refs.menuCategoryOrderList.addEventListener("click", (event) => {
      const button = event.target.closest("[data-order-move]");
      if (button) moveRow(button, button.dataset.orderMove);
    });
    refs.menuOrderList.addEventListener("click", (event) => {
      const button = event.target.closest("[data-order-move]");
      if (button) moveRow(button, button.dataset.orderMove);
    });
    refs.menuOrderCategory.addEventListener("change", (event) => {
      state.menuOrderCategory = event.target.value;
      renderMenuOrder();
    });
    refs.menuSaveCategoryOrderBtn.addEventListener("click", () => void saveCategoryOrder());
    refs.menuSaveMenuOrderBtn.addEventListener("click", () => void saveMenuOrder());

    refs.menuEditorForm.addEventListener("submit", (event) => void saveMenuEditor(event));
    refs.menuDeleteBtn.addEventListener("click", () => void deleteMenuItem());
    refs.menuEditorClose.addEventListener("click", closeMenuEditor);
    refs.menuEditorCancel.addEventListener("click", closeMenuEditor);
    refs.menuEditorModal.addEventListener("click", (event) => {
      if (event.target === refs.menuEditorModal) closeMenuEditor();
    });

    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape" && refs.menuEditorModal.classList.contains("is-open")) {
        closeMenuEditor();
      }
    });
  }

  function bootstrap() {
    cacheRefs();
    refs.todayHeading.textContent = new Intl.DateTimeFormat("en-US", {
      weekday: "long",
      month: "long",
      day: "numeric",
      year: "numeric"
    }).format(new Date());
    bindEvents();
    renderReservationDayChips();
    renderReservationBranchChips();
    renderReservationMetrics([]);
    updateMenuAuthView();
    setActiveTab("reservations");
    if (supabaseClient) {
      supabaseClient.auth.onAuthStateChange((_event, session) => {
        state.menuSession = session;
        updateMenuAuthView();
        if (session && state.activeTab === "menu" && !state.menuItems.length) void fetchMenuItems();
      });
      void refreshMenuSession();
    } else {
      setMenuAuthStatus("Supabase client could not load.", "error");
    }
    void fetchReservations();
  }

  bootstrap();
})();
