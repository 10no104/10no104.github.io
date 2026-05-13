const SPREADSHEET_ID = "1xa9OZbctYnlbaAL8lKIgmefM5hvSw0Plk01lxp5G2fc";

const COLUMN = {
  timestamp: 1,
  date: 2,
  time: 3,
  people: 4,
  name: 5,
  phone: 6,
  notes: 7,
  status: 8,
  alertStatus: 9,
  alertType: 10,
  tableAssignment: 11
};

function doPost(e) {
  try {
    const params = normalizeParams_(e);
    const action = (params.action || "").trim().toLowerCase();

    switch (action) {
      case "create":
        return respond_(handleCreate_(params));
      case "update":
        return respond_(handleUpdate_(params));
      case "status":
        return respond_(handleStatusUpdate_(params));
      case "alertstatus":
        return respond_(handleAlertUpdate_(params));
      default:
        throw new Error("Unsupported action: " + action);
    }
  } catch (error) {
    return respond_({
      ok: false,
      error: error && error.message ? error.message : String(error)
    });
  }
}

function handleCreate_(params) {
  const lock = LockService.getScriptLock();
  lock.waitLock(5000);

  try {
    return createReservation_(params);
  } finally {
    lock.releaseLock();
  }
}

function createReservation_(params) {
  const sheet = getSheet_(params.sheetName);
  const duplicate = findDuplicateReservation_(sheet, params);
  if (duplicate) {
    const duplicateResult = resolveDuplicateReservation_(sheet, duplicate, params);
    return {
      ok: true,
      duplicate: true,
      skipped: duplicateResult.skipped,
      updated: duplicateResult.updated,
      action: "create",
      sheetName: sheet.getName(),
      rowNumber: duplicate.rowNumber
    };
  }

  const row = [];
  row[COLUMN.timestamp - 1] = new Date();
  row[COLUMN.date - 1] = getText_(params.date);
  row[COLUMN.time - 1] = getText_(params.time);
  row[COLUMN.people - 1] = getText_(params.people);
  row[COLUMN.name - 1] = getText_(params.name);
  row[COLUMN.phone - 1] = getText_(params.phone);
  row[COLUMN.notes - 1] = getText_(params.notes);
  row[COLUMN.status - 1] = getText_(params.status || "active");
  row[COLUMN.alertStatus - 1] = getText_(params.alertStatus || "confirmed");
  row[COLUMN.alertType - 1] = getText_(params.alertType);
  row[COLUMN.tableAssignment - 1] = getText_(params.tableAssignment);
  sheet.appendRow(row);

  return {
    ok: true,
    action: "create",
    sheetName: sheet.getName(),
    rowNumber: sheet.getLastRow()
  };
}

function resolveDuplicateReservation_(sheet, duplicate, params) {
  const values = ensureWidth_(duplicate.values, COLUMN.tableAssignment);
  const existingNotes = getText_(values[COLUMN.notes - 1]);
  const incomingNotes = getText_(params.notes);
  const nextNotes = chooseBestNotes_(existingNotes, incomingNotes);

  if (nextNotes !== existingNotes) {
    values[COLUMN.notes - 1] = nextNotes;
    writeRowValues_(sheet, duplicate.rowNumber, values);
    return {
      skipped: false,
      updated: true
    };
  }

  return {
    skipped: true,
    updated: false
  };
}

function findDuplicateReservation_(sheet, params) {
  const lastRow = sheet.getLastRow();
  if (lastRow < 2) return null;

  const incomingKey = getDuplicateKey_({
    date: params.date,
    time: params.time,
    people: params.people,
    name: params.name,
    phone: params.phone
  });

  const rows = sheet.getRange(2, 1, lastRow - 1, COLUMN.tableAssignment).getValues();
  for (var index = 0; index < rows.length; index += 1) {
    const row = ensureWidth_(rows[index], COLUMN.tableAssignment);
    const status = getText_(row[COLUMN.status - 1]).toLowerCase();
    if (status === "removed" || status === "canceled" || status === "cancelled") continue;

    const rowKey = getDuplicateKey_({
      date: row[COLUMN.date - 1],
      time: row[COLUMN.time - 1],
      people: row[COLUMN.people - 1],
      name: row[COLUMN.name - 1],
      phone: row[COLUMN.phone - 1]
    });

    if (rowKey === incomingKey) {
      return {
        rowNumber: index + 2,
        values: row
      };
    }
  }

  return null;
}

function handleUpdate_(params) {
  const sheet = getSheet_(params.sheetName);
  const rowNumber = getRowNumber_(params.rowNumber);
  const values = getRowValues_(sheet, rowNumber);

  if ("date" in params) values[COLUMN.date - 1] = getText_(params.date);
  if ("time" in params) values[COLUMN.time - 1] = getText_(params.time);
  if ("people" in params) values[COLUMN.people - 1] = getText_(params.people);
  if ("name" in params) values[COLUMN.name - 1] = getText_(params.name);
  if ("phone" in params) values[COLUMN.phone - 1] = getText_(params.phone);
  if ("notes" in params) values[COLUMN.notes - 1] = getText_(params.notes);

  if ("status" in params) values[COLUMN.status - 1] = getText_(params.status);
  if ("alertStatus" in params) values[COLUMN.alertStatus - 1] = getText_(params.alertStatus);
  if ("alertType" in params) values[COLUMN.alertType - 1] = getText_(params.alertType);
  if ("tableAssignment" in params) values[COLUMN.tableAssignment - 1] = getText_(params.tableAssignment);

  writeRowValues_(sheet, rowNumber, values);

  return {
    ok: true,
    action: "update",
    sheetName: sheet.getName(),
    rowNumber: rowNumber
  };
}

