const SPREADSHEET_ID = '1rjed3e9dTv9ZddDnrqHv_wYLHJegKPHeXnDpLOiGMrM';
const SHEET_NAME = 'CONSULTAS';

function doPost(e) {
  try {
    const payload = JSON.parse((e && e.postData && e.postData.contents) || '{}');
    const code = String(payload.codigo_acceso || '').trim();
    if (!code) return json({ ok: false, error: 'missing_access_code' });

    const sheet = SpreadsheetApp.openById(SPREADSHEET_ID).getSheetByName(SHEET_NAME);
    sheet.appendRow([
      payload.consulta_id || `consulta-${Date.now()}`,
      payload.fecha || new Date().toISOString(),
      payload.tirada_id || 'tres-umbrales',
      payload.cartas || '',
      payload.orientaciones || '',
      payload.respuesta_mostrada || '',
      '',
      'nueva',
      payload.fuente || 'EVIGILA · página pública'
    ]);
    return json({ ok: true });
  } catch (error) {
    return json({ ok: false, error: String(error) });
  }
}

function json(value) {
  return ContentService
    .createTextOutput(JSON.stringify(value))
    .setMimeType(ContentService.MimeType.JSON);
}
