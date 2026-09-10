@IsTest
private class GeminiClientTest {
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
  static void testGenerateJsonReturnsInnerText() {
    Test.setMock(
      HttpCalloutMock.class,
      new GeminiHttpMock(200, wrapGeminiText('{"foo":"bar"}'))
    );

    Test.startTest();
    String result = GeminiClient.generateJson('a prompt', null, null);
    Test.stopTest();

    System.assertEquals('{"foo":"bar"}', result);
  }

  @IsTest
  static void testGenerateJsonWithInlineImageData() {
    Test.setMock(
      HttpCalloutMock.class,
      new GeminiHttpMock(200, wrapGeminiText('{"ok":true}'))
    );

    Test.startTest();
    String result = GeminiClient.generateJson(
      'a prompt',
      'base64data',
      'image/jpeg'
    );
    Test.stopTest();

    System.assertEquals('{"ok":true}', result);
  }

  @IsTest
  static void testGenerateJsonThrowsOnNon200() {
    Test.setMock(
      HttpCalloutMock.class,
      new GeminiHttpMock(500, '{"error":"boom"}')
    );

    Test.startTest();
    Boolean threw = false;
    try {
      GeminiClient.generateJson('a prompt', null, null);
    } catch (CalloutException e) {
      threw = true;
    }
    Test.stopTest();

    System.assertEquals(true, threw);
  }

  @IsTest
  static void testGenerateJsonThrowsWhenNoCandidates() {
    Test.setMock(
      HttpCalloutMock.class,
      new GeminiHttpMock(200, '{"candidates":[]}')
    );

    Test.startTest();
    Boolean threw = false;
    try {
      GeminiClient.generateJson('a prompt', null, null);
    } catch (CalloutException e) {
      threw = true;
    }
    Test.stopTest();

    System.assertEquals(true, threw);
  }
}
