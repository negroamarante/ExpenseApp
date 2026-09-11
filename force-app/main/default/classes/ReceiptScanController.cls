public with sharing class ReceiptScanController {
  private static final String DEFAULT_PERSON = 'Emi';

  public class ReceiptScanResult {
    @AuraEnabled
    public String description;
    @AuraEnabled
    public String purchaseDate;
    @AuraEnabled
    public Decimal totalAmount;
    @AuraEnabled
    public String category;
    @AuraEnabled
    public String person;
  }

  @AuraEnabled
  public static ReceiptScanResult scanReceipt(
    String base64Image,
    String mimeType,
    List<String> categoryOptions,
    List<String> personOptions
  ) {
    try {
      String prompt = buildPrompt(categoryOptions, personOptions);
      String responseText;
      try {
        responseText = GeminiClient.generateJson(prompt, base64Image, mimeType);
      } catch (Exception e) {
        throw buildError('No se pudo leer el ticket: ' + e.getMessage());
      }
      ReceiptScanResult result = parseResponse(responseText);
      validateRequiredFields(result);
      return result;
    } catch (AuraHandledException e) {
      ErrorNotifier.notify('Error al escanear ticket', e.getMessage());
      throw e;
    }
  }

  @AuraEnabled
  public static void attachReceipt(
    Id expenseId,
    String base64Data,
    String fileName,
    String mimeType
  ) {
    ContentVersion cv = new ContentVersion(
      Title = fileName,
      PathOnClient = fileName,
      VersionData = EncodingUtil.base64Decode(base64Data)
    );
    insert cv;

    Id contentDocumentId = [
      SELECT ContentDocumentId
      FROM ContentVersion
      WHERE Id = :cv.Id
      LIMIT 1
    ]
    .ContentDocumentId;

    insert new ContentDocumentLink(
      ContentDocumentId = contentDocumentId,
      LinkedEntityId = expenseId,
      ShareType = 'V',
      Visibility = 'AllUsers'
    );
  }

  private static String buildPrompt(
    List<String> categoryOptions,
    List<String> personOptions
  ) {
    return 'Analiza esta foto de un ticket o factura de compra y devolvé SOLO un JSON (sin texto adicional, sin markdown) con estos campos: ' +
      '{"description": string breve describiendo el comercio o la compra, ' +
      '"purchaseDate": fecha en formato YYYY-MM-DD, ' +
      '"totalAmount": monto total como número sin símbolo de moneda ni separadores de miles, ' +
      '"category": una de estas opciones exactas o null si ninguna aplica bien [' +
      String.join(categoryOptions, ', ') +
      '], ' +
      '"person": una de estas opciones exactas o null si no está claro [' +
      String.join(personOptions, ', ') +
      ']}. ' +
      'Si no podés determinar un campo con confianza, usá null en ese campo.';
  }

  private static void validateRequiredFields(ReceiptScanResult result) {
    List<String> missing = new List<String>();
    if (String.isBlank(result.description)) {
      missing.add('descripción');
    }
    if (String.isBlank(result.purchaseDate)) {
      missing.add('fecha');
    }
    if (result.totalAmount == null) {
      missing.add('monto');
    }
    if (!missing.isEmpty()) {
      throw buildError(
        'No se pudo leer del ticket: ' +
          String.join(missing, ', ') +
          '. Completá esos campos a mano.'
      );
    }
  }

  private static AuraHandledException buildError(String message) {
    AuraHandledException ex = new AuraHandledException(message);
    ex.setMessage(message);
    return ex;
  }

  private static ReceiptScanResult parseResponse(String responseText) {
    Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(
      responseText
    );

    ReceiptScanResult result = new ReceiptScanResult();
    result.description = (String) data.get('description');
    result.purchaseDate = (String) data.get('purchaseDate');
    Object amount = data.get('totalAmount');
    result.totalAmount = amount != null
      ? Decimal.valueOf(String.valueOf(amount))
      : null;
    result.category = (String) data.get('category');
    result.person = (String) data.get('person');
    if (String.isBlank(result.person)) {
      result.person = DEFAULT_PERSON;
    }
    return result;
  }
}
