@IsTest
private class BudgetEmailHandlerTest {
  private class GeminiHttpMock implements HttpCalloutMock {
    Integer statusCode;
    String body;
    GeminiHttpMock(String body) {
      this(200, body);
    }
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
  static void testCreatesNewBudgetFromEmail() {
    Test.setMock(
      HttpCalloutMock.class,
      new GeminiHttpMock(
        wrapGeminiText('{"totalAmount": 1500.50, "invoiceDate": "2026-09-05"}')
      )
    );

    Messaging.InboundEmail email = new Messaging.InboundEmail();
    email.plainTextBody = 'Factura de prueba, total 1.500,50';
    Messaging.InboundEnvelope envelope = new Messaging.InboundEnvelope();

    Test.startTest();
    Messaging.InboundEmailResult result = new BudgetEmailHandler()
      .handleInboundEmail(email, envelope);
    Test.stopTest();

    System.assertEquals(true, result.success);
    Monthly_Budget__c budget = [
      SELECT
        Budget_Amount__c,
        Source_Email_Body__c,
        Source_Email_Processed_Date__c
      FROM Monthly_Budget__c
      WHERE Month_Start__c = :Date.newInstance(2026, 9, 1)
    ];
    System.assertEquals(1500.50, budget.Budget_Amount__c);
    System.assertNotEquals(null, budget.Source_Email_Processed_Date__c);
    System.assertEquals(
      'Factura de prueba, total 1.500,50',
      budget.Source_Email_Body__c
    );
    System.assertEquals(0, ErrorNotifier.notificationCount);
  }

  @IsTest
  static void testUpdatesExistingBudgetForMonth() {
    insert new Monthly_Budget__c(
      Month_Start__c = Date.newInstance(2026, 9, 1),
      Budget_Amount__c = 100
    );

    Test.setMock(
      HttpCalloutMock.class,
      new GeminiHttpMock(
        wrapGeminiText('{"totalAmount": 999, "invoiceDate": "2026-09-10"}')
      )
    );

    Messaging.InboundEmail email = new Messaging.InboundEmail();
    email.plainTextBody = 'Nueva factura';
    Messaging.InboundEnvelope envelope = new Messaging.InboundEnvelope();

    Test.startTest();
    new BudgetEmailHandler().handleInboundEmail(email, envelope);
    Test.stopTest();

    List<Monthly_Budget__c> budgets = [
      SELECT Budget_Amount__c
      FROM Monthly_Budget__c
      WHERE Month_Start__c = :Date.newInstance(2026, 9, 1)
    ];
    System.assertEquals(1, budgets.size());
    System.assertEquals(999, budgets[0].Budget_Amount__c);
  }

  @IsTest
  static void testFallsBackToCurrentMonthWhenNoInvoiceDate() {
    Test.setMock(
      HttpCalloutMock.class,
      new GeminiHttpMock(wrapGeminiText('{"totalAmount": 200}'))
    );

    Messaging.InboundEmail email = new Messaging.InboundEmail();
    email.plainTextBody = 'Factura sin fecha';
    Messaging.InboundEnvelope envelope = new Messaging.InboundEnvelope();

    Test.startTest();
    new BudgetEmailHandler().handleInboundEmail(email, envelope);
    Test.stopTest();

    Date currentMonthStart = Date.today().toStartOfMonth();
    List<Monthly_Budget__c> budgets = [
      SELECT Id
      FROM Monthly_Budget__c
      WHERE Month_Start__c = :currentMonthStart
    ];
    System.assertEquals(1, budgets.size());
  }

  @IsTest
  static void testNoAmountDoesNotCreateBudget() {
    Test.setMock(
      HttpCalloutMock.class,
      new GeminiHttpMock(wrapGeminiText('{"totalAmount": null}'))
    );

    Messaging.InboundEmail email = new Messaging.InboundEmail();
    email.plainTextBody = 'Mail sin monto';
    Messaging.InboundEnvelope envelope = new Messaging.InboundEnvelope();

    Test.startTest();
    Messaging.InboundEmailResult result = new BudgetEmailHandler()
      .handleInboundEmail(email, envelope);
    Test.stopTest();

    System.assertEquals(true, result.success);
    System.assertEquals(0, [SELECT COUNT() FROM Monthly_Budget__c]);
    System.assertEquals(1, ErrorNotifier.notificationCount);
  }

  @IsTest
  static void testGeminiCalloutFailureNotifiesError() {
    Test.setMock(
      HttpCalloutMock.class,
      new GeminiHttpMock(500, '{"error":"boom"}')
    );

    Messaging.InboundEmail email = new Messaging.InboundEmail();
    email.subject = 'Factura de prueba';
    email.plainTextBody = 'contenido de la factura';
    Messaging.InboundEnvelope envelope = new Messaging.InboundEnvelope();

    Test.startTest();
    Messaging.InboundEmailResult result = new BudgetEmailHandler()
      .handleInboundEmail(email, envelope);
    Test.stopTest();

    System.assertEquals(true, result.success);
    System.assertEquals(0, [SELECT COUNT() FROM Monthly_Budget__c]);
    System.assertEquals(1, ErrorNotifier.notificationCount);
  }

  @IsTest
  static void testBlankBodyDoesNothing() {
    Messaging.InboundEmail email = new Messaging.InboundEmail();
    Messaging.InboundEnvelope envelope = new Messaging.InboundEnvelope();

    Test.startTest();
    Messaging.InboundEmailResult result = new BudgetEmailHandler()
      .handleInboundEmail(email, envelope);
    Test.stopTest();

    System.assertEquals(true, result.success);
    System.assertEquals(0, [SELECT COUNT() FROM Monthly_Budget__c]);
  }

  @IsTest
  static void testUsesHtmlBodyWhenNoPlainText() {
    Test.setMock(
      HttpCalloutMock.class,
      new GeminiHttpMock(wrapGeminiText('{"totalAmount": 50}'))
    );

    Messaging.InboundEmail email = new Messaging.InboundEmail();
    email.htmlBody = '<p>Factura <b>HTML</b></p>';
    Messaging.InboundEnvelope envelope = new Messaging.InboundEnvelope();

    Test.startTest();
    new BudgetEmailHandler().handleInboundEmail(email, envelope);
    Test.stopTest();

    Date currentMonthStart = Date.today().toStartOfMonth();
    Monthly_Budget__c budget = [
      SELECT Source_Email_Body__c
      FROM Monthly_Budget__c
      WHERE Month_Start__c = :currentMonthStart
    ];
    System.assert(!budget.Source_Email_Body__c.contains('<p>'));
  }
}
