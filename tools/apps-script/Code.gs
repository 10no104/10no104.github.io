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
  const sheet = getSheet_(params.sheetName);
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

function getText_(value) {
  return value == null ? "" : String(value).trim();
}

function respond_(payload) {
  return ContentService
    .createTextOutput(JSON.stringify(payload))
    .setMimeType(ContentService.MimeType.JSON);
}
