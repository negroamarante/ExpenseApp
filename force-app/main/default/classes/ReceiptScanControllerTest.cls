@IsTest
private class ReceiptScanControllerTest {
  private class GeminiHttpMock implements HttpCalloutMock {
    Integer statusCode;
    String body;
    GeminiHttpMock(Integer statusCode, String body) {
      this.statusCode = statusCode;
      this.body = body;
    }
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(statusCode);
      res.setHeader('Content-Type', 'application/json');
      res.setBody(body);
      return res;
    }
  }

  private static String wrapGeminiText(String innerJson) {
    return JSON.serialize(
      new Map<String, Object>{
        'candidates' => new List<Object>{
          new Map<String, Object>{
            'content' => new Map<String, Object>{
              'parts' => new List<Object>{
                new Map<String, Object>{ 'text' => innerJson }
              }
            }
          }
        }
      }
    );
  }

  @TestSetup
  static void setup() {
    Api_Key_Store__c settings = Api_Key_Store__c.getOrgDefaults();
    settings.Gemini_Api_Key__c = 'test-key';
    upsert settings;
  }

  @IsTest
  static void testScanReceiptReturnsParsedFields() {
    Test.setMock(
      HttpCalloutMock.class,
      new GeminiHttpMock(
        200,
        wrapGeminiText(
          '{"description":"Supermercado","purchaseDate":"2026-09-01","totalAmount":1234.5,"category":"Supermercado","person":"Diego"}'
        )
      )
    );

    Test.startTest();
    ReceiptScanController.ReceiptScanResult result = ReceiptScanController.scanReceipt(
      'base64image',
      'image/jpeg',
      new List<String>{ 'Supermercado', 'Otros' },
      new List<String>{ 'Diego', 'Emi' }
    );
    Test.stopTest();

    System.assertEquals('Supermercado', result.description);
    System.assertEquals('2026-09-01', result.purchaseDate);
    System.assertEquals(1234.5, result.totalAmount);
    System.assertEquals('Supermercado', result.category);
    System.assertEquals('Diego', result.person);
    System.assertEquals(0, ErrorNotifier.notificationCount);
  }

  @IsTest
  static void testScanReceiptThrowsOnCalloutFailure() {
    Test.setMock(
      HttpCalloutMock.class,
      new GeminiHttpMock(500, '{"error":"boom"}')
    );

    Test.startTest();
    String message;
    try {
      ReceiptScanController.scanReceipt(
        'base64image',
        'image/jpeg',
        new List<String>(),
        new List<String>()
      );
    } catch (AuraHandledException e) {
      message = e.getMessage();
    }
    Test.stopTest();

    System.assert(
      message != null && message.contains('No se pudo leer el ticket')
    );
    System.assertEquals(1, ErrorNotifier.notificationCount);
  }

  @IsTest
  static void testScanReceiptThrowsWhenRequiredFieldsAreMissing() {
    Test.setMock(
      HttpCalloutMock.class,
      new GeminiHttpMock(
        200,
        wrapGeminiText(
          '{"description":null,"purchaseDate":"2026-09-01","totalAmount":null,"category":null,"person":"Diego"}'
        )
      )
    );

    Test.startTest();
    String message;
    try {
      ReceiptScanController.scanReceipt(
        'base64image',
        'image/jpeg',
        new List<String>(),
        new List<String>()
      );
    } catch (AuraHandledException e) {
      message = e.getMessage();
    }
    Test.stopTest();

    System.assert(message != null);
    System.assert(message.contains('descripción'));
    System.assert(message.contains('monto'));
    System.assert(!message.contains('persona'));
    System.assertEquals(1, ErrorNotifier.notificationCount);
  }

  @IsTest
  static void testScanReceiptDefaultsPersonWhenBlank() {
    Test.setMock(
      HttpCalloutMock.class,
      new GeminiHttpMock(
        200,
        wrapGeminiText(
          '{"description":"Restaurante","purchaseDate":"2026-09-11","totalAmount":63000,"category":"Entretenimiento","person":null}'
        )
      )
    );

    Test.startTest();
    ReceiptScanController.ReceiptScanResult result = ReceiptScanController.scanReceipt(
      'base64image',
      'image/jpeg',
      new List<String>{ 'Entretenimiento' },
      new List<String>{ 'Diego', 'Emi' }
    );
    Test.stopTest();

    System.assertEquals('Emi', result.person);
    System.assertEquals(0, ErrorNotifier.notificationCount);
  }

  @IsTest
  static void testScanReceiptAllowsMissingCategory() {
    Test.setMock(
      HttpCalloutMock.class,
      new GeminiHttpMock(
        200,
        wrapGeminiText(
          '{"description":"Supermercado","purchaseDate":"2026-09-01","totalAmount":500,"category":null,"person":"Diego"}'
        )
      )
    );

    Test.startTest();
    ReceiptScanController.ReceiptScanResult result = ReceiptScanController.scanReceipt(
      'base64image',
      'image/jpeg',
      new List<String>(),
      new List<String>()
    );
    Test.stopTest();

    System.assertEquals(null, result.category);
    System.assertEquals(500, result.totalAmount);
  }

  @IsTest
  static void testAttachReceiptLinksFileToExpense() {
    Expense__c expense = new Expense__c(
      Description__c = 'Consumo de prueba',
      Purchase_Date__c = Date.newInstance(2026, 9, 1),
      Total_Amount__c = 1000,
      Number_Of_Installments__c = '1',
      Person__c = 'Diego'
    );
    insert expense;

    Test.startTest();
    ReceiptScanController.attachReceipt(
      expense.Id,
      EncodingUtil.base64Encode(Blob.valueOf('fake image bytes')),
      'ticket.jpg',
      'image/jpeg'
    );
    Test.stopTest();

    List<ContentDocumentLink> links = [
      SELECT Id
      FROM ContentDocumentLink
      WHERE LinkedEntityId = :expense.Id
    ];
    System.assertEquals(1, links.size());
  }
}
