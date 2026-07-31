(function () {
  "use strict";

  const S = window.EhwaSettlement;
  const client = S.client;
  const refs = {};
  const state = {
    session: null,
    view: "entry",
    branch: "downtown",
    businessDate: S.isoDate(new Date()),
    entry: null,
    staff: [],
    roster: [],
    loading: false,
    saving: false
  };

  function cacheRefs() {
    [
      "authGate",
      "authForm",
      "authEmail",
      "authPassword",
      "signInButton",
      "authStatus",
      "settlementWorkspace",
      "entryView",
      "summaryView",
      "settlementTabs",
      "sessionUser",
      "signOutButton",
      "businessDate",
      "previousDateButton",
      "nextDateButton",
      "todayButton",
      "entryBranchControl",
      "sourceBadge",
      "entryForm",
      "entryDateLabel",
      "totalSales",
      "cardSales",
      "cashRemainder",
      "receiptAmount",
      "cardTip",
      "cardTipFeePercent",
      "kitchenSharePercent",
      "hallSharePercent",
      "netTipAdjustment",
      "cashSalesPreview",
      "netTipPreview",
      "tipPercentPreview",
      "kitchenTipPreview",
      "kitchenRatePreview",
      "hallTipPreview",
      "hallRatePreview",
      "staffCountLabel",
      "staffSections",
      "dailyNote",
      "noteLength",
      "noteDateLabel",
      "entryStatus",
      "saveEntryButton",
      "periodLabel",
      "sideTotalSales",
      "sideNetTip",
      "sideKitchenHours",
      "sideHallHours",
      "sideStaffTips",
      "sideVariance",
      "openRosterButton",
      "rosterDialog",
      "closeRosterButton",
      "rosterForm",
      "rosterName",
      "rosterDepartment",
      "rosterTipEligible",
      "saveRosterButton",
      "rosterStatus",
      "rosterList"
    ].forEach((id) => {
      refs[id] = S.byId(id);
    });
    refs.branchButtons = Array.from(refs.entryBranchControl.querySelectorAll("[data-branch]"));
    refs.viewButtons = Array.from(refs.settlementTabs.querySelectorAll("[data-view-target]"));
  }

  function setSignedInView(session) {
    state.session = session || null;
    const signedIn = Boolean(session?.access_token);
    refs.authGate.hidden = signedIn;
    refs.settlementWorkspace.hidden = !signedIn;
    refs.signOutButton.hidden = !signedIn;
    refs.sessionUser.textContent = signedIn ? session.user?.email || "관리자" : "";
    window.dispatchEvent(new CustomEvent("ehwa:settlement-auth", {
      detail: { session: state.session }
    }));
    if (signedIn && state.view === "entry") void loadDay();
  }

  async function signIn() {
    if (!client) {
      S.setStatus(refs.authStatus, "Supabase 클라이언트를 불러오지 못했습니다.", "error");
      return;
    }
    const email = refs.authEmail.value.trim();
    const password = refs.authPassword.value;
    if (!email || !password) return;

    refs.signInButton.disabled = true;
    S.setStatus(refs.authStatus, "로그인 중...");
    const { data, error } = await client.auth.signInWithPassword({ email, password });
    refs.signInButton.disabled = false;
    if (error) {
      S.setStatus(refs.authStatus, error.message, "error");
      return;
    }
    refs.authPassword.value = "";
    setSignedInView(data.session);
  }

  async function signOut() {
    if (!client) return;
    await client.auth.signOut();
    state.entry = null;
    state.staff = [];
    setSignedInView(null);
  }

  function setView(view, updateUrl = true) {
    state.view = view === "summary" ? "summary" : "entry";
    refs.entryView.hidden = state.view !== "entry";
    refs.summaryView.hidden = state.view !== "summary";
    refs.viewButtons.forEach((button) => {
      const active = button.dataset.viewTarget === state.view;
      button.classList.toggle("is-active", active);
      button.setAttribute("aria-selected", String(active));
    });
    document.title = state.view === "summary"
      ? "이화 정산 요약"
      : "이화 정산 입력";

    if (updateUrl) {
      const url = new URL(window.location.href);
      if (state.view === "summary") {
        url.searchParams.set("view", "summary");
        url.searchParams.delete("date");
      } else {
        url.searchParams.delete("view");
      }
      window.history.replaceState({}, "", url);
    }

    window.dispatchEvent(new CustomEvent("ehwa:settlement-view", {
      detail: { view: state.view }
    }));
    if (state.session && state.view === "entry" && !state.entry) void loadDay();
    window.scrollTo({ top: 0, behavior: "auto" });
  }

  function setBranch(branch) {
    state.branch = branch === "uptown" ? "uptown" : "downtown";
    refs.branchButtons.forEach((button) => {
      button.classList.toggle("is-active", button.dataset.branch === state.branch);
    });
  }

  function publishBranch() {
    window.dispatchEvent(new CustomEvent("ehwa:settlement-branch", {
      detail: { branch: state.branch, source: "entry" }
    }));
  }

  function getPeriodRange(value) {
    const date = S.safeDate(value);
    const anchor = S.safeDate("2025-12-31");
    if (!date || !anchor) return { start: value, end: value };
    const diffDays = Math.floor((date.getTime() - anchor.getTime()) / 86400000);
    const offset = Math.floor(diffDays / 14) * 14;
    const start = new Date(anchor);
    start.setDate(start.getDate() + offset);
    const end = new Date(start);
    end.setDate(end.getDate() + 13);
    return { start: S.isoDate(start), end: S.isoDate(end) };
  }

  function setInputValue(input, value, fallback = 0) {
    input.value = Number.isFinite(Number(value)) ? Number(value) : fallback;
  }

  function renderEntry() {
    const entry = state.entry || {};
    setInputValue(refs.totalSales, entry.total_sales);
    setInputValue(refs.cardSales, entry.card_sales);
    setInputValue(refs.cashRemainder, entry.cash_remainder);
    setInputValue(refs.receiptAmount, entry.receipt_amount);
    setInputValue(refs.cardTip, entry.card_tip);
    setInputValue(refs.cardTipFeePercent, S.toNumber(entry.card_tip_fee_rate, 0.02) * 100, 2);
    setInputValue(refs.kitchenSharePercent, S.toNumber(entry.kitchen_share_rate, 0.4) * 100, 40);
    setInputValue(refs.hallSharePercent, S.toNumber(entry.hall_share_rate, 0.6) * 100, 60);
    setInputValue(refs.netTipAdjustment, entry.net_tip_adjustment);
    refs.dailyNote.value = entry.note || "";
    refs.sourceBadge.hidden = !entry.source;
    refs.sourceBadge.textContent = entry.source === "xlsx" ? "엑셀 이관" : entry.source === "google_sheet" ? "시트 이관" : "저장됨";
    refs.entryDateLabel.textContent = S.formatDate(state.businessDate, { year: true });
    refs.noteDateLabel.textContent = `${S.formatDate(state.businessDate)} 노트`;
    refs.noteLength.textContent = `${refs.dailyNote.value.length} / 2000`;
    const period = getPeriodRange(state.businessDate);
    refs.periodLabel.textContent = S.formatRange(period.start, period.end);
    renderStaff();
    calculatePreview();
  }

  function staffRowTemplate(staff) {
    const override = staff.tip_override;
    const hasOverride = override !== null && override !== undefined && override !== "";
    return `
      <tr data-staff-id="${S.escapeHtml(staff.staff_id)}" data-tip-override="${hasOverride ? S.escapeHtml(override) : ""}">
        <td class="staff-name">
          ${S.escapeHtml(staff.display_name)}
          ${staff.active ? "" : "<small>이전 직원</small>"}
        </td>
        <td>
          <input
            class="staff-hours"
            type="number"
            min="0"
            max="24"
            step="0.25"
            inputmode="decimal"
            value="${S.escapeHtml(S.toNumber(staff.hours))}"
            aria-label="${S.escapeHtml(staff.display_name)} 근무시간"
          />
        </td>
        <td>
          <label class="toggle" title="팁 배분 포함">
            <input class="staff-eligible" type="checkbox" ${staff.tip_eligible ? "checked" : ""} aria-label="${S.escapeHtml(staff.display_name)} 팁 배분 포함" />
            <span></span>
          </label>
        </td>
        <td>
          <input
            class="staff-adjustment"
            type="number"
            step="0.01"
            inputmode="decimal"
            value="${S.escapeHtml(S.toNumber(staff.tip_adjustment))}"
            aria-label="${S.escapeHtml(staff.display_name)} 팁 보정"
          />
        </td>
        <td>
          <strong class="tip-value ${hasOverride ? "is-override" : ""}">${S.formatMoney(staff.tip_amount)}</strong>
        </td>
      </tr>
    `;
  }

  function staffSectionTemplate(department, title) {
    const rows = state.staff.filter((staff) => staff.department === department);
    return `
      <section class="staff-section" data-department="${department}">
        <div class="staff-section-head">
          <span class="department-dot ${department === "hall" ? "is-hall" : ""}"></span>
          <h3>${title}</h3>
        </div>
        <div class="staff-table-wrap">
          <table class="staff-table">
            <thead>
              <tr>
                <th>직원</th>
                <th>시간</th>
                <th>팁 대상</th>
                <th>팁 보정</th>
                <th>예상 팁</th>
              </tr>
            </thead>
            <tbody>
              ${rows.length ? rows.map(staffRowTemplate).join("") : `<tr><td class="empty-row" colspan="5">직원을 추가하세요.</td></tr>`}
            </tbody>
          </table>
        </div>
      </section>
    `;
  }

  function renderStaff() {
    refs.staffSections.innerHTML =
      staffSectionTemplate("kitchen", "주방") +
      staffSectionTemplate("hall", "홀");
    refs.staffCountLabel.textContent = `${state.staff.length}명`;
  }

  function getStaffInputs() {
    return Array.from(refs.staffSections.querySelectorAll("[data-staff-id]")).map((row) => {
      const source = state.staff.find((item) => item.staff_id === row.dataset.staffId) || {};
      const overrideValue = row.dataset.tipOverride;
      return {
        row,
        staff_id: row.dataset.staffId,
        display_name: source.display_name || "",
        department: source.department || "hall",
        hours: S.toNumber(row.querySelector(".staff-hours")?.value),
        tip_eligible: Boolean(row.querySelector(".staff-eligible")?.checked),
        tip_adjustment: S.toNumber(row.querySelector(".staff-adjustment")?.value),
        tip_override: overrideValue === "" ? null : S.toNumber(overrideValue)
      };
    });
  }

  function clearTipOverrides(targetRow = null) {
    const rows = targetRow
      ? [targetRow]
      : Array.from(refs.staffSections.querySelectorAll("[data-staff-id]"));
    rows.forEach((row) => {
      row.dataset.tipOverride = "";
      row.querySelector(".tip-value")?.classList.remove("is-override");
    });
  }

  function calculatePreview() {
    const totalSales = S.toNumber(refs.totalSales.value);
    const cardSales = S.toNumber(refs.cardSales.value);
    const cashRemainder = S.toNumber(refs.cashRemainder.value);
    const receiptAmount = S.toNumber(refs.receiptAmount.value);
    const cardTip = S.toNumber(refs.cardTip.value);
    const feeRate = S.toNumber(refs.cardTipFeePercent.value, 2) / 100;
    const kitchenShare = S.toNumber(refs.kitchenSharePercent.value, 40) / 100;
    const hallShare = S.toNumber(refs.hallSharePercent.value, 60) / 100;
    const netAdjustment = S.toNumber(refs.netTipAdjustment.value);
    const cashSales = totalSales - cardSales;
    const netTip =
      cardSales -
      totalSales +
      cashRemainder +
      receiptAmount -
      cardTip * feeRate +
      netAdjustment;
    const kitchenTip = netTip * kitchenShare;
    const hallTip = netTip * hallShare;
    const staffRows = getStaffInputs();
    const kitchenHours = staffRows
      .filter((staff) => staff.department === "kitchen" && staff.tip_eligible)
      .reduce((sum, staff) => sum + staff.hours, 0);
    const hallHours = staffRows
      .filter((staff) => staff.department === "hall" && staff.tip_eligible)
      .reduce((sum, staff) => sum + staff.hours, 0);
    const kitchenRate = kitchenHours > 0 ? kitchenTip / kitchenHours : 0;
    const hallRate = hallHours > 0 ? hallTip / hallHours : 0;
    let staffTipTotal = 0;

    staffRows.forEach((staff) => {
      const departmentRate = staff.department === "kitchen" ? kitchenRate : hallRate;
      const tipAmount = staff.tip_override !== null
        ? staff.tip_override
        : (staff.tip_eligible ? staff.hours * departmentRate : 0) + staff.tip_adjustment;
      staffTipTotal += tipAmount;
      const tipElement = staff.row.querySelector(".tip-value");
      if (tipElement) tipElement.textContent = S.formatMoney(tipAmount);
    });

    refs.cashSalesPreview.textContent = S.formatMoney(cashSales);
    refs.netTipPreview.textContent = S.formatMoney(netTip);
    refs.tipPercentPreview.textContent = totalSales
      ? `${S.formatNumber((netTip / totalSales) * 100)}%`
      : "0%";
    refs.kitchenTipPreview.textContent = S.formatMoney(kitchenTip);
    refs.kitchenRatePreview.textContent = `${S.formatMoney(kitchenRate)}/h`;
    refs.hallTipPreview.textContent = S.formatMoney(hallTip);
    refs.hallRatePreview.textContent = `${S.formatMoney(hallRate)}/h`;
    refs.sideTotalSales.textContent = S.formatMoney(totalSales);
    refs.sideNetTip.textContent = S.formatMoney(netTip);
    refs.sideKitchenHours.textContent = S.formatNumber(kitchenHours, "h");
    refs.sideHallHours.textContent = S.formatNumber(hallHours, "h");
    refs.sideStaffTips.textContent = S.formatMoney(staffTipTotal);
    refs.sideVariance.textContent = S.formatMoney(staffTipTotal - netTip);
  }

  async function loadDay() {
    if (!client || !state.session || state.loading) return;
    state.loading = true;
    refs.businessDate.value = state.businessDate;
    refs.saveEntryButton.disabled = true;
    S.setStatus(refs.entryStatus, "불러오는 중...");

    const { data, error } = await client.rpc("settlement_get_day_v1", {
      input_branch: state.branch,
      input_date: state.businessDate
    });

    state.loading = false;
    refs.saveEntryButton.disabled = false;
    if (error) {
      state.entry = null;
      state.staff = [];
      renderEntry();
      S.setStatus(refs.entryStatus, S.getErrorMessage(error), "error");
      return;
    }

    state.entry = data?.entry || null;
    state.staff = Array.isArray(data?.staff) ? data.staff : [];
    renderEntry();
    S.setStatus(refs.entryStatus, state.entry ? "저장된 정산을 불러왔습니다." : "새 정산");
  }

  async function saveEntry() {
    if (!client || !state.session || state.saving) return;
    const kitchenShare = S.toNumber(refs.kitchenSharePercent.value, 40);
    const hallShare = S.toNumber(refs.hallSharePercent.value, 60);
    if (Math.abs(kitchenShare + hallShare - 100) > 0.001) {
      S.setStatus(refs.entryStatus, "주방과 홀 배분 합계가 100%여야 합니다.", "error");
      return;
    }

    const staff = getStaffInputs();
    if (staff.some((item) => item.hours < 0 || item.hours > 24)) {
      S.setStatus(refs.entryStatus, "근무시간은 0시간에서 24시간 사이로 입력하세요.", "error");
      return;
    }

    const payload = {
      branch: state.branch,
      business_date: state.businessDate,
      total_sales: S.toNumber(refs.totalSales.value),
      card_sales: S.toNumber(refs.cardSales.value),
      cash_remainder: S.toNumber(refs.cashRemainder.value),
      receipt_amount: S.toNumber(refs.receiptAmount.value),
      card_tip: S.toNumber(refs.cardTip.value),
      card_tip_fee_rate: S.toNumber(refs.cardTipFeePercent.value, 2) / 100,
      kitchen_share_rate: kitchenShare / 100,
      hall_share_rate: hallShare / 100,
      net_tip_adjustment: S.toNumber(refs.netTipAdjustment.value),
      note: refs.dailyNote.value,
      staff: staff.map((item) => ({
        staff_id: item.staff_id,
        hours: item.hours,
        tip_eligible: item.tip_eligible,
        tip_adjustment: item.tip_adjustment,
        tip_override: item.tip_override
      }))
    };

    state.saving = true;
    refs.saveEntryButton.disabled = true;
    S.setStatus(refs.entryStatus, "저장 중...");
    const { data, error } = await client.rpc("settlement_save_day_v1", {
      input_payload: payload
    });
    state.saving = false;
    refs.saveEntryButton.disabled = false;

    if (error) {
      S.setStatus(refs.entryStatus, S.getErrorMessage(error, "정산을 저장하지 못했습니다."), "error");
      return;
    }

    state.entry = data?.entry || null;
    state.staff = Array.isArray(data?.staff) ? data.staff : [];
    renderEntry();
    S.setStatus(refs.entryStatus, "정산을 저장했습니다.", "success");
    window.dispatchEvent(new CustomEvent("ehwa:settlement-saved"));
  }

  async function loadRoster() {
    if (!client || !state.session) return;
    S.setStatus(refs.rosterStatus, "불러오는 중...");
    const { data, error } = await client
      .from("settlement_staff_members")
      .select("*")
      .eq("branch", state.branch)
      .order("department", { ascending: false })
      .order("sort_order", { ascending: true });

    if (error) {
      state.roster = [];
      renderRoster();
      S.setStatus(refs.rosterStatus, S.getErrorMessage(error), "error");
      return;
    }
    state.roster = Array.isArray(data) ? data : [];
    renderRoster();
    S.setStatus(refs.rosterStatus, "");
  }

  function renderRoster() {
    refs.rosterList.innerHTML = state.roster.length
      ? state.roster.map((staff) => `
        <div class="roster-item" data-roster-id="${S.escapeHtml(staff.id)}">
          <strong>${S.escapeHtml(staff.display_name)}</strong>
          <span>${staff.department === "kitchen" ? "주방" : "홀"}</span>
          <span>${staff.tip_eligible_default ? "팁 대상" : "팁 제외"}</span>
          <button class="btn btn-small ${staff.active ? "btn-danger" : ""}" type="button" data-roster-toggle>
            ${staff.active ? "비활성" : "활성"}
          </button>
        </div>
      `).join("")
      : `<div class="empty-row">직원이 없습니다.</div>`;
  }

  async function saveRosterMember(payload) {
    refs.saveRosterButton.disabled = true;
    S.setStatus(refs.rosterStatus, "저장 중...");
    const { error } = await client.rpc("settlement_save_staff_v1", {
      input_payload: payload
    });
    refs.saveRosterButton.disabled = false;
    if (error) {
      S.setStatus(refs.rosterStatus, S.getErrorMessage(error), "error");
      return false;
    }
    await loadRoster();
    await loadDay();
    return true;
  }

  async function addRosterMember() {
    const name = refs.rosterName.value.trim();
    if (!name) return;
    const saved = await saveRosterMember({
      branch: state.branch,
      department: refs.rosterDepartment.value,
      staff_key: name,
      display_name: name,
      tip_eligible_default: refs.rosterTipEligible.checked,
      active: true,
      sort_order: state.roster.length + 1
    });
    if (saved) {
      refs.rosterForm.reset();
      refs.rosterTipEligible.checked = true;
      S.setStatus(refs.rosterStatus, "직원을 추가했습니다.", "success");
    }
  }

  async function toggleRosterMember(id) {
    const staff = state.roster.find((item) => item.id === id);
    if (!staff) return;
    const saved = await saveRosterMember({
      id: staff.id,
      branch: staff.branch,
      department: staff.department,
      staff_key: staff.staff_key,
      display_name: staff.display_name,
      tip_eligible_default: staff.tip_eligible_default,
      active: !staff.active,
      sort_order: staff.sort_order
    });
    if (saved) S.setStatus(refs.rosterStatus, "직원 상태를 변경했습니다.", "success");
  }

  function bindEvents() {
    refs.authForm.addEventListener("submit", (event) => {
      event.preventDefault();
      void signIn();
    });
    refs.signOutButton.addEventListener("click", () => void signOut());
    refs.entryForm.addEventListener("submit", (event) => {
      event.preventDefault();
      void saveEntry();
    });
    refs.previousDateButton.addEventListener("click", () => {
      state.businessDate = S.shiftDate(state.businessDate, -1);
      void loadDay();
    });
    refs.nextDateButton.addEventListener("click", () => {
      state.businessDate = S.shiftDate(state.businessDate, 1);
      void loadDay();
    });
    refs.todayButton.addEventListener("click", () => {
      state.businessDate = S.isoDate(new Date());
      void loadDay();
    });
    refs.businessDate.addEventListener("change", () => {
      if (!refs.businessDate.value) return;
      state.businessDate = refs.businessDate.value;
      void loadDay();
    });
    refs.branchButtons.forEach((button) => {
      button.addEventListener("click", () => {
        setBranch(button.dataset.branch);
        publishBranch();
        void loadDay();
      });
    });
    refs.viewButtons.forEach((button) => {
      button.addEventListener("click", () => setView(button.dataset.viewTarget));
    });
    window.addEventListener("ehwa:settlement-branch", (event) => {
      if (event.detail?.source !== "summary") return;
      const nextBranch = event.detail?.branch === "uptown" ? "uptown" : "downtown";
      if (nextBranch === state.branch) return;
      setBranch(nextBranch);
      state.entry = null;
      if (state.session && state.view === "entry") void loadDay();
    });

    [
      refs.totalSales,
      refs.cardSales,
      refs.cashRemainder,
      refs.receiptAmount,
      refs.cardTip,
      refs.cardTipFeePercent,
      refs.kitchenSharePercent,
      refs.hallSharePercent,
      refs.netTipAdjustment
    ].forEach((input) => {
      input.addEventListener("input", () => {
        clearTipOverrides();
        calculatePreview();
      });
    });

    refs.staffSections.addEventListener("input", (event) => {
      const row = event.target.closest("[data-staff-id]");
      if (!row) return;
      clearTipOverrides(row);
      calculatePreview();
    });
    refs.staffSections.addEventListener("change", (event) => {
      const row = event.target.closest("[data-staff-id]");
      if (!row) return;
      clearTipOverrides(row);
      calculatePreview();
    });
    refs.dailyNote.addEventListener("input", () => {
      refs.noteLength.textContent = `${refs.dailyNote.value.length} / 2000`;
    });

    refs.openRosterButton.addEventListener("click", () => {
      refs.rosterDialog.showModal();
      void loadRoster();
    });
    refs.closeRosterButton.addEventListener("click", () => refs.rosterDialog.close());
    refs.rosterForm.addEventListener("submit", (event) => {
      event.preventDefault();
      void addRosterMember();
    });
    refs.rosterList.addEventListener("click", (event) => {
      const button = event.target.closest("[data-roster-toggle]");
      const item = button?.closest("[data-roster-id]");
      if (item) void toggleRosterMember(item.dataset.rosterId);
    });
    refs.rosterDialog.addEventListener("click", (event) => {
      if (event.target === refs.rosterDialog) refs.rosterDialog.close();
    });
  }

  async function bootstrap() {
    cacheRefs();
    const params = new URLSearchParams(window.location.search);
    const requestedDate = params.get("date");
    const requestedBranch = params.get("branch");
    if (/^\d{4}-\d{2}-\d{2}$/.test(requestedDate || "")) {
      state.businessDate = requestedDate;
    }
    setBranch(requestedBranch || "downtown");
    setView(requestedDate ? "entry" : params.get("view"), false);
    refs.businessDate.value = state.businessDate;
    bindEvents();
    window.EhwaSettlementApp = {
      getSession: () => state.session,
      getBranch: () => state.branch,
      getView: () => state.view,
      showView: (view) => setView(view)
    };
    if (!client) {
      S.setStatus(refs.authStatus, "Supabase 클라이언트를 불러오지 못했습니다.", "error");
      return;
    }

    const { data, error } = await client.auth.getSession();
    if (error) {
      S.setStatus(refs.authStatus, error.message, "error");
    }
    setSignedInView(data?.session || null);
    client.auth.onAuthStateChange((_event, session) => {
      if (session?.access_token === state.session?.access_token) return;
      setSignedInView(session);
    });
  }

  void bootstrap();
})();
