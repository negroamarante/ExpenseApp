public with sharing class BudgetEmailHandler implements Messaging.InboundEmailHandler {
  private static final String PROMPT_PREFIX =
    'Analiza el siguiente texto de un email con una factura o resumen de cuenta y devolvé SOLO un JSON (sin texto adicional, sin markdown) con estos campos: ' +
    '{"totalAmount": monto total a pagar como número sin símbolo de moneda ni separadores de miles, ' +
    '"invoiceDate": fecha del comprobante en formato YYYY-MM-DD si figura, o null}. ' +
    'Texto del email:\n\n';

  public Messaging.InboundEmailResult handleInboundEmail(
    Messaging.InboundEmail email,
    Messaging.InboundEnvelope envelope
  ) {
    Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();
    result.success = true;
    String bodyText;

    try {
      bodyText = extractBodyText(email);
      if (String.isBlank(bodyText)) {
        return result;
      }

      String responseText = GeminiClient.generateJson(
        PROMPT_PREFIX + bodyText,
        null,
        null
      );
      Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(
        responseText
      );

      Object amountValue = data.get('totalAmount');
      if (amountValue == null) {
        throw new BudgetEmailException(
          'No se pudo determinar el monto de la factura recibida por mail.'
        );
      }
      Decimal amount = Decimal.valueOf(String.valueOf(amountValue));

      Date monthStart = Date.today().toStartOfMonth();
      Date invoiceDate = parseDate((String) data.get('invoiceDate'));
      if (invoiceDate != null) {
        monthStart = invoiceDate.toStartOfMonth();
      }

      saveBudgetWithSource(monthStart, amount, bodyText);
    } catch (Exception e) {
      notifyFailure(email, bodyText, e);
      System.debug(
        LoggingLevel.ERROR,
        'BudgetEmailHandler failed: ' + e.getMessage()
      );
    }

    return result;
  }

  private void notifyFailure(
    Messaging.InboundEmail email,
    String bodyText,
    Exception e
  ) {
    String subjectLine = String.isNotBlank(email.subject)
      ? email.subject
      : '(sin asunto)';
    String message =
      'No se pudo actualizar el presupuesto a partir del mail "' +
      subjectLine +
      '".\n\nError: ' +
      e.getMessage();
    if (bodyText != null) {
      message += '\n\nTexto del mail:\n' + bodyText.abbreviate(1000);
    }
    ErrorNotifier.notify(
      'Error al procesar la factura del presupuesto por mail',
      message
    );
  }

  private class BudgetEmailException extends Exception {
  }

  private void saveBudgetWithSource(
    Date monthStart,
    Decimal amount,
    String bodyText
  ) {
    List<Monthly_Budget__c> existing = [
      SELECT Id
      FROM Monthly_Budget__c
      WHERE Month_Start__c = :monthStart
      LIMIT 1
    ];
    Monthly_Budget__c budget = existing.isEmpty()
      ? new Monthly_Budget__c(Month_Start__c = monthStart)
      : existing[0];
    budget.Budget_Amount__c = amount;
    budget.Source_Email_Body__c = bodyText.abbreviate(4000);
    budget.Source_Email_Processed_Date__c = Datetime.now();
    upsert budget;
  }

  private String extractBodyText(Messaging.InboundEmail email) {
    if (String.isNotBlank(email.plainTextBody)) {
      return email.plainTextBody;
    }
    if (String.isNotBlank(email.htmlBody)) {
      return email.htmlBody.replaceAll('<[^>]+>', ' ');
    }
    return null;
  }

  private Date parseDate(String iso) {
    if (String.isBlank(iso)) {
      return null;
    }
    try {
      List<String> parts = iso.split('-');
      return Date.newInstance(
        Integer.valueOf(parts[0]),
        Integer.valueOf(parts[1]),
        Integer.valueOf(parts[2])
      );
    } catch (Exception e) {
      return null;
    }
  }
}