function handleStatusUpdate_(params) {
  const sheet = getSheet_(params.sheetName);
  const rowNumber = getRowNumber_(params.rowNumber);
  const values = getRowValues_(sheet, rowNumber);

  values[COLUMN.status - 1] = getText_(params.status || values[COLUMN.status - 1]);
  if ("alertStatus" in params) values[COLUMN.alertStatus - 1] = getText_(params.alertStatus);
  if ("alertType" in params) values[COLUMN.alertType - 1] = getText_(params.alertType);

  writeRowValues_(sheet, rowNumber, values);

  return {
    ok: true,
    action: "status",
    sheetName: sheet.getName(),
    rowNumber: rowNumber
  };
}

function handleAlertUpdate_(params) {
  const sheet = getSheet_(params.sheetName);
  const rowNumber = getRowNumber_(params.rowNumber);
  const values = getRowValues_(sheet, rowNumber);

  if ("status" in params) values[COLUMN.status - 1] = getText_(params.status);
  values[COLUMN.alertStatus - 1] = getText_(params.alertStatus || "confirmed");
  values[COLUMN.alertType - 1] = getText_(params.alertType);

  writeRowValues_(sheet, rowNumber, values);

  return {
    ok: true,
    action: "alertStatus",
    sheetName: sheet.getName(),
    rowNumber: rowNumber
  };
}

function normalizeParams_(e) {
  const source = (e && e.parameter) || {};
  const params = {};
  Object.keys(source).forEach(function(key) {
    params[key] = getText_(source[key]);
  });
  return params;
}

function getSheet_(sheetName) {
  const name = getText_(sheetName);
  if (!name) throw new Error("Missing sheetName");
  const spreadsheet = SpreadsheetApp.openById(SPREADSHEET_ID);
  const sheet = spreadsheet.getSheetByName(name);
  if (!sheet) throw new Error("Sheet not found: " + name);
  return sheet;
}

function getRowNumber_(value) {
  const rowNumber = Number(value);
  if (!Number.isFinite(rowNumber) || rowNumber < 2) {
    throw new Error("Invalid rowNumber: " + value);
  }
  return rowNumber;
}

function getRowValues_(sheet, rowNumber) {
  const values = sheet.getRange(rowNumber, 1, 1, COLUMN.tableAssignment).getValues()[0];
  return ensureWidth_(values, COLUMN.tableAssignment);
}

function writeRowValues_(sheet, rowNumber, values) {
  const row = ensureWidth_(values, COLUMN.tableAssignment);
  sheet.getRange(rowNumber, 1, 1, COLUMN.tableAssignment).setValues([row]);
}

function ensureWidth_(values, width) {
  const row = Array.isArray(values) ? values.slice(0, width) : [];
  while (row.length < width) row.push("");
  return row;
}

function getDuplicateKey_(reservation) {
  return [
    normalizeTextKey_(reservation.date),
    normalizeTextKey_(reservation.time),
    normalizeGuestKey_(reservation.people),
    normalizeTextKey_(reservation.name),
    normalizePhoneKey_(reservation.phone)
  ].join("::");
}

function chooseBestNotes_(existingNotes, incomingNotes) {
  const existing = getText_(existingNotes);
  const incoming = getText_(incomingNotes);
  const existingKey = normalizeTextKey_(existing);
  const incomingKey = normalizeTextKey_(incoming);

  if (!incomingKey || incomingKey === "-") return existing;
  if (!existingKey || existingKey === "-") return incoming;
  if (existingKey === incomingKey) return existing;
  if (existingKey.indexOf(incomingKey) !== -1) return existing;
  if (incomingKey.indexOf(existingKey) !== -1) return incoming;

  return existing.length >= incoming.length
    ? existing + " / " + incoming
    : incoming + " / " + existing;
}

function normalizeTextKey_(value) {
  return getText_(value).toLowerCase().replace(/\s+/g, " ");
}

function normalizeGuestKey_(value) {
  const digits = getText_(value).replace(/\D/g, "");
  return digits || normalizeTextKey_(value);
}

function normalizePhoneKey_(value) {
  let digits = getText_(value).replace(/\D/g, "");
  if (digits.charAt(0) === "1" && digits.length === 11) digits = digits.slice(1);
  return digits;
}

function getText_(value) {
  return value == null ? "" : String(value).trim();
}

function respond_(payload) {
  return ContentService
    .createTextOutput(JSON.stringify(payload))
    .setMimeType(ContentService.MimeType.JSON);
}
