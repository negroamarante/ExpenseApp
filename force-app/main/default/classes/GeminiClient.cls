public with sharing class GeminiClient {
  private static final String MODEL_ID = 'gemini-3.6-flash';

  public static String generateJson(
    String prompt,
    String base64Data,
    String mimeType
  ) {
    List<Object> parts = new List<Object>{
      new Map<String, Object>{ 'text' => prompt }
    };
    if (base64Data != null) {
      parts.add(
        new Map<String, Object>{
          'inline_data' => new Map<String, Object>{
            'mime_type' => mimeType,
            'data' => base64Data
          }
        }
      );
    }

    Map<String, Object> requestBody = new Map<String, Object>{
      'contents' => new List<Object>{
        new Map<String, Object>{ 'parts' => parts }
      },
      'generationConfig' => new Map<String, Object>{
        'response_mime_type' => 'application/json'
      }
    };

    HttpRequest req = new HttpRequest();
    req.setEndpoint(
      'callout:Gemini_API/v1beta/models/' + MODEL_ID + ':generateContent'
    );
    req.setMethod('POST');
    req.setHeader('Content-Type', 'application/json');
    req.setHeader(
      'x-goog-api-key',
      Api_Key_Store__c.getOrgDefaults().Gemini_Api_Key__c
    );
    req.setBody(JSON.serialize(requestBody));
    req.setTimeout(60000);

    HttpResponse res = new Http().send(req);
    if (res.getStatusCode() != 200) {
      throw new CalloutException(
        'Gemini call failed (' + res.getStatus() + '): ' + res.getBody()
      );
    }

    Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(
      res.getBody()
    );
    List<Object> candidates = (List<Object>) parsed.get('candidates');
    if (candidates == null || candidates.isEmpty()) {
      throw new CalloutException('Gemini returned no candidates.');
    }
    Map<String, Object> content = (Map<String, Object>) ((Map<String, Object>) candidates[0])
      .get('content');
    List<Object> responseParts = (List<Object>) content.get('parts');
    return (String) ((Map<String, Object>) responseParts[0]).get('text');
  }
}
