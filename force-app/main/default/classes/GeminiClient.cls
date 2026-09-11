public with sharing class GeminiClient {
  private static final String PRIMARY_MODEL = 'gemini-3.6-flash';
  private static final String FALLBACK_MODEL = 'gemini-3.6-flash-lite';

  private static final Integer MAX_ATTEMPTS_PRIMARY = 2;
  private static final Integer MAX_ATTEMPTS_FALLBACK = 2;

  private static final Set<Integer> RETRYABLE_STATUS_CODES = new Set<Integer>{
    429,
    503
  };

  public static String generateJson(
    String prompt,
    String base64Data,
    String mimeType
  ) {
    try {
      return callModel(
        PRIMARY_MODEL,
        prompt,
        base64Data,
        mimeType,
        MAX_ATTEMPTS_PRIMARY
      );
    } catch (CalloutException primaryException) {
      try {
        return callModel(
          FALLBACK_MODEL,
          prompt,
          base64Data,
          mimeType,
          MAX_ATTEMPTS_FALLBACK
        );
      } catch (CalloutException fallbackException) {
        throw new CalloutException(
          'Gemini primary model failed: ' +
            primaryException.getMessage() +
            ' | Fallback model failed: ' +
            fallbackException.getMessage()
        );
      }
    }
  }

  private static String callModel(
    String modelId,
    String prompt,
    String base64Data,
    String mimeType,
    Integer maxAttempts
  ) {
    for (Integer attempt = 1; attempt <= maxAttempts; attempt++) {
      HttpRequest req = buildRequest(modelId, prompt, base64Data, mimeType);

      HttpResponse res;

      try {
        res = new Http().send(req);
      } catch (Exception e) {
        throw new CalloutException(
          'HTTP callout failed for model ' + modelId + ': ' + e.getMessage()
        );
      }

      Integer statusCode = res.getStatusCode();

      if (statusCode == 200) {
        return extractText(res.getBody());
      }

      Boolean isRetryable = RETRYABLE_STATUS_CODES.contains(statusCode);

      Boolean hasAttemptsLeft = attempt < maxAttempts;

      if (isRetryable && hasAttemptsLeft) {
        continue;
      }

      throw new CalloutException(
        'Gemini model ' +
          modelId +
          ' failed (' +
          res.getStatus() +
          '): ' +
          res.getBody()
      );
    }

    throw new CalloutException(
      'Gemini model ' + modelId + ' failed after ' + maxAttempts + ' attempts.'
    );
  }

  private static HttpRequest buildRequest(
    String modelId,
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
      'callout:Gemini_API/v1beta/models/' + modelId + ':generateContent'
    );

    req.setMethod('POST');
    req.setHeader('Content-Type', 'application/json');

    req.setHeader(
      'x-goog-api-key',
      Api_Key_Store__c.getOrgDefaults().Gemini_Api_Key__c
    );

    req.setBody(JSON.serialize(requestBody));
    req.setTimeout(60000);

    return req;
  }

  private static String extractText(String responseBody) {
    System.debug('responseBody: ' + JSON.serializePretty(responseBody));
    Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(
      responseBody
    );

    List<Object> candidates = (List<Object>) parsed.get('candidates');

    if (candidates == null || candidates.isEmpty()) {
      throw new CalloutException(
        'Gemini returned no candidates. Response: ' + responseBody
      );
    }

    Map<String, Object> firstCandidate = (Map<String, Object>) candidates[0];

    Map<String, Object> content = (Map<String, Object>) firstCandidate.get(
      'content'
    );

    if (content == null) {
      throw new CalloutException(
        'Gemini response contains no content. Response: ' + responseBody
      );
    }

    List<Object> responseParts = (List<Object>) content.get('parts');

    if (responseParts == null || responseParts.isEmpty()) {
      throw new CalloutException(
        'Gemini response contains no parts. Response: ' + responseBody
      );
    }

    Map<String, Object> firstPart = (Map<String, Object>) responseParts[0];

    String text = (String) firstPart.get('text');

    if (String.isBlank(text)) {
      throw new CalloutException(
        'Gemini response contains no text. Response: ' + responseBody
      );
    }

    return text;
  }
}
