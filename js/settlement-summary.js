(function () {
  "use strict";

  const S = window.EhwaSettlement;
  const client = S.client;
  const refs = {};
  const state = {
    session: null,
    branch: "downtown",
    daily: [],
    periods: [],
    staff: [],
    selectedPeriod: "all",
    department: "all",
    search: "",
    historyLimit: 30,
    loading: false,
    loaded: false
  };

  function cacheRefs() {
    [
      "summaryView",
      "summaryBranchControl",
      "periodSelect",
      "historySearch",
      "refreshButton",
      "summaryStatus",
      "metricSales",
      "metricDays",
      "metricNetTip",
      "metricTipRate",
      "metricKitchenTip",
      "metricKitchenRate",
      "metricHallTip",
      "metricHallRate",
      "metricKitchenHours",
      "metricKitchenStaff",
      "metricHallHours",
      "metricHallStaff",
      "trendRangeLabel",
      "trendChart",
      "periodCountLabel",
      "periodTableBody",
      "departmentTabs",
      "staffSummaryBody",
      "historyCountLabel",
      "historyTableBody",
      "historyFooter",
      "showMoreButton"
    ].forEach((id) => {
      refs[id] = S.byId(id);
    });
    refs.branchButtons = Array.from(refs.summaryBranchControl.querySelectorAll("[data-branch]"));
    refs.departmentButtons = Array.from(refs.departmentTabs.querySelectorAll("[data-department]"));
  }

  function setBranch(branch) {
    state.branch = branch === "uptown" ? "uptown" : "downtown";
    refs.branchButtons.forEach((button) => {
      button.classList.toggle("is-active", button.dataset.branch === state.branch);
    });
  }

  function periodKey(period) {
    return `${period.period_start}:${period.period_end}`;
  }

  function selectedPeriodRow() {
    return state.periods.find((period) => periodKey(period) === state.selectedPeriod) || null;
  }

  function getFilteredDaily() {
    const period = selectedPeriodRow();
    const normalizedSearch = state.search.trim().toLowerCase();
    return state.daily.filter((day) => {
      const inPeriod = !period || (
        day.business_date >= period.period_start &&
        day.business_date <= period.period_end
      );
      if (!inPeriod) return false;
      if (!normalizedSearch) return true;
      return (
        String(day.business_date).toLowerCase().includes(normalizedSearch) ||
        String(day.note || "").toLowerCase().includes(normalizedSearch)
      );
    });
  }

  function getFilteredStaff() {
    const period = selectedPeriodRow();
    return state.staff.filter((row) => {
      const inPeriod = !period || (
        row.period_start === period.period_start &&
        row.period_end === period.period_end
      );
      const inDepartment = state.department === "all" || row.department === state.department;
      return inPeriod && inDepartment;
    });
  }

  function sum(rows, key) {
    return rows.reduce((total, row) => total + S.toNumber(row[key]), 0);
  }

  function renderPeriodSelect() {
    const options = state.periods.map((period) => `
      <option value="${S.escapeHtml(periodKey(period))}">
        ${S.escapeHtml(S.formatRange(period.period_start, period.period_end))}
      </option>
    `).join("");
    refs.periodSelect.innerHTML = `<option value="all">전체 기간</option>${options}`;
    if (!state.periods.some((period) => periodKey(period) === state.selectedPeriod)) {
      state.selectedPeriod = "all";
    }
    refs.periodSelect.value = state.selectedPeriod;
  }

  function renderMetrics() {
    const daily = getFilteredDaily();
    const staff = getFilteredStaff();
    const totalSales = sum(daily, "total_sales");
    const netTip = sum(daily, "net_tip");
    const kitchenTip = sum(daily, "kitchen_tip");
    const hallTip = sum(daily, "hall_tip");
    const kitchenHours = sum(daily, "kitchen_hours");
    const hallHours = sum(daily, "hall_hours");
    const kitchenStaff = new Set(
      staff.filter((row) => row.department === "kitchen" && S.toNumber(row.total_hours) > 0)
        .map((row) => row.staff_id)
    ).size;
    const hallStaff = new Set(
      staff.filter((row) => row.department === "hall" && S.toNumber(row.total_hours) > 0)
        .map((row) => row.staff_id)
    ).size;

    refs.metricSales.textContent = S.formatMoney(totalSales);
    refs.metricDays.textContent = `${daily.length}일`;
    refs.metricNetTip.textContent = S.formatMoney(netTip);
    refs.metricTipRate.textContent = totalSales ? `${S.formatNumber((netTip / totalSales) * 100)}%` : "0%";
    refs.metricKitchenTip.textContent = S.formatMoney(kitchenTip);
    refs.metricKitchenRate.textContent = `${S.formatMoney(kitchenHours ? kitchenTip / kitchenHours : 0)}/h`;
    refs.metricHallTip.textContent = S.formatMoney(hallTip);
    refs.metricHallRate.textContent = `${S.formatMoney(hallHours ? hallTip / hallHours : 0)}/h`;
    refs.metricKitchenHours.textContent = S.formatNumber(kitchenHours, "h");
    refs.metricKitchenStaff.textContent = `${kitchenStaff}명`;
    refs.metricHallHours.textContent = S.formatNumber(hallHours, "h");
    refs.metricHallStaff.textContent = `${hallStaff}명`;
  }

  function renderTrend() {
    const filtered = getFilteredDaily().slice().sort((a, b) => (
      a.business_date.localeCompare(b.business_date)
    ));
    const daily = state.selectedPeriod === "all" ? filtered.slice(-30) : filtered;
    const maxSales = Math.max(...daily.map((day) => S.toNumber(day.total_sales)), 1);
    const maxTip = Math.max(...daily.map((day) => Math.abs(S.toNumber(day.net_tip))), 1);
    const first = daily[0];
    const last = daily[daily.length - 1];

    refs.trendRangeLabel.textContent = first && last
      ? S.formatRange(first.business_date, last.business_date)
      : "";
    refs.trendChart.innerHTML = daily.length
      ? daily.map((day) => {
        const salesHeight = Math.max(2, (S.toNumber(day.total_sales) / maxSales) * 112);
        const tipHeight = Math.max(2, (Math.abs(S.toNumber(day.net_tip)) / maxTip) * 34);
        const date = S.safeDate(day.business_date);
        const label = date ? `${date.getMonth() + 1}/${date.getDate()}` : day.business_date;
        return `
          <div class="trend-day" title="${S.escapeHtml(S.formatDate(day.business_date))} · 매출 ${S.escapeHtml(S.formatMoney(day.total_sales))} · 팁 ${S.escapeHtml(S.formatMoney(day.net_tip))}">
            <div class="trend-bar" style="height:${salesHeight}px"></div>
            <div class="trend-tip" style="height:${tipHeight}px"></div>
            <span>${S.escapeHtml(label)}</span>
          </div>
        `;
      }).join("")
      : `<div class="empty-row">표시할 기록이 없습니다.</div>`;
  }

  function renderPeriods() {
    refs.periodCountLabel.textContent = `${state.periods.length}개`;
    refs.periodTableBody.innerHTML = state.periods.length
      ? state.periods.map((period) => {
        const key = periodKey(period);
        return `
          <tr class="period-row ${key === state.selectedPeriod ? "is-selected" : ""}" data-period-key="${S.escapeHtml(key)}">
            <td class="period-range">${S.escapeHtml(S.formatRange(period.period_start, period.period_end))}</td>
            <td>${S.toNumber(period.entered_days)}일</td>
            <td>${S.formatMoney(period.total_sales)}</td>
            <td>${S.formatMoney(period.net_tip)}</td>
            <td>${S.formatMoney(period.kitchen_tip)}</td>
            <td>${S.formatMoney(period.hall_tip)}</td>
            <td>${S.formatNumber(period.kitchen_hours, "h")}</td>
            <td>${S.formatNumber(period.hall_hours, "h")}</td>
            <td>${S.toNumber(period.note_count)}건</td>
          </tr>
        `;
      }).join("")
      : `<tr><td class="empty-row" colspan="9">정산 기록이 없습니다.</td></tr>`;
  }

  function aggregateStaff(rows) {
    const grouped = new Map();
    rows.forEach((row) => {
      const key = row.staff_id;
      if (!grouped.has(key)) {
        grouped.set(key, {
          staff_id: row.staff_id,
          display_name: row.display_name,
          department: row.department,
          worked_days: 0,
          total_hours: 0,
          total_tip: 0,
          sort_order: S.toNumber(row.sort_order)
        });
      }
      const item = grouped.get(key);
      item.worked_days += S.toNumber(row.worked_days);
      item.total_hours += S.toNumber(row.total_hours);
      item.total_tip += S.toNumber(row.total_tip);
    });
    return Array.from(grouped.values()).sort((a, b) => {
      if (a.department !== b.department) return a.department === "kitchen" ? -1 : 1;
      if (a.sort_order !== b.sort_order) return a.sort_order - b.sort_order;
      return a.display_name.localeCompare(b.display_name);
    });
  }

  function renderStaffSummary() {
    const rows = aggregateStaff(getFilteredStaff());
    refs.staffSummaryBody.innerHTML = rows.length
      ? rows.map((row) => `
        <tr>
          <td class="staff-name">${S.escapeHtml(row.display_name)}</td>
          <td>${row.department === "kitchen" ? "주방" : "홀"}</td>
          <td>${S.formatNumber(row.worked_days)}일</td>
          <td>${S.formatNumber(row.total_hours, "h")}</td>
          <td>${S.formatMoney(row.total_tip)}</td>
          <td>${S.formatMoney(row.total_hours ? row.total_tip / row.total_hours : 0)}</td>
        </tr>
      `).join("")
      : `<tr><td class="empty-row" colspan="6">직원 정산 기록이 없습니다.</td></tr>`;
  }

  function renderHistory() {
    const rows = getFilteredDaily();
    const visibleRows = rows.slice(0, state.historyLimit);
    refs.historyCountLabel.textContent = `${rows.length}건`;
    refs.historyTableBody.innerHTML = visibleRows.length
      ? visibleRows.map((day) => `
        <tr>
          <td class="history-date">
            <a href="./settlement.html?date=${encodeURIComponent(day.business_date)}&branch=${encodeURIComponent(state.branch)}">
              ${S.escapeHtml(S.formatDate(day.business_date))}
            </a>
          </td>
          <td>${S.formatMoney(day.total_sales)}</td>
          <td>${S.formatMoney(day.card_sales)}</td>
          <td>${S.formatMoney(day.net_tip)}</td>
          <td>${S.formatMoney(day.kitchen_hourly_tip)}</td>
          <td>${S.formatMoney(day.hall_hourly_tip)}</td>
          <td class="note-cell">${day.note ? S.escapeHtml(day.note) : "-"}</td>
        </tr>
      `).join("")
      : `<tr><td class="empty-row" colspan="7">일별 기록이 없습니다.</td></tr>`;
    refs.historyFooter.hidden = visibleRows.length >= rows.length;
  }

  function renderAll() {
    renderPeriodSelect();
    renderMetrics();
    renderTrend();
    renderPeriods();
    renderStaffSummary();
    renderHistory();
  }

  async function loadSummary() {
    if (!client || !state.session || state.loading) return;
    state.loading = true;
    refs.refreshButton.disabled = true;
    S.setStatus(refs.summaryStatus, "정산 기록을 불러오는 중...");
    const { data, error } = await client.rpc("settlement_get_summary_v1", {
      input_branch: state.branch,
      input_from: null,
      input_to: null
    });
    state.loading = false;
    refs.refreshButton.disabled = false;

    if (error) {
      state.daily = [];
      state.periods = [];
      state.staff = [];
      renderAll();
      state.loaded = false;
      S.setStatus(refs.summaryStatus, S.getErrorMessage(error), "error");
      return;
    }

    state.daily = Array.isArray(data?.daily) ? data.daily : [];
    state.periods = Array.isArray(data?.periods) ? data.periods : [];
    state.staff = Array.isArray(data?.staff) ? data.staff : [];
    state.historyLimit = 30;
    state.loaded = true;
    renderAll();
    const range = data?.range;
    const rangeLabel = range?.first_date && range?.last_date
      ? S.formatRange(range.first_date, range.last_date)
      : "";
    S.setStatus(
      refs.summaryStatus,
      state.daily.length ? `${rangeLabel} · ${state.daily.length}일` : "정산 기록이 없습니다."
    );
  }

  function selectPeriod(value) {
    state.selectedPeriod = value || "all";
    state.historyLimit = 30;
    refs.periodSelect.value = state.selectedPeriod;
    renderMetrics();
    renderTrend();
    renderPeriods();
    renderStaffSummary();
    renderHistory();
  }

  function bindEvents() {
    refs.refreshButton.addEventListener("click", () => void loadSummary());
    refs.branchButtons.forEach((button) => {
      button.addEventListener("click", () => {
        setBranch(button.dataset.branch);
        state.selectedPeriod = "all";
        state.loaded = false;
        window.dispatchEvent(new CustomEvent("ehwa:settlement-branch", {
          detail: { branch: state.branch, source: "summary" }
        }));
        void loadSummary();
      });
    });
    refs.periodSelect.addEventListener("change", () => selectPeriod(refs.periodSelect.value));
    refs.periodTableBody.addEventListener("click", (event) => {
      const row = event.target.closest("[data-period-key]");
      if (row) selectPeriod(row.dataset.periodKey);
    });
    refs.departmentButtons.forEach((button) => {
      button.addEventListener("click", () => {
        state.department = button.dataset.department || "all";
        refs.departmentButtons.forEach((item) => {
          item.classList.toggle("is-active", item === button);
        });
        renderStaffSummary();
      });
    });
    refs.historySearch.addEventListener("input", () => {
      state.search = refs.historySearch.value;
      state.historyLimit = 30;
      renderMetrics();
      renderTrend();
      renderHistory();
    });
    refs.showMoreButton.addEventListener("click", () => {
      state.historyLimit += 30;
      renderHistory();
    });
    window.addEventListener("ehwa:settlement-auth", (event) => {
      state.session = event.detail?.session || null;
      if (!state.session) {
        state.daily = [];
        state.periods = [];
        state.staff = [];
        state.loaded = false;
        return;
      }
      if (!refs.summaryView.hidden) void loadSummary();
    });
    window.addEventListener("ehwa:settlement-view", (event) => {
      if (event.detail?.view === "summary" && state.session && !state.loaded) {
        void loadSummary();
      }
    });
    window.addEventListener("ehwa:settlement-branch", (event) => {
      if (event.detail?.source !== "entry") return;
      const nextBranch = event.detail?.branch === "uptown" ? "uptown" : "downtown";
      if (nextBranch === state.branch) return;
      setBranch(nextBranch);
      state.selectedPeriod = "all";
      state.loaded = false;
      if (state.session && !refs.summaryView.hidden) void loadSummary();
    });
    window.addEventListener("ehwa:settlement-saved", () => {
      state.loaded = false;
      if (state.session && !refs.summaryView.hidden) void loadSummary();
    });
  }

  function bootstrap() {
    cacheRefs();
    const params = new URLSearchParams(window.location.search);
    setBranch(window.EhwaSettlementApp?.getBranch() || params.get("branch") || "downtown");
    bindEvents();
    state.session = window.EhwaSettlementApp?.getSession() || null;
    if (state.session && window.EhwaSettlementApp?.getView() === "summary") {
      void loadSummary();
    }
  }

  void bootstrap();
})();
